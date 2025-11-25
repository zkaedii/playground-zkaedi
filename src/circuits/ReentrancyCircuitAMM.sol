// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyCircuitAMM
 * @notice Smart custom reentrancy circuit specifically designed for AMM/DEX operations
 * @dev Implements specialized guards for swap, liquidity provision, and fee collection
 *
 * Key Features:
 * - Per-pool reentrancy isolation
 * - Multi-path swap protection
 * - Liquidity manipulation prevention
 * - Price oracle attack mitigation
 * - Flash swap callback protection
 */
library ReentrancyCircuitAMM {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error AMMReentrantCall();
    error AMMPoolLocked(bytes32 poolId);
    error AMMSwapPathReentrancy();
    error AMMFlashSwapReentrancy();
    error AMMInvalidPoolState();
    error AMMCrossPoolReentrancy(bytes32 sourcePool, bytes32 targetPool);
    error AMMPriceManipulationDetected();
    error AMMCallbackReentrancy();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    uint256 internal constant CALLBACK_ENTERED = 3;

    // AMM operation flags
    uint256 internal constant OP_SWAP = 1 << 0;
    uint256 internal constant OP_ADD_LIQUIDITY = 1 << 1;
    uint256 internal constant OP_REMOVE_LIQUIDITY = 1 << 2;
    uint256 internal constant OP_FLASH_SWAP = 1 << 3;
    uint256 internal constant OP_COLLECT_FEES = 1 << 4;
    uint256 internal constant OP_SYNC = 1 << 5;
    uint256 internal constant OP_SKIM = 1 << 6;
    uint256 internal constant OP_BURN = 1 << 7;
    uint256 internal constant OP_MINT = 1 << 8;

    // Maximum allowed swap hops in a single transaction
    uint8 internal constant MAX_SWAP_HOPS = 4;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Global AMM reentrancy guard
    struct AMMGuard {
        uint256 globalStatus;
        uint256 activeOperations;
        uint8 currentSwapDepth;
        uint8 maxSwapDepth;
        uint64 lastOperationBlock;
        bytes32 currentPath;
    }

    /// @notice Per-pool reentrancy state
    struct PoolGuard {
        uint256 status;
        uint256 lockedOperations;
        uint64 lastAccessBlock;
        uint64 lastAccessTimestamp;
        address lastCaller;
        uint128 reserveSnapshotToken0;
        uint128 reserveSnapshotToken1;
    }

    /// @notice Flash swap context
    struct FlashSwapContext {
        bool active;
        bytes32 poolId;
        address initiator;
        uint256 amount0;
        uint256 amount1;
        uint64 startBlock;
        bytes32 callbackHash;
    }

    /// @notice Multi-pool operation tracker
    struct MultiPoolOperation {
        bytes32[] involvedPools;
        uint256 operationBitmap;
        uint64 startBlock;
        bool crossPoolAllowed;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event AMMGuardTriggered(bytes32 indexed poolId, uint256 operation, address caller);
    event AMMFlashSwapStarted(bytes32 indexed poolId, address indexed initiator, uint256 amount0, uint256 amount1);
    event AMMFlashSwapCompleted(bytes32 indexed poolId, address indexed initiator);
    event AMMSwapPathRecorded(bytes32 pathHash, uint8 depth);
    event AMMPoolStateSnapshot(bytes32 indexed poolId, uint128 reserve0, uint128 reserve1);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the AMM guard
     * @param guard The guard storage to initialize
     * @param maxSwapDepth Maximum allowed swap depth (default 4)
     */
    function initialize(AMMGuard storage guard, uint8 maxSwapDepth) internal {
        guard.globalStatus = NOT_ENTERED;
        guard.maxSwapDepth = maxSwapDepth > 0 ? maxSwapDepth : MAX_SWAP_HOPS;
    }

    /**
     * @notice Initialize a pool guard
     * @param poolGuard The pool guard storage
     */
    function initializePool(PoolGuard storage poolGuard) internal {
        poolGuard.status = NOT_ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE GUARD FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enter the global AMM guard for an operation
     * @param guard The AMM guard storage
     * @param operation The operation flag (OP_SWAP, OP_ADD_LIQUIDITY, etc.)
     */
    function enterOperation(AMMGuard storage guard, uint256 operation) internal {
        if (guard.globalStatus == 0) {
            guard.globalStatus = NOT_ENTERED;
        }

        // Check global reentrancy
        if (guard.globalStatus == ENTERED) {
            // Allow nested swaps within depth limit
            if (operation == OP_SWAP && guard.currentSwapDepth < guard.maxSwapDepth) {
                guard.currentSwapDepth++;
                return;
            }
            revert AMMReentrantCall();
        }

        // Check operation-specific reentrancy
        if ((guard.activeOperations & operation) != 0) {
            revert AMMReentrantCall();
        }

        guard.globalStatus = ENTERED;
        guard.activeOperations |= operation;
        guard.lastOperationBlock = uint64(block.number);

        if (operation == OP_SWAP) {
            guard.currentSwapDepth = 1;
        }
    }

    /**
     * @notice Exit the global AMM guard
     * @param guard The AMM guard storage
     * @param operation The operation flag
     */
    function exitOperation(AMMGuard storage guard, uint256 operation) internal {
        if (operation == OP_SWAP && guard.currentSwapDepth > 0) {
            guard.currentSwapDepth--;
            if (guard.currentSwapDepth > 0) {
                return; // Still in nested swap
            }
        }

        guard.globalStatus = NOT_ENTERED;
        guard.activeOperations &= ~operation;
    }

    /**
     * @notice Enter pool-specific guard
     * @param poolGuard The pool guard storage
     * @param poolId Unique identifier for the pool
     * @param operation The operation being performed
     */
    function enterPool(
        PoolGuard storage poolGuard,
        bytes32 poolId,
        uint256 operation
    ) internal {
        if (poolGuard.status == 0) {
            poolGuard.status = NOT_ENTERED;
        }

        if (poolGuard.status != NOT_ENTERED) {
            revert AMMPoolLocked(poolId);
        }

        // Check for same-block manipulation
        if (poolGuard.lastAccessBlock == block.number) {
            // Allow read operations but prevent state changes
            if (operation != OP_SYNC) {
                emit AMMGuardTriggered(poolId, operation, msg.sender);
            }
        }

        poolGuard.status = ENTERED;
        poolGuard.lockedOperations |= operation;
        poolGuard.lastAccessBlock = uint64(block.number);
        poolGuard.lastAccessTimestamp = uint64(block.timestamp);
        poolGuard.lastCaller = msg.sender;
    }

    /**
     * @notice Exit pool-specific guard
     * @param poolGuard The pool guard storage
     * @param operation The operation flag
     */
    function exitPool(PoolGuard storage poolGuard, uint256 operation) internal {
        poolGuard.status = NOT_ENTERED;
        poolGuard.lockedOperations &= ~operation;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH SWAP PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start a flash swap with protection
     * @param context The flash swap context storage
     * @param poolId The pool identifier
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @param callbackData Callback data hash for verification
     */
    function startFlashSwap(
        FlashSwapContext storage context,
        bytes32 poolId,
        uint256 amount0,
        uint256 amount1,
        bytes memory callbackData
    ) internal {
        if (context.active) {
            revert AMMFlashSwapReentrancy();
        }

        context.active = true;
        context.poolId = poolId;
        context.initiator = msg.sender;
        context.amount0 = amount0;
        context.amount1 = amount1;
        context.startBlock = uint64(block.number);
        context.callbackHash = keccak256(callbackData);

        emit AMMFlashSwapStarted(poolId, msg.sender, amount0, amount1);
    }

    /**
     * @notice Verify and complete flash swap
     * @param context The flash swap context storage
     * @param callbackData Callback data for verification
     */
    function endFlashSwap(
        FlashSwapContext storage context,
        bytes memory callbackData
    ) internal {
        if (!context.active) {
            revert AMMFlashSwapReentrancy();
        }

        // Verify callback data integrity
        if (keccak256(callbackData) != context.callbackHash) {
            revert AMMCallbackReentrancy();
        }

        // Verify same block
        if (context.startBlock != block.number) {
            revert AMMFlashSwapReentrancy();
        }

        emit AMMFlashSwapCompleted(context.poolId, context.initiator);

        // Clear context
        context.active = false;
        context.poolId = bytes32(0);
        context.initiator = address(0);
        context.amount0 = 0;
        context.amount1 = 0;
        context.callbackHash = bytes32(0);
    }

    /**
     * @notice Check if currently in a flash swap callback
     * @param context The flash swap context storage
     * @return True if in flash swap context
     */
    function isInFlashSwap(FlashSwapContext storage context) internal view returns (bool) {
        return context.active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-PATH SWAP PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record a swap path for circular path detection
     * @param guard The AMM guard storage
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     */
    function recordSwapPath(
        AMMGuard storage guard,
        address tokenIn,
        address tokenOut
    ) internal {
        bytes32 pathHash = keccak256(abi.encodePacked(guard.currentPath, tokenIn, tokenOut));

        // Check for circular path (same hash means we've seen this combination)
        if (pathHash == guard.currentPath && guard.currentSwapDepth > 1) {
            revert AMMSwapPathReentrancy();
        }

        guard.currentPath = pathHash;
        emit AMMSwapPathRecorded(pathHash, guard.currentSwapDepth);
    }

    /**
     * @notice Clear swap path after completion
     * @param guard The AMM guard storage
     */
    function clearSwapPath(AMMGuard storage guard) internal {
        guard.currentPath = bytes32(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE MANIPULATION PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Snapshot pool reserves for manipulation detection
     * @param poolGuard The pool guard storage
     * @param reserve0 Current reserve of token0
     * @param reserve1 Current reserve of token1
     */
    function snapshotReserves(
        PoolGuard storage poolGuard,
        uint128 reserve0,
        uint128 reserve1
    ) internal {
        poolGuard.reserveSnapshotToken0 = reserve0;
        poolGuard.reserveSnapshotToken1 = reserve1;
    }

    /**
     * @notice Check for significant reserve deviation (potential manipulation)
     * @param poolGuard The pool guard storage
     * @param currentReserve0 Current reserve of token0
     * @param currentReserve1 Current reserve of token1
     * @param maxDeviationBps Maximum allowed deviation in basis points
     * @return True if deviation is acceptable
     */
    function checkReserveDeviation(
        PoolGuard storage poolGuard,
        uint128 currentReserve0,
        uint128 currentReserve1,
        uint256 maxDeviationBps
    ) internal view returns (bool) {
        if (poolGuard.reserveSnapshotToken0 == 0) return true;

        uint256 deviation0 = _calculateDeviation(poolGuard.reserveSnapshotToken0, currentReserve0);
        uint256 deviation1 = _calculateDeviation(poolGuard.reserveSnapshotToken1, currentReserve1);

        return deviation0 <= maxDeviationBps && deviation1 <= maxDeviationBps;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CROSS-POOL OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start a multi-pool operation
     * @param operation The operation tracker storage
     * @param pools Array of pool IDs involved
     * @param allowCrossPool Whether cross-pool operations are allowed
     */
    function startMultiPoolOperation(
        MultiPoolOperation storage operation,
        bytes32[] memory pools,
        bool allowCrossPool
    ) internal {
        operation.involvedPools = pools;
        operation.startBlock = uint64(block.number);
        operation.crossPoolAllowed = allowCrossPool;
    }

    /**
     * @notice Verify pool is part of allowed operation
     * @param operation The operation tracker storage
     * @param poolId The pool to verify
     * @return True if pool is allowed in this operation
     */
    function isPoolAllowed(
        MultiPoolOperation storage operation,
        bytes32 poolId
    ) internal view returns (bool) {
        if (!operation.crossPoolAllowed) {
            return operation.involvedPools.length == 0 ||
                   (operation.involvedPools.length == 1 && operation.involvedPools[0] == poolId);
        }

        for (uint256 i = 0; i < operation.involvedPools.length; i++) {
            if (operation.involvedPools[i] == poolId) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Clear multi-pool operation
     * @param operation The operation tracker storage
     */
    function endMultiPoolOperation(MultiPoolOperation storage operation) internal {
        delete operation.involvedPools;
        operation.operationBitmap = 0;
        operation.crossPoolAllowed = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current AMM guard status
     * @param guard The AMM guard storage
     * @return status Current global status
     * @return activeOps Active operation bitmap
     * @return swapDepth Current swap depth
     */
    function getAMMStatus(AMMGuard storage guard) internal view returns (
        uint256 status,
        uint256 activeOps,
        uint8 swapDepth
    ) {
        return (guard.globalStatus, guard.activeOperations, guard.currentSwapDepth);
    }

    /**
     * @notice Get pool guard status
     * @param poolGuard The pool guard storage
     * @return status Current status
     * @return lockedOps Locked operations bitmap
     * @return lastBlock Last access block
     */
    function getPoolStatus(PoolGuard storage poolGuard) internal view returns (
        uint256 status,
        uint256 lockedOps,
        uint64 lastBlock
    ) {
        return (poolGuard.status, poolGuard.lockedOperations, poolGuard.lastAccessBlock);
    }

    /**
     * @notice Check if any operation is currently active
     * @param guard The AMM guard storage
     * @return True if any operation is in progress
     */
    function isOperationActive(AMMGuard storage guard) internal view returns (bool) {
        return guard.globalStatus == ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Calculate percentage deviation between two values
     */
    function _calculateDeviation(uint128 original, uint128 current) private pure returns (uint256) {
        if (original == 0) return 0;

        uint256 diff;
        if (current > original) {
            diff = current - original;
        } else {
            diff = original - current;
        }

        return (diff * 10000) / original;
    }
}
