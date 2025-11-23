// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*//////////////////////////////////////////////////////////////
                    MESSAGE CATCHER & HANDLER
//////////////////////////////////////////////////////////////*/

/**
 * @title MessageCatcher
 * @notice Catches, decodes, and routes cross-chain messages to appropriate handlers
 * @dev Features:
 *      - Message type routing
 *      - Payload validation
 *      - Action execution
 *      - Response generation
 *      - Error recovery
 */
contract MessageCatcher is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Message types
    enum MessageType {
        SWAP,               // Token swap request
        TRANSFER,           // Simple token transfer
        LIQUIDITY_ADD,      // Add liquidity
        LIQUIDITY_REMOVE,   // Remove liquidity
        STAKE,              // Staking operation
        UNSTAKE,            // Unstaking operation
        GOVERNANCE,         // Governance action
        ORACLE_UPDATE,      // Oracle price update
        EMERGENCY,          // Emergency action
        CUSTOM              // Custom handler
    }

    /// @notice Decoded message structure
    struct DecodedMessage {
        MessageType msgType;
        address sender;
        address recipient;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 deadline;
        bytes extraData;
    }

    /// @notice Handler info
    struct HandlerInfo {
        address handler;
        bytes4 selector;
        bool isActive;
        uint256 gasLimit;
    }

    /// @notice Execution result
    struct ExecutionResult {
        bool success;
        bytes returnData;
        uint256 gasUsed;
        uint256 amountOut;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidMessageType();
    error HandlerNotFound();
    error HandlerInactive();
    error DeadlineExpired();
    error InsufficientOutput();
    error ExecutionFailed(string reason);
    error InvalidPayload();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MessageCaught(
        bytes32 indexed messageId,
        MessageType indexed msgType,
        address sender,
        address recipient
    );
    event MessageExecuted(
        bytes32 indexed messageId,
        bool success,
        uint256 amountOut,
        uint256 gasUsed
    );
    event HandlerRegistered(
        MessageType indexed msgType,
        address handler,
        bytes4 selector
    );

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Message type => Handler info
    mapping(MessageType => HandlerInfo) public handlers;

    /// @dev Custom action selector => handler
    mapping(bytes4 => HandlerInfo) public customHandlers;

    /// @dev Message ID => execution result
    mapping(bytes32 => ExecutionResult) public results;

    /// @dev Authorized callers
    mapping(address => bool) public authorizedCallers;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /*//////////////////////////////////////////////////////////////
                    MESSAGE CATCHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Catch and process a message
    function catchMessage(
        bytes32 messageId,
        bytes calldata payload,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (ExecutionResult memory result) {
        require(authorizedCallers[msg.sender], "Unauthorized");

        // Decode message
        DecodedMessage memory decoded = decodeMessage(payload);

        emit MessageCaught(messageId, decoded.msgType, decoded.sender, decoded.recipient);

        // Check deadline
        if (decoded.deadline != 0 && block.timestamp > decoded.deadline) {
            revert DeadlineExpired();
        }

        // Get handler
        HandlerInfo memory handler = handlers[decoded.msgType];
        if (handler.handler == address(0)) revert HandlerNotFound();
        if (!handler.isActive) revert HandlerInactive();

        // Execute
        uint256 gasStart = gasleft();

        (bool success, bytes memory returnData) = handler.handler.call{gas: handler.gasLimit}(
            abi.encodeWithSelector(
                handler.selector,
                messageId,
                decoded,
                tokens,
                amounts
            )
        );

        result = ExecutionResult({
            success: success,
            returnData: returnData,
            gasUsed: gasStart - gasleft(),
            amountOut: success ? abi.decode(returnData, (uint256)) : 0
        });

        results[messageId] = result;

        emit MessageExecuted(messageId, success, result.amountOut, result.gasUsed);

        return result;
    }

    /// @notice Decode message payload
    function decodeMessage(bytes calldata payload)
        public pure returns (DecodedMessage memory decoded)
    {
        if (payload.length < 4) revert InvalidPayload();

        // First byte is message type
        uint8 msgTypeRaw = uint8(payload[0]);
        if (msgTypeRaw > uint8(MessageType.CUSTOM)) revert InvalidMessageType();

        decoded.msgType = MessageType(msgTypeRaw);

        // Decode based on message type
        if (decoded.msgType == MessageType.SWAP) {
            (
                ,
                decoded.sender,
                decoded.recipient,
                decoded.tokenIn,
                decoded.tokenOut,
                decoded.amountIn,
                decoded.amountOutMin,
                decoded.deadline,
                decoded.extraData
            ) = abi.decode(
                payload,
                (uint8, address, address, address, address, uint256, uint256, uint256, bytes)
            );
        } else if (decoded.msgType == MessageType.TRANSFER) {
            (
                ,
                decoded.sender,
                decoded.recipient,
                decoded.tokenIn,
                decoded.amountIn
            ) = abi.decode(
                payload,
                (uint8, address, address, address, uint256)
            );
        } else {
            // Generic decode for other types
            decoded.extraData = payload[1:];
        }
    }

    /// @notice Encode a swap message
    function encodeSwapMessage(
        address sender,
        address recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        return abi.encode(
            uint8(MessageType.SWAP),
            sender,
            recipient,
            tokenIn,
            tokenOut,
            amountIn,
            amountOutMin,
            deadline,
            extraData
        );
    }

    /// @notice Encode a transfer message
    function encodeTransferMessage(
        address sender,
        address recipient,
        address token,
        uint256 amount
    ) external pure returns (bytes memory) {
        return abi.encode(
            uint8(MessageType.TRANSFER),
            sender,
            recipient,
            token,
            amount
        );
    }

    /*//////////////////////////////////////////////////////////////
                    SPECIFIC HANDLERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle swap message
    function handleSwap(
        bytes32 messageId,
        DecodedMessage calldata msg_,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256 amountOut) {
        // This would integrate with DEX router
        // For now, simple transfer
        if (tokens.length > 0 && amounts.length > 0) {
            IERC20(tokens[0]).safeTransfer(msg_.recipient, amounts[0]);
            amountOut = amounts[0];
        }
    }

    /// @notice Handle transfer message
    function handleTransfer(
        bytes32,
        DecodedMessage calldata msg_,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256) {
        if (tokens.length > 0 && amounts.length > 0) {
            IERC20(tokens[0]).safeTransfer(msg_.recipient, amounts[0]);
            return amounts[0];
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function registerHandler(
        MessageType msgType,
        address handler,
        bytes4 selector,
        uint256 gasLimit
    ) external onlyOwner {
        handlers[msgType] = HandlerInfo({
            handler: handler,
            selector: selector,
            isActive: true,
            gasLimit: gasLimit
        });

        emit HandlerRegistered(msgType, handler, selector);
    }

    function registerCustomHandler(
        bytes4 actionSelector,
        address handler,
        bytes4 handlerSelector,
        uint256 gasLimit
    ) external onlyOwner {
        customHandlers[actionSelector] = HandlerInfo({
            handler: handler,
            selector: handlerSelector,
            isActive: true,
            gasLimit: gasLimit
        });
    }

    function setHandlerActive(MessageType msgType, bool active) external onlyOwner {
        handlers[msgType].isActive = active;
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    uint256[40] private __gap;
}
