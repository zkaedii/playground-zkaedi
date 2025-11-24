// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AccessControlLib
 * @notice Gas-efficient role-based access control library for DeFi protocols
 * @dev Implements hierarchical roles, time-locked permissions, and multi-sig patterns
 */
library AccessControlLib {
    // ============ ERRORS ============
    error AccessDenied(address account, bytes32 role);
    error RoleNotGranted(address account, bytes32 role);
    error InvalidRoleAdmin(bytes32 role);
    error TimelockNotExpired(uint256 currentTime, uint256 unlockTime);
    error TimelockAlreadySet(bytes32 role, address account);
    error InvalidTimelockDuration(uint256 duration);
    error InsufficientSignatures(uint256 required, uint256 provided);
    error SignatureAlreadyUsed(address signer);
    error InvalidSigner(address signer);
    error QuorumNotMet(uint256 required, uint256 current);
    error RoleAlreadyGranted(address account, bytes32 role);
    error CannotRevokeLastAdmin();
    error ZeroAddress();

    // ============ CONSTANTS ============
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 internal constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    uint256 internal constant MIN_TIMELOCK_DURATION = 1 hours;
    uint256 internal constant MAX_TIMELOCK_DURATION = 30 days;
    uint256 internal constant DEFAULT_TIMELOCK_DURATION = 2 days;

    // ============ TYPES ============
    struct RoleData {
        mapping(address => bool) members;
        mapping(address => uint256) grantedAt;
        bytes32 adminRole;
        uint256 memberCount;
    }

    struct AccessControlStorage {
        mapping(bytes32 => RoleData) roles;
        mapping(bytes32 => mapping(address => uint256)) timelocks;
        mapping(bytes32 => uint256) roleTimelockDuration;
    }

    struct TimelockRequest {
        bytes32 role;
        address account;
        bool isGrant; // true = grant, false = revoke
        uint256 requestedAt;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
    }

    struct MultiSigConfig {
        address[] signers;
        uint256 quorum;
        mapping(address => bool) isSigner;
    }

    struct MultiSigRequest {
        bytes32 operationId;
        bytes data;
        uint256 confirmations;
        mapping(address => bool) hasConfirmed;
        bool executed;
        uint256 createdAt;
        uint256 expiresAt;
    }

    // ============ EVENTS ============
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event TimelockScheduled(bytes32 indexed role, address indexed account, uint256 executeAfter);
    event TimelockExecuted(bytes32 indexed role, address indexed account);
    event TimelockCancelled(bytes32 indexed role, address indexed account);
    event MultiSigConfirmation(bytes32 indexed operationId, address indexed signer, uint256 confirmations);
    event MultiSigExecution(bytes32 indexed operationId);

    // ============ ROLE MANAGEMENT ============

    /**
     * @notice Check if an account has a specific role
     * @param storage_ The access control storage
     * @param role The role to check
     * @param account The account to check
     * @return True if the account has the role
     */
    function hasRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return storage_.roles[role].members[account];
    }

    /**
     * @notice Get the admin role for a given role
     * @param storage_ The access control storage
     * @param role The role to query
     * @return The admin role
     */
    function getRoleAdmin(
        AccessControlStorage storage storage_,
        bytes32 role
    ) internal view returns (bytes32) {
        return storage_.roles[role].adminRole;
    }

    /**
     * @notice Get the number of members for a role
     * @param storage_ The access control storage
     * @param role The role to query
     * @return The number of members
     */
    function getRoleMemberCount(
        AccessControlStorage storage storage_,
        bytes32 role
    ) internal view returns (uint256) {
        return storage_.roles[role].memberCount;
    }

    /**
     * @notice Get when a role was granted to an account
     * @param storage_ The access control storage
     * @param role The role to query
     * @param account The account to query
     * @return The timestamp when the role was granted
     */
    function getGrantedAt(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal view returns (uint256) {
        return storage_.roles[role].grantedAt[account];
    }

    /**
     * @notice Grant a role to an account
     * @param storage_ The access control storage
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function grantRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal {
        if (account == address(0)) revert ZeroAddress();
        if (storage_.roles[role].members[account]) revert RoleAlreadyGranted(account, role);

        storage_.roles[role].members[account] = true;
        storage_.roles[role].grantedAt[account] = block.timestamp;
        storage_.roles[role].memberCount++;

        emit RoleGranted(role, account, msg.sender);
    }

    /**
     * @notice Revoke a role from an account
     * @param storage_ The access control storage
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function revokeRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal {
        if (!storage_.roles[role].members[account]) revert RoleNotGranted(account, role);

        // Prevent revoking the last admin
        if (role == DEFAULT_ADMIN_ROLE && storage_.roles[role].memberCount == 1) {
            revert CannotRevokeLastAdmin();
        }

        storage_.roles[role].members[account] = false;
        storage_.roles[role].grantedAt[account] = 0;
        storage_.roles[role].memberCount--;

        emit RoleRevoked(role, account, msg.sender);
    }

    /**
     * @notice Renounce a role (account renounces their own role)
     * @param storage_ The access control storage
     * @param role The role to renounce
     * @param account The account renouncing (must be msg.sender)
     */
    function renounceRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal {
        if (account != msg.sender) revert AccessDenied(account, role);
        revokeRole(storage_, role, account);
    }

    /**
     * @notice Set the admin role for a role
     * @param storage_ The access control storage
     * @param role The role to set admin for
     * @param adminRole The new admin role
     */
    function setRoleAdmin(
        AccessControlStorage storage storage_,
        bytes32 role,
        bytes32 adminRole
    ) internal {
        bytes32 previousAdminRole = storage_.roles[role].adminRole;
        storage_.roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    // ============ ACCESS CHECKS ============

    /**
     * @notice Check role and revert if not granted
     * @param storage_ The access control storage
     * @param role The role to check
     * @param account The account to check
     */
    function checkRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal view {
        if (!hasRole(storage_, role, account)) {
            revert AccessDenied(account, role);
        }
    }

    /**
     * @notice Check if sender has the admin role for a given role
     * @param storage_ The access control storage
     * @param role The role to check admin for
     */
    function checkRoleAdmin(
        AccessControlStorage storage storage_,
        bytes32 role
    ) internal view {
        bytes32 adminRole = getRoleAdmin(storage_, role);
        checkRole(storage_, adminRole, msg.sender);
    }

    /**
     * @notice Check if account has any of the specified roles
     * @param storage_ The access control storage
     * @param roles Array of roles to check
     * @param account The account to check
     * @return True if account has any of the roles
     */
    function hasAnyRole(
        AccessControlStorage storage storage_,
        bytes32[] memory roles,
        address account
    ) internal view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(storage_, roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if account has all of the specified roles
     * @param storage_ The access control storage
     * @param roles Array of roles to check
     * @param account The account to check
     * @return True if account has all of the roles
     */
    function hasAllRoles(
        AccessControlStorage storage storage_,
        bytes32[] memory roles,
        address account
    ) internal view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(storage_, roles[i], account)) {
                return false;
            }
        }
        return true;
    }

    // ============ TIMELOCK FUNCTIONS ============

    /**
     * @notice Set timelock duration for a role
     * @param storage_ The access control storage
     * @param role The role to set timelock for
     * @param duration The timelock duration in seconds
     */
    function setRoleTimelockDuration(
        AccessControlStorage storage storage_,
        bytes32 role,
        uint256 duration
    ) internal {
        if (duration < MIN_TIMELOCK_DURATION || duration > MAX_TIMELOCK_DURATION) {
            revert InvalidTimelockDuration(duration);
        }
        storage_.roleTimelockDuration[role] = duration;
    }

    /**
     * @notice Schedule a timelocked role grant
     * @param storage_ The access control storage
     * @param role The role to grant
     * @param account The account to grant the role to
     * @return executeAfter The timestamp when the grant can be executed
     */
    function scheduleRoleGrant(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal returns (uint256 executeAfter) {
        if (account == address(0)) revert ZeroAddress();
        if (storage_.timelocks[role][account] != 0) {
            revert TimelockAlreadySet(role, account);
        }

        uint256 duration = storage_.roleTimelockDuration[role];
        if (duration == 0) duration = DEFAULT_TIMELOCK_DURATION;

        executeAfter = block.timestamp + duration;
        storage_.timelocks[role][account] = executeAfter;

        emit TimelockScheduled(role, account, executeAfter);
    }

    /**
     * @notice Execute a timelocked role grant
     * @param storage_ The access control storage
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function executeTimelocked(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal {
        uint256 unlockTime = storage_.timelocks[role][account];
        if (unlockTime == 0) revert RoleNotGranted(account, role);
        if (block.timestamp < unlockTime) {
            revert TimelockNotExpired(block.timestamp, unlockTime);
        }

        storage_.timelocks[role][account] = 0;
        grantRole(storage_, role, account);

        emit TimelockExecuted(role, account);
    }

    /**
     * @notice Cancel a timelocked role grant
     * @param storage_ The access control storage
     * @param role The role to cancel
     * @param account The account to cancel for
     */
    function cancelTimelock(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal {
        if (storage_.timelocks[role][account] == 0) {
            revert RoleNotGranted(account, role);
        }

        storage_.timelocks[role][account] = 0;

        emit TimelockCancelled(role, account);
    }

    /**
     * @notice Get timelock status for a role grant
     * @param storage_ The access control storage
     * @param role The role to check
     * @param account The account to check
     * @return isPending Whether a timelock is pending
     * @return executeAfter When the timelock can be executed
     * @return isReady Whether the timelock is ready to execute
     */
    function getTimelockStatus(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account
    ) internal view returns (bool isPending, uint256 executeAfter, bool isReady) {
        executeAfter = storage_.timelocks[role][account];
        isPending = executeAfter != 0;
        isReady = isPending && block.timestamp >= executeAfter;
    }

    // ============ HIERARCHICAL ROLE SETUP ============

    /**
     * @notice Initialize a standard role hierarchy
     * @param storage_ The access control storage
     * @param admin The initial admin address
     */
    function initializeStandardRoles(
        AccessControlStorage storage storage_,
        address admin
    ) internal {
        if (admin == address(0)) revert ZeroAddress();

        // Grant admin role
        grantRole(storage_, DEFAULT_ADMIN_ROLE, admin);

        // Set role admins (hierarchical structure)
        setRoleAdmin(storage_, OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);
        setRoleAdmin(storage_, GUARDIAN_ROLE, DEFAULT_ADMIN_ROLE);
        setRoleAdmin(storage_, UPGRADER_ROLE, DEFAULT_ADMIN_ROLE);
        setRoleAdmin(storage_, PAUSER_ROLE, GUARDIAN_ROLE);
        setRoleAdmin(storage_, MINTER_ROLE, OPERATOR_ROLE);
        setRoleAdmin(storage_, BURNER_ROLE, OPERATOR_ROLE);
        setRoleAdmin(storage_, FEE_MANAGER_ROLE, OPERATOR_ROLE);
        setRoleAdmin(storage_, ORACLE_ROLE, OPERATOR_ROLE);
        setRoleAdmin(storage_, RELAYER_ROLE, OPERATOR_ROLE);

        // Set timelocks for sensitive roles
        storage_.roleTimelockDuration[DEFAULT_ADMIN_ROLE] = 7 days;
        storage_.roleTimelockDuration[UPGRADER_ROLE] = 3 days;
        storage_.roleTimelockDuration[GUARDIAN_ROLE] = 2 days;
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Compute role identifier from string
     * @param roleString The role name string
     * @return The role identifier (keccak256 hash)
     */
    function computeRoleId(string memory roleString) internal pure returns (bytes32) {
        return keccak256(bytes(roleString));
    }

    /**
     * @notice Check if an account has held a role for a minimum duration
     * @param storage_ The access control storage
     * @param role The role to check
     * @param account The account to check
     * @param minDuration The minimum duration in seconds
     * @return True if the account has held the role for the minimum duration
     */
    function hasRoleForDuration(
        AccessControlStorage storage storage_,
        bytes32 role,
        address account,
        uint256 minDuration
    ) internal view returns (bool) {
        if (!hasRole(storage_, role, account)) return false;
        uint256 grantedAt = storage_.roles[role].grantedAt[account];
        return block.timestamp >= grantedAt + minDuration;
    }

    /**
     * @notice Batch grant roles to multiple accounts
     * @param storage_ The access control storage
     * @param role The role to grant
     * @param accounts Array of accounts to grant the role to
     */
    function batchGrantRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address[] memory accounts
    ) internal {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (!hasRole(storage_, role, accounts[i])) {
                grantRole(storage_, role, accounts[i]);
            }
        }
    }

    /**
     * @notice Batch revoke roles from multiple accounts
     * @param storage_ The access control storage
     * @param role The role to revoke
     * @param accounts Array of accounts to revoke the role from
     */
    function batchRevokeRole(
        AccessControlStorage storage storage_,
        bytes32 role,
        address[] memory accounts
    ) internal {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (hasRole(storage_, role, accounts[i])) {
                revokeRole(storage_, role, accounts[i]);
            }
        }
    }
}
