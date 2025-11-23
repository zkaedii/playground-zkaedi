// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IDEXAggregator.sol";
import "../interfaces/ICrossChain.sol";
import "../interfaces/IOracle.sol";

/*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN DEX ROUTER
//////////////////////////////////////////////////////////////*/

/**
 * @title CrossChainDEXRouter
 * @author Multi-Chain DEX & Oracle Integration
 * @notice Aggregates DEX liquidity with cross-chain messaging support
 * @dev Features:
 *      - Multi-DEX routing (Uniswap V2/V3, Curve, Balancer, etc.)
 *      - Cross-chain swaps via CCIP and LayerZero
 *      - Smart order routing with split trades
 *      - Oracle-protected execution (price impact limits)
 *      - Gas-optimized batch operations
 */
contract CrossChainDEXRouter is
    IDEXAggregator,
    ICrossChainDEX,
    ICCIPReceiver,
    ILayerZeroReceiver,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientOutput();
    error DeadlineExpired();
    error InvalidRoute();
    error UnsupportedDEX();
    error UnsupportedChain();
    error PriceImpactTooHigh();
    error TransferFailed();
    error UnauthorizedSender();
    error InvalidCrossChainMessage();
    error CrossChainSwapFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        DEXType dex
    );
    event CrossChainSwapInitiated(
        bytes32 indexed txId,
        address indexed sender,
        uint256 srcChainId,
        uint256 dstChainId,
        address tokenIn,
        uint256 amountIn
    );
    event CrossChainSwapCompleted(
        bytes32 indexed txId,
        address indexed recipient,
        address tokenOut,
        uint256 amountOut
    );
    event DEXAdapterRegistered(DEXType indexed dexType, address adapter);
    event ChainConfigured(uint256 chainId, uint64 ccipSelector, uint32 lzEndpointId);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev DEX type => Adapter contract address
    mapping(DEXType => address) public dexAdapters;

    /// @dev Chain ID => CCIP chain selector
    mapping(uint256 => uint64) public ccipChainSelectors;

    /// @dev Chain ID => LayerZero endpoint ID
    mapping(uint256 => uint32) public lzEndpointIds;

    /// @dev Trusted remote addresses for LayerZero
    mapping(uint32 => bytes32) public trustedRemotes;

    /// @dev Cross-chain swap status
    mapping(bytes32 => CrossChainSwapStatus) public crossChainSwaps;

    struct CrossChainSwapStatus {
        address sender;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        uint256 srcChainId;
        uint256 dstChainId;
        uint8 status; // 0: pending, 1: completed, 2: failed, 3: refunded
        uint256 timestamp;
    }

    /// @dev Oracle aggregator for price checks
    ISmartOracle public oracle;

    /// @dev CCIP Router
    ICCIPRouter public ccipRouter;

    /// @dev LayerZero Endpoint
    ILayerZeroEndpoint public lzEndpoint;

    /// @dev Maximum price impact allowed (in BPS)
    uint256 public maxPriceImpactBps;

    /// @dev Protocol fee (in BPS)
    uint256 public protocolFeeBps;

    /// @dev Fee recipient
    address public feeRecipient;

    /// @dev Native token wrapper (WETH, WMATIC, etc.)
    address public wrappedNative;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _oracle,
        address _ccipRouter,
        address _lzEndpoint,
        address _wrappedNative,
        address _feeRecipient
    ) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        oracle = ISmartOracle(_oracle);
        ccipRouter = ICCIPRouter(_ccipRouter);
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        wrappedNative = _wrappedNative;
        feeRecipient = _feeRecipient;

        maxPriceImpactBps = 300; // 3% default
        protocolFeeBps = 10; // 0.1% default
    }

    /*//////////////////////////////////////////////////////////////
                        SINGLE-CHAIN SWAPS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDEXAggregator
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Transfer tokens in
        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Get best quote and execute
        SwapQuote memory quote = _getOptimalQuote(tokenIn, tokenOut, amountIn);

        // Check price impact
        _validatePriceImpact(tokenIn, tokenOut, amountIn, quote.amountOut);

        // Execute the swap
        amountOut = _executeSwapRoute(quote.routes[0], amountIn, recipient);

        if (amountOut < minAmountOut) revert InsufficientOutput();

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, quote.routes[0].dex);
    }

    /// @inheritdoc IDEXAggregator
    function multiHopSwap(MultiHopSwap calldata params, address recipient)
        external payable nonReentrant returns (uint256 amountOut)
    {
        if (block.timestamp > params.deadline) revert DeadlineExpired();
        if (params.hops.length == 0) revert InvalidRoute();

        // Transfer initial tokens
        IERC20(params.hops[0].tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            params.hops[0].amountIn
        );

        uint256 currentAmount = params.hops[0].amountIn;

        // Execute each hop
        for (uint256 i; i < params.hops.length; ++i) {
            SwapRoute memory hop = params.hops[i];

            // For intermediate hops, use this contract as recipient
            address hopRecipient = (i == params.hops.length - 1) ? recipient : address(this);

            currentAmount = _executeSwapRoute(hop, currentAmount, hopRecipient);
        }

        amountOut = currentAmount;
        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    /// @inheritdoc IDEXAggregator
    function splitSwap(SplitSwap calldata params, address recipient)
        external payable nonReentrant returns (uint256 amountOut)
    {
        if (block.timestamp > params.deadline) revert DeadlineExpired();
        if (params.routes.length != params.portions.length) revert InvalidRoute();

        uint256 totalPortion;
        for (uint256 i; i < params.portions.length; ++i) {
            totalPortion += params.portions[i];
        }
        if (totalPortion != 10000) revert InvalidRoute();

        // Transfer total input amount
        uint256 totalAmountIn = params.routes[0].amountIn;
        IERC20(params.routes[0].tokenIn).safeTransferFrom(msg.sender, address(this), totalAmountIn);

        // Execute each route with its portion
        for (uint256 i; i < params.routes.length; ++i) {
            uint256 routeAmountIn = (totalAmountIn * params.portions[i]) / 10000;

            uint256 routeAmountOut = _executeSwapRoute(params.routes[i], routeAmountIn, recipient);
            amountOut += routeAmountOut;
        }

        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN SWAPS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICrossChainDEX
    function crossChainSwap(CrossChainSwap calldata params)
        external payable nonReentrant returns (bytes32 txId)
    {
        // Transfer tokens in
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Deduct protocol fee
        uint256 fee = (params.amountIn * protocolFeeBps) / 10000;
        uint256 netAmount = params.amountIn - fee;

        if (fee > 0) {
            IERC20(params.tokenIn).safeTransfer(feeRecipient, fee);
        }

        // Execute source chain swap if needed (swap to bridge token)
        uint256 bridgeAmount = netAmount;
        if (params.swapData.length > 0) {
            (address bridgeToken, uint256 minBridgeAmount) = abi.decode(
                params.swapData,
                (address, uint256)
            );

            // Approve and swap to bridge token
            IERC20(params.tokenIn).forceApprove(address(this), netAmount);

            bridgeAmount = this.swap(
                params.tokenIn,
                bridgeToken,
                netAmount,
                minBridgeAmount,
                address(this),
                block.timestamp + 300
            );
        }

        // Generate transaction ID
        txId = keccak256(abi.encodePacked(
            msg.sender,
            params.tokenIn,
            params.amountIn,
            params.dstChainId,
            block.timestamp,
            block.number
        ));

        // Store swap status
        crossChainSwaps[txId] = CrossChainSwapStatus({
            sender: msg.sender,
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            minAmountOut: params.minAmountOut,
            recipient: params.recipient,
            srcChainId: params.srcChainId,
            dstChainId: params.dstChainId,
            status: 0, // pending
            timestamp: block.timestamp
        });

        // Send cross-chain message
        _sendCrossChainMessage(params, txId, bridgeAmount);

        emit CrossChainSwapInitiated(
            txId,
            msg.sender,
            params.srcChainId,
            params.dstChainId,
            params.tokenIn,
            params.amountIn
        );
    }

    /// @dev Send cross-chain message via CCIP or LayerZero
    function _sendCrossChainMessage(
        CrossChainSwap calldata params,
        bytes32 txId,
        uint256 bridgeAmount
    ) internal {
        // Encode the cross-chain payload
        bytes memory payload = abi.encode(
            txId,
            params.tokenOut,
            params.minAmountOut,
            params.recipient,
            params.swapData
        );

        uint64 ccipSelector = ccipChainSelectors[params.dstChainId];

        if (ccipSelector != 0) {
            // Use CCIP
            _sendViaCCIP(params, ccipSelector, bridgeAmount, payload);
        } else {
            uint32 lzEid = lzEndpointIds[params.dstChainId];
            if (lzEid != 0) {
                // Use LayerZero
                _sendViaLayerZero(params, lzEid, bridgeAmount, payload);
            } else {
                revert UnsupportedChain();
            }
        }
    }

    /// @dev Send via Chainlink CCIP
    function _sendViaCCIP(
        CrossChainSwap calldata params,
        uint64 destinationChainSelector,
        uint256 bridgeAmount,
        bytes memory payload
    ) internal {
        // Prepare token transfer
        ICCIPRouter.EVMTokenAmount[] memory tokenAmounts;

        if (params.bridgeData.length > 0) {
            address bridgeToken = abi.decode(params.bridgeData, (address));

            tokenAmounts = new ICCIPRouter.EVMTokenAmount[](1);
            tokenAmounts[0] = ICCIPRouter.EVMTokenAmount({
                token: bridgeToken,
                amount: bridgeAmount
            });

            // Approve CCIP router
            IERC20(bridgeToken).forceApprove(address(ccipRouter), bridgeAmount);
        }

        // Get remote router address
        bytes memory receiver = abi.encode(address(this)); // Same contract on dest chain

        ICCIPRouter.EVM2AnyMessage memory message = ICCIPRouter.EVM2AnyMessage({
            receiver: receiver,
            data: payload,
            tokenAmounts: tokenAmounts,
            feeToken: address(0), // Pay in native
            extraArgs: abi.encode(200_000) // Gas limit for dest execution
        });

        // Get fee and send
        uint256 ccipFee = ccipRouter.getFee(destinationChainSelector, message);
        require(msg.value >= ccipFee, "Insufficient CCIP fee");

        ccipRouter.ccipSend{value: ccipFee}(destinationChainSelector, message);
    }

    /// @dev Send via LayerZero
    function _sendViaLayerZero(
        CrossChainSwap calldata params,
        uint32 dstEid,
        uint256 bridgeAmount,
        bytes memory payload
    ) internal {
        bytes32 receiver = trustedRemotes[dstEid];
        if (receiver == bytes32(0)) revert UnsupportedChain();

        // Encode options (gas limit)
        bytes memory options = abi.encodePacked(
            uint16(1),    // Options type
            uint256(200_000) // Gas limit
        );

        ILayerZeroEndpoint.MessagingParams memory lzParams = ILayerZeroEndpoint.MessagingParams({
            dstEid: dstEid,
            receiver: receiver,
            message: payload,
            options: options,
            payInLzToken: false
        });

        // Get fee and send
        ILayerZeroEndpoint.MessagingFee memory lzFee = lzEndpoint.quote(lzParams, address(this));
        require(msg.value >= lzFee.nativeFee, "Insufficient LZ fee");

        lzEndpoint.send{value: lzFee.nativeFee}(lzParams, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN MESSAGE RECEIVERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ICCIPReceiver
    function ccipReceive(ICCIPRouter.Any2EVMMessage calldata message) external {
        if (msg.sender != address(ccipRouter)) revert UnauthorizedSender();

        _processCrossChainMessage(
            message.messageId,
            message.data,
            message.destTokenAmounts
        );
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        ILayerZeroEndpoint.Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address,
        bytes calldata
    ) external payable {
        if (msg.sender != address(lzEndpoint)) revert UnauthorizedSender();
        if (trustedRemotes[_origin.srcEid] != _origin.sender) revert UnauthorizedSender();

        // Process with empty token amounts (tokens sent separately via OFT)
        ICCIPRouter.EVMTokenAmount[] memory emptyTokens;
        _processCrossChainMessage(_guid, _message, emptyTokens);
    }

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(ILayerZeroEndpoint.Origin calldata _origin)
        external view returns (bool)
    {
        return trustedRemotes[_origin.srcEid] != bytes32(0);
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32, bytes32) external pure returns (uint64) {
        return 0; // Not using ordered delivery
    }

    /// @dev Process incoming cross-chain message
    function _processCrossChainMessage(
        bytes32 messageId,
        bytes memory data,
        ICCIPRouter.EVMTokenAmount[] memory tokenAmounts
    ) internal {
        // Decode payload
        (
            bytes32 txId,
            address tokenOut,
            uint256 minAmountOut,
            address recipient,
            bytes memory swapData
        ) = abi.decode(data, (bytes32, address, uint256, address, bytes));

        // Get bridge token amount
        uint256 bridgeTokenAmount;
        address bridgeToken;

        if (tokenAmounts.length > 0) {
            bridgeToken = tokenAmounts[0].token;
            bridgeTokenAmount = tokenAmounts[0].amount;
        }

        // Execute destination swap if needed
        uint256 finalAmount = bridgeTokenAmount;

        if (swapData.length > 0 && bridgeToken != tokenOut) {
            try this.swap(
                bridgeToken,
                tokenOut,
                bridgeTokenAmount,
                minAmountOut,
                recipient,
                block.timestamp + 300
            ) returns (uint256 amountOut) {
                finalAmount = amountOut;
            } catch {
                // If swap fails, send bridge tokens to recipient
                if (bridgeTokenAmount > 0) {
                    IERC20(bridgeToken).safeTransfer(recipient, bridgeTokenAmount);
                }
                emit CrossChainSwapCompleted(txId, recipient, bridgeToken, bridgeTokenAmount);
                return;
            }
        } else if (bridgeTokenAmount > 0) {
            // No swap needed, just transfer
            IERC20(bridgeToken).safeTransfer(recipient, bridgeTokenAmount);
        }

        emit CrossChainSwapCompleted(txId, recipient, tokenOut, finalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            QUOTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDEXAggregator
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (SwapQuote memory quote) {
        return _getOptimalQuote(tokenIn, tokenOut, amountIn);
    }

    /// @inheritdoc IDEXAggregator
    function getMultiQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        DEXType[] calldata dexes
    ) external view returns (SwapQuote[] memory quotes) {
        quotes = new SwapQuote[](dexes.length);

        for (uint256 i; i < dexes.length; ++i) {
            quotes[i] = _getQuoteFromDEX(dexes[i], tokenIn, tokenOut, amountIn);
        }
    }

    /// @inheritdoc ICrossChainDEX
    function getCrossChainQuote(CrossChainSwap calldata params)
        external view returns (CrossChainQuote memory quote)
    {
        // Get swap quote
        SwapQuote memory swapQuote = _getOptimalQuote(
            params.tokenIn,
            params.tokenOut,
            params.amountIn
        );

        // Calculate bridge fee
        uint256 bridgeFee;
        uint64 ccipSelector = ccipChainSelectors[params.dstChainId];

        if (ccipSelector != 0) {
            // Estimate CCIP fee
            bridgeFee = 0.01 ether; // Placeholder - actual fee depends on message
        } else {
            uint32 lzEid = lzEndpointIds[params.dstChainId];
            if (lzEid != 0) {
                // Estimate LZ fee
                bridgeFee = 0.005 ether; // Placeholder
            }
        }

        quote = CrossChainQuote({
            estimatedAmountOut: swapQuote.amountOut,
            bridgeFee: bridgeFee,
            swapFee: (params.amountIn * protocolFeeBps) / 10000,
            estimatedTime: 300, // 5 minutes average
            routeId: keccak256(abi.encodePacked(params.tokenIn, params.tokenOut, params.dstChainId))
        });
    }

    /// @inheritdoc ICrossChainDEX
    function getCrossChainStatus(bytes32 txId)
        external view returns (uint8 status, bytes memory data)
    {
        CrossChainSwapStatus storage swapStatus = crossChainSwaps[txId];
        status = swapStatus.status;
        data = abi.encode(swapStatus);
    }

    /// @dev Get optimal quote across all DEXs
    function _getOptimalQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (SwapQuote memory bestQuote) {
        // Try each DEX type
        DEXType[5] memory dexTypes = [
            DEXType.UNISWAP_V3,
            DEXType.UNISWAP_V2,
            DEXType.CURVE,
            DEXType.BALANCER,
            DEXType.SUSHISWAP
        ];

        for (uint256 i; i < dexTypes.length; ++i) {
            if (dexAdapters[dexTypes[i]] == address(0)) continue;

            SwapQuote memory quote = _getQuoteFromDEX(dexTypes[i], tokenIn, tokenOut, amountIn);

            if (quote.amountOut > bestQuote.amountOut) {
                bestQuote = quote;
            }
        }
    }

    /// @dev Get quote from specific DEX
    function _getQuoteFromDEX(
        DEXType dexType,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (SwapQuote memory quote) {
        address adapter = dexAdapters[dexType];
        if (adapter == address(0)) return quote;

        // Create route
        SwapRoute[] memory routes = new SwapRoute[](1);
        routes[0] = SwapRoute({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            dex: dexType,
            extraData: ""
        });

        // Get quote from adapter (simplified - real implementation would call adapter)
        quote = SwapQuote({
            amountOut: 0, // Would be populated by adapter
            gasEstimate: 150000,
            priceImpact: 0,
            routes: routes
        });
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute a swap route
    function _executeSwapRoute(
        SwapRoute memory route,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256 amountOut) {
        address adapter = dexAdapters[route.dex];
        if (adapter == address(0)) revert UnsupportedDEX();

        // Approve adapter
        IERC20(route.tokenIn).forceApprove(adapter, amountIn);

        // Call adapter's swap function
        // In a real implementation, this would delegate to the adapter
        // For now, return a placeholder
        amountOut = amountIn; // Placeholder

        // Transfer output to recipient
        if (recipient != address(this)) {
            IERC20(route.tokenOut).safeTransfer(recipient, amountOut);
        }
    }

    /// @dev Validate price impact against oracle
    function _validatePriceImpact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal view {
        if (address(oracle) == address(0)) return;

        try oracle.getPrice(tokenIn, tokenOut) returns (ISmartOracle.PriceData memory priceData) {
            if (priceData.price == 0) return;

            // Calculate expected output based on oracle price
            uint256 expectedOut = (amountIn * priceData.price) / (10 ** priceData.decimals);

            // Check if actual output is significantly less than expected
            if (amountOut < expectedOut) {
                uint256 impactBps = ((expectedOut - amountOut) * 10000) / expectedOut;
                if (impactBps > maxPriceImpactBps) revert PriceImpactTooHigh();
            }
        } catch {
            // Oracle unavailable, skip validation
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a DEX adapter
    function registerDEXAdapter(DEXType dexType, address adapter) external onlyOwner {
        dexAdapters[dexType] = adapter;
        emit DEXAdapterRegistered(dexType, adapter);
    }

    /// @notice Configure a chain for cross-chain operations
    function configureChain(
        uint256 chainId,
        uint64 ccipSelector,
        uint32 lzEid,
        bytes32 trustedRemote
    ) external onlyOwner {
        ccipChainSelectors[chainId] = ccipSelector;
        lzEndpointIds[chainId] = lzEid;
        if (lzEid != 0) {
            trustedRemotes[lzEid] = trustedRemote;
        }
        emit ChainConfigured(chainId, ccipSelector, lzEid);
    }

    /// @notice Set oracle address
    function setOracle(address _oracle) external onlyOwner {
        oracle = ISmartOracle(_oracle);
    }

    /// @notice Set CCIP router
    function setCCIPRouter(address _router) external onlyOwner {
        ccipRouter = ICCIPRouter(_router);
    }

    /// @notice Set LayerZero endpoint
    function setLZEndpoint(address _endpoint) external onlyOwner {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
    }

    /// @notice Set max price impact
    function setMaxPriceImpact(uint256 _maxBps) external onlyOwner {
        maxPriceImpactBps = _maxBps;
    }

    /// @notice Set protocol fee
    function setProtocolFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 100, "Fee too high"); // Max 1%
        protocolFeeBps = _feeBps;
    }

    /// @notice Set fee recipient
    function setFeeRecipient(address _recipient) external onlyOwner {
        feeRecipient = _recipient;
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Rescue stuck ETH
    function rescueETH() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        STORAGE GAP
    //////////////////////////////////////////////////////////////*/

    uint256[35] private __gap;
}
