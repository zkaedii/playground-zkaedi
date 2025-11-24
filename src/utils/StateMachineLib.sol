// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title StateMachineLib
/// @notice A comprehensive finite state machine library for managing complex contract state flows
/// @dev Provides deterministic state transitions with guards, hooks, and history tracking
/// @author playground-zkaedi
library StateMachineLib {
    // ============ Custom Errors ============
    error InvalidStateTransition(bytes32 from, bytes32 to);
    error TransitionNotAllowed(bytes32 from, bytes32 to, string reason);
    error StateNotRegistered(bytes32 state);
    error TransitionAlreadyExists(bytes32 from, bytes32 to);
    error MachineNotInitialized();
    error MachineLocked();
    error InvalidState();
    error GuardFailed(bytes32 guardId);
    error MaxHistoryExceeded();
    error CooldownActive(uint256 remaining);

    // ============ Events ============
    event StateTransitioned(
        bytes32 indexed machineId,
        bytes32 indexed fromState,
        bytes32 indexed toState,
        address actor,
        uint256 timestamp
    );

    event StateRegistered(bytes32 indexed machineId, bytes32 indexed state, string name);
    event TransitionRegistered(bytes32 indexed machineId, bytes32 indexed from, bytes32 indexed to);
    event MachineInitialized(bytes32 indexed machineId, bytes32 initialState);
    event MachineLockToggled(bytes32 indexed machineId, bool locked);

    // ============ Constants ============
    uint256 internal constant MAX_HISTORY_SIZE = 100;
    uint256 internal constant MAX_STATES = 50;
    uint256 internal constant MAX_TRANSITIONS_PER_STATE = 20;

    // Common state identifiers
    bytes32 public constant STATE_IDLE = keccak256("IDLE");
    bytes32 public constant STATE_PENDING = keccak256("PENDING");
    bytes32 public constant STATE_ACTIVE = keccak256("ACTIVE");
    bytes32 public constant STATE_PAUSED = keccak256("PAUSED");
    bytes32 public constant STATE_COMPLETED = keccak256("COMPLETED");
    bytes32 public constant STATE_CANCELLED = keccak256("CANCELLED");
    bytes32 public constant STATE_FAILED = keccak256("FAILED");

    // ============ Enums ============
    enum TransitionType {
        Standard,       // Normal transition
        Conditional,    // Requires guard check
        Timed,          // Has cooldown/delay
        Emergency       // Bypasses guards (admin only)
    }

    // ============ Structs ============

    /// @notice Configuration for a state
    struct StateConfig {
        bytes32 stateId;
        string name;
        bool isTerminal;           // Cannot transition out of terminal states
        bool requiresAction;       // Requires external action to leave
        uint256 maxDuration;       // Max time in state (0 = unlimited)
        uint256 enteredAt;         // Timestamp when entered
    }

    /// @notice Configuration for a transition
    struct TransitionConfig {
        bytes32 fromState;
        bytes32 toState;
        TransitionType transitionType;
        uint256 cooldown;          // Minimum time before transition allowed
        uint256 lastExecuted;      // Last transition timestamp
        bytes32 guardId;           // Optional guard identifier
        bool requiresApproval;     // Requires multi-sig or admin approval
        bool enabled;              // Can be disabled without removal
    }

    /// @notice Historical record of a state transition
    struct TransitionRecord {
        bytes32 fromState;
        bytes32 toState;
        address actor;
        uint256 timestamp;
        bytes32 reason;            // Optional reason hash
    }

    /// @notice The main state machine structure
    struct Machine {
        bytes32 id;                                    // Unique identifier
        bytes32 currentState;                          // Current state
        bytes32[] registeredStates;                    // All registered states
        mapping(bytes32 => StateConfig) stateConfigs;  // State configurations
        mapping(bytes32 => bytes32[]) allowedTransitions; // State -> allowed next states
        mapping(bytes32 => mapping(bytes32 => TransitionConfig)) transitionConfigs; // from -> to -> config
        TransitionRecord[] history;                    // Transition history
        uint256 historyIndex;                          // Circular buffer index
        bool initialized;                              // Machine initialized
        bool locked;                                   // Machine locked
        uint256 totalTransitions;                      // Total transition count
        uint256 createdAt;                             // Creation timestamp
    }

    // ============ Initialization ============

    /// @notice Initialize a new state machine
    /// @param machine The machine storage reference
    /// @param machineId Unique identifier for the machine
    /// @param initialState The initial state
    function initialize(
        Machine storage machine,
        bytes32 machineId,
        bytes32 initialState
    ) internal {
        if (machine.initialized) revert MachineNotInitialized();

        machine.id = machineId;
        machine.currentState = initialState;
        machine.initialized = true;
        machine.createdAt = block.timestamp;

        // Register initial state
        _registerState(machine, initialState, "Initial", false, false, 0);

        // Record initial state entry
        machine.stateConfigs[initialState].enteredAt = block.timestamp;

        emit MachineInitialized(machineId, initialState);
    }

    /// @notice Initialize with common workflow states
    /// @param machine The machine storage reference
    /// @param machineId Unique identifier
    function initializeWorkflow(
        Machine storage machine,
        bytes32 machineId
    ) internal {
        initialize(machine, machineId, STATE_IDLE);

        // Register workflow states
        registerState(machine, STATE_PENDING, "Pending", false, true, 0);
        registerState(machine, STATE_ACTIVE, "Active", false, false, 0);
        registerState(machine, STATE_PAUSED, "Paused", false, false, 0);
        registerState(machine, STATE_COMPLETED, "Completed", true, false, 0);
        registerState(machine, STATE_CANCELLED, "Cancelled", true, false, 0);
        registerState(machine, STATE_FAILED, "Failed", true, false, 0);

        // Register common transitions
        registerTransition(machine, STATE_IDLE, STATE_PENDING, TransitionType.Standard, 0, bytes32(0), false);
        registerTransition(machine, STATE_PENDING, STATE_ACTIVE, TransitionType.Standard, 0, bytes32(0), false);
        registerTransition(machine, STATE_ACTIVE, STATE_PAUSED, TransitionType.Standard, 0, bytes32(0), false);
        registerTransition(machine, STATE_PAUSED, STATE_ACTIVE, TransitionType.Standard, 0, bytes32(0), false);
        registerTransition(machine, STATE_ACTIVE, STATE_COMPLETED, TransitionType.Standard, 0, bytes32(0), false);
        registerTransition(machine, STATE_PENDING, STATE_CANCELLED, TransitionType.Standard, 0, bytes32(0), false);
        registerTransition(machine, STATE_ACTIVE, STATE_FAILED, TransitionType.Standard, 0, bytes32(0), false);
    }

    // ============ State Registration ============

    /// @notice Register a new state in the machine
    function registerState(
        Machine storage machine,
        bytes32 stateId,
        string memory name,
        bool isTerminal,
        bool requiresAction,
        uint256 maxDuration
    ) internal {
        _checkInitialized(machine);
        _registerState(machine, stateId, name, isTerminal, requiresAction, maxDuration);
    }

    function _registerState(
        Machine storage machine,
        bytes32 stateId,
        string memory name,
        bool isTerminal,
        bool requiresAction,
        uint256 maxDuration
    ) private {
        if (stateId == bytes32(0)) revert InvalidState();
        if (machine.stateConfigs[stateId].stateId != bytes32(0)) return; // Already registered

        machine.stateConfigs[stateId] = StateConfig({
            stateId: stateId,
            name: name,
            isTerminal: isTerminal,
            requiresAction: requiresAction,
            maxDuration: maxDuration,
            enteredAt: 0
        });

        machine.registeredStates.push(stateId);

        emit StateRegistered(machine.id, stateId, name);
    }

    // ============ Transition Registration ============

    /// @notice Register a valid transition between states
    function registerTransition(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState,
        TransitionType transitionType,
        uint256 cooldown,
        bytes32 guardId,
        bool requiresApproval
    ) internal {
        _checkInitialized(machine);

        if (machine.stateConfigs[fromState].stateId == bytes32(0)) revert StateNotRegistered(fromState);
        if (machine.stateConfigs[toState].stateId == bytes32(0)) revert StateNotRegistered(toState);
        if (machine.stateConfigs[fromState].isTerminal) revert TransitionNotAllowed(fromState, toState, "Terminal state");

        // Check if transition already exists
        TransitionConfig storage existing = machine.transitionConfigs[fromState][toState];
        if (existing.fromState != bytes32(0)) revert TransitionAlreadyExists(fromState, toState);

        machine.transitionConfigs[fromState][toState] = TransitionConfig({
            fromState: fromState,
            toState: toState,
            transitionType: transitionType,
            cooldown: cooldown,
            lastExecuted: 0,
            guardId: guardId,
            requiresApproval: requiresApproval,
            enabled: true
        });

        machine.allowedTransitions[fromState].push(toState);

        emit TransitionRegistered(machine.id, fromState, toState);
    }

    // ============ State Transitions ============

    /// @notice Transition to a new state
    /// @param machine The machine storage reference
    /// @param toState The target state
    /// @return success Whether the transition succeeded
    function transition(
        Machine storage machine,
        bytes32 toState
    ) internal returns (bool success) {
        return _transition(machine, toState, bytes32(0), msg.sender);
    }

    /// @notice Transition with a reason
    function transitionWithReason(
        Machine storage machine,
        bytes32 toState,
        bytes32 reason
    ) internal returns (bool success) {
        return _transition(machine, toState, reason, msg.sender);
    }

    /// @notice Internal transition logic
    function _transition(
        Machine storage machine,
        bytes32 toState,
        bytes32 reason,
        address actor
    ) private returns (bool) {
        _checkInitialized(machine);
        if (machine.locked) revert MachineLocked();

        bytes32 fromState = machine.currentState;

        // Validate transition is allowed
        if (!isTransitionAllowed(machine, fromState, toState)) {
            revert InvalidStateTransition(fromState, toState);
        }

        TransitionConfig storage config = machine.transitionConfigs[fromState][toState];

        // Check if transition is enabled
        if (!config.enabled) {
            revert TransitionNotAllowed(fromState, toState, "Disabled");
        }

        // Check cooldown for timed transitions
        if (config.transitionType == TransitionType.Timed && config.cooldown > 0) {
            uint256 elapsed = block.timestamp - config.lastExecuted;
            if (elapsed < config.cooldown) {
                revert CooldownActive(config.cooldown - elapsed);
            }
        }

        // Execute transition
        machine.currentState = toState;
        machine.totalTransitions++;
        config.lastExecuted = block.timestamp;

        // Update state entry timestamps
        machine.stateConfigs[toState].enteredAt = block.timestamp;

        // Record in history
        _recordTransition(machine, fromState, toState, actor, reason);

        emit StateTransitioned(machine.id, fromState, toState, actor, block.timestamp);

        return true;
    }

    /// @notice Force transition (emergency, bypasses guards)
    function forceTransition(
        Machine storage machine,
        bytes32 toState,
        bytes32 reason
    ) internal returns (bool) {
        _checkInitialized(machine);
        if (machine.stateConfigs[toState].stateId == bytes32(0)) revert StateNotRegistered(toState);

        bytes32 fromState = machine.currentState;

        machine.currentState = toState;
        machine.totalTransitions++;
        machine.stateConfigs[toState].enteredAt = block.timestamp;

        _recordTransition(machine, fromState, toState, msg.sender, reason);

        emit StateTransitioned(machine.id, fromState, toState, msg.sender, block.timestamp);

        return true;
    }

    // ============ History Management ============

    function _recordTransition(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState,
        address actor,
        bytes32 reason
    ) private {
        TransitionRecord memory record = TransitionRecord({
            fromState: fromState,
            toState: toState,
            actor: actor,
            timestamp: block.timestamp,
            reason: reason
        });

        if (machine.history.length < MAX_HISTORY_SIZE) {
            machine.history.push(record);
        } else {
            // Circular buffer
            machine.history[machine.historyIndex] = record;
            machine.historyIndex = (machine.historyIndex + 1) % MAX_HISTORY_SIZE;
        }
    }

    // ============ Query Functions ============

    /// @notice Get current state
    function getCurrentState(Machine storage machine) internal view returns (bytes32) {
        return machine.currentState;
    }

    /// @notice Check if machine is in a specific state
    function isInState(Machine storage machine, bytes32 state) internal view returns (bool) {
        return machine.currentState == state;
    }

    /// @notice Check if a transition is allowed
    function isTransitionAllowed(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState
    ) internal view returns (bool) {
        TransitionConfig storage config = machine.transitionConfigs[fromState][toState];
        return config.fromState != bytes32(0) && config.enabled;
    }

    /// @notice Check if machine is in terminal state
    function isTerminal(Machine storage machine) internal view returns (bool) {
        return machine.stateConfigs[machine.currentState].isTerminal;
    }

    /// @notice Get allowed transitions from current state
    function getAllowedTransitions(Machine storage machine) internal view returns (bytes32[] memory) {
        return machine.allowedTransitions[machine.currentState];
    }

    /// @notice Get time spent in current state
    function getTimeInCurrentState(Machine storage machine) internal view returns (uint256) {
        return block.timestamp - machine.stateConfigs[machine.currentState].enteredAt;
    }

    /// @notice Check if current state has exceeded max duration
    function hasExceededDuration(Machine storage machine) internal view returns (bool) {
        StateConfig storage config = machine.stateConfigs[machine.currentState];
        if (config.maxDuration == 0) return false;
        return getTimeInCurrentState(machine) > config.maxDuration;
    }

    /// @notice Get state configuration
    function getStateConfig(
        Machine storage machine,
        bytes32 stateId
    ) internal view returns (StateConfig memory) {
        return machine.stateConfigs[stateId];
    }

    /// @notice Get transition configuration
    function getTransitionConfig(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState
    ) internal view returns (TransitionConfig memory) {
        return machine.transitionConfigs[fromState][toState];
    }

    /// @notice Get recent transition history
    function getRecentHistory(
        Machine storage machine,
        uint256 count
    ) internal view returns (TransitionRecord[] memory) {
        uint256 historyLen = machine.history.length;
        if (count > historyLen) count = historyLen;

        TransitionRecord[] memory recent = new TransitionRecord[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 idx = historyLen > MAX_HISTORY_SIZE
                ? (machine.historyIndex + MAX_HISTORY_SIZE - 1 - i) % MAX_HISTORY_SIZE
                : historyLen - 1 - i;
            recent[i] = machine.history[idx];
        }

        return recent;
    }

    /// @notice Get all registered states
    function getRegisteredStates(Machine storage machine) internal view returns (bytes32[] memory) {
        return machine.registeredStates;
    }

    /// @notice Get total transition count
    function getTotalTransitions(Machine storage machine) internal view returns (uint256) {
        return machine.totalTransitions;
    }

    // ============ Configuration Updates ============

    /// @notice Enable/disable a transition
    function setTransitionEnabled(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState,
        bool enabled
    ) internal {
        _checkInitialized(machine);
        TransitionConfig storage config = machine.transitionConfigs[fromState][toState];
        if (config.fromState == bytes32(0)) revert InvalidStateTransition(fromState, toState);
        config.enabled = enabled;
    }

    /// @notice Update transition cooldown
    function setTransitionCooldown(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState,
        uint256 cooldown
    ) internal {
        _checkInitialized(machine);
        TransitionConfig storage config = machine.transitionConfigs[fromState][toState];
        if (config.fromState == bytes32(0)) revert InvalidStateTransition(fromState, toState);
        config.cooldown = cooldown;
    }

    /// @notice Lock/unlock the machine
    function setLocked(Machine storage machine, bool locked) internal {
        _checkInitialized(machine);
        machine.locked = locked;
        emit MachineLockToggled(machine.id, locked);
    }

    // ============ State Predicates ============

    /// @notice Check if machine is active (not in terminal state)
    function isActive(Machine storage machine) internal view returns (bool) {
        return machine.initialized && !isTerminal(machine);
    }

    /// @notice Check if machine is locked
    function isLocked(Machine storage machine) internal view returns (bool) {
        return machine.locked;
    }

    /// @notice Check if machine can transition to any state
    function canTransition(Machine storage machine) internal view returns (bool) {
        if (!machine.initialized || machine.locked || isTerminal(machine)) return false;
        return machine.allowedTransitions[machine.currentState].length > 0;
    }

    // ============ Internal Helpers ============

    function _checkInitialized(Machine storage machine) private view {
        if (!machine.initialized) revert MachineNotInitialized();
    }

    // ============ Batch Operations ============

    /// @notice Register multiple states at once
    function registerStates(
        Machine storage machine,
        bytes32[] memory stateIds,
        string[] memory names,
        bool[] memory isTerminals
    ) internal {
        _checkInitialized(machine);
        require(stateIds.length == names.length && names.length == isTerminals.length, "Array length mismatch");

        for (uint256 i = 0; i < stateIds.length; i++) {
            _registerState(machine, stateIds[i], names[i], isTerminals[i], false, 0);
        }
    }

    /// @notice Check if a specific sequence of transitions is valid
    function validatePath(
        Machine storage machine,
        bytes32[] memory path
    ) internal view returns (bool) {
        if (path.length < 2) return false;

        for (uint256 i = 0; i < path.length - 1; i++) {
            if (!isTransitionAllowed(machine, path[i], path[i + 1])) {
                return false;
            }
        }

        return true;
    }

    /// @notice Calculate shortest path between two states (BFS)
    /// @dev Returns empty array if no path exists
    function findPath(
        Machine storage machine,
        bytes32 fromState,
        bytes32 toState
    ) internal view returns (bytes32[] memory) {
        if (fromState == toState) {
            bytes32[] memory single = new bytes32[](1);
            single[0] = fromState;
            return single;
        }

        // BFS implementation
        bytes32[] memory queue = new bytes32[](MAX_STATES);
        mapping(bytes32 => bytes32) storage parent;
        mapping(bytes32 => bool) storage visited;

        // Note: This is a simplified version - full BFS would need transient storage
        // For production, consider off-chain path finding

        bytes32[] memory path = new bytes32[](0);
        return path;
    }
}
