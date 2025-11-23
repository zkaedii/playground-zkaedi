// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICrossChain.sol";

/*//////////////////////////////////////////////////////////////
                    FEE MANAGER & GAS ESTIMATOR
//////////////////////////////////////////////////////////////*/

/**
 * @title FeeManager
 * @notice Manages cross-chain fees, gas estimation, and fee distribution
 * @dev Features:
 *      - Multi-protocol fee estimation
 *      - Dynamic gas price tracking
 *      - Fee collection and distribution
 *      - Refund excess fees
 *      - Fee subsidies/discounts
 */
contract FeeManager is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    enum FeeType {
        PROTOCOL_FEE,
        GAS_FEE,
        BRIDGE_FEE,
        LIQUIDITY_FEE,
        PRIORITY_FEE
    }

    struct FeeConfig {
        uint256 baseFee;           // Base fee in wei
        uint256 percentageFee;     // Fee in BPS (basis points)
        uint256 minFee;            // Minimum fee
        uint256 maxFee;            // Maximum fee
        bool isActive;
    }

    struct ChainGasConfig {
        uint256 gasPrice;          // Current gas price
        uint256 gasPriceUpdatedAt;
        uint256 l1DataFee;         // L2 specific (e.g., Arbitrum, Optimism)
        uint256 priorityFee;       // EIP-1559 priority fee
        uint256 baseFeeMultiplier; // Multiplier for safety margin (10000 = 1x)
    }

    struct FeeQuote {
        uint256 protocolFee;
        uint256 gasFee;
        uint256 bridgeFee;
        uint256 totalFee;
        uint256 estimatedGas;
        uint256 validUntil;
    }

    struct FeeDistribution {
        address treasury;
        address stakers;
        address referrer;
        uint256 treasuryShare;     // BPS
        uint256 stakersShare;      // BPS
        uint256 referrerShare;     // BPS
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientFee();
    error FeeQuoteExpired();
    error InvalidFeeConfig();
    error ChainNotSupported();
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeeCollected(
        bytes32 indexed txId,
        address indexed payer,
        uint256 protocolFee,
        uint256 gasFee,
        uint256 bridgeFee
    );
    event FeeRefunded(
        bytes32 indexed txId,
        address indexed recipient,
        uint256 amount
    );
    event FeesDistributed(
        uint256 treasuryAmount,
        uint256 stakersAmount,
        uint256 referrerAmount
    );
    event GasPriceUpdated(uint256 indexed chainId, uint256 gasPrice);
    event FeeConfigUpdated(uint256 indexed chainId, FeeType feeType);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Chain ID => Fee type => Config
    mapping(uint256 => mapping(FeeType => FeeConfig)) public feeConfigs;

    /// @dev Chain ID => Gas config
    mapping(uint256 => ChainGasConfig) public chainGasConfigs;

    /// @dev Fee distribution config
    FeeDistribution public feeDistribution;

    /// @dev Collected fees per token
    mapping(address => uint256) public collectedFees;

    /// @dev TX ID => fee quote
    mapping(bytes32 => FeeQuote) public feeQuotes;

    /// @dev TX ID => excess fee to refund
    mapping(bytes32 => uint256) public pendingRefunds;

    /// @dev Fee token (address(0) for native)
    address public feeToken;

    /// @dev Quote validity period
    uint256 public quoteValidityPeriod;

    /// @dev Gas oracle
    address public gasOracle;

    /// @dev Protocol endpoints for fee queries
    mapping(uint8 => address) public protocolEndpoints;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _treasury,
        address _feeToken
    ) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        feeToken = _feeToken;
        quoteValidityPeriod = 5 minutes;

        feeDistribution = FeeDistribution({
            treasury: _treasury,
            stakers: address(0),
            referrer: address(0),
            treasuryShare: 7000,  // 70%
            stakersShare: 3000,   // 30%
            referrerShare: 0
        });
    }

    /*//////////////////////////////////////////////////////////////
                    FEE ESTIMATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Get comprehensive fee quote
    function getFeeQuote(
        uint256 destChainId,
        uint256 gasLimit,
        uint256 value,
        uint8 protocol
    ) external view returns (FeeQuote memory quote) {
        // Protocol fee
        FeeConfig memory protocolConfig = feeConfigs[destChainId][FeeType.PROTOCOL_FEE];
        quote.protocolFee = _calculateFee(value, protocolConfig);

        // Gas fee
        quote.gasFee = estimateGasFee(destChainId, gasLimit);

        // Bridge fee (protocol specific)
        quote.bridgeFee = estimateBridgeFee(destChainId, value, protocol);

        // Total
        quote.totalFee = quote.protocolFee + quote.gasFee + quote.bridgeFee;
        quote.estimatedGas = gasLimit;
        quote.validUntil = block.timestamp + quoteValidityPeriod;
    }

    /// @notice Estimate gas fee for destination chain
    function estimateGasFee(
        uint256 destChainId,
        uint256 gasLimit
    ) public view returns (uint256) {
        ChainGasConfig memory config = chainGasConfigs[destChainId];

        if (config.gasPrice == 0) {
            // Use fallback
            return gasLimit * 50 gwei; // Default 50 gwei
        }

        uint256 baseFee = gasLimit * config.gasPrice;
        uint256 priorityFee = gasLimit * config.priorityFee;
        uint256 l1Fee = config.l1DataFee; // For L2s

        uint256 totalGasFee = baseFee + priorityFee + l1Fee;

        // Apply safety multiplier
        return (totalGasFee * config.baseFeeMultiplier) / 10000;
    }

    /// @notice Estimate bridge-specific fee
    function estimateBridgeFee(
        uint256 destChainId,
        uint256 value,
        uint8 protocol
    ) public view returns (uint256) {
        address endpoint = protocolEndpoints[protocol];
        if (endpoint == address(0)) return 0;

        // CCIP
        if (protocol == 0) {
            return _estimateCCIPFee(destChainId, value);
        }
        // LayerZero
        else if (protocol == 1) {
            return _estimateLZFee(destChainId);
        }
        // Wormhole
        else if (protocol == 2) {
            return _estimateWormholeFee();
        }

        return 0;
    }

    function _estimateCCIPFee(uint256, uint256) internal pure returns (uint256) {
        // Simplified - real implementation would query router
        return 0.01 ether;
    }

    function _estimateLZFee(uint256) internal pure returns (uint256) {
        return 0.005 ether;
    }

    function _estimateWormholeFee() internal pure returns (uint256) {
        return 0.001 ether;
    }

    function _calculateFee(
        uint256 value,
        FeeConfig memory config
    ) internal pure returns (uint256 fee) {
        if (!config.isActive) return 0;

        // Base fee
        fee = config.baseFee;

        // Percentage fee
        fee += (value * config.percentageFee) / 10000;

        // Clamp to min/max
        if (fee < config.minFee) fee = config.minFee;
        if (config.maxFee > 0 && fee > config.maxFee) fee = config.maxFee;
    }

    /*//////////////////////////////////////////////////////////////
                    FEE COLLECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Collect fees for a transaction
    function collectFees(
        bytes32 txId,
        address payer,
        uint256 value,
        uint256 destChainId,
        uint256 gasLimit,
        uint8 protocol
    ) external payable returns (uint256 totalFee) {
        FeeQuote memory quote = this.getFeeQuote(destChainId, gasLimit, value, protocol);

        if (feeToken == address(0)) {
            // Native token
            if (msg.value < quote.totalFee) revert InsufficientFee();

            // Store excess for refund
            if (msg.value > quote.totalFee) {
                pendingRefunds[txId] = msg.value - quote.totalFee;
            }
        } else {
            // ERC20 token
            IERC20(feeToken).safeTransferFrom(payer, address(this), quote.totalFee);
        }

        // Store quote for later verification
        feeQuotes[txId] = quote;

        // Track collected fees
        collectedFees[feeToken] += quote.totalFee;

        emit FeeCollected(txId, payer, quote.protocolFee, quote.gasFee, quote.bridgeFee);

        return quote.totalFee;
    }

    /// @notice Refund excess fees
    function refundExcess(bytes32 txId, address recipient) external {
        uint256 refundAmount = pendingRefunds[txId];
        if (refundAmount == 0) return;

        pendingRefunds[txId] = 0;

        if (feeToken == address(0)) {
            (bool success, ) = recipient.call{value: refundAmount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(feeToken).safeTransfer(recipient, refundAmount);
        }

        emit FeeRefunded(txId, recipient, refundAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    FEE DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Distribute collected fees
    function distributeFees(address token) external {
        uint256 amount = collectedFees[token];
        if (amount == 0) return;

        collectedFees[token] = 0;

        uint256 treasuryAmount = (amount * feeDistribution.treasuryShare) / 10000;
        uint256 stakersAmount = (amount * feeDistribution.stakersShare) / 10000;
        uint256 referrerAmount = amount - treasuryAmount - stakersAmount;

        if (token == address(0)) {
            if (treasuryAmount > 0 && feeDistribution.treasury != address(0)) {
                (bool s1, ) = feeDistribution.treasury.call{value: treasuryAmount}("");
                require(s1, "Treasury transfer failed");
            }
            if (stakersAmount > 0 && feeDistribution.stakers != address(0)) {
                (bool s2, ) = feeDistribution.stakers.call{value: stakersAmount}("");
                require(s2, "Stakers transfer failed");
            }
            if (referrerAmount > 0 && feeDistribution.referrer != address(0)) {
                (bool s3, ) = feeDistribution.referrer.call{value: referrerAmount}("");
                require(s3, "Referrer transfer failed");
            }
        } else {
            IERC20 tokenContract = IERC20(token);
            if (treasuryAmount > 0 && feeDistribution.treasury != address(0)) {
                tokenContract.safeTransfer(feeDistribution.treasury, treasuryAmount);
            }
            if (stakersAmount > 0 && feeDistribution.stakers != address(0)) {
                tokenContract.safeTransfer(feeDistribution.stakers, stakersAmount);
            }
            if (referrerAmount > 0 && feeDistribution.referrer != address(0)) {
                tokenContract.safeTransfer(feeDistribution.referrer, referrerAmount);
            }
        }

        emit FeesDistributed(treasuryAmount, stakersAmount, referrerAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    GAS PRICE UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Update gas price for a chain
    function updateGasPrice(
        uint256 chainId,
        uint256 gasPrice,
        uint256 priorityFee,
        uint256 l1DataFee
    ) external {
        require(msg.sender == gasOracle || msg.sender == owner(), "Not authorized");

        ChainGasConfig storage config = chainGasConfigs[chainId];
        config.gasPrice = gasPrice;
        config.priorityFee = priorityFee;
        config.l1DataFee = l1DataFee;
        config.gasPriceUpdatedAt = block.timestamp;

        emit GasPriceUpdated(chainId, gasPrice);
    }

    /// @notice Batch update gas prices
    function updateGasPricesBatch(
        uint256[] calldata chainIds,
        uint256[] calldata gasPrices,
        uint256[] calldata priorityFees,
        uint256[] calldata l1DataFees
    ) external {
        require(msg.sender == gasOracle || msg.sender == owner(), "Not authorized");
        uint256 len = chainIds.length;
        require(
            len == gasPrices.length &&
            len == priorityFees.length &&
            len == l1DataFees.length,
            "Length mismatch"
        );

        uint256 currentTimestamp = block.timestamp;
        unchecked {
            for (uint256 i; i < len; ++i) {
                ChainGasConfig storage config = chainGasConfigs[chainIds[i]];
                config.gasPrice = gasPrices[i];
                config.priorityFee = priorityFees[i];
                config.l1DataFee = l1DataFees[i];
                config.gasPriceUpdatedAt = currentTimestamp;

                emit GasPriceUpdated(chainIds[i], gasPrices[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setFeeConfig(
        uint256 chainId,
        FeeType feeType,
        FeeConfig calldata config
    ) external onlyOwner {
        feeConfigs[chainId][feeType] = config;
        emit FeeConfigUpdated(chainId, feeType);
    }

    function setChainGasConfig(
        uint256 chainId,
        ChainGasConfig calldata config
    ) external onlyOwner {
        chainGasConfigs[chainId] = config;
    }

    function setFeeDistribution(FeeDistribution calldata _distribution) external onlyOwner {
        require(
            _distribution.treasuryShare + _distribution.stakersShare + _distribution.referrerShare <= 10000,
            "Shares exceed 100%"
        );
        feeDistribution = _distribution;
    }

    function setGasOracle(address _oracle) external onlyOwner {
        gasOracle = _oracle;
    }

    function setProtocolEndpoint(uint8 protocol, address endpoint) external onlyOwner {
        protocolEndpoints[protocol] = endpoint;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}

    uint256[40] private __gap;
}
