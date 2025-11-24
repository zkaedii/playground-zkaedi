// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISecurityManager
 * @notice Interface for security management contracts
 * @dev Defines standard security operations for DeFi protocols
 */
interface ISecurityManager {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event OperationQueued(bytes32 indexed operationId, address target, uint256 eta);
    event OperationExecuted(bytes32 indexed operationId, address target);
    event OperationCancelled(bytes32 indexed operationId);
    event EmergencyActivated(bytes32 reason);
    event EmergencyDeactivated();
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMELOCK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Queue an operation for timelock execution
     * @param target Target contract
     * @param data Calldata
     * @param value ETH value
     * @param delay Delay in seconds
     * @return operationId Unique operation identifier
     */
    function queueOperation(
        address target,
        bytes calldata data,
        uint256 value,
        uint256 delay
    ) external returns (bytes32 operationId);

    /**
     * @notice Execute a queued operation
     * @param operationId Operation ID
     * @return success True if execution succeeded
     * @return returnData Return data from execution
     */
    function executeOperation(bytes32 operationId)
        external
        returns (bool success, bytes memory returnData);

    /**
     * @notice Cancel a queued operation
     * @param operationId Operation ID
     */
    function cancelOperation(bytes32 operationId) external;

    /**
     * @notice Add guardian signature to operation
     * @param operationId Operation ID
     */
    function signOperation(bytes32 operationId) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Activate emergency mode
     * @param reason Reason for emergency
     */
    function activateEmergency(bytes32 reason) external;

    /**
     * @notice Deactivate emergency mode
     */
    function deactivateEmergency() external;

    /**
     * @notice Check if emergency mode is active
     * @return active True if emergency mode is active
     */
    function isEmergencyActive() external view returns (bool active);

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Grant role to account
     * @param role Role identifier
     * @param account Account to grant role
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Revoke role from account
     * @param role Role identifier
     * @param account Account to revoke role
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Check if account has role
     * @param role Role identifier
     * @param account Account to check
     * @return hasRole True if account has role
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    // ═══════════════════════════════════════════════════════════════════════════
    // BLACKLIST MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add address to blacklist
     * @param account Address to blacklist
     */
    function blacklist(address account) external;

    /**
     * @notice Remove address from blacklist
     * @param account Address to remove
     */
    function removeFromBlacklist(address account) external;

    /**
     * @notice Check if address is blacklisted
     * @param account Address to check
     * @return blacklisted True if blacklisted
     */
    function isBlacklisted(address account) external view returns (bool blacklisted);

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
     * @return valid True if signature is valid
     */
    function validateSignature(
        address signer,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (bool valid);

    /**
     * @notice Get user's current nonce
     * @param user User address
     * @return nonce Current nonce
     */
    function getNonce(address user) external view returns (uint256 nonce);
}
