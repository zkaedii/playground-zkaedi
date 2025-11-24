// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVault
 * @notice Interface for DeFi vault contracts
 * @dev Defines standard vault operations with security features
 */
interface IVault {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyActivated(address indexed activator, bytes32 reason);
    event EmergencyDeactivated(address indexed deactivator);
    event RefundCreated(bytes32 indexed refundId, address indexed recipient, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    struct StakerStats {
        uint256 totalStaked;
        uint256 totalRewardsClaimed;
        uint256 currentRewards;
        uint256 votingPower;
        uint256 delegatedPower;
        uint256 lockEndTime;
        uint256 boostMultiplier;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit tokens into the vault
     * @param amount Amount to deposit
     * @return shares Shares received
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Deposit with permit (gasless approval)
     * @param amount Amount to deposit
     * @param deadline Permit deadline
     * @param v Signature v
     * @param r Signature r
     * @param s Signature s
     * @return shares Shares received
     */
    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);

    // ═══════════════════════════════════════════════════════════════════════════
    // WITHDRAWAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initiate withdrawal cooldown
     * @param amount Amount to withdraw
     */
    function initiateWithdrawal(uint256 amount) external;

    /**
     * @notice Complete withdrawal after cooldown
     * @return amount Amount withdrawn
     * @return rewards Rewards claimed
     */
    function completeWithdrawal() external returns (uint256 amount, uint256 rewards);

    /**
     * @notice Emergency withdraw (bypasses cooldown in emergency mode)
     * @return amount Amount withdrawn
     */
    function emergencyWithdraw() external returns (uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARDS FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim pending rewards
     * @return rewards Amount of rewards claimed
     */
    function claimRewards() external returns (uint256 rewards);

    /**
     * @notice Get pending rewards for user
     * @param user User address
     * @return pending Pending reward amount
     */
    function getPendingRewards(address user) external view returns (uint256 pending);

    // ═══════════════════════════════════════════════════════════════════════════
    // REFUND FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a refund for failed transaction
     * @param recipient Refund recipient
     * @param token Token to refund
     * @param amount Refund amount
     * @param reason Reason for refund
     * @return refundId Refund identifier
     */
    function createRefund(
        address recipient,
        address token,
        uint256 amount,
        bytes32 reason
    ) external returns (bytes32 refundId);

    /**
     * @notice Claim a refund
     * @param refundId Refund ID to claim
     */
    function claimRefund(bytes32 refundId) external;

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
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add address to blacklist
     * @param addr Address to blacklist
     */
    function addToBlacklist(address addr) external;

    /**
     * @notice Remove address from blacklist
     * @param addr Address to remove
     */
    function removeFromBlacklist(address addr) external;

    /**
     * @notice Update reward rate
     * @param newRate New reward rate per second
     */
    function setRewardRate(uint256 newRate) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user staking stats
     * @param user User address
     * @return stats Staking statistics
     */
    function getUserStats(address user) external view returns (StakerStats memory stats);

    /**
     * @notice Get remaining rate limit
     * @return remaining Remaining deposits in current window
     */
    function getRemainingDeposits() external view returns (uint256 remaining);

    /**
     * @notice Get user's current nonce
     * @param user User address
     * @return nonce Current nonce
     */
    function getNonce(address user) external view returns (uint256 nonce);

    /**
     * @notice Check if user is blacklisted
     * @param user User address
     * @return blacklisted True if blacklisted
     */
    function isBlacklisted(address user) external view returns (bool blacklisted);

    /**
     * @notice Get vault token address
     * @return token Vault token address
     */
    function vaultToken() external view returns (address token);

    /**
     * @notice Get reward token address
     * @return token Reward token address
     */
    function rewardToken() external view returns (address token);
}
