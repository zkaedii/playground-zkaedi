// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyCircuitLending
 * @notice Smart custom reentrancy circuit designed for lending protocol operations
 * @dev Provides specialized guards for deposits, borrows, repayments, and liquidations
 *
 * Key Features:
 * - Per-market isolation
 * - Cross-collateral reentrancy prevention
 * - Liquidation cascade protection
 * - Interest accrual guards
 * - Oracle manipulation during borrow prevention
 */
library ReentrancyCircuitLending {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error LendingReentrantCall();
    error LendingMarketLocked(address market);
    error LendingCrossCollateralReentrancy();
    error LendingLiquidationCascade();
    error LendingOracleReentrancy();
    error LendingInterestAccrualLocked();
    error LendingBorrowDuringDeposit();
    error LendingInvalidMarketState();
    error LendingMaxOperationsExceeded();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    uint256 internal constant LIQUIDATION_ENTERED = 3;

    // Lending operation flags
    uint256 internal constant OP_DEPOSIT = 1 << 0;
    uint256 internal constant OP_WITHDRAW = 1 << 1;
    uint256 internal constant OP_BORROW = 1 << 2;
    uint256 internal constant OP_REPAY = 1 << 3;
    uint256 internal constant OP_LIQUIDATE = 1 << 4;
    uint256 internal constant OP_ACCRUE_INTEREST = 1 << 5;
    uint256 internal constant OP_SEIZE = 1 << 6;
    uint256 internal constant OP_TRANSFER = 1 << 7;
    uint256 internal constant OP_FLASH_LOAN = 1 << 8;
    uint256 internal constant OP_REDEEM = 1 << 9;

    // Forbidden operation combinations
    uint256 internal constant FORBIDDEN_BORROW_DURING_DEPOSIT = OP_DEPOSIT | OP_BORROW;
    uint256 internal constant FORBIDDEN_LIQUIDATE_DURING_BORROW = OP_BORROW | OP_LIQUIDATE;
    uint256 internal constant FORBIDDEN_WITHDRAW_DURING_LIQUIDATE = OP_WITHDRAW | OP_LIQUIDATE;

    // Maximum liquidation depth to prevent cascades
    uint8 internal constant MAX_LIQUIDATION_DEPTH = 3;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Global lending protocol guard
    struct LendingGuard {
        uint256 globalStatus;
        uint256 activeOperations;
        uint8 liquidationDepth;
        uint64 lastOperationBlock;
        address currentUser;
        bool oracleCallActive;
    }

    /// @notice Per-market reentrancy state
    struct MarketGuard {
        uint256 status;
        uint256 lockedOperations;
        uint64 lastInterestAccrual;
        uint64 lastAccessBlock;
        uint256 accruedInterestSnapshot;
        address lastBorrower;
    }

    /// @notice User position guard for cross-collateral protection
    struct UserPositionGuard {
        uint256 operationsInProgress;
        uint8 marketsInvolved;
        uint64 operationStartBlock;
        bool liquidationInProgress;
    }

    /// @notice Liquidation context
    struct LiquidationContext {
        bool active;
        address liquidator;
        address borrower;
        address collateralMarket;
        address borrowMarket;
        uint256 repayAmount;
        uint256 seizeAmount;
        uint64 startBlock;
        uint8 cascadeDepth;
    }

    /// @notice Interest rate model guard
    struct InterestGuard {
        bool accruing;
        uint64 lastAccrualBlock;
        uint256 borrowIndex;
        uint256 supplyIndex;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event LendingGuardTriggered(address indexed market, uint256 operation, address caller);
    event LiquidationStarted(address indexed borrower, address indexed liquidator, address collateral);
    event LiquidationCompleted(address indexed borrower, uint256 repayAmount, uint256 seizeAmount);
    event CrossCollateralOperationBlocked(address indexed user, uint8 marketsInvolved);
    event InterestAccrued(address indexed market, uint256 borrowIndex, uint256 supplyIndex);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the lending guard
     * @param guard The guard storage to initialize
     */
    function initialize(LendingGuard storage guard) internal {
        guard.globalStatus = NOT_ENTERED;
    }

    /**
     * @notice Initialize a market guard
     * @param marketGuard The market guard storage
     */
    function initializeMarket(MarketGuard storage marketGuard) internal {
        marketGuard.status = NOT_ENTERED;
        marketGuard.lastInterestAccrual = uint64(block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE GUARD FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enter the global lending guard for an operation
     * @param guard The lending guard storage
     * @param operation The operation flag
     */
    function enterOperation(LendingGuard storage guard, uint256 operation) internal {
        if (guard.globalStatus == 0) {
            guard.globalStatus = NOT_ENTERED;
        }

        // Check for forbidden combinations
        if (_isForbiddenCombination(guard.activeOperations | operation)) {
            revert LendingReentrantCall();
        }

        // Special handling for liquidations
        if (operation == OP_LIQUIDATE) {
            if (guard.liquidationDepth >= MAX_LIQUIDATION_DEPTH) {
                revert LendingLiquidationCascade();
            }
            guard.liquidationDepth++;
            guard.globalStatus = LIQUIDATION_ENTERED;
        } else if (guard.globalStatus == ENTERED) {
            // Allow certain nested operations
            if (!_isNestingAllowed(guard.activeOperations, operation)) {
                revert LendingReentrantCall();
            }
        } else {
            guard.globalStatus = ENTERED;
        }

        guard.activeOperations |= operation;
        guard.lastOperationBlock = uint64(block.number);
        guard.currentUser = msg.sender;
    }

    /**
     * @notice Exit the global lending guard
     * @param guard The lending guard storage
     * @param operation The operation flag
     */
    function exitOperation(LendingGuard storage guard, uint256 operation) internal {
        if (operation == OP_LIQUIDATE && guard.liquidationDepth > 0) {
            guard.liquidationDepth--;
        }

        guard.activeOperations &= ~operation;

        if (guard.activeOperations == 0) {
            guard.globalStatus = NOT_ENTERED;
            guard.currentUser = address(0);
        } else if (guard.liquidationDepth == 0 && guard.globalStatus == LIQUIDATION_ENTERED) {
            guard.globalStatus = ENTERED;
        }
    }

    /**
     * @notice Enter market-specific guard
     * @param marketGuard The market guard storage
     * @param market Market address
     * @param operation The operation being performed
     */
    function enterMarket(
        MarketGuard storage marketGuard,
        address market,
        uint256 operation
    ) internal {
        if (marketGuard.status == 0) {
            marketGuard.status = NOT_ENTERED;
        }

        if (marketGuard.status != NOT_ENTERED) {
            revert LendingMarketLocked(market);
        }

        // Check operation compatibility
        if ((marketGuard.lockedOperations & operation) != 0) {
            revert LendingMarketLocked(market);
        }

        marketGuard.status = ENTERED;
        marketGuard.lockedOperations |= operation;
        marketGuard.lastAccessBlock = uint64(block.number);

        emit LendingGuardTriggered(market, operation, msg.sender);
    }

    /**
     * @notice Exit market-specific guard
     * @param marketGuard The market guard storage
     * @param operation The operation flag
     */
    function exitMarket(MarketGuard storage marketGuard, uint256 operation) internal {
        marketGuard.status = NOT_ENTERED;
        marketGuard.lockedOperations &= ~operation;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER POSITION PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start user position operation
     * @param positionGuard The user position guard
     * @param operation The operation flag
     * @param marketCount Number of markets involved
     */
    function enterUserPosition(
        UserPositionGuard storage positionGuard,
        uint256 operation,
        uint8 marketCount
    ) internal {
        // Prevent multi-market manipulation in same block
        if (positionGuard.operationStartBlock == block.number &&
            positionGuard.marketsInvolved != marketCount) {
            revert LendingCrossCollateralReentrancy();
        }

        // Prevent operations during liquidation
        if (positionGuard.liquidationInProgress && operation != OP_SEIZE) {
            revert LendingCrossCollateralReentrancy();
        }

        positionGuard.operationsInProgress |= operation;
        positionGuard.marketsInvolved = marketCount;
        positionGuard.operationStartBlock = uint64(block.number);
    }

    /**
     * @notice Mark user as being liquidated
     * @param positionGuard The user position guard
     */
    function markLiquidationStarted(UserPositionGuard storage positionGuard) internal {
        positionGuard.liquidationInProgress = true;
    }

    /**
     * @notice Clear liquidation flag
     * @param positionGuard The user position guard
     */
    function markLiquidationEnded(UserPositionGuard storage positionGuard) internal {
        positionGuard.liquidationInProgress = false;
    }

    /**
     * @notice Exit user position operation
     * @param positionGuard The user position guard
     * @param operation The operation flag
     */
    function exitUserPosition(UserPositionGuard storage positionGuard, uint256 operation) internal {
        positionGuard.operationsInProgress &= ~operation;
        if (positionGuard.operationsInProgress == 0) {
            positionGuard.marketsInvolved = 0;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LIQUIDATION PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start a liquidation with protection
     * @param context The liquidation context storage
     * @param liquidator Address of the liquidator
     * @param borrower Address of the borrower
     * @param collateralMarket Collateral market address
     * @param borrowMarket Borrow market address
     * @param repayAmount Amount being repaid
     */
    function startLiquidation(
        LiquidationContext storage context,
        address liquidator,
        address borrower,
        address collateralMarket,
        address borrowMarket,
        uint256 repayAmount
    ) internal {
        if (context.active) {
            context.cascadeDepth++;
            if (context.cascadeDepth > MAX_LIQUIDATION_DEPTH) {
                revert LendingLiquidationCascade();
            }
        }

        context.active = true;
        context.liquidator = liquidator;
        context.borrower = borrower;
        context.collateralMarket = collateralMarket;
        context.borrowMarket = borrowMarket;
        context.repayAmount = repayAmount;
        context.startBlock = uint64(block.number);

        emit LiquidationStarted(borrower, liquidator, collateralMarket);
    }

    /**
     * @notice Record seize amount during liquidation
     * @param context The liquidation context
     * @param seizeAmount Amount of collateral seized
     */
    function recordSeize(LiquidationContext storage context, uint256 seizeAmount) internal {
        context.seizeAmount = seizeAmount;
    }

    /**
     * @notice Complete liquidation
     * @param context The liquidation context
     */
    function endLiquidation(LiquidationContext storage context) internal {
        if (!context.active) {
            revert LendingReentrantCall();
        }

        emit LiquidationCompleted(context.borrower, context.repayAmount, context.seizeAmount);

        if (context.cascadeDepth > 0) {
            context.cascadeDepth--;
        } else {
            // Clear full context
            context.active = false;
            context.liquidator = address(0);
            context.borrower = address(0);
            context.collateralMarket = address(0);
            context.borrowMarket = address(0);
            context.repayAmount = 0;
            context.seizeAmount = 0;
        }
    }

    /**
     * @notice Check if currently in liquidation
     * @param context The liquidation context
     * @return True if liquidation is in progress
     */
    function isLiquidationActive(LiquidationContext storage context) internal view returns (bool) {
        return context.active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEREST ACCRUAL PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start interest accrual with guard
     * @param interestGuard The interest guard storage
     */
    function startAccrueInterest(InterestGuard storage interestGuard) internal {
        if (interestGuard.accruing) {
            revert LendingInterestAccrualLocked();
        }

        interestGuard.accruing = true;
    }

    /**
     * @notice Complete interest accrual
     * @param interestGuard The interest guard
     * @param newBorrowIndex Updated borrow index
     * @param newSupplyIndex Updated supply index
     */
    function endAccrueInterest(
        InterestGuard storage interestGuard,
        uint256 newBorrowIndex,
        uint256 newSupplyIndex
    ) internal {
        interestGuard.accruing = false;
        interestGuard.lastAccrualBlock = uint64(block.number);
        interestGuard.borrowIndex = newBorrowIndex;
        interestGuard.supplyIndex = newSupplyIndex;
    }

    /**
     * @notice Check if interest is currently accruing
     * @param interestGuard The interest guard
     * @return True if accrual is in progress
     */
    function isAccruing(InterestGuard storage interestGuard) internal view returns (bool) {
        return interestGuard.accruing;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mark oracle call as active
     * @param guard The lending guard
     */
    function enterOracleCall(LendingGuard storage guard) internal {
        if (guard.oracleCallActive) {
            revert LendingOracleReentrancy();
        }
        guard.oracleCallActive = true;
    }

    /**
     * @notice Mark oracle call as complete
     * @param guard The lending guard
     */
    function exitOracleCall(LendingGuard storage guard) internal {
        guard.oracleCallActive = false;
    }

    /**
     * @notice Check if safe to call oracle (not in manipulation-prone state)
     * @param guard The lending guard
     * @return True if oracle call is safe
     */
    function isOracleCallSafe(LendingGuard storage guard) internal view returns (bool) {
        // Unsafe if in flash loan or liquidation
        return (guard.activeOperations & (OP_FLASH_LOAN | OP_LIQUIDATE)) == 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current lending guard status
     * @param guard The lending guard storage
     */
    function getLendingStatus(LendingGuard storage guard) internal view returns (
        uint256 status,
        uint256 activeOps,
        uint8 liquidationDepth,
        address currentUser
    ) {
        return (
            guard.globalStatus,
            guard.activeOperations,
            guard.liquidationDepth,
            guard.currentUser
        );
    }

    /**
     * @notice Get market guard status
     * @param marketGuard The market guard storage
     */
    function getMarketStatus(MarketGuard storage marketGuard) internal view returns (
        uint256 status,
        uint256 lockedOps,
        uint64 lastAccrual
    ) {
        return (
            marketGuard.status,
            marketGuard.lockedOperations,
            marketGuard.lastInterestAccrual
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Check if operation combination is forbidden
     */
    function _isForbiddenCombination(uint256 combinedOps) private pure returns (bool) {
        // Check specific forbidden combinations
        if ((combinedOps & FORBIDDEN_BORROW_DURING_DEPOSIT) == FORBIDDEN_BORROW_DURING_DEPOSIT) {
            return true;
        }
        if ((combinedOps & FORBIDDEN_LIQUIDATE_DURING_BORROW) == FORBIDDEN_LIQUIDATE_DURING_BORROW) {
            return true;
        }
        if ((combinedOps & FORBIDDEN_WITHDRAW_DURING_LIQUIDATE) == FORBIDDEN_WITHDRAW_DURING_LIQUIDATE) {
            return true;
        }
        return false;
    }

    /**
     * @dev Check if nesting is allowed for operations
     */
    function _isNestingAllowed(uint256 current, uint256 newOp) private pure returns (bool) {
        // Allow interest accrual to nest with anything
        if (newOp == OP_ACCRUE_INTEREST) return true;

        // Allow seize during liquidation
        if (newOp == OP_SEIZE && (current & OP_LIQUIDATE) != 0) return true;

        // Allow transfer during redeem
        if (newOp == OP_TRANSFER && (current & OP_REDEEM) != 0) return true;

        return false;
    }
}
