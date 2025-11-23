// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*//////////////////////////////////////////////////////////////
                    REFUND MANAGER
//////////////////////////////////////////////////////////////*/

/**
 * @title RefundManager
 * @notice Handles refunds for failed cross-chain transactions
 * @dev Features:
 *      - Automatic refund triggers
 *      - Manual refund claims
 *      - Partial refund support
 *      - Fee deduction handling
 *      - Multi-token refunds
 *      - Time-locked refunds
 *      - Dispute resolution
 */
contract RefundManager is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            ENUMS & STRUCTS
    //////////////////////////////////////////////////////////////*/

    enum RefundStatus {
        NONE,
        PENDING,
        CLAIMABLE,
        CLAIMED,
        DISPUTED,
        RESOLVED,
        EXPIRED
    }

    enum RefundReason {
        TRANSACTION_FAILED,
        TIMEOUT_EXPIRED,
        INSUFFICIENT_LIQUIDITY,
        SLIPPAGE_EXCEEDED,
        BRIDGE_FAILURE,
        MANUAL_CANCELLATION,
        DESTINATION_REJECTED,
        GAS_ESTIMATION_FAILED
    }

    struct RefundRequest {
        bytes32 originalTxId;
        address recipient;
        address token;
        uint256 amount;
        uint256 feeDeducted;
        uint256 createdAt;
        uint256 claimableAt;
        uint256 expiresAt;
        RefundStatus status;
        RefundReason reason;
        bytes32 proofHash;
    }

    struct RefundConfig {
        uint256 claimDelay;         // Time before refund is claimable
        uint256 expiryPeriod;       // Time until refund expires
        uint256 minRefundAmount;    // Minimum amount to process
        uint256 feePercentage;      // Fee percentage (BPS)
        bool requireProof;          // Whether proof is required
        bool autoProcess;           // Auto-process refunds
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error RefundNotFound();
    error RefundNotClaimable();
    error RefundAlreadyClaimed();
    error RefundExpired();
    error InvalidProof();
    error RefundTooSmall();
    error Unauthorized();
    error DisputeActive();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event RefundCreated(
        bytes32 indexed refundId,
        bytes32 indexed originalTxId,
        address indexed recipient,
        address token,
        uint256 amount,
        RefundReason reason
    );
    event RefundClaimed(
        bytes32 indexed refundId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );
    event RefundDisputed(
        bytes32 indexed refundId,
        address indexed disputer,
        string reason
    );
    event RefundResolved(
        bytes32 indexed refundId,
        RefundStatus resolution,
        uint256 finalAmount
    );
    event RefundExpired(bytes32 indexed refundId);
    event EmergencyRefund(
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Refund ID => RefundRequest
    mapping(bytes32 => RefundRequest) public refunds;

    /// @dev Original TX ID => Refund ID
    mapping(bytes32 => bytes32) public txToRefund;

    /// @dev User => pending refund IDs
    mapping(address => bytes32[]) public userRefunds;

    /// @dev Token => refund config
    mapping(address => RefundConfig) public tokenConfigs;

    /// @dev Default config
    RefundConfig public defaultConfig;

    /// @dev Authorized processors
    mapping(address => bool) public processors;

    /// @dev Dispute resolvers
    mapping(address => bool) public resolvers;

    /// @dev Treasury for fees
    address public treasury;

    /// @dev Total refunds processed per token
    mapping(address => uint256) public totalRefunded;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _treasury) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        treasury = _treasury;

        // Set default config
        defaultConfig = RefundConfig({
            claimDelay: 1 hours,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 50, // 0.5%
            requireProof: false,
            autoProcess: true
        });
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a refund request
    /// @param originalTxId The original transaction ID that failed
    /// @param recipient The address to receive the refund
    /// @param token The token to refund (address(0) for ETH)
    /// @param amount The amount to refund
    /// @param reason The reason for the refund
    /// @param proofHash Optional proof hash for verification
    /// @return refundId The unique ID for this refund request
    function createRefund(
        bytes32 originalTxId,
        address recipient,
        address token,
        uint256 amount,
        RefundReason reason,
        bytes32 proofHash
    ) external returns (bytes32 refundId) {
        require(processors[msg.sender] || msg.sender == owner(), "Not authorized");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be positive");

        RefundConfig memory config = _getConfig(token);

        if (amount < config.minRefundAmount) revert RefundTooSmall();

        refundId = keccak256(abi.encodePacked(
            originalTxId,
            recipient,
            token,
            amount,
            block.timestamp
        ));

        // Check not already created
        if (refunds[refundId].createdAt != 0) revert InvalidAmount();

        // Calculate fee
        uint256 fee = (amount * config.feePercentage) / 10000;
        uint256 refundAmount = amount - fee;

        RefundStatus initialStatus = config.claimDelay == 0
            ? RefundStatus.CLAIMABLE
            : RefundStatus.PENDING;

        refunds[refundId] = RefundRequest({
            originalTxId: originalTxId,
            recipient: recipient,
            token: token,
            amount: refundAmount,
            feeDeducted: fee,
            createdAt: block.timestamp,
            claimableAt: block.timestamp + config.claimDelay,
            expiresAt: block.timestamp + config.expiryPeriod,
            status: initialStatus,
            reason: reason,
            proofHash: proofHash
        });

        txToRefund[originalTxId] = refundId;
        userRefunds[recipient].push(refundId);

        emit RefundCreated(
            refundId,
            originalTxId,
            recipient,
            token,
            refundAmount,
            reason
        );

        // Auto-process if enabled and claimable
        if (config.autoProcess && initialStatus == RefundStatus.CLAIMABLE) {
            _processRefund(refundId);
        }
    }

    /// @notice Batch create refunds
    function createRefundBatch(
        bytes32[] calldata originalTxIds,
        address[] calldata recipients,
        address[] calldata tokens,
        uint256[] calldata amounts,
        RefundReason[] calldata reasons
    ) external returns (bytes32[] memory refundIds) {
        require(processors[msg.sender] || msg.sender == owner(), "Not authorized");
        require(
            originalTxIds.length == recipients.length &&
            recipients.length == tokens.length &&
            tokens.length == amounts.length &&
            amounts.length == reasons.length,
            "Length mismatch"
        );

        refundIds = new bytes32[](originalTxIds.length);

        for (uint256 i; i < originalTxIds.length; ++i) {
            refundIds[i] = this.createRefund(
                originalTxIds[i],
                recipients[i],
                tokens[i],
                amounts[i],
                reasons[i],
                bytes32(0)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND CLAIMING
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim a refund
    function claimRefund(bytes32 refundId) external nonReentrant {
        RefundRequest storage refund = refunds[refundId];

        if (refund.createdAt == 0) revert RefundNotFound();
        if (refund.recipient != msg.sender) revert Unauthorized();
        if (refund.status == RefundStatus.CLAIMED) revert RefundAlreadyClaimed();
        if (refund.status == RefundStatus.DISPUTED) revert DisputeActive();
        if (block.timestamp < refund.claimableAt) revert RefundNotClaimable();
        if (block.timestamp > refund.expiresAt) {
            refund.status = RefundStatus.EXPIRED;
            emit RefundExpired(refundId);
            revert RefundExpired();
        }

        _processRefund(refundId);
    }

    /// @notice Claim multiple refunds
    function claimRefundBatch(bytes32[] calldata refundIds) external nonReentrant {
        for (uint256 i; i < refundIds.length; ++i) {
            RefundRequest storage refund = refunds[refundIds[i]];

            if (refund.createdAt == 0) continue;
            if (refund.recipient != msg.sender) continue;
            if (refund.status != RefundStatus.CLAIMABLE &&
                refund.status != RefundStatus.PENDING) continue;
            if (block.timestamp < refund.claimableAt) continue;
            if (block.timestamp > refund.expiresAt) {
                refund.status = RefundStatus.EXPIRED;
                continue;
            }

            _processRefund(refundIds[i]);
        }
    }

    /// @dev Internal refund processing
    function _processRefund(bytes32 refundId) internal {
        RefundRequest storage refund = refunds[refundId];

        refund.status = RefundStatus.CLAIMED;

        // Transfer refund amount
        if (refund.token == address(0)) {
            (bool success, ) = refund.recipient.call{value: refund.amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(refund.token).safeTransfer(refund.recipient, refund.amount);
        }

        // Transfer fee to treasury
        if (refund.feeDeducted > 0 && treasury != address(0)) {
            if (refund.token == address(0)) {
                (bool success, ) = treasury.call{value: refund.feeDeducted}("");
                require(success, "Fee transfer failed");
            } else {
                IERC20(refund.token).safeTransfer(treasury, refund.feeDeducted);
            }
        }

        totalRefunded[refund.token] += refund.amount;

        emit RefundClaimed(
            refundId,
            refund.recipient,
            refund.amount,
            refund.feeDeducted
        );
    }

    /*//////////////////////////////////////////////////////////////
                    DISPUTE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Dispute a refund
    function disputeRefund(bytes32 refundId, string calldata reason) external {
        RefundRequest storage refund = refunds[refundId];

        if (refund.createdAt == 0) revert RefundNotFound();
        if (refund.status == RefundStatus.CLAIMED) revert RefundAlreadyClaimed();

        // Only recipient or owner can dispute
        require(
            msg.sender == refund.recipient || msg.sender == owner(),
            "Not authorized"
        );

        refund.status = RefundStatus.DISPUTED;

        emit RefundDisputed(refundId, msg.sender, reason);
    }

    /// @notice Resolve a dispute
    function resolveDispute(
        bytes32 refundId,
        bool approve,
        uint256 adjustedAmount
    ) external {
        require(resolvers[msg.sender] || msg.sender == owner(), "Not resolver");

        RefundRequest storage refund = refunds[refundId];

        if (refund.status != RefundStatus.DISPUTED) revert RefundNotFound();

        if (approve) {
            if (adjustedAmount > 0 && adjustedAmount <= refund.amount + refund.feeDeducted) {
                refund.amount = adjustedAmount;
                refund.feeDeducted = 0;
            }
            refund.status = RefundStatus.CLAIMABLE;
            emit RefundResolved(refundId, RefundStatus.CLAIMABLE, refund.amount);
        } else {
            refund.status = RefundStatus.RESOLVED;
            emit RefundResolved(refundId, RefundStatus.RESOLVED, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency refund without normal flow
    function emergencyRefund(
        address recipient,
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit EmergencyRefund(recipient, token, amount);
    }

    /// @notice Recover stuck tokens
    function recoverTokens(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get user's pending refunds
    function getPendingRefunds(address user)
        external view returns (bytes32[] memory, uint256 totalPending)
    {
        bytes32[] memory allRefunds = userRefunds[user];
        bytes32[] memory pending = new bytes32[](allRefunds.length);
        uint256 count;

        for (uint256 i; i < allRefunds.length; ++i) {
            RefundRequest storage refund = refunds[allRefunds[i]];
            if (refund.status == RefundStatus.PENDING ||
                refund.status == RefundStatus.CLAIMABLE) {
                pending[count] = allRefunds[i];
                totalPending += refund.amount;
                ++count;
            }
        }

        // Resize array
        assembly {
            mstore(pending, count)
        }

        return (pending, totalPending);
    }

    /// @notice Check if refund is claimable
    function isClaimable(bytes32 refundId) external view returns (bool) {
        RefundRequest storage refund = refunds[refundId];
        return refund.createdAt != 0 &&
               (refund.status == RefundStatus.PENDING || refund.status == RefundStatus.CLAIMABLE) &&
               block.timestamp >= refund.claimableAt &&
               block.timestamp <= refund.expiresAt;
    }

    /// @notice Get refund details
    function getRefund(bytes32 refundId) external view returns (RefundRequest memory) {
        return refunds[refundId];
    }

    function _getConfig(address token) internal view returns (RefundConfig memory) {
        RefundConfig memory config = tokenConfigs[token];
        if (config.expiryPeriod == 0) {
            return defaultConfig;
        }
        return config;
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setTokenConfig(address token, RefundConfig calldata config) external onlyOwner {
        require(config.feePercentage <= 1000, "Fee too high"); // Max 10%
        require(config.expiryPeriod >= 1 days, "Expiry too short");
        tokenConfigs[token] = config;
    }

    function setDefaultConfig(RefundConfig calldata config) external onlyOwner {
        require(config.feePercentage <= 1000, "Fee too high"); // Max 10%
        require(config.expiryPeriod >= 1 days, "Expiry too short");
        defaultConfig = config;
    }

    function setProcessor(address processor, bool status) external onlyOwner {
        require(processor != address(0), "Invalid processor");
        processors[processor] = status;
    }

    function setResolver(address resolver, bool status) external onlyOwner {
        require(resolver != address(0), "Invalid resolver");
        resolvers[resolver] = status;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}

    uint256[40] private __gap;
}
