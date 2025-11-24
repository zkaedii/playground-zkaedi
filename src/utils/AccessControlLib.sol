// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AccessControlLib
 * @notice Role-based access control utilities with delegation and time-locks
 * @dev Provides flexible permission management for DeFi protocols
 */
library AccessControlLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Role data structure
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;        // Role that can manage this role
        uint64 memberCount;       // Number of members
    }

    /// @notice Role storage
    struct Roles {
        mapping(bytes32 => RoleData) roles;
        mapping(address => uint256) userRoleBitmap;  // Bitmap of user's roles
    }

    /// @notice Time-locked role change
    struct PendingRoleChange {
        address account;
        bytes32 role;
        bool isGrant;             // true = grant, false = revoke
        uint64 executeAfter;      // Timestamp when executable
        uint64 expiresAt;         // Timestamp when expires
        bool executed;
    }

    /// @notice Delegation record
    struct Delegation {
        address delegatee;        // Who can act on behalf
        bytes32 role;             // Which role is delegated
        uint64 validUntil;        // Expiry timestamp
        bool active;
    }

    /// @notice Multi-sig requirement
    struct MultiSigRequirement {
        uint8 threshold;          // Required signatures
        uint8 signerCount;        // Total signers
        mapping(address => bool) isSigner;
        mapping(bytes32 => mapping(address => bool)) approvals;
        mapping(bytes32 => uint8) approvalCount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error MissingRole(address account, bytes32 role);
    error RoleAlreadyGranted(address account, bytes32 role);
    error RoleNotGranted(address account, bytes32 role);
    error CannotRenounceOthersRole();
    error TimeLockNotExpired(uint64 executeAfter, uint64 currentTime);
    error ChangeExpired(uint64 expiresAt, uint64 currentTime);
    error ChangeAlreadyExecuted();
    error DelegationExpired();
    error DelegationNotActive();
    error InvalidThreshold();
    error NotASigner();
    error AlreadyApproved();
    error ThresholdNotMet(uint8 current, uint8 required);

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS (for use in implementing contracts)
    // ═══════════════════════════════════════════════════════════════════════════

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdmin, bytes32 indexed newAdmin);
    event RoleChangeScheduled(bytes32 indexed role, address indexed account, bool isGrant, uint64 executeAfter);
    event DelegationCreated(address indexed delegator, address indexed delegatee, bytes32 role);
    event DelegationRevoked(address indexed delegator, address indexed delegatee, bytes32 role);

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC ROLE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if account has role
     * @param roles Role storage
     * @param role Role to check
     * @param account Account to check
     * @return True if account has role
     */
    function hasRole(
        Roles storage roles,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return roles.roles[role].members[account];
    }

    /**
     * @notice Require account has role (reverts if not)
     */
    function checkRole(
        Roles storage roles,
        bytes32 role,
        address account
    ) internal view {
        if (!hasRole(roles, role, account)) {
            revert MissingRole(account, role);
        }
    }

    /**
     * @notice Grant role to account
     * @param roles Role storage
     * @param role Role to grant
     * @param account Account to receive role
     */
    function grantRole(
        Roles storage roles,
        bytes32 role,
        address account
    ) internal {
        if (hasRole(roles, role, account)) {
            revert RoleAlreadyGranted(account, role);
        }

        roles.roles[role].members[account] = true;
        roles.roles[role].memberCount++;
    }

    /**
     * @notice Revoke role from account
     */
    function revokeRole(
        Roles storage roles,
        bytes32 role,
        address account
    ) internal {
        if (!hasRole(roles, role, account)) {
            revert RoleNotGranted(account, role);
        }

        roles.roles[role].members[account] = false;
        roles.roles[role].memberCount--;
    }

    /**
     * @notice Renounce own role
     */
    function renounceRole(
        Roles storage roles,
        bytes32 role,
        address account,
        address caller
    ) internal {
        if (account != caller) {
            revert CannotRenounceOthersRole();
        }
        revokeRole(roles, role, account);
    }

    /**
     * @notice Set admin role for a role
     */
    function setRoleAdmin(
        Roles storage roles,
        bytes32 role,
        bytes32 adminRole
    ) internal {
        roles.roles[role].adminRole = adminRole;
    }

    /**
     * @notice Get admin role for a role
     */
    function getRoleAdmin(
        Roles storage roles,
        bytes32 role
    ) internal view returns (bytes32) {
        return roles.roles[role].adminRole;
    }

    /**
     * @notice Get member count for role
     */
    function getRoleMemberCount(
        Roles storage roles,
        bytes32 role
    ) internal view returns (uint64) {
        return roles.roles[role].memberCount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME-LOCKED ROLE CHANGES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Schedule a role change with time-lock
     */
    function scheduleRoleChange(
        PendingRoleChange storage pending,
        address account,
        bytes32 role,
        bool isGrant,
        uint64 delay,
        uint64 validityPeriod
    ) internal {
        pending.account = account;
        pending.role = role;
        pending.isGrant = isGrant;
        pending.executeAfter = uint64(block.timestamp) + delay;
        pending.expiresAt = pending.executeAfter + validityPeriod;
        pending.executed = false;
    }

    /**
     * @notice Execute scheduled role change
     */
    function executeRoleChange(
        Roles storage roles,
        PendingRoleChange storage pending
    ) internal {
        if (pending.executed) revert ChangeAlreadyExecuted();
        if (block.timestamp < pending.executeAfter) {
            revert TimeLockNotExpired(pending.executeAfter, uint64(block.timestamp));
        }
        if (block.timestamp > pending.expiresAt) {
            revert ChangeExpired(pending.expiresAt, uint64(block.timestamp));
        }

        pending.executed = true;

        if (pending.isGrant) {
            grantRole(roles, pending.role, pending.account);
        } else {
            revokeRole(roles, pending.role, pending.account);
        }
    }

    /**
     * @notice Cancel pending role change
     */
    function cancelRoleChange(PendingRoleChange storage pending) internal {
        pending.executed = true; // Mark as executed to prevent future execution
    }

    /**
     * @notice Check if role change is ready to execute
     */
    function isRoleChangeReady(PendingRoleChange storage pending) internal view returns (bool) {
        return !pending.executed &&
               block.timestamp >= pending.executeAfter &&
               block.timestamp <= pending.expiresAt;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE DELEGATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create delegation
     */
    function delegate(
        Delegation storage delegation,
        address delegatee,
        bytes32 role,
        uint64 duration
    ) internal {
        delegation.delegatee = delegatee;
        delegation.role = role;
        delegation.validUntil = uint64(block.timestamp) + duration;
        delegation.active = true;
    }

    /**
     * @notice Revoke delegation
     */
    function revokeDelegation(Delegation storage delegation) internal {
        delegation.active = false;
    }

    /**
     * @notice Check if delegation is valid
     */
    function isDelegationValid(Delegation storage delegation) internal view returns (bool) {
        return delegation.active && block.timestamp <= delegation.validUntil;
    }

    /**
     * @notice Check if account can act for role (either has role or valid delegation)
     */
    function canActForRole(
        Roles storage roles,
        bytes32 role,
        address account,
        mapping(address => Delegation) storage delegations
    ) internal view returns (bool) {
        // Direct role holder
        if (hasRole(roles, role, account)) return true;

        // Check delegation
        Delegation storage delegation = delegations[account];
        return delegation.role == role && isDelegationValid(delegation);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-SIG OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize multi-sig requirement
     */
    function initMultiSig(
        MultiSigRequirement storage multiSig,
        address[] memory signers,
        uint8 threshold
    ) internal {
        if (threshold == 0 || threshold > signers.length) {
            revert InvalidThreshold();
        }

        multiSig.threshold = threshold;
        multiSig.signerCount = uint8(signers.length);

        for (uint256 i; i < signers.length;) {
            multiSig.isSigner[signers[i]] = true;
            unchecked { ++i; }
        }
    }

    /**
     * @notice Approve operation
     */
    function approve(
        MultiSigRequirement storage multiSig,
        bytes32 operationId,
        address signer
    ) internal {
        if (!multiSig.isSigner[signer]) revert NotASigner();
        if (multiSig.approvals[operationId][signer]) revert AlreadyApproved();

        multiSig.approvals[operationId][signer] = true;
        multiSig.approvalCount[operationId]++;
    }

    /**
     * @notice Check if operation has enough approvals
     */
    function hasEnoughApprovals(
        MultiSigRequirement storage multiSig,
        bytes32 operationId
    ) internal view returns (bool) {
        return multiSig.approvalCount[operationId] >= multiSig.threshold;
    }

    /**
     * @notice Require enough approvals or revert
     */
    function requireApprovals(
        MultiSigRequirement storage multiSig,
        bytes32 operationId
    ) internal view {
        uint8 current = multiSig.approvalCount[operationId];
        if (current < multiSig.threshold) {
            revert ThresholdNotMet(current, multiSig.threshold);
        }
    }

    /**
     * @notice Reset approvals for operation
     */
    function resetApprovals(
        MultiSigRequirement storage multiSig,
        bytes32 operationId,
        address[] memory signers
    ) internal {
        for (uint256 i; i < signers.length;) {
            multiSig.approvals[operationId][signers[i]] = false;
            unchecked { ++i; }
        }
        multiSig.approvalCount[operationId] = 0;
    }

    /**
     * @notice Add signer to multi-sig
     */
    function addSigner(
        MultiSigRequirement storage multiSig,
        address signer
    ) internal {
        if (!multiSig.isSigner[signer]) {
            multiSig.isSigner[signer] = true;
            multiSig.signerCount++;
        }
    }

    /**
     * @notice Remove signer from multi-sig
     */
    function removeSigner(
        MultiSigRequirement storage multiSig,
        address signer
    ) internal {
        if (multiSig.isSigner[signer]) {
            multiSig.isSigner[signer] = false;
            multiSig.signerCount--;

            // Ensure threshold is still achievable
            if (multiSig.threshold > multiSig.signerCount) {
                multiSig.threshold = multiSig.signerCount;
            }
        }
    }

    /**
     * @notice Update threshold
     */
    function updateThreshold(
        MultiSigRequirement storage multiSig,
        uint8 newThreshold
    ) internal {
        if (newThreshold == 0 || newThreshold > multiSig.signerCount) {
            revert InvalidThreshold();
        }
        multiSig.threshold = newThreshold;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if account has any of the specified roles
     */
    function hasAnyRole(
        Roles storage roles,
        address account,
        bytes32[] memory roleList
    ) internal view returns (bool) {
        for (uint256 i; i < roleList.length;) {
            if (hasRole(roles, roleList[i], account)) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Check if account has all specified roles
     */
    function hasAllRoles(
        Roles storage roles,
        address account,
        bytes32[] memory roleList
    ) internal view returns (bool) {
        for (uint256 i; i < roleList.length;) {
            if (!hasRole(roles, roleList[i], account)) return false;
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @notice Generate role from string
     */
    function roleFromString(string memory roleString) internal pure returns (bytes32) {
        return keccak256(bytes(roleString));
    }

    /**
     * @notice Generate operation ID for multi-sig
     */
    function generateOperationId(
        address target,
        bytes memory data,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, data, nonce));
    }
}
