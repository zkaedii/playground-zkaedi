// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyCircuitVault
 * @notice Smart custom reentrancy circuit for vault and yield aggregator operations
 * @dev Implements ERC-4626 compliant protection with strategy and harvest guards
 *
 * Key Features:
 * - Deposit/withdraw atomic operation protection
 * - Strategy execution isolation
 * - Harvest callback protection
 * - Share price manipulation prevention
 * - Multi-strategy vault protection
 */
library ReentrancyCircuitVault {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error VaultReentrantCall();
    error VaultOperationLocked();
    error VaultStrategyLocked(address strategy);
    error VaultHarvestInProgress();
    error VaultSharePriceManipulation();
    error VaultMaxStrategiesExceeded();
    error VaultInvalidStrategyState();
    error VaultWithdrawDuringHarvest();
    error VaultDepositDuringRebalance();
    error VaultEmergencyActive();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    uint256 internal constant HARVEST_ENTERED = 3;
    uint256 internal constant EMERGENCY_ENTERED = 4;

    // Vault operation flags
    uint256 internal constant OP_DEPOSIT = 1 << 0;
    uint256 internal constant OP_WITHDRAW = 1 << 1;
    uint256 internal constant OP_HARVEST = 1 << 2;
    uint256 internal constant OP_REBALANCE = 1 << 3;
    uint256 internal constant OP_STRATEGY_DEPOSIT = 1 << 4;
    uint256 internal constant OP_STRATEGY_WITHDRAW = 1 << 5;
    uint256 internal constant OP_COMPOUND = 1 << 6;
    uint256 internal constant OP_EMERGENCY_EXIT = 1 << 7;
    uint256 internal constant OP_UPDATE_STRATEGY = 1 << 8;
    uint256 internal constant OP_REPORT = 1 << 9;

    // Maximum strategies per vault
    uint8 internal constant MAX_STRATEGIES = 20;

    // Share price deviation threshold (basis points)
    uint256 internal constant MAX_SHARE_PRICE_DEVIATION = 100; // 1%

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Global vault guard
    struct VaultGuard {
        uint256 status;
        uint256 activeOperations;
        uint64 lastOperationBlock;
        uint8 activeStrategies;
        bool harvestInProgress;
        bool emergencyActive;
    }

    /// @notice Per-strategy guard
    struct StrategyGuard {
        uint256 status;
        uint256 lockedOperations;
        uint64 lastHarvestBlock;
        uint64 lastReportBlock;
        uint256 lastReportedGain;
        uint256 lastReportedLoss;
        bool migrating;
    }

    /// @notice Deposit/withdraw operation context
    struct VaultOperationContext {
        bool active;
        address user;
        uint256 assets;
        uint256 shares;
        uint256 sharePriceSnapshot;
        uint64 startBlock;
        bool isDeposit;
    }

    /// @notice Harvest context
    struct HarvestContext {
        bool active;
        address strategy;
        uint256 expectedGain;
        uint256 actualGain;
        uint256 loss;
        uint64 startBlock;
        bytes32 reportHash;
    }

    /// @notice Share price protection
    struct SharePriceGuard {
        uint256 lastPrice;
        uint64 lastUpdateBlock;
        uint256 priceFloor;
        uint256 priceCeiling;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event VaultGuardTriggered(uint256 operation, address caller);
    event VaultOperationStarted(bool isDeposit, address indexed user, uint256 assets);
    event VaultOperationCompleted(bool isDeposit, address indexed user, uint256 shares);
    event VaultHarvestStarted(address indexed strategy);
    event VaultHarvestCompleted(address indexed strategy, uint256 gain, uint256 loss);
    event VaultSharePriceSnapshot(uint256 price, uint64 block_);
    event VaultEmergencyActivated(address indexed caller);
    event VaultEmergencyDeactivated(address indexed caller);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the vault guard
     * @param guard The guard storage to initialize
     */
    function initialize(VaultGuard storage guard) internal {
        guard.status = NOT_ENTERED;
    }

    /**
     * @notice Initialize a strategy guard
     * @param strategyGuard The strategy guard storage
     */
    function initializeStrategy(StrategyGuard storage strategyGuard) internal {
        strategyGuard.status = NOT_ENTERED;
    }

    /**
     * @notice Initialize share price guard
     * @param priceGuard The price guard storage
     * @param initialPrice Initial share price
     */
    function initializeSharePriceGuard(
        SharePriceGuard storage priceGuard,
        uint256 initialPrice
    ) internal {
        priceGuard.lastPrice = initialPrice;
        priceGuard.lastUpdateBlock = uint64(block.number);
        priceGuard.priceFloor = initialPrice * (10000 - MAX_SHARE_PRICE_DEVIATION) / 10000;
        priceGuard.priceCeiling = initialPrice * (10000 + MAX_SHARE_PRICE_DEVIATION) / 10000;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE VAULT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enter vault operation guard
     * @param guard The vault guard
     * @param operation The operation flag
     */
    function enterOperation(VaultGuard storage guard, uint256 operation) internal {
        if (guard.status == 0) {
            guard.status = NOT_ENTERED;
        }

        // Check emergency state
        if (guard.emergencyActive && operation != OP_EMERGENCY_EXIT && operation != OP_WITHDRAW) {
            revert VaultEmergencyActive();
        }

        // Check forbidden combinations
        if (_isForbiddenCombination(guard.activeOperations, operation)) {
            revert VaultReentrantCall();
        }

        // Special states
        if (operation == OP_HARVEST) {
            guard.status = HARVEST_ENTERED;
            guard.harvestInProgress = true;
        } else if (operation == OP_EMERGENCY_EXIT) {
            guard.status = EMERGENCY_ENTERED;
        } else if (guard.status != NOT_ENTERED && !_isNestingAllowed(guard.activeOperations, operation)) {
            revert VaultReentrantCall();
        } else {
            guard.status = ENTERED;
        }

        guard.activeOperations |= operation;
        guard.lastOperationBlock = uint64(block.number);

        emit VaultGuardTriggered(operation, msg.sender);
    }

    /**
     * @notice Exit vault operation guard
     * @param guard The vault guard
     * @param operation The operation flag
     */
    function exitOperation(VaultGuard storage guard, uint256 operation) internal {
        guard.activeOperations &= ~operation;

        if (operation == OP_HARVEST) {
            guard.harvestInProgress = false;
        }

        if (guard.activeOperations == 0) {
            if (!guard.emergencyActive) {
                guard.status = NOT_ENTERED;
            } else {
                guard.status = EMERGENCY_ENTERED;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT/WITHDRAW PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start a deposit/withdraw operation
     * @param context The operation context
     * @param priceGuard The share price guard
     * @param user User address
     * @param assets Asset amount
     * @param currentSharePrice Current share price
     * @param isDeposit True for deposit, false for withdraw
     */
    function startVaultOperation(
        VaultOperationContext storage context,
        SharePriceGuard storage priceGuard,
        address user,
        uint256 assets,
        uint256 currentSharePrice,
        bool isDeposit
    ) internal {
        if (context.active) {
            revert VaultOperationLocked();
        }

        // Check share price bounds
        _verifySharePrice(priceGuard, currentSharePrice);

        context.active = true;
        context.user = user;
        context.assets = assets;
        context.sharePriceSnapshot = currentSharePrice;
        context.startBlock = uint64(block.number);
        context.isDeposit = isDeposit;

        emit VaultOperationStarted(isDeposit, user, assets);
    }

    /**
     * @notice Complete a deposit/withdraw operation
     * @param context The operation context
     * @param priceGuard The share price guard
     * @param shares Resulting shares
     * @param finalSharePrice Share price after operation
     */
    function completeVaultOperation(
        VaultOperationContext storage context,
        SharePriceGuard storage priceGuard,
        uint256 shares,
        uint256 finalSharePrice
    ) internal {
        if (!context.active) {
            revert VaultReentrantCall();
        }

        // Verify share price didn't deviate too much during operation
        uint256 deviation = _calculateDeviation(context.sharePriceSnapshot, finalSharePrice);
        if (deviation > MAX_SHARE_PRICE_DEVIATION) {
            revert VaultSharePriceManipulation();
        }

        context.shares = shares;

        // Update price guard
        _updateSharePriceGuard(priceGuard, finalSharePrice);

        emit VaultOperationCompleted(context.isDeposit, context.user, shares);

        // Clear context
        _clearOperationContext(context);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRATEGY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enter strategy guard
     * @param strategyGuard The strategy guard
     * @param strategy Strategy address
     * @param operation The operation flag
     */
    function enterStrategy(
        StrategyGuard storage strategyGuard,
        address strategy,
        uint256 operation
    ) internal {
        if (strategyGuard.status == 0) {
            strategyGuard.status = NOT_ENTERED;
        }

        if (strategyGuard.status != NOT_ENTERED) {
            revert VaultStrategyLocked(strategy);
        }

        if (strategyGuard.migrating && operation != OP_STRATEGY_WITHDRAW) {
            revert VaultInvalidStrategyState();
        }

        strategyGuard.status = ENTERED;
        strategyGuard.lockedOperations |= operation;
    }

    /**
     * @notice Exit strategy guard
     * @param strategyGuard The strategy guard
     * @param operation The operation flag
     */
    function exitStrategy(StrategyGuard storage strategyGuard, uint256 operation) internal {
        strategyGuard.status = NOT_ENTERED;
        strategyGuard.lockedOperations &= ~operation;
    }

    /**
     * @notice Mark strategy as migrating
     * @param strategyGuard The strategy guard
     */
    function markStrategyMigrating(StrategyGuard storage strategyGuard) internal {
        strategyGuard.migrating = true;
    }

    /**
     * @notice Complete strategy migration
     * @param strategyGuard The strategy guard
     */
    function completeStrategyMigration(StrategyGuard storage strategyGuard) internal {
        strategyGuard.migrating = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HARVEST PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start harvest operation
     * @param guard The vault guard
     * @param harvestContext The harvest context
     * @param strategy Strategy being harvested
     * @param expectedGain Expected gain from harvest
     */
    function startHarvest(
        VaultGuard storage guard,
        HarvestContext storage harvestContext,
        address strategy,
        uint256 expectedGain
    ) internal {
        if (harvestContext.active) {
            revert VaultHarvestInProgress();
        }

        enterOperation(guard, OP_HARVEST);

        harvestContext.active = true;
        harvestContext.strategy = strategy;
        harvestContext.expectedGain = expectedGain;
        harvestContext.startBlock = uint64(block.number);
        harvestContext.reportHash = keccak256(abi.encodePacked(strategy, expectedGain, block.number));

        emit VaultHarvestStarted(strategy);
    }

    /**
     * @notice Record harvest results
     * @param harvestContext The harvest context
     * @param actualGain Actual gain
     * @param loss Actual loss
     */
    function recordHarvestResults(
        HarvestContext storage harvestContext,
        uint256 actualGain,
        uint256 loss
    ) internal {
        if (!harvestContext.active) {
            revert VaultReentrantCall();
        }

        harvestContext.actualGain = actualGain;
        harvestContext.loss = loss;
    }

    /**
     * @notice Complete harvest operation
     * @param guard The vault guard
     * @param harvestContext The harvest context
     * @param strategyGuard The strategy guard
     */
    function completeHarvest(
        VaultGuard storage guard,
        HarvestContext storage harvestContext,
        StrategyGuard storage strategyGuard
    ) internal {
        if (!harvestContext.active) {
            revert VaultReentrantCall();
        }

        // Update strategy report data
        strategyGuard.lastHarvestBlock = uint64(block.number);
        strategyGuard.lastReportBlock = uint64(block.number);
        strategyGuard.lastReportedGain = harvestContext.actualGain;
        strategyGuard.lastReportedLoss = harvestContext.loss;

        emit VaultHarvestCompleted(
            harvestContext.strategy,
            harvestContext.actualGain,
            harvestContext.loss
        );

        // Clear harvest context
        harvestContext.active = false;
        harvestContext.strategy = address(0);
        harvestContext.expectedGain = 0;
        harvestContext.actualGain = 0;
        harvestContext.loss = 0;
        harvestContext.reportHash = bytes32(0);

        exitOperation(guard, OP_HARVEST);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Activate emergency mode
     * @param guard The vault guard
     */
    function activateEmergency(VaultGuard storage guard) internal {
        guard.emergencyActive = true;
        guard.status = EMERGENCY_ENTERED;
        emit VaultEmergencyActivated(msg.sender);
    }

    /**
     * @notice Deactivate emergency mode
     * @param guard The vault guard
     */
    function deactivateEmergency(VaultGuard storage guard) internal {
        guard.emergencyActive = false;
        if (guard.activeOperations == 0) {
            guard.status = NOT_ENTERED;
        }
        emit VaultEmergencyDeactivated(msg.sender);
    }

    /**
     * @notice Check if emergency is active
     * @param guard The vault guard
     * @return True if emergency mode active
     */
    function isEmergencyActive(VaultGuard storage guard) internal view returns (bool) {
        return guard.emergencyActive;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SHARE PRICE PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update share price bounds
     * @param priceGuard The price guard
     * @param newDeviationBps New deviation in basis points
     */
    function updateSharePriceBounds(
        SharePriceGuard storage priceGuard,
        uint256 newDeviationBps
    ) internal {
        priceGuard.priceFloor = priceGuard.lastPrice * (10000 - newDeviationBps) / 10000;
        priceGuard.priceCeiling = priceGuard.lastPrice * (10000 + newDeviationBps) / 10000;
    }

    /**
     * @notice Get current share price bounds
     * @param priceGuard The price guard
     */
    function getSharePriceBounds(SharePriceGuard storage priceGuard) internal view returns (
        uint256 lastPrice,
        uint256 floor,
        uint256 ceiling
    ) {
        return (priceGuard.lastPrice, priceGuard.priceFloor, priceGuard.priceCeiling);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get vault guard status
     * @param guard The vault guard
     */
    function getVaultStatus(VaultGuard storage guard) internal view returns (
        uint256 status,
        uint256 activeOps,
        bool harvesting,
        bool emergency
    ) {
        return (
            guard.status,
            guard.activeOperations,
            guard.harvestInProgress,
            guard.emergencyActive
        );
    }

    /**
     * @notice Get strategy guard status
     * @param strategyGuard The strategy guard
     */
    function getStrategyStatus(StrategyGuard storage strategyGuard) internal view returns (
        uint256 status,
        uint64 lastHarvest,
        uint256 lastGain,
        uint256 lastLoss,
        bool migrating
    ) {
        return (
            strategyGuard.status,
            strategyGuard.lastHarvestBlock,
            strategyGuard.lastReportedGain,
            strategyGuard.lastReportedLoss,
            strategyGuard.migrating
        );
    }

    /**
     * @notice Check if vault operation is in progress
     * @param guard The vault guard
     * @return True if any operation active
     */
    function isOperationActive(VaultGuard storage guard) internal view returns (bool) {
        return guard.status != NOT_ENTERED;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _isForbiddenCombination(uint256 current, uint256 newOp) private pure returns (bool) {
        // Cannot withdraw during harvest
        if ((current & OP_HARVEST) != 0 && newOp == OP_WITHDRAW) {
            return true;
        }
        // Cannot deposit during rebalance
        if ((current & OP_REBALANCE) != 0 && newOp == OP_DEPOSIT) {
            return true;
        }
        // Cannot update strategy during harvest
        if ((current & OP_HARVEST) != 0 && newOp == OP_UPDATE_STRATEGY) {
            return true;
        }
        return false;
    }

    function _isNestingAllowed(uint256 current, uint256 newOp) private pure returns (bool) {
        // Allow compound during harvest
        if (newOp == OP_COMPOUND && (current & OP_HARVEST) != 0) return true;
        // Allow strategy operations during rebalance
        if ((newOp == OP_STRATEGY_DEPOSIT || newOp == OP_STRATEGY_WITHDRAW) &&
            (current & OP_REBALANCE) != 0) return true;
        // Allow report during harvest
        if (newOp == OP_REPORT && (current & OP_HARVEST) != 0) return true;
        return false;
    }

    function _verifySharePrice(SharePriceGuard storage priceGuard, uint256 currentPrice) private view {
        if (priceGuard.lastPrice == 0) return;

        if (currentPrice < priceGuard.priceFloor || currentPrice > priceGuard.priceCeiling) {
            revert VaultSharePriceManipulation();
        }
    }

    function _updateSharePriceGuard(SharePriceGuard storage priceGuard, uint256 newPrice) private {
        priceGuard.lastPrice = newPrice;
        priceGuard.lastUpdateBlock = uint64(block.number);
        priceGuard.priceFloor = newPrice * (10000 - MAX_SHARE_PRICE_DEVIATION) / 10000;
        priceGuard.priceCeiling = newPrice * (10000 + MAX_SHARE_PRICE_DEVIATION) / 10000;

        emit VaultSharePriceSnapshot(newPrice, uint64(block.number));
    }

    function _calculateDeviation(uint256 original, uint256 current) private pure returns (uint256) {
        if (original == 0) return 0;

        uint256 diff;
        if (current > original) {
            diff = current - original;
        } else {
            diff = original - current;
        }

        return (diff * 10000) / original;
    }

    function _clearOperationContext(VaultOperationContext storage context) private {
        context.active = false;
        context.user = address(0);
        context.assets = 0;
        context.shares = 0;
        context.sharePriceSnapshot = 0;
        context.isDeposit = false;
    }
}
