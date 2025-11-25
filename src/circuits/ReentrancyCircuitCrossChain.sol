// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyCircuitCrossChain
 * @notice Smart custom reentrancy circuit for cross-chain bridge and messaging operations
 * @dev Implements specialized guards for bridge deposits, withdrawals, and message relaying
 *
 * Key Features:
 * - Per-chain isolation
 * - Message replay protection
 * - Bridge callback reentrancy prevention
 * - Cross-chain arbitrage protection
 * - Nonce-based execution ordering
 */
library ReentrancyCircuitCrossChain {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error CrossChainReentrantCall();
    error CrossChainBridgeLocked(uint256 chainId);
    error CrossChainMessageReplay(bytes32 messageId);
    error CrossChainCallbackReentrancy();
    error CrossChainInvalidNonce(uint256 expected, uint256 received);
    error CrossChainExecutionPending();
    error CrossChainSourceBlocked(uint256 sourceChainId);
    error CrossChainMaxDepthExceeded();
    error CrossChainInvalidState();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    uint256 internal constant CALLBACK_ENTERED = 3;
    uint256 internal constant RELAY_ENTERED = 4;

    // Cross-chain operation flags
    uint256 internal constant OP_BRIDGE_DEPOSIT = 1 << 0;
    uint256 internal constant OP_BRIDGE_WITHDRAW = 1 << 1;
    uint256 internal constant OP_MESSAGE_SEND = 1 << 2;
    uint256 internal constant OP_MESSAGE_RECEIVE = 1 << 3;
    uint256 internal constant OP_CALLBACK_EXECUTE = 1 << 4;
    uint256 internal constant OP_RELAY = 1 << 5;
    uint256 internal constant OP_FINALIZE = 1 << 6;
    uint256 internal constant OP_PROVE = 1 << 7;
    uint256 internal constant OP_CHALLENGE = 1 << 8;

    // Maximum allowed cross-chain operation depth
    uint8 internal constant MAX_CROSS_CHAIN_DEPTH = 2;

    // Message expiry time (default 24 hours)
    uint64 internal constant MESSAGE_EXPIRY = 86400;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Global cross-chain guard
    struct CrossChainGuard {
        uint256 globalStatus;
        uint256 activeOperations;
        uint8 operationDepth;
        uint64 lastOperationBlock;
        uint256 currentSourceChain;
        bytes32 currentMessageId;
    }

    /// @notice Per-chain bridge state
    struct ChainBridgeGuard {
        uint256 status;
        uint256 lockedOperations;
        uint64 lastBridgeBlock;
        uint64 lastBridgeTimestamp;
        uint256 pendingInbound;
        uint256 pendingOutbound;
        uint256 nonce;
    }

    /// @notice Message execution context
    struct MessageContext {
        bytes32 messageId;
        uint256 sourceChainId;
        uint256 targetChainId;
        address sender;
        address receiver;
        uint64 timestamp;
        uint256 nonce;
        bool executed;
        bool reverted;
    }

    /// @notice Callback protection
    struct CallbackGuard {
        bool active;
        bytes32 expectedCallbackId;
        address expectedCaller;
        uint64 startBlock;
        bytes32 dataHash;
    }

    /// @notice Relay operation tracker
    struct RelayOperation {
        bool active;
        uint256 sourceChainId;
        bytes32 messageHash;
        uint64 submittedBlock;
        address relayer;
        uint256 gasLimit;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event CrossChainGuardTriggered(uint256 indexed chainId, uint256 operation, address caller);
    event CrossChainMessageQueued(bytes32 indexed messageId, uint256 sourceChain, uint256 targetChain);
    event CrossChainMessageExecuted(bytes32 indexed messageId, bool success);
    event CrossChainCallbackStarted(bytes32 indexed callbackId, address caller);
    event CrossChainCallbackCompleted(bytes32 indexed callbackId, bool success);
    event CrossChainBridgeLockChanged(uint256 indexed chainId, bool locked);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the cross-chain guard
     * @param guard The guard storage to initialize
     */
    function initialize(CrossChainGuard storage guard) internal {
        guard.globalStatus = NOT_ENTERED;
    }

    /**
     * @notice Initialize a chain bridge guard
     * @param bridgeGuard The bridge guard storage
     */
    function initializeChainBridge(ChainBridgeGuard storage bridgeGuard) internal {
        bridgeGuard.status = NOT_ENTERED;
        bridgeGuard.nonce = 1; // Start at 1 to differentiate from uninitialized
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE GUARD FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enter the global cross-chain guard
     * @param guard The cross-chain guard storage
     * @param operation The operation flag
     * @param sourceChainId Source chain identifier (0 for outbound)
     */
    function enterOperation(
        CrossChainGuard storage guard,
        uint256 operation,
        uint256 sourceChainId
    ) internal {
        if (guard.globalStatus == 0) {
            guard.globalStatus = NOT_ENTERED;
        }

        // Allow limited nesting for relay operations
        if (guard.globalStatus != NOT_ENTERED) {
            if (guard.operationDepth >= MAX_CROSS_CHAIN_DEPTH) {
                revert CrossChainMaxDepthExceeded();
            }
            // Only allow specific nested operations
            if (!_isNestingAllowed(guard.activeOperations, operation)) {
                revert CrossChainReentrantCall();
            }
            guard.operationDepth++;
        } else {
            guard.globalStatus = ENTERED;
            guard.operationDepth = 1;
        }

        guard.activeOperations |= operation;
        guard.lastOperationBlock = uint64(block.number);
        guard.currentSourceChain = sourceChainId;
    }

    /**
     * @notice Exit the global cross-chain guard
     * @param guard The cross-chain guard storage
     * @param operation The operation flag
     */
    function exitOperation(CrossChainGuard storage guard, uint256 operation) internal {
        guard.activeOperations &= ~operation;

        if (guard.operationDepth > 0) {
            guard.operationDepth--;
        }

        if (guard.operationDepth == 0) {
            guard.globalStatus = NOT_ENTERED;
            guard.currentSourceChain = 0;
            guard.currentMessageId = bytes32(0);
        }
    }

    /**
     * @notice Enter chain-specific bridge guard
     * @param bridgeGuard The bridge guard storage
     * @param chainId The chain identifier
     * @param operation The operation being performed
     */
    function enterChainBridge(
        ChainBridgeGuard storage bridgeGuard,
        uint256 chainId,
        uint256 operation
    ) internal {
        if (bridgeGuard.status == 0) {
            bridgeGuard.status = NOT_ENTERED;
        }

        if (bridgeGuard.status != NOT_ENTERED) {
            revert CrossChainBridgeLocked(chainId);
        }

        bridgeGuard.status = ENTERED;
        bridgeGuard.lockedOperations |= operation;
        bridgeGuard.lastBridgeBlock = uint64(block.number);
        bridgeGuard.lastBridgeTimestamp = uint64(block.timestamp);

        emit CrossChainGuardTriggered(chainId, operation, msg.sender);
    }

    /**
     * @notice Exit chain-specific bridge guard
     * @param bridgeGuard The bridge guard storage
     * @param operation The operation flag
     */
    function exitChainBridge(ChainBridgeGuard storage bridgeGuard, uint256 operation) internal {
        bridgeGuard.status = NOT_ENTERED;
        bridgeGuard.lockedOperations &= ~operation;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MESSAGE PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create and protect a message context
     * @param context The message context storage
     * @param sourceChainId Source chain ID
     * @param targetChainId Target chain ID
     * @param sender Message sender
     * @param receiver Message receiver
     * @param nonce Message nonce
     * @return messageId Unique message identifier
     */
    function createMessageContext(
        MessageContext storage context,
        uint256 sourceChainId,
        uint256 targetChainId,
        address sender,
        address receiver,
        uint256 nonce
    ) internal returns (bytes32 messageId) {
        messageId = keccak256(abi.encodePacked(
            sourceChainId,
            targetChainId,
            sender,
            receiver,
            nonce,
            block.timestamp
        ));

        context.messageId = messageId;
        context.sourceChainId = sourceChainId;
        context.targetChainId = targetChainId;
        context.sender = sender;
        context.receiver = receiver;
        context.timestamp = uint64(block.timestamp);
        context.nonce = nonce;
        context.executed = false;
        context.reverted = false;

        emit CrossChainMessageQueued(messageId, sourceChainId, targetChainId);
    }

    /**
     * @notice Mark message as executed
     * @param context The message context
     * @param success Whether execution succeeded
     */
    function markMessageExecuted(MessageContext storage context, bool success) internal {
        if (context.executed) {
            revert CrossChainMessageReplay(context.messageId);
        }

        context.executed = true;
        context.reverted = !success;

        emit CrossChainMessageExecuted(context.messageId, success);
    }

    /**
     * @notice Check if message is valid and not expired
     * @param context The message context
     * @return True if message can be executed
     */
    function isMessageValid(MessageContext storage context) internal view returns (bool) {
        if (context.executed) return false;
        if (context.messageId == bytes32(0)) return false;
        if (block.timestamp > context.timestamp + MESSAGE_EXPIRY) return false;
        return true;
    }

    /**
     * @notice Verify message nonce ordering
     * @param bridgeGuard The bridge guard
     * @param expectedNonce Expected nonce value
     */
    function verifyNonce(
        ChainBridgeGuard storage bridgeGuard,
        uint256 expectedNonce
    ) internal view {
        if (bridgeGuard.nonce != expectedNonce) {
            revert CrossChainInvalidNonce(bridgeGuard.nonce, expectedNonce);
        }
    }

    /**
     * @notice Increment bridge nonce
     * @param bridgeGuard The bridge guard
     * @return newNonce The new nonce value
     */
    function incrementNonce(ChainBridgeGuard storage bridgeGuard) internal returns (uint256 newNonce) {
        newNonce = ++bridgeGuard.nonce;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLBACK PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start callback with protection
     * @param callbackGuard The callback guard storage
     * @param callbackId Expected callback identifier
     * @param expectedCaller Expected callback caller
     * @param data Callback data for verification
     */
    function startCallback(
        CallbackGuard storage callbackGuard,
        bytes32 callbackId,
        address expectedCaller,
        bytes memory data
    ) internal {
        if (callbackGuard.active) {
            revert CrossChainCallbackReentrancy();
        }

        callbackGuard.active = true;
        callbackGuard.expectedCallbackId = callbackId;
        callbackGuard.expectedCaller = expectedCaller;
        callbackGuard.startBlock = uint64(block.number);
        callbackGuard.dataHash = keccak256(data);

        emit CrossChainCallbackStarted(callbackId, expectedCaller);
    }

    /**
     * @notice Verify callback and complete
     * @param callbackGuard The callback guard
     * @param callbackId Callback ID to verify
     * @param data Callback data to verify
     * @return success True if callback is valid
     */
    function verifyAndCompleteCallback(
        CallbackGuard storage callbackGuard,
        bytes32 callbackId,
        bytes memory data
    ) internal returns (bool success) {
        if (!callbackGuard.active) {
            revert CrossChainCallbackReentrancy();
        }

        // Verify callback identity
        success = callbackGuard.expectedCallbackId == callbackId &&
                  callbackGuard.expectedCaller == msg.sender &&
                  callbackGuard.dataHash == keccak256(data) &&
                  callbackGuard.startBlock == block.number;

        emit CrossChainCallbackCompleted(callbackId, success);

        // Clear callback state
        callbackGuard.active = false;
        callbackGuard.expectedCallbackId = bytes32(0);
        callbackGuard.expectedCaller = address(0);
        callbackGuard.dataHash = bytes32(0);
    }

    /**
     * @notice Check if callback is pending
     * @param callbackGuard The callback guard
     * @return True if callback is active
     */
    function isCallbackPending(CallbackGuard storage callbackGuard) internal view returns (bool) {
        return callbackGuard.active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RELAY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start relay operation
     * @param relay The relay operation storage
     * @param sourceChainId Source chain ID
     * @param messageHash Hash of the message being relayed
     * @param gasLimit Gas limit for execution
     */
    function startRelay(
        RelayOperation storage relay,
        uint256 sourceChainId,
        bytes32 messageHash,
        uint256 gasLimit
    ) internal {
        if (relay.active) {
            revert CrossChainExecutionPending();
        }

        relay.active = true;
        relay.sourceChainId = sourceChainId;
        relay.messageHash = messageHash;
        relay.submittedBlock = uint64(block.number);
        relay.relayer = msg.sender;
        relay.gasLimit = gasLimit;
    }

    /**
     * @notice Complete relay operation
     * @param relay The relay operation storage
     */
    function endRelay(RelayOperation storage relay) internal {
        relay.active = false;
        relay.sourceChainId = 0;
        relay.messageHash = bytes32(0);
        relay.relayer = address(0);
        relay.gasLimit = 0;
    }

    /**
     * @notice Check if relay is in progress
     * @param relay The relay operation
     * @return True if relay is active
     */
    function isRelayActive(RelayOperation storage relay) internal view returns (bool) {
        return relay.active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PENDING OPERATION TRACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Track pending inbound operation
     * @param bridgeGuard The bridge guard
     */
    function incrementPendingInbound(ChainBridgeGuard storage bridgeGuard) internal {
        bridgeGuard.pendingInbound++;
    }

    /**
     * @notice Track pending outbound operation
     * @param bridgeGuard The bridge guard
     */
    function incrementPendingOutbound(ChainBridgeGuard storage bridgeGuard) internal {
        bridgeGuard.pendingOutbound++;
    }

    /**
     * @notice Finalize inbound operation
     * @param bridgeGuard The bridge guard
     */
    function decrementPendingInbound(ChainBridgeGuard storage bridgeGuard) internal {
        if (bridgeGuard.pendingInbound > 0) {
            bridgeGuard.pendingInbound--;
        }
    }

    /**
     * @notice Finalize outbound operation
     * @param bridgeGuard The bridge guard
     */
    function decrementPendingOutbound(ChainBridgeGuard storage bridgeGuard) internal {
        if (bridgeGuard.pendingOutbound > 0) {
            bridgeGuard.pendingOutbound--;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get cross-chain guard status
     * @param guard The cross-chain guard
     */
    function getCrossChainStatus(CrossChainGuard storage guard) internal view returns (
        uint256 status,
        uint256 activeOps,
        uint8 depth,
        uint256 sourceChain
    ) {
        return (
            guard.globalStatus,
            guard.activeOperations,
            guard.operationDepth,
            guard.currentSourceChain
        );
    }

    /**
     * @notice Get bridge guard status
     * @param bridgeGuard The bridge guard
     */
    function getBridgeStatus(ChainBridgeGuard storage bridgeGuard) internal view returns (
        uint256 status,
        uint256 pendingIn,
        uint256 pendingOut,
        uint256 nonce
    ) {
        return (
            bridgeGuard.status,
            bridgeGuard.pendingInbound,
            bridgeGuard.pendingOutbound,
            bridgeGuard.nonce
        );
    }

    /**
     * @notice Check if operations are safe for a source chain
     * @param guard The cross-chain guard
     * @param sourceChainId The source chain to check
     * @return True if operations from this chain are allowed
     */
    function isSourceChainAllowed(
        CrossChainGuard storage guard,
        uint256 sourceChainId
    ) internal view returns (bool) {
        // Don't allow if already processing from same source
        if (guard.currentSourceChain == sourceChainId && guard.globalStatus == ENTERED) {
            return false;
        }
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Check if nesting is allowed for operations
     */
    function _isNestingAllowed(uint256 current, uint256 newOp) private pure returns (bool) {
        // Allow callback execution during message receive
        if (newOp == OP_CALLBACK_EXECUTE && (current & OP_MESSAGE_RECEIVE) != 0) {
            return true;
        }

        // Allow finalize during relay
        if (newOp == OP_FINALIZE && (current & OP_RELAY) != 0) {
            return true;
        }

        // Allow prove during challenge
        if (newOp == OP_PROVE && (current & OP_CHALLENGE) != 0) {
            return true;
        }

        return false;
    }
}
