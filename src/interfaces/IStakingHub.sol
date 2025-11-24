// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStakingHub
 * @notice Interface for staking hub contracts
 * @dev Defines standard staking operations with tiered rewards
 */
interface IStakingHub {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event PoolCreated(uint256 indexed poolId, address stakingToken, address rewardToken);
    event Staked(uint256 indexed poolId, address indexed user, uint256 amount, uint256 lockDuration);
    event Unstaked(uint256 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(uint256 indexed poolId, address indexed user, uint256 amount);
    event TierUpgraded(address indexed user, uint256 oldTier, uint256 newTier);

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

    struct TierInfo {
        uint256 threshold;
        uint256 multiplierBps;
        uint256 bonusAmount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new staking pool
     * @param stakingToken Token to stake
     * @param rewardToken Token for rewards
     * @param rewardRate Rewards per second
     * @param poolCap Maximum pool capacity
     * @return poolId Created pool ID
     */
    function createPool(
        address stakingToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 poolCap
    ) external returns (uint256 poolId);

    /**
     * @notice Update pool reward rate
     * @param poolId Pool ID
     * @param newRate New reward rate
     */
    function setPoolRewardRate(uint256 poolId, uint256 newRate) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Stake tokens without lock
     * @param poolId Pool to stake in
     * @param amount Amount to stake
     * @return shares Shares received
     */
    function stake(uint256 poolId, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Stake tokens with time lock for boost
     * @param poolId Pool to stake in
     * @param amount Amount to stake
     * @param lockDuration Lock duration in seconds
     * @return shares Shares received
     */
    function stakeWithLock(
        uint256 poolId,
        uint256 amount,
        uint256 lockDuration
    ) external returns (uint256 shares);

    /**
     * @notice Initiate unstake cooldown
     * @param poolId Pool ID
     * @param amount Amount to unstake
     */
    function initiateUnstake(uint256 poolId, uint256 amount) external;

    /**
     * @notice Complete unstake after cooldown
     * @param poolId Pool ID
     * @return amount Amount unstaked
     * @return rewards Rewards claimed
     */
    function completeUnstake(uint256 poolId)
        external
        returns (uint256 amount, uint256 rewards);

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARDS FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim rewards from a pool
     * @param poolId Pool ID
     * @return rewards Amount claimed
     */
    function claimRewards(uint256 poolId) external returns (uint256 rewards);

    /**
     * @notice Compound rewards back into stake
     * @param poolId Pool ID
     * @return compounded Amount compounded
     */
    function compoundRewards(uint256 poolId) external returns (uint256 compounded);

    /**
     * @notice Get pending rewards for user
     * @param poolId Pool ID
     * @param user User address
     * @return pending Pending reward amount
     */
    function getPendingRewards(uint256 poolId, address user)
        external
        view
        returns (uint256 pending);

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user staking stats for a pool
     * @param poolId Pool ID
     * @param user User address
     * @return stats Staker statistics
     */
    function getUserPoolStats(uint256 poolId, address user)
        external
        view
        returns (StakerStats memory stats);

    /**
     * @notice Get user's current tier
     * @param user User address
     * @return tier User's tier index
     */
    function getUserTier(address user) external view returns (uint256 tier);

    /**
     * @notice Get user's current multiplier
     * @param user User address
     * @return multiplier Current multiplier (WAD)
     */
    function getUserMultiplier(address user) external view returns (uint256 multiplier);

    /**
     * @notice Get tier info
     * @param tierIndex Tier index
     * @return info Tier information
     */
    function getTierInfo(uint256 tierIndex) external view returns (TierInfo memory info);

    /**
     * @notice Get pool APR
     * @param poolId Pool ID
     * @return apr Annual percentage rate (WAD)
     */
    function getPoolAPR(uint256 poolId) external view returns (uint256 apr);

    /**
     * @notice Calculate boost for lock duration
     * @param lockDuration Lock duration in seconds
     * @return boost Boost multiplier (WAD)
     */
    function calculateLockBoost(uint256 lockDuration) external view returns (uint256 boost);
}
