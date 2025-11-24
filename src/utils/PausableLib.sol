// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PausableLib
 * @notice Comprehensive pausability library with granular control and emergency patterns
 * @dev Implements global pause, function-level pause, tiered pausing, and automatic unpause
 */
library PausableLib {
    // ============ ERRORS ============
    error ContractPaused();
    error ContractNotPaused();
    error FunctionPaused(bytes4 selector);
    error FunctionNotPaused(bytes4 selector);
    error TierPaused(uint8 tier);
    error TierNotPaused(uint8 tier);
    error InvalidPauseDuration(uint256 duration);
    error AutoUnpauseNotReady(uint256 currentTime, uint256 unpauseTime);
    error EmergencyAlreadyActive();
    error NoEmergencyActive();
    error CooldownNotExpired(uint256 currentTime, uint256 cooldownEnd);
    error MaxPauseDurationExceeded(uint256 requested, uint256 maximum);
    error InvalidTier(uint8 tier);

    // ============ CONSTANTS ============
    uint256 internal constant MAX_PAUSE_DURATION = 30 days;
    uint256 internal constant MIN_PAUSE_DURATION = 1 hours;
    uint256 internal constant DEFAULT_PAUSE_DURATION = 7 days;
    uint256 internal constant COOLDOWN_PERIOD = 1 days;
    uint256 internal constant EMERGENCY_DURATION = 24 hours;

    // Pause tiers (lower number = more critical)
    uint8 internal constant TIER_CRITICAL = 0;    // Full system pause
    uint8 internal constant TIER_HIGH = 1;        // High-risk operations
    uint8 internal constant TIER_MEDIUM = 2;      // Medium-risk operations
    uint8 internal constant TIER_LOW = 3;         // Low-risk operations
    uint8 internal constant MAX_TIERS = 4;

    // Function categories for granular pausing
    uint256 internal constant CATEGORY_DEPOSITS = 1 << 0;
    uint256 internal constant CATEGORY_WITHDRAWALS = 1 << 1;
    uint256 internal constant CATEGORY_SWAPS = 1 << 2;
    uint256 internal constant CATEGORY_BORROWS = 1 << 3;
    uint256 internal constant CATEGORY_LIQUIDATIONS = 1 << 4;
    uint256 internal constant CATEGORY_GOVERNANCE = 1 << 5;
    uint256 internal constant CATEGORY_REWARDS = 1 << 6;
    uint256 internal constant CATEGORY_BRIDGING = 1 << 7;
    uint256 internal constant CATEGORY_MINTING = 1 << 8;
    uint256 internal constant CATEGORY_BURNING = 1 << 9;

    // ============ TYPES ============
    struct PauseState {
        bool paused;
        uint256 pausedAt;
        uint256 unpauseAt;    // 0 = indefinite pause
        address pausedBy;
        string reason;
    }

    struct GranularPauseState {
        bool globalPaused;
        uint256 pausedCategories;  // Bitmap of paused categories
        mapping(bytes4 => bool) functionPaused;
        mapping(uint8 => bool) tierPaused;
        uint256 pausedAt;
        uint256 unpauseAt;
        uint256 lastUnpauseAt;  // For cooldown tracking
    }

    struct EmergencyState {
        bool active;
        uint256 activatedAt;
        uint256 expiresAt;
        address activatedBy;
        bytes32 emergencyType;
        string description;
    }

    struct PauseHistory {
        uint256 totalPauses;
        uint256 totalDuration;
        uint256 lastPausedAt;
        uint256 lastUnpausedAt;
    }

    // ============ EVENTS ============
    event Paused(address indexed account, string reason);
    event Unpaused(address indexed account);
    event FunctionPausedEvent(bytes4 indexed selector, address indexed account);
    event FunctionUnpausedEvent(bytes4 indexed selector, address indexed account);
    event TierPausedEvent(uint8 indexed tier, address indexed account);
    event TierUnpausedEvent(uint8 indexed tier, address indexed account);
    event CategoryPaused(uint256 indexed category, address indexed account);
    event CategoryUnpaused(uint256 indexed category, address indexed account);
    event EmergencyActivated(bytes32 indexed emergencyType, address indexed activatedBy, uint256 expiresAt);
    event EmergencyDeactivated(bytes32 indexed emergencyType, address indexed deactivatedBy);
    event AutoUnpauseScheduled(uint256 unpauseAt);
    event AutoUnpauseExecuted(uint256 timestamp);

    // ============ BASIC PAUSE FUNCTIONS ============

    /**
     * @notice Pause the contract
     * @param state The pause state storage
     * @param reason The reason for pausing
     */
    function pause(PauseState storage state, string memory reason) internal {
        if (state.paused) revert ContractPaused();

        state.paused = true;
        state.pausedAt = block.timestamp;
        state.pausedBy = msg.sender;
        state.reason = reason;
        state.unpauseAt = 0; // Indefinite

        emit Paused(msg.sender, reason);
    }

    /**
     * @notice Pause with auto-unpause
     * @param state The pause state storage
     * @param reason The reason for pausing
     * @param duration The pause duration in seconds
     */
    function pauseFor(
        PauseState storage state,
        string memory reason,
        uint256 duration
    ) internal {
        if (state.paused) revert ContractPaused();
        if (duration < MIN_PAUSE_DURATION) revert InvalidPauseDuration(duration);
        if (duration > MAX_PAUSE_DURATION) revert MaxPauseDurationExceeded(duration, MAX_PAUSE_DURATION);

        state.paused = true;
        state.pausedAt = block.timestamp;
        state.pausedBy = msg.sender;
        state.reason = reason;
        state.unpauseAt = block.timestamp + duration;

        emit Paused(msg.sender, reason);
        emit AutoUnpauseScheduled(state.unpauseAt);
    }

    /**
     * @notice Unpause the contract
     * @param state The pause state storage
     */
    function unpause(PauseState storage state) internal {
        if (!state.paused) revert ContractNotPaused();

        state.paused = false;
        state.pausedAt = 0;
        state.unpauseAt = 0;
        state.pausedBy = address(0);
        state.reason = "";

        emit Unpaused(msg.sender);
    }

    /**
     * @notice Execute auto-unpause if time has passed
     * @param state The pause state storage
     * @return True if auto-unpause was executed
     */
    function tryAutoUnpause(PauseState storage state) internal returns (bool) {
        if (!state.paused) return false;
        if (state.unpauseAt == 0) return false; // Indefinite pause
        if (block.timestamp < state.unpauseAt) return false;

        state.paused = false;
        state.pausedAt = 0;
        state.unpauseAt = 0;
        state.pausedBy = address(0);
        state.reason = "";

        emit AutoUnpauseExecuted(block.timestamp);
        emit Unpaused(address(this));
        return true;
    }

    /**
     * @notice Check if paused (with auto-unpause check)
     * @param state The pause state storage
     * @return True if currently paused
     */
    function isPaused(PauseState storage state) internal returns (bool) {
        tryAutoUnpause(state);
        return state.paused;
    }

    /**
     * @notice Check if paused (view only, no auto-unpause)
     * @param state The pause state storage
     * @return True if currently paused
     */
    function isPausedView(PauseState storage state) internal view returns (bool) {
        if (!state.paused) return false;
        if (state.unpauseAt != 0 && block.timestamp >= state.unpauseAt) return false;
        return true;
    }

    /**
     * @notice Require not paused (revert if paused)
     * @param state The pause state storage
     */
    function requireNotPaused(PauseState storage state) internal {
        if (isPaused(state)) revert ContractPaused();
    }

    /**
     * @notice Require paused (revert if not paused)
     * @param state The pause state storage
     */
    function requirePaused(PauseState storage state) internal view {
        if (!state.paused) revert ContractNotPaused();
    }

    // ============ GRANULAR PAUSE FUNCTIONS ============

    /**
     * @notice Global pause with granular state
     * @param state The granular pause state
     */
    function globalPause(GranularPauseState storage state) internal {
        if (state.globalPaused) revert ContractPaused();

        state.globalPaused = true;
        state.pausedAt = block.timestamp;

        emit Paused(msg.sender, "Global pause");
    }

    /**
     * @notice Global unpause
     * @param state The granular pause state
     */
    function globalUnpause(GranularPauseState storage state) internal {
        if (!state.globalPaused) revert ContractNotPaused();

        // Check cooldown
        if (state.lastUnpauseAt != 0 &&
            block.timestamp < state.lastUnpauseAt + COOLDOWN_PERIOD) {
            revert CooldownNotExpired(block.timestamp, state.lastUnpauseAt + COOLDOWN_PERIOD);
        }

        state.globalPaused = false;
        state.pausedAt = 0;
        state.lastUnpauseAt = block.timestamp;

        emit Unpaused(msg.sender);
    }

    /**
     * @notice Pause a specific function
     * @param state The granular pause state
     * @param selector The function selector to pause
     */
    function pauseFunction(GranularPauseState storage state, bytes4 selector) internal {
        if (state.functionPaused[selector]) revert FunctionPaused(selector);

        state.functionPaused[selector] = true;

        emit FunctionPausedEvent(selector, msg.sender);
    }

    /**
     * @notice Unpause a specific function
     * @param state The granular pause state
     * @param selector The function selector to unpause
     */
    function unpauseFunction(GranularPauseState storage state, bytes4 selector) internal {
        if (!state.functionPaused[selector]) revert FunctionNotPaused(selector);

        state.functionPaused[selector] = false;

        emit FunctionUnpausedEvent(selector, msg.sender);
    }

    /**
     * @notice Check if a function is paused
     * @param state The granular pause state
     * @param selector The function selector to check
     * @return True if the function is paused
     */
    function isFunctionPaused(
        GranularPauseState storage state,
        bytes4 selector
    ) internal view returns (bool) {
        return state.globalPaused || state.functionPaused[selector];
    }

    /**
     * @notice Require function not paused
     * @param state The granular pause state
     * @param selector The function selector to check
     */
    function requireFunctionNotPaused(
        GranularPauseState storage state,
        bytes4 selector
    ) internal view {
        if (state.globalPaused) revert ContractPaused();
        if (state.functionPaused[selector]) revert FunctionPaused(selector);
    }

    // ============ CATEGORY-BASED PAUSING ============

    /**
     * @notice Pause a category of functions
     * @param state The granular pause state
     * @param category The category flag to pause
     */
    function pauseCategory(GranularPauseState storage state, uint256 category) internal {
        state.pausedCategories |= category;
        emit CategoryPaused(category, msg.sender);
    }

    /**
     * @notice Unpause a category of functions
     * @param state The granular pause state
     * @param category The category flag to unpause
     */
    function unpauseCategory(GranularPauseState storage state, uint256 category) internal {
        state.pausedCategories &= ~category;
        emit CategoryUnpaused(category, msg.sender);
    }

    /**
     * @notice Check if a category is paused
     * @param state The granular pause state
     * @param category The category flag to check
     * @return True if the category is paused
     */
    function isCategoryPaused(
        GranularPauseState storage state,
        uint256 category
    ) internal view returns (bool) {
        return state.globalPaused || (state.pausedCategories & category) != 0;
    }

    /**
     * @notice Require category not paused
     * @param state The granular pause state
     * @param category The category flag to check
     */
    function requireCategoryNotPaused(
        GranularPauseState storage state,
        uint256 category
    ) internal view {
        if (state.globalPaused) revert ContractPaused();
        if ((state.pausedCategories & category) != 0) revert ContractPaused();
    }

    // ============ TIER-BASED PAUSING ============

    /**
     * @notice Pause a tier and all lower tiers
     * @param state The granular pause state
     * @param tier The tier to pause
     */
    function pauseTier(GranularPauseState storage state, uint8 tier) internal {
        if (tier >= MAX_TIERS) revert InvalidTier(tier);

        // Pause this tier and all higher-risk (lower number) tiers
        for (uint8 i = 0; i <= tier; i++) {
            state.tierPaused[i] = true;
            emit TierPausedEvent(i, msg.sender);
        }
    }

    /**
     * @notice Unpause a tier
     * @param state The granular pause state
     * @param tier The tier to unpause
     */
    function unpauseTier(GranularPauseState storage state, uint8 tier) internal {
        if (tier >= MAX_TIERS) revert InvalidTier(tier);
        if (!state.tierPaused[tier]) revert TierNotPaused(tier);

        state.tierPaused[tier] = false;
        emit TierUnpausedEvent(tier, msg.sender);
    }

    /**
     * @notice Check if a tier is paused
     * @param state The granular pause state
     * @param tier The tier to check
     * @return True if the tier is paused
     */
    function isTierPaused(
        GranularPauseState storage state,
        uint8 tier
    ) internal view returns (bool) {
        if (tier >= MAX_TIERS) revert InvalidTier(tier);
        return state.globalPaused || state.tierPaused[tier];
    }

    // ============ EMERGENCY FUNCTIONS ============

    /**
     * @notice Activate emergency mode
     * @param state The emergency state
     * @param emergencyType The type of emergency
     * @param description Description of the emergency
     */
    function activateEmergency(
        EmergencyState storage state,
        bytes32 emergencyType,
        string memory description
    ) internal {
        if (state.active) revert EmergencyAlreadyActive();

        state.active = true;
        state.activatedAt = block.timestamp;
        state.expiresAt = block.timestamp + EMERGENCY_DURATION;
        state.activatedBy = msg.sender;
        state.emergencyType = emergencyType;
        state.description = description;

        emit EmergencyActivated(emergencyType, msg.sender, state.expiresAt);
    }

    /**
     * @notice Deactivate emergency mode
     * @param state The emergency state
     */
    function deactivateEmergency(EmergencyState storage state) internal {
        if (!state.active) revert NoEmergencyActive();

        bytes32 emergencyType = state.emergencyType;

        state.active = false;
        state.activatedAt = 0;
        state.expiresAt = 0;
        state.activatedBy = address(0);
        state.emergencyType = bytes32(0);
        state.description = "";

        emit EmergencyDeactivated(emergencyType, msg.sender);
    }

    /**
     * @notice Check and auto-deactivate expired emergency
     * @param state The emergency state
     * @return True if emergency is still active
     */
    function isEmergencyActive(EmergencyState storage state) internal returns (bool) {
        if (!state.active) return false;

        if (block.timestamp >= state.expiresAt) {
            deactivateEmergency(state);
            return false;
        }

        return true;
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Get pause info
     * @param state The pause state
     * @return paused Whether currently paused
     * @return pausedAt When paused
     * @return unpauseAt When auto-unpause is scheduled (0 if indefinite)
     * @return pausedBy Who paused
     * @return reason The pause reason
     */
    function getPauseInfo(
        PauseState storage state
    ) internal view returns (
        bool paused,
        uint256 pausedAt,
        uint256 unpauseAt,
        address pausedBy,
        string memory reason
    ) {
        return (
            state.paused,
            state.pausedAt,
            state.unpauseAt,
            state.pausedBy,
            state.reason
        );
    }

    /**
     * @notice Get time until auto-unpause
     * @param state The pause state
     * @return remaining Time remaining in seconds (0 if not scheduled or not paused)
     */
    function timeUntilUnpause(PauseState storage state) internal view returns (uint256 remaining) {
        if (!state.paused || state.unpauseAt == 0) return 0;
        if (block.timestamp >= state.unpauseAt) return 0;
        return state.unpauseAt - block.timestamp;
    }

    /**
     * @notice Batch pause multiple functions
     * @param state The granular pause state
     * @param selectors Array of function selectors to pause
     */
    function batchPauseFunctions(
        GranularPauseState storage state,
        bytes4[] memory selectors
    ) internal {
        for (uint256 i = 0; i < selectors.length; i++) {
            if (!state.functionPaused[selectors[i]]) {
                state.functionPaused[selectors[i]] = true;
                emit FunctionPausedEvent(selectors[i], msg.sender);
            }
        }
    }

    /**
     * @notice Batch unpause multiple functions
     * @param state The granular pause state
     * @param selectors Array of function selectors to unpause
     */
    function batchUnpauseFunctions(
        GranularPauseState storage state,
        bytes4[] memory selectors
    ) internal {
        for (uint256 i = 0; i < selectors.length; i++) {
            if (state.functionPaused[selectors[i]]) {
                state.functionPaused[selectors[i]] = false;
                emit FunctionUnpausedEvent(selectors[i], msg.sender);
            }
        }
    }
}
