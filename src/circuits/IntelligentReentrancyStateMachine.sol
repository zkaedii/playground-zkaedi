// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IntelligentReentrancyStateMachine
 * @notice Intelligent reentrancy circuit using finite state machine with transition rules
 * @dev Implements formal state machine verification for complex multi-step operations
 *
 * Key Features:
 * - Formal state machine with defined transitions
 * - Invalid transition detection
 * - State history tracking for forensics
 * - Timeout-based state recovery
 * - Conditional transition guards
 */
library IntelligentReentrancyStateMachine {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error SMInvalidTransition(uint8 from, uint8 to);
    error SMStateTimeout(uint8 state, uint64 elapsed);
    error SMReentrantTransition();
    error SMInvalidState(uint8 state);
    error SMGuardConditionFailed(bytes32 condition);
    error SMMaxHistoryExceeded();
    error SMStateNotInitialized();
    error SMConcurrentTransition();
    error SMInvalidRollback();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    // State definitions
    uint8 internal constant STATE_IDLE = 0;
    uint8 internal constant STATE_INITIALIZING = 1;
    uint8 internal constant STATE_READY = 2;
    uint8 internal constant STATE_EXECUTING = 3;
    uint8 internal constant STATE_CALLBACK = 4;
    uint8 internal constant STATE_COMPLETING = 5;
    uint8 internal constant STATE_FINALIZING = 6;
    uint8 internal constant STATE_ERROR = 7;
    uint8 internal constant STATE_PAUSED = 8;
    uint8 internal constant STATE_RECOVERING = 9;

    uint8 internal constant MAX_STATES = 10;

    // Transition flags (packed into bitmap)
    // Format: (from_state * 16 + to_state) bit position
    uint256 internal constant VALID_TRANSITIONS =
        (1 << (STATE_IDLE * 16 + STATE_INITIALIZING)) |
        (1 << (STATE_INITIALIZING * 16 + STATE_READY)) |
        (1 << (STATE_READY * 16 + STATE_EXECUTING)) |
        (1 << (STATE_EXECUTING * 16 + STATE_CALLBACK)) |
        (1 << (STATE_EXECUTING * 16 + STATE_COMPLETING)) |
        (1 << (STATE_CALLBACK * 16 + STATE_EXECUTING)) |
        (1 << (STATE_CALLBACK * 16 + STATE_COMPLETING)) |
        (1 << (STATE_COMPLETING * 16 + STATE_FINALIZING)) |
        (1 << (STATE_FINALIZING * 16 + STATE_IDLE)) |
        (1 << (STATE_FINALIZING * 16 + STATE_READY)) |
        // Error transitions (any state can go to error)
        (1 << (STATE_EXECUTING * 16 + STATE_ERROR)) |
        (1 << (STATE_CALLBACK * 16 + STATE_ERROR)) |
        (1 << (STATE_COMPLETING * 16 + STATE_ERROR)) |
        // Recovery transitions
        (1 << (STATE_ERROR * 16 + STATE_RECOVERING)) |
        (1 << (STATE_RECOVERING * 16 + STATE_IDLE)) |
        // Pause transitions
        (1 << (STATE_READY * 16 + STATE_PAUSED)) |
        (1 << (STATE_PAUSED * 16 + STATE_READY));

    // Default state timeout (5 minutes)
    uint64 internal constant DEFAULT_STATE_TIMEOUT = 300;

    // Maximum history entries
    uint8 internal constant MAX_HISTORY = 50;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice State machine configuration
    struct StateMachineConfig {
        uint256 validTransitions;
        uint64 defaultTimeout;
        bool requiresGuardConditions;
        bool trackHistory;
        bool allowRollback;
    }

    /// @notice State machine instance
    struct StateMachine {
        uint8 currentState;
        uint8 previousState;
        uint64 stateEnteredAt;
        uint64 lastTransitionBlock;
        address lastTransitionCaller;
        bool transitioning;
        bytes32 stateData;
    }

    /// @notice Transition history entry
    struct TransitionEntry {
        uint8 fromState;
        uint8 toState;
        uint64 timestamp;
        uint64 blockNumber;
        address caller;
        bytes32 reason;
    }

    /// @notice State history tracker
    struct StateHistory {
        TransitionEntry[] entries;
        uint8 currentIndex;
        bool wrapped;
    }

    /// @notice Guard condition for transitions
    struct TransitionGuard {
        bytes32 conditionHash;
        bool required;
        bool satisfied;
    }

    /// @notice State timeout configuration
    struct StateTimeouts {
        mapping(uint8 => uint64) timeouts;
        bool enforced;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event StateTransition(uint8 indexed from, uint8 indexed to, address caller, bytes32 reason);
    event StateTimeout(uint8 indexed state, uint64 elapsed);
    event InvalidTransitionAttempt(uint8 indexed from, uint8 indexed to, address caller);
    event GuardConditionChecked(bytes32 indexed condition, bool satisfied);
    event StateRecoveryInitiated(uint8 indexed fromState, address initiator);
    event StateRollback(uint8 indexed from, uint8 indexed to, bytes32 reason);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize state machine with default configuration
     * @param machine The state machine storage
     */
    function initialize(StateMachine storage machine) internal {
        machine.currentState = STATE_IDLE;
        machine.previousState = STATE_IDLE;
        machine.stateEnteredAt = uint64(block.timestamp);
        machine.lastTransitionBlock = uint64(block.number);
    }

    /**
     * @notice Initialize with custom configuration
     * @param machine The state machine storage
     * @param config Configuration settings
     */
    function initializeWithConfig(
        StateMachine storage machine,
        StateMachineConfig memory config
    ) internal {
        initialize(machine);
        // Config is stored separately if needed
    }

    /**
     * @notice Initialize state history
     * @param history The history storage
     */
    function initializeHistory(StateHistory storage history) internal {
        // History starts empty, entries are added dynamically
        history.currentIndex = 0;
        history.wrapped = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Transition to a new state
     * @param machine The state machine
     * @param newState Target state
     * @param reason Reason for transition
     */
    function transition(
        StateMachine storage machine,
        uint8 newState,
        bytes32 reason
    ) internal {
        uint8 currentState = machine.currentState;

        // Prevent concurrent transitions
        if (machine.transitioning) {
            revert SMConcurrentTransition();
        }

        // Validate transition
        if (!isValidTransition(currentState, newState)) {
            emit InvalidTransitionAttempt(currentState, newState, msg.sender);
            revert SMInvalidTransition(currentState, newState);
        }

        // Mark transitioning
        machine.transitioning = true;

        // Update state
        machine.previousState = currentState;
        machine.currentState = newState;
        machine.stateEnteredAt = uint64(block.timestamp);
        machine.lastTransitionBlock = uint64(block.number);
        machine.lastTransitionCaller = msg.sender;

        // Clear transitioning flag
        machine.transitioning = false;

        emit StateTransition(currentState, newState, msg.sender, reason);
    }

    /**
     * @notice Transition with guard condition
     * @param machine The state machine
     * @param guard The guard condition
     * @param newState Target state
     * @param reason Reason for transition
     */
    function transitionWithGuard(
        StateMachine storage machine,
        TransitionGuard storage guard,
        uint8 newState,
        bytes32 reason
    ) internal {
        // Check guard condition
        if (guard.required && !guard.satisfied) {
            emit GuardConditionChecked(guard.conditionHash, false);
            revert SMGuardConditionFailed(guard.conditionHash);
        }

        emit GuardConditionChecked(guard.conditionHash, true);

        // Clear guard after use
        guard.satisfied = false;

        transition(machine, newState, reason);
    }

    /**
     * @notice Safe transition with timeout check
     * @param machine The state machine
     * @param timeouts Timeout configuration
     * @param newState Target state
     * @param reason Reason for transition
     */
    function safeTransition(
        StateMachine storage machine,
        StateTimeouts storage timeouts,
        uint8 newState,
        bytes32 reason
    ) internal {
        // Check if current state has timed out
        if (timeouts.enforced) {
            uint64 timeout = timeouts.timeouts[machine.currentState];
            if (timeout > 0) {
                uint64 elapsed = uint64(block.timestamp) - machine.stateEnteredAt;
                if (elapsed > timeout) {
                    emit StateTimeout(machine.currentState, elapsed);
                    // Force to error state instead
                    transition(machine, STATE_ERROR, "STATE_TIMEOUT");
                    return;
                }
            }
        }

        transition(machine, newState, reason);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if a transition is valid
     * @param from Source state
     * @param to Target state
     * @return True if transition is valid
     */
    function isValidTransition(uint8 from, uint8 to) internal pure returns (bool) {
        if (from >= MAX_STATES || to >= MAX_STATES) {
            return false;
        }

        uint256 transitionBit = 1 << (from * 16 + to);
        return (VALID_TRANSITIONS & transitionBit) != 0;
    }

    /**
     * @notice Check if currently in a specific state
     * @param machine The state machine
     * @param expectedState Expected state
     * @return True if in expected state
     */
    function isInState(StateMachine storage machine, uint8 expectedState) internal view returns (bool) {
        return machine.currentState == expectedState;
    }

    /**
     * @notice Check if state machine is idle
     * @param machine The state machine
     * @return True if idle
     */
    function isIdle(StateMachine storage machine) internal view returns (bool) {
        return machine.currentState == STATE_IDLE;
    }

    /**
     * @notice Check if state machine is in error state
     * @param machine The state machine
     * @return True if in error
     */
    function isInError(StateMachine storage machine) internal view returns (bool) {
        return machine.currentState == STATE_ERROR;
    }

    /**
     * @notice Check if currently transitioning
     * @param machine The state machine
     * @return True if transition in progress
     */
    function isTransitioning(StateMachine storage machine) internal view returns (bool) {
        return machine.transitioning;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GUARD CONDITIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set guard condition
     * @param guard The guard storage
     * @param conditionHash Hash identifying the condition
     */
    function setGuardCondition(TransitionGuard storage guard, bytes32 conditionHash) internal {
        guard.conditionHash = conditionHash;
        guard.required = true;
        guard.satisfied = false;
    }

    /**
     * @notice Satisfy guard condition
     * @param guard The guard storage
     * @param conditionHash Hash to verify
     */
    function satisfyGuard(TransitionGuard storage guard, bytes32 conditionHash) internal {
        if (guard.conditionHash != conditionHash) {
            revert SMGuardConditionFailed(conditionHash);
        }
        guard.satisfied = true;
    }

    /**
     * @notice Clear guard condition
     * @param guard The guard storage
     */
    function clearGuard(TransitionGuard storage guard) internal {
        guard.conditionHash = bytes32(0);
        guard.required = false;
        guard.satisfied = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE HISTORY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record transition in history
     * @param history The history storage
     * @param from Source state
     * @param to Target state
     * @param reason Transition reason
     */
    function recordTransition(
        StateHistory storage history,
        uint8 from,
        uint8 to,
        bytes32 reason
    ) internal {
        TransitionEntry memory entry = TransitionEntry({
            fromState: from,
            toState: to,
            timestamp: uint64(block.timestamp),
            blockNumber: uint64(block.number),
            caller: msg.sender,
            reason: reason
        });

        if (history.entries.length < MAX_HISTORY) {
            history.entries.push(entry);
        } else {
            history.entries[history.currentIndex] = entry;
            history.wrapped = true;
        }

        history.currentIndex = (history.currentIndex + 1) % MAX_HISTORY;
    }

    /**
     * @notice Get recent transitions
     * @param history The history storage
     * @param count Number of entries to retrieve
     * @return entries Array of recent entries
     */
    function getRecentTransitions(
        StateHistory storage history,
        uint8 count
    ) internal view returns (TransitionEntry[] memory entries) {
        uint256 available = history.wrapped ? MAX_HISTORY : history.entries.length;
        uint256 toReturn = count > available ? available : count;

        entries = new TransitionEntry[](toReturn);

        for (uint256 i = 0; i < toReturn; i++) {
            uint256 idx = (history.currentIndex + MAX_HISTORY - 1 - i) % MAX_HISTORY;
            if (idx < history.entries.length) {
                entries[i] = history.entries[idx];
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE RECOVERY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initiate state recovery
     * @param machine The state machine
     */
    function initiateRecovery(StateMachine storage machine) internal {
        uint8 currentState = machine.currentState;

        // Can only recover from error state
        if (currentState != STATE_ERROR) {
            revert SMInvalidState(currentState);
        }

        emit StateRecoveryInitiated(currentState, msg.sender);

        machine.previousState = currentState;
        machine.currentState = STATE_RECOVERING;
        machine.stateEnteredAt = uint64(block.timestamp);
        machine.lastTransitionCaller = msg.sender;
    }

    /**
     * @notice Complete recovery and return to idle
     * @param machine The state machine
     */
    function completeRecovery(StateMachine storage machine) internal {
        if (machine.currentState != STATE_RECOVERING) {
            revert SMInvalidState(machine.currentState);
        }

        transition(machine, STATE_IDLE, "RECOVERY_COMPLETE");
    }

    /**
     * @notice Rollback to previous state
     * @param machine The state machine
     * @param reason Rollback reason
     */
    function rollback(StateMachine storage machine, bytes32 reason) internal {
        uint8 current = machine.currentState;
        uint8 previous = machine.previousState;

        // Validate rollback is possible
        if (!isValidTransition(current, previous)) {
            revert SMInvalidRollback();
        }

        emit StateRollback(current, previous, reason);

        machine.currentState = previous;
        machine.previousState = current;
        machine.stateEnteredAt = uint64(block.timestamp);
        machine.lastTransitionBlock = uint64(block.number);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMEOUT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set timeout for a state
     * @param timeouts The timeouts storage
     * @param state The state
     * @param timeout Timeout in seconds
     */
    function setStateTimeout(
        StateTimeouts storage timeouts,
        uint8 state,
        uint64 timeout
    ) internal {
        if (state >= MAX_STATES) {
            revert SMInvalidState(state);
        }
        timeouts.timeouts[state] = timeout;
    }

    /**
     * @notice Enable timeout enforcement
     * @param timeouts The timeouts storage
     */
    function enableTimeouts(StateTimeouts storage timeouts) internal {
        timeouts.enforced = true;
    }

    /**
     * @notice Disable timeout enforcement
     * @param timeouts The timeouts storage
     */
    function disableTimeouts(StateTimeouts storage timeouts) internal {
        timeouts.enforced = false;
    }

    /**
     * @notice Check if current state has timed out
     * @param machine The state machine
     * @param timeouts The timeouts storage
     * @return True if timed out
     */
    function hasTimedOut(
        StateMachine storage machine,
        StateTimeouts storage timeouts
    ) internal view returns (bool) {
        if (!timeouts.enforced) return false;

        uint64 timeout = timeouts.timeouts[machine.currentState];
        if (timeout == 0) return false;

        uint64 elapsed = uint64(block.timestamp) - machine.stateEnteredAt;
        return elapsed > timeout;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current state info
     * @param machine The state machine
     */
    function getStateInfo(StateMachine storage machine) internal view returns (
        uint8 current,
        uint8 previous,
        uint64 enteredAt,
        uint64 lastBlock,
        address lastCaller
    ) {
        return (
            machine.currentState,
            machine.previousState,
            machine.stateEnteredAt,
            machine.lastTransitionBlock,
            machine.lastTransitionCaller
        );
    }

    /**
     * @notice Get time in current state
     * @param machine The state machine
     * @return Time in seconds
     */
    function getTimeInState(StateMachine storage machine) internal view returns (uint64) {
        return uint64(block.timestamp) - machine.stateEnteredAt;
    }

    /**
     * @notice Get state name
     * @param state The state value
     * @return name State name string
     */
    function getStateName(uint8 state) internal pure returns (string memory name) {
        if (state == STATE_IDLE) return "IDLE";
        if (state == STATE_INITIALIZING) return "INITIALIZING";
        if (state == STATE_READY) return "READY";
        if (state == STATE_EXECUTING) return "EXECUTING";
        if (state == STATE_CALLBACK) return "CALLBACK";
        if (state == STATE_COMPLETING) return "COMPLETING";
        if (state == STATE_FINALIZING) return "FINALIZING";
        if (state == STATE_ERROR) return "ERROR";
        if (state == STATE_PAUSED) return "PAUSED";
        if (state == STATE_RECOVERING) return "RECOVERING";
        return "UNKNOWN";
    }
}
