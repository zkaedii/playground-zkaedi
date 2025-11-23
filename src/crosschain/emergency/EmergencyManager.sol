// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*//////////////////////////////////////////////////////////////
                    EMERGENCY MANAGER
//////////////////////////////////////////////////////////////*/

/**
 * @title EmergencyManager
 * @notice Handles emergency situations, circuit breakers, and fallback mechanisms
 * @dev Features:
 *      - Global and per-contract circuit breakers
 *      - Emergency pause functionality
 *      - Fallback routing
 *      - Asset recovery
 *      - Multi-sig emergency actions
 *      - Timelock bypasses for critical situations
 */
contract EmergencyManager is
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    enum EmergencyLevel {
        NONE,
        LOW,        // Monitor closely
        MEDIUM,     // Restrict new operations
        HIGH,       // Pause non-essential functions
        CRITICAL    // Full shutdown
    }

    enum CircuitBreakerType {
        GLOBAL,
        PROTOCOL,
        CHAIN,
        TOKEN,
        CUSTOM
    }

    struct CircuitBreaker {
        CircuitBreakerType breakerType;
        bytes32 identifier;
        bool isTriggered;
        uint256 triggeredAt;
        uint256 cooldownPeriod;
        uint256 triggerCount;
        string reason;
        address triggeredBy;
    }

    struct EmergencyAction {
        bytes32 actionId;
        address target;
        bytes data;
        uint256 value;
        uint256 proposedAt;
        uint256 executedAt;
        uint256 requiredApprovals;
        uint256 currentApprovals;
        bool executed;
        bool cancelled;
        mapping(address => bool) approvals;
    }

    struct FallbackRoute {
        address primary;
        address fallback;
        bool useFallback;
        uint256 switchedAt;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error CircuitBreakerTriggered();
    error CooldownActive();
    error NotAuthorized();
    error ActionNotFound();
    error ActionAlreadyExecuted();
    error InsufficientApprovals();
    error TimelockActive();
    error InvalidFallback();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event EmergencyLevelChanged(EmergencyLevel oldLevel, EmergencyLevel newLevel);
    event CircuitBreakerTriggered_(
        bytes32 indexed breakerId,
        CircuitBreakerType breakerType,
        string reason
    );
    event CircuitBreakerReset(bytes32 indexed breakerId);
    event EmergencyActionProposed(
        bytes32 indexed actionId,
        address target,
        uint256 requiredApprovals
    );
    event EmergencyActionApproved(bytes32 indexed actionId, address approver);
    event EmergencyActionExecuted(bytes32 indexed actionId, bool success);
    event FallbackActivated(address indexed primary, address indexed fallback);
    event AssetRecovered(address indexed token, address indexed recipient, uint256 amount);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Current emergency level
    EmergencyLevel public emergencyLevel;

    /// @dev Circuit breakers
    mapping(bytes32 => CircuitBreaker) public circuitBreakers;

    /// @dev Emergency actions
    mapping(bytes32 => EmergencyAction) internal _actions;

    /// @dev Fallback routes
    mapping(address => FallbackRoute) public fallbackRoutes;

    /// @dev Emergency guardians (multi-sig)
    mapping(address => bool) public guardians;
    uint256 public guardianCount;

    /// @dev Required approvals for emergency actions
    uint256 public requiredApprovals;

    /// @dev Emergency timelock (can be bypassed in CRITICAL)
    uint256 public emergencyTimelock;

    /// @dev Contracts that can be paused
    mapping(address => bool) public pausableContracts;

    /// @dev Action nonce
    uint256 private _actionNonce;

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
        __Pausable_init();

        emergencyLevel = EmergencyLevel.NONE;
        requiredApprovals = 2;
        emergencyTimelock = 1 hours;

        // Owner is first guardian
        guardians[msg.sender] = true;
        guardianCount = 1;
    }

    /*//////////////////////////////////////////////////////////////
                    CIRCUIT BREAKERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Trigger a circuit breaker
    function triggerCircuitBreaker(
        CircuitBreakerType breakerType,
        bytes32 identifier,
        string calldata reason,
        uint256 cooldownPeriod
    ) external {
        require(guardians[msg.sender], "Not guardian");

        bytes32 breakerId = keccak256(abi.encodePacked(breakerType, identifier));

        CircuitBreaker storage breaker = circuitBreakers[breakerId];

        // Check cooldown from previous trigger
        if (breaker.isTriggered &&
            block.timestamp < breaker.triggeredAt + breaker.cooldownPeriod) {
            revert CooldownActive();
        }

        breaker.breakerType = breakerType;
        breaker.identifier = identifier;
        breaker.isTriggered = true;
        breaker.triggeredAt = block.timestamp;
        breaker.cooldownPeriod = cooldownPeriod;
        breaker.triggerCount++;
        breaker.reason = reason;
        breaker.triggeredBy = msg.sender;

        emit CircuitBreakerTriggered_(breakerId, breakerType, reason);

        // Auto-escalate emergency level if multiple breakers triggered
        if (breaker.triggerCount >= 3 && emergencyLevel < EmergencyLevel.HIGH) {
            _setEmergencyLevel(EmergencyLevel.HIGH);
        }
    }

    /// @notice Reset a circuit breaker
    function resetCircuitBreaker(bytes32 breakerId) external {
        require(guardians[msg.sender], "Not guardian");

        CircuitBreaker storage breaker = circuitBreakers[breakerId];

        // Must wait for cooldown unless owner
        if (msg.sender != owner() &&
            block.timestamp < breaker.triggeredAt + breaker.cooldownPeriod) {
            revert CooldownActive();
        }

        breaker.isTriggered = false;

        emit CircuitBreakerReset(breakerId);
    }

    /// @notice Check if circuit breaker is active
    function isCircuitBreakerActive(
        CircuitBreakerType breakerType,
        bytes32 identifier
    ) external view returns (bool) {
        bytes32 breakerId = keccak256(abi.encodePacked(breakerType, identifier));
        return circuitBreakers[breakerId].isTriggered;
    }

    /// @notice Modifier to check circuit breaker
    modifier circuitBreakerCheck(CircuitBreakerType breakerType, bytes32 identifier) {
        bytes32 breakerId = keccak256(abi.encodePacked(breakerType, identifier));
        if (circuitBreakers[breakerId].isTriggered) revert CircuitBreakerTriggered();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY LEVELS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set emergency level
    function setEmergencyLevel(EmergencyLevel level) external {
        require(guardians[msg.sender], "Not guardian");
        _setEmergencyLevel(level);
    }

    function _setEmergencyLevel(EmergencyLevel level) internal {
        EmergencyLevel oldLevel = emergencyLevel;
        emergencyLevel = level;

        // Auto-pause on HIGH or CRITICAL
        if (level >= EmergencyLevel.HIGH && !paused()) {
            _pause();
        }

        // Auto-unpause when returning to LOW or NONE
        if (level <= EmergencyLevel.LOW && paused()) {
            _unpause();
        }

        emit EmergencyLevelChanged(oldLevel, level);
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Propose an emergency action
    function proposeEmergencyAction(
        address target,
        bytes calldata data,
        uint256 value
    ) external returns (bytes32 actionId) {
        require(guardians[msg.sender], "Not guardian");

        actionId = keccak256(abi.encodePacked(
            target,
            data,
            value,
            block.timestamp,
            _actionNonce++
        ));

        EmergencyAction storage action = _actions[actionId];
        action.actionId = actionId;
        action.target = target;
        action.data = data;
        action.value = value;
        action.proposedAt = block.timestamp;
        action.requiredApprovals = emergencyLevel == EmergencyLevel.CRITICAL ? 1 : requiredApprovals;

        // Proposer auto-approves
        action.approvals[msg.sender] = true;
        action.currentApprovals = 1;

        emit EmergencyActionProposed(actionId, target, action.requiredApprovals);

        return actionId;
    }

    /// @notice Approve an emergency action
    function approveEmergencyAction(bytes32 actionId) external {
        require(guardians[msg.sender], "Not guardian");

        EmergencyAction storage action = _actions[actionId];
        if (action.proposedAt == 0) revert ActionNotFound();
        if (action.executed) revert ActionAlreadyExecuted();
        if (action.approvals[msg.sender]) return; // Already approved

        action.approvals[msg.sender] = true;
        action.currentApprovals++;

        emit EmergencyActionApproved(actionId, msg.sender);
    }

    /// @notice Execute an approved emergency action
    function executeEmergencyAction(bytes32 actionId) external {
        require(guardians[msg.sender], "Not guardian");

        EmergencyAction storage action = _actions[actionId];
        if (action.proposedAt == 0) revert ActionNotFound();
        if (action.executed) revert ActionAlreadyExecuted();
        if (action.currentApprovals < action.requiredApprovals) revert InsufficientApprovals();

        // Check timelock (bypass in CRITICAL)
        if (emergencyLevel != EmergencyLevel.CRITICAL) {
            if (block.timestamp < action.proposedAt + emergencyTimelock) {
                revert TimelockActive();
            }
        }

        action.executed = true;
        action.executedAt = block.timestamp;

        (bool success, ) = action.target.call{value: action.value}(action.data);

        emit EmergencyActionExecuted(actionId, success);
    }

    /*//////////////////////////////////////////////////////////////
                    FALLBACK ROUTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Set fallback route for a contract
    function setFallbackRoute(
        address primary,
        address fallback_
    ) external onlyOwner {
        fallbackRoutes[primary] = FallbackRoute({
            primary: primary,
            fallback: fallback_,
            useFallback: false,
            switchedAt: 0
        });
    }

    /// @notice Activate fallback for a contract
    function activateFallback(address primary) external {
        require(guardians[msg.sender], "Not guardian");

        FallbackRoute storage route = fallbackRoutes[primary];
        if (route.fallback == address(0)) revert InvalidFallback();

        route.useFallback = true;
        route.switchedAt = block.timestamp;

        emit FallbackActivated(primary, route.fallback);
    }

    /// @notice Deactivate fallback
    function deactivateFallback(address primary) external {
        require(guardians[msg.sender], "Not guardian");

        fallbackRoutes[primary].useFallback = false;
    }

    /// @notice Get active address (primary or fallback)
    function getActiveAddress(address primary) external view returns (address) {
        FallbackRoute storage route = fallbackRoutes[primary];
        return route.useFallback ? route.fallback : primary;
    }

    /*//////////////////////////////////////////////////////////////
                    ASSET RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @notice Recover stuck tokens
    function recoverTokens(
        address token,
        address recipient,
        uint256 amount
    ) external {
        require(guardians[msg.sender], "Not guardian");
        require(
            emergencyLevel >= EmergencyLevel.MEDIUM ||
            msg.sender == owner(),
            "Insufficient emergency level"
        );

        if (token == address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit AssetRecovered(token, recipient, amount);
    }

    /// @notice Recover tokens from another contract
    function recoverTokensFrom(
        address contractAddr,
        address token,
        address recipient,
        uint256 amount
    ) external {
        require(guardians[msg.sender], "Not guardian");
        require(emergencyLevel >= EmergencyLevel.HIGH, "Insufficient emergency level");

        // Try to call rescue function on target contract
        (bool success, ) = contractAddr.call(
            abi.encodeWithSignature(
                "rescueTokens(address,address,uint256)",
                token,
                recipient,
                amount
            )
        );

        if (!success) {
            // Try alternative signature
            contractAddr.call(
                abi.encodeWithSignature(
                    "emergencyWithdraw(address,uint256)",
                    token,
                    amount
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    PAUSE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause all registered contracts
    function pauseAll() external {
        require(guardians[msg.sender], "Not guardian");
        _pause();
    }

    /// @notice Unpause all
    function unpauseAll() external {
        require(guardians[msg.sender], "Not guardian");
        require(emergencyLevel <= EmergencyLevel.MEDIUM, "Emergency level too high");
        _unpause();
    }

    /// @notice Pause specific contract
    function pauseContract(address target) external {
        require(guardians[msg.sender], "Not guardian");

        (bool success, ) = target.call(
            abi.encodeWithSignature("pause()")
        );
        require(success, "Pause failed");
    }

    /*//////////////////////////////////////////////////////////////
                    GUARDIAN MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addGuardian(address guardian) external onlyOwner {
        require(guardian != address(0), "Invalid guardian");
        require(!guardians[guardian], "Already guardian");
        require(guardianCount < 10, "Max guardians reached");
        guardians[guardian] = true;
        unchecked { guardianCount++; }
        emit GuardianAdded(guardian);
    }

    function removeGuardian(address guardian) external onlyOwner {
        require(guardians[guardian], "Not guardian");
        require(guardianCount > 1, "Cannot remove last guardian");
        guardians[guardian] = false;
        unchecked { guardianCount--; }
        emit GuardianRemoved(guardian);
    }

    function setRequiredApprovals(uint256 _required) external onlyOwner {
        require(_required <= guardianCount, "Too many required");
        require(_required > 0, "Must be at least 1");
        requiredApprovals = _required;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getEmergencyAction(bytes32 actionId) external view returns (
        address target,
        bytes memory data,
        uint256 value,
        uint256 proposedAt,
        uint256 requiredApprovals_,
        uint256 currentApprovals,
        bool executed
    ) {
        EmergencyAction storage action = _actions[actionId];
        return (
            action.target,
            action.data,
            action.value,
            action.proposedAt,
            action.requiredApprovals,
            action.currentApprovals,
            action.executed
        );
    }

    function isGuardian(address addr) external view returns (bool) {
        return guardians[addr];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}

    uint256[40] private __gap;
}
