// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/HardenedSecurityLib.sol";
import "../utils/ValidatorsLib.sol";
import "../utils/SolversLib.sol";
import "../utils/SynergyLib.sol";

/**
 * @title SecurityManager
 * @notice Comprehensive security management contract for DeFi protocols
 * @dev Demonstrates advanced security patterns including timelocks, guardians, and manipulation protection
 */
contract SecurityManager {
    using HardenedSecurityLib for *;
    using ValidatorsLib for *;
    using SolversLib for *;
    using SynergyLib for *;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 30 days;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant GUARDIAN_QUORUM = 2;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Timelock storage
    HardenedSecurityLib.TimelockState private timelockState;

    /// @notice Emergency state
    HardenedSecurityLib.EmergencyState private emergencyState;

    /// @notice Rate limiters per function
    mapping(bytes4 => HardenedSecurityLib.RateLimiter) private functionLimiters;

    /// @notice Cooldown tracker per user per function
    mapping(bytes4 => HardenedSecurityLib.CooldownTracker) private functionCooldowns;

    /// @notice Manipulation guard for price-sensitive operations
    HardenedSecurityLib.ManipulationGuard private manipulationGuard;

    /// @notice TWAP oracle state
    HardenedSecurityLib.TWAPState private twapState;

    /// @notice Sandwich protection
    HardenedSecurityLib.SandwichGuard private sandwichGuard;

    /// @notice Flash loan guard
    HardenedSecurityLib.FlashLoanGuard private flashLoanGuard;

    /// @notice Nonce manager for signatures
    HardenedSecurityLib.NonceManager private nonceManager;

    /// @notice Address validation lists
    ValidatorsLib.AddressLists private addressLists;

    /// @notice Protocol registry for multi-protocol operations
    SynergyLib.ProtocolRegistry private protocolRegistry;

    /// @notice Role members
    mapping(bytes32 => mapping(address => bool)) private roleMembers;

    /// @notice Role member count
    mapping(bytes32 => uint256) private roleMemberCount;

    /// @notice Guardian signatures for multi-sig operations
    mapping(bytes32 => mapping(address => bool)) private guardianSignatures;
    mapping(bytes32 => uint256) private signatureCount;

    /// @notice Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice Pending operations
    mapping(bytes32 => PendingOperation) public pendingOperations;

    struct PendingOperation {
        address target;
        bytes data;
        uint256 value;
        uint256 eta;
        bool executed;
        bool cancelled;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event OperationQueued(bytes32 indexed operationId, address target, uint256 eta);
    event OperationExecuted(bytes32 indexed operationId, address target);
    event OperationCancelled(bytes32 indexed operationId);
    event EmergencyActivated(bytes32 reason);
    event EmergencyDeactivated();
    event GuardianSignatureAdded(bytes32 indexed operationId, address guardian);
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);
    event ProtocolRegistered(bytes32 indexed protocolId, address protocol);
    event ManipulationDetected(address indexed account, uint256 change);
    event RateLimitExceeded(bytes4 indexed selector, address indexed account);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error Unauthorized();
    error OperationNotFound();
    error OperationNotReady();
    error OperationExpired();
    error OperationAlreadyExecuted();
    error OperationAlreadyCancelled();
    error InsufficientSignatures();
    error AlreadySigned();
    error InvalidDelay();
    error ExecutionFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    modifier onlyRole(bytes32 role) {
        if (!roleMembers[role][msg.sender]) revert Unauthorized();
        _;
    }

    modifier notInEmergency() {
        emergencyState.requireNotEmergency();
        _;
    }

    modifier rateLimited(bytes4 selector) {
        functionLimiters[selector].consumeRateLimit(msg.sender);
        _;
    }

    modifier cooledDown(bytes4 selector) {
        functionCooldowns[selector].enforceCooldown(msg.sender);
        _;
    }

    modifier flashLoanProtected() {
        flashLoanGuard.enforceFlashLoanProtection(msg.sender);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address[] memory initialGuardians) {
        // Grant admin role to deployer
        roleMembers[ADMIN_ROLE][msg.sender] = true;
        roleMemberCount[ADMIN_ROLE] = 1;

        // Add initial guardians
        for (uint256 i = 0; i < initialGuardians.length; i++) {
            ValidatorsLib.requireNonZeroAddress(initialGuardians[i]);
            roleMembers[GUARDIAN_ROLE][initialGuardians[i]] = true;
            roleMemberCount[GUARDIAN_ROLE]++;
        }

        // Initialize security mechanisms
        timelockState.initTimelock(MIN_DELAY, GRACE_PERIOD);
        flashLoanGuard.initFlashLoanGuard(1);
        manipulationGuard.initManipulationGuard(500); // 5% threshold

        // Initialize rate limiters for critical functions
        functionLimiters[this.queueOperation.selector].initRateLimiter(10, 1 hours);
        functionLimiters[this.executeOperation.selector].initRateLimiter(5, 1 hours);
        functionLimiters[this.grantRole.selector].initRateLimiter(3, 1 hours);

        // Initialize cooldowns
        functionCooldowns[this.activateEmergency.selector].initCooldown(1 hours);

        // Enable blacklist
        addressLists.blacklistEnabled = true;

        // Build domain separator
        DOMAIN_SEPARATOR = HardenedSecurityLib.buildDomainSeparator(
            "SecurityManager",
            "1"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMELOCK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Queue an operation for timelock execution
     * @param target Target contract
     * @param data Calldata
     * @param value ETH value
     * @param delay Delay in seconds
     */
    function queueOperation(
        address target,
        bytes calldata data,
        uint256 value,
        uint256 delay
    )
        external
        onlyRole(ADMIN_ROLE)
        notInEmergency
        rateLimited(this.queueOperation.selector)
        returns (bytes32 operationId)
    {
        ValidatorsLib.requireNonZeroAddress(target);

        if (delay < MIN_DELAY || delay > MAX_DELAY) revert InvalidDelay();

        uint256 eta = block.timestamp + delay;

        operationId = keccak256(abi.encode(target, data, value, eta, block.number));

        pendingOperations[operationId] = PendingOperation({
            target: target,
            data: data,
            value: value,
            eta: eta,
            executed: false,
            cancelled: false
        });

        // Queue in timelock state
        timelockState.queueOperation(operationId, eta);

        emit OperationQueued(operationId, target, eta);
    }

    /**
     * @notice Execute a queued operation
     * @param operationId Operation ID
     */
    function executeOperation(bytes32 operationId)
        external
        onlyRole(ADMIN_ROLE)
        notInEmergency
        rateLimited(this.executeOperation.selector)
        flashLoanProtected
        returns (bool success, bytes memory returnData)
    {
        PendingOperation storage op = pendingOperations[operationId];

        if (op.target == address(0)) revert OperationNotFound();
        if (op.executed) revert OperationAlreadyExecuted();
        if (op.cancelled) revert OperationAlreadyCancelled();
        if (block.timestamp < op.eta) revert OperationNotReady();
        if (block.timestamp > op.eta + GRACE_PERIOD) revert OperationExpired();

        // Check guardian signatures if required
        if (signatureCount[operationId] < GUARDIAN_QUORUM) {
            revert InsufficientSignatures();
        }

        // Execute via timelock
        timelockState.executeOperation(operationId);

        op.executed = true;

        (success, returnData) = op.target.call{value: op.value}(op.data);
        if (!success) revert ExecutionFailed();

        emit OperationExecuted(operationId, op.target);
    }

    /**
     * @notice Cancel a queued operation
     * @param operationId Operation ID
     */
    function cancelOperation(bytes32 operationId)
        external
        onlyRole(ADMIN_ROLE)
    {
        PendingOperation storage op = pendingOperations[operationId];

        if (op.target == address(0)) revert OperationNotFound();
        if (op.executed) revert OperationAlreadyExecuted();

        op.cancelled = true;
        timelockState.cancelOperation(operationId);

        emit OperationCancelled(operationId);
    }

    /**
     * @notice Add guardian signature to operation
     * @param operationId Operation ID
     */
    function signOperation(bytes32 operationId)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        PendingOperation storage op = pendingOperations[operationId];

        if (op.target == address(0)) revert OperationNotFound();
        if (op.executed || op.cancelled) revert OperationAlreadyExecuted();
        if (guardianSignatures[operationId][msg.sender]) revert AlreadySigned();

        guardianSignatures[operationId][msg.sender] = true;
        signatureCount[operationId]++;

        emit GuardianSignatureAdded(operationId, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Activate emergency mode
     * @param reason Reason for emergency
     */
    function activateEmergency(bytes32 reason)
        external
        onlyRole(GUARDIAN_ROLE)
        cooledDown(this.activateEmergency.selector)
    {
        emergencyState.activateEmergencyMode(reason);
        emit EmergencyActivated(reason);
    }

    /**
     * @notice Deactivate emergency mode (requires admin)
     */
    function deactivateEmergency()
        external
        onlyRole(ADMIN_ROLE)
    {
        emergencyState.deactivateEmergencyMode();
        emit EmergencyDeactivated();
    }

    /**
     * @notice Check if emergency mode is active
     */
    function isEmergencyActive() external view returns (bool) {
        return emergencyState.isEmergencyActive();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Grant role to account
     * @param role Role identifier
     * @param account Account to grant role
     */
    function grantRole(bytes32 role, address account)
        external
        onlyRole(ADMIN_ROLE)
        rateLimited(this.grantRole.selector)
    {
        ValidatorsLib.requireNonZeroAddress(account);

        // Validate not blacklisted
        ValidatorsLib.AddressConfig memory config = ValidatorsLib.AddressConfig({
            allowZero: false,
            allowContract: true,
            allowEOA: true,
            checkBlacklist: true,
            checkWhitelist: false
        });
        ValidatorsLib.validateAddress(account, config, addressLists);

        if (!roleMembers[role][account]) {
            roleMembers[role][account] = true;
            roleMemberCount[role]++;
            emit RoleGranted(role, account);
        }
    }

    /**
     * @notice Revoke role from account
     * @param role Role identifier
     * @param account Account to revoke role
     */
    function revokeRole(bytes32 role, address account)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (roleMembers[role][account]) {
            roleMembers[role][account] = false;
            roleMemberCount[role]--;
            emit RoleRevoked(role, account);
        }
    }

    /**
     * @notice Check if account has role
     * @param role Role identifier
     * @param account Account to check
     */
    function hasRole(bytes32 role, address account) external view returns (bool) {
        return roleMembers[role][account];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MANIPULATION PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check for price manipulation
     * @param currentValue Current value
     * @param previousValue Previous value
     */
    function checkManipulation(uint256 currentValue, uint256 previousValue)
        external
        view
        returns (bool isSafe)
    {
        return !manipulationGuard.detectManipulation(currentValue, previousValue);
    }

    /**
     * @notice Update TWAP oracle
     * @param newPrice New price observation
     */
    function updateTWAP(uint256 newPrice)
        external
        onlyRole(OPERATOR_ROLE)
    {
        twapState.recordObservation(newPrice);
    }

    /**
     * @notice Get TWAP price
     * @param period Period in seconds
     */
    function getTWAP(uint256 period)
        external
        view
        returns (uint256)
    {
        return twapState.calculateTWAP(period);
    }

    /**
     * @notice Validate price against TWAP
     * @param spotPrice Spot price to validate
     * @param maxDeviationBps Maximum deviation in basis points
     */
    function validatePriceAgainstTWAP(uint256 spotPrice, uint256 maxDeviationBps)
        external
        view
        returns (bool valid)
    {
        uint256 twapPrice = twapState.calculateTWAP(1 hours);
        return twapState.validateSpotPrice(spotPrice, twapPrice, maxDeviationBps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROTOCOL REGISTRY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Register a protocol
     * @param protocolAddress Protocol address
     * @param name Protocol name
     * @param trustScore Initial trust score
     * @param supportedSelectors Supported function selectors
     */
    function registerProtocol(
        address protocolAddress,
        bytes32 name,
        uint256 trustScore,
        bytes4[] calldata supportedSelectors
    )
        external
        onlyRole(ADMIN_ROLE)
        returns (bytes32 protocolId)
    {
        ValidatorsLib.requireNonZeroAddress(protocolAddress);

        protocolId = protocolRegistry.registerProtocol(
            protocolAddress,
            name,
            trustScore,
            supportedSelectors
        );

        emit ProtocolRegistered(protocolId, protocolAddress);
    }

    /**
     * @notice Update protocol trust score
     * @param protocolId Protocol ID
     * @param newScore New trust score
     */
    function updateProtocolTrustScore(bytes32 protocolId, uint256 newScore)
        external
        onlyRole(ADMIN_ROLE)
    {
        protocolRegistry.updateTrustScore(protocolId, newScore);
    }

    /**
     * @notice Get protocol info
     * @param protocolId Protocol ID
     */
    function getProtocolInfo(bytes32 protocolId)
        external
        view
        returns (SynergyLib.Protocol memory)
    {
        return protocolRegistry.getProtocol(protocolId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BLACKLIST MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add address to blacklist
     * @param account Address to blacklist
     */
    function blacklist(address account) external onlyRole(ADMIN_ROLE) {
        ValidatorsLib.addToBlacklist(addressLists, account);

        // Revoke all roles
        if (roleMembers[ADMIN_ROLE][account]) {
            roleMembers[ADMIN_ROLE][account] = false;
            roleMemberCount[ADMIN_ROLE]--;
        }
        if (roleMembers[GUARDIAN_ROLE][account]) {
            roleMembers[GUARDIAN_ROLE][account] = false;
            roleMemberCount[GUARDIAN_ROLE]--;
        }
        if (roleMembers[OPERATOR_ROLE][account]) {
            roleMembers[OPERATOR_ROLE][account] = false;
            roleMemberCount[OPERATOR_ROLE]--;
        }
    }

    /**
     * @notice Remove address from blacklist
     * @param account Address to remove
     */
    function removeFromBlacklist(address account) external onlyRole(ADMIN_ROLE) {
        ValidatorsLib.removeFromBlacklist(addressLists, account);
    }

    /**
     * @notice Check if address is blacklisted
     * @param account Address to check
     */
    function isBlacklisted(address account) external view returns (bool) {
        return addressLists.blacklist[account];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNATURE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate a signature
     * @param signer Expected signer
     * @param hash Message hash
     * @param v Signature v
     * @param r Signature r
     * @param s Signature s
     */
    function validateSignature(
        address signer,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (bool valid) {
        ValidatorsLib.SignatureParams memory params = ValidatorsLib.SignatureParams({
            hash: hash,
            v: v,
            r: r,
            s: s,
            expectedSigner: signer,
            deadline: 0
        });

        return ValidatorsLib.validateSignature(params);
    }

    /**
     * @notice Get user's current nonce
     * @param user User address
     */
    function getNonce(address user) external view returns (uint256) {
        return nonceManager.getCurrentNonce(user);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get operation details
     * @param operationId Operation ID
     */
    function getOperation(bytes32 operationId)
        external
        view
        returns (PendingOperation memory)
    {
        return pendingOperations[operationId];
    }

    /**
     * @notice Get operation signature count
     * @param operationId Operation ID
     */
    function getSignatureCount(bytes32 operationId) external view returns (uint256) {
        return signatureCount[operationId];
    }

    /**
     * @notice Get role member count
     * @param role Role identifier
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return roleMemberCount[role];
    }

    /**
     * @notice Get remaining rate limit
     * @param selector Function selector
     */
    function getRemainingRateLimit(bytes4 selector) external view returns (uint256) {
        return functionLimiters[selector].getRemainingOperations();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RECEIVE
    // ═══════════════════════════════════════════════════════════════════════════

    receive() external payable {}
}
