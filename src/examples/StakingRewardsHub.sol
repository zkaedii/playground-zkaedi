// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/StakingLib.sol";
import "../utils/RewardLib.sol";
import "../utils/ValidatorsLib.sol";

/**
 * @title StakingRewardsHub
 * @notice Multi-pool staking hub with tiered rewards and vesting
 * @dev Demonstrates advanced staking patterns with multiple reward tokens
 */
contract StakingRewardsHub {
    using StakingLib for StakingLib.StakingPool;
    using RewardLib for *;
    using ValidatorsLib for *;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public constant MAX_POOLS = 10;
    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_LOCK_DURATION = 4 * 365 days;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Pool ID counter
    uint256 public poolCount;

    /// @notice Staking pools by ID
    mapping(uint256 => StakingLib.StakingPool) private stakingPools;

    /// @notice Pool staking tokens
    mapping(uint256 => address) public poolTokens;

    /// @notice Tiered rewards system
    RewardLib.TieredRewards private tieredRewards;

    /// @notice Epoch-based rewards
    RewardLib.EpochRewards private epochRewards;

    /// @notice User vesting schedules
    mapping(address => RewardLib.VestingSchedule) private vestingSchedules;

    /// @notice User multipliers
    mapping(address => RewardLib.UserMultiplier) private userMultipliers;

    /// @notice Multiplier configuration
    RewardLib.MultiplierConfig private multiplierConfig;

    /// @notice Lock schedule for boost calculation
    StakingLib.LockSchedule public lockSchedule;

    /// @notice Owner
    address public owner;

    /// @notice Paused state
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event PoolCreated(uint256 indexed poolId, address stakingToken, address rewardToken);
    event Staked(uint256 indexed poolId, address indexed user, uint256 amount, uint256 lockDuration);
    event Unstaked(uint256 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(uint256 indexed poolId, address indexed user, uint256 amount);
    event VestingCreated(address indexed beneficiary, uint256 amount, uint256 duration);
    event VestingClaimed(address indexed beneficiary, uint256 amount);
    event TierUpgraded(address indexed user, uint256 oldTier, uint256 newTier);
    event MultiplierBoosted(address indexed user, uint256 newMultiplier);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error Unauthorized();
    error Paused();
    error InvalidPool();
    error TransferFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier validPool(uint256 poolId) {
        if (poolId >= poolCount) revert InvalidPool();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor() {
        owner = msg.sender;

        // Initialize lock schedule
        lockSchedule = StakingLib.LockSchedule({
            baseMultiplier: WAD,           // 1x base
            maxMultiplier: 4 * WAD,        // 4x max
            minLockDuration: 7 days,
            maxLockDuration: MAX_LOCK_DURATION
        });

        // Initialize multiplier config
        multiplierConfig.initializeMultiplier(
            WAD,           // 1x base
            10 * WAD,      // 10x max
            WAD / 10,      // 0.1x boost per unit
            WAD / (365 days) // Decay over 1 year
        );

        // Initialize tiered rewards (5 tiers)
        tieredRewards.addTier(0, 10000, 0);              // Bronze: 1x, no bonus
        tieredRewards.addTier(1000 * WAD, 12500, 100);   // Silver: 1.25x, 100 token bonus
        tieredRewards.addTier(10000 * WAD, 15000, 500);  // Gold: 1.5x, 500 token bonus
        tieredRewards.addTier(50000 * WAD, 20000, 2000); // Platinum: 2x, 2000 token bonus
        tieredRewards.addTier(100000 * WAD, 30000, 5000);// Diamond: 3x, 5000 token bonus

        // Initialize epoch rewards (7-day epochs)
        epochRewards.initializeEpochRewards(7 days, 10000 * WAD);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new staking pool
     * @param stakingToken Token to stake
     * @param rewardToken Token for rewards
     * @param rewardRate Rewards per second
     * @param poolCap Maximum pool capacity (0 = unlimited)
     */
    function createPool(
        address stakingToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 poolCap
    ) external onlyOwner returns (uint256 poolId) {
        ValidatorsLib.requireNonZeroAddress(stakingToken);
        ValidatorsLib.requireNonZeroAddress(rewardToken);

        poolId = poolCount++;

        stakingPools[poolId].initializePool(
            stakingToken,
            rewardToken,
            rewardRate,
            poolCap == 0 ? type(uint256).max : poolCap
        );

        poolTokens[poolId] = stakingToken;

        emit PoolCreated(poolId, stakingToken, rewardToken);
    }

    /**
     * @notice Update pool reward rate
     * @param poolId Pool ID
     * @param newRate New reward rate
     */
    function setPoolRewardRate(uint256 poolId, uint256 newRate)
        external
        onlyOwner
        validPool(poolId)
    {
        stakingPools[poolId].setRewardRate(newRate);
    }

    /**
     * @notice Pause/unpause pool
     * @param poolId Pool ID
     * @param status New status
     */
    function setPoolStatus(uint256 poolId, StakingLib.PoolStatus status)
        external
        onlyOwner
        validPool(poolId)
    {
        stakingPools[poolId].setPoolStatus(status);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Stake tokens without lock
     * @param poolId Pool to stake in
     * @param amount Amount to stake
     */
    function stake(uint256 poolId, uint256 amount)
        external
        whenNotPaused
        validPool(poolId)
        returns (uint256 shares)
    {
        ValidatorsLib.requireNonZeroAmount(amount);

        shares = stakingPools[poolId].stake(msg.sender, amount);

        // Update user tier
        _updateUserTier(msg.sender, poolId);

        // Record epoch shares
        epochRewards.recordEpochShares(msg.sender, shares);

        // Transfer tokens
        _transferIn(poolTokens[poolId], amount);

        emit Staked(poolId, msg.sender, amount, 0);
    }

    /**
     * @notice Stake tokens with time lock for boost
     * @param poolId Pool to stake in
     * @param amount Amount to stake
     * @param lockDuration Lock duration in seconds
     */
    function stakeWithLock(uint256 poolId, uint256 amount, uint256 lockDuration)
        external
        whenNotPaused
        validPool(poolId)
        returns (uint256 shares)
    {
        ValidatorsLib.requireNonZeroAmount(amount);
        ValidatorsLib.requireValidDuration(
            lockDuration,
            lockSchedule.minLockDuration,
            lockSchedule.maxLockDuration
        );

        shares = stakingPools[poolId].stakeWithLock(
            msg.sender,
            amount,
            lockDuration,
            lockSchedule
        );

        // Apply multiplier boost based on lock
        uint256 boostUnits = lockDuration / 30 days; // 1 boost unit per month
        userMultipliers[msg.sender].applyBoost(multiplierConfig, boostUnits);

        // Update user tier
        _updateUserTier(msg.sender, poolId);

        // Record epoch shares
        epochRewards.recordEpochShares(msg.sender, shares);

        // Transfer tokens
        _transferIn(poolTokens[poolId], amount);

        emit Staked(poolId, msg.sender, amount, lockDuration);
        emit MultiplierBoosted(msg.sender, userMultipliers[msg.sender].currentMultiplier);
    }

    /**
     * @notice Initiate unstake cooldown
     * @param poolId Pool ID
     * @param amount Amount to unstake
     */
    function initiateUnstake(uint256 poolId, uint256 amount)
        external
        validPool(poolId)
    {
        ValidatorsLib.requireNonZeroAmount(amount);
        stakingPools[poolId].initiateCooldown(msg.sender, amount);
    }

    /**
     * @notice Complete unstake after cooldown
     * @param poolId Pool ID
     */
    function completeUnstake(uint256 poolId)
        external
        validPool(poolId)
        returns (uint256 amount, uint256 rewards)
    {
        (amount, rewards) = stakingPools[poolId].unstake(msg.sender);

        // Apply tiered reward multiplier
        uint256 userTier = tieredRewards.userTiers[msg.sender];
        RewardLib.RewardTier storage tier = tieredRewards.tiers[userTier];
        rewards = (rewards * tier.multiplierBps) / 10000;
        rewards += tier.bonusAmount;

        // Transfer tokens
        _transferOut(poolTokens[poolId], amount);

        // Transfer rewards (assuming same token for simplicity)
        if (rewards > 0) {
            _transferOut(stakingPools[poolId].config.rewardToken, rewards);
        }

        // Update user tier
        _updateUserTier(msg.sender, poolId);

        emit Unstaked(poolId, msg.sender, amount);
        if (rewards > 0) {
            emit RewardsClaimed(poolId, msg.sender, rewards);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARDS FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim rewards from a pool
     * @param poolId Pool ID
     */
    function claimRewards(uint256 poolId)
        external
        validPool(poolId)
        returns (uint256 rewards)
    {
        rewards = stakingPools[poolId].claimRewards(msg.sender);

        if (rewards > 0) {
            // Apply tiered multiplier
            rewards = tieredRewards.calculateTieredReward(
                rewards,
                stakingPools[poolId].stakes[msg.sender].amount
            );

            // Apply user multiplier
            uint256 multiplier = userMultipliers[msg.sender].calculateMultiplier(multiplierConfig);
            rewards = (rewards * multiplier) / WAD;

            _transferOut(stakingPools[poolId].config.rewardToken, rewards);
        }

        emit RewardsClaimed(poolId, msg.sender, rewards);
    }

    /**
     * @notice Claim epoch rewards
     * @param startEpoch First epoch to claim
     * @param endEpoch Last epoch to claim
     */
    function claimEpochRewards(uint256 startEpoch, uint256 endEpoch)
        external
        returns (uint256 totalRewards)
    {
        totalRewards = epochRewards.claimMultipleEpochs(msg.sender, startEpoch, endEpoch);

        if (totalRewards > 0) {
            // Apply multipliers
            uint256 multiplier = userMultipliers[msg.sender].calculateMultiplier(multiplierConfig);
            totalRewards = (totalRewards * multiplier) / WAD;

            // Note: In production, transfer actual reward tokens
        }
    }

    /**
     * @notice Compound rewards back into stake
     * @param poolId Pool ID
     */
    function compoundRewards(uint256 poolId)
        external
        validPool(poolId)
        returns (uint256 compounded)
    {
        uint256 rewards = stakingPools[poolId].claimRewards(msg.sender);

        if (rewards > 0) {
            // Re-stake rewards
            compounded = stakingPools[poolId].stake(msg.sender, rewards);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VESTING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create vesting schedule for user
     * @param beneficiary Vesting beneficiary
     * @param amount Total vesting amount
     * @param cliffDuration Cliff duration
     * @param vestingDuration Total vesting duration
     */
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) external onlyOwner {
        ValidatorsLib.requireNonZeroAddress(beneficiary);
        ValidatorsLib.requireNonZeroAmount(amount);

        RewardLib.VestingConfig memory config = RewardLib.VestingConfig({
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            slicePeriod: 1 days,
            revocable: true
        });

        vestingSchedules[beneficiary] = RewardLib.createVestingSchedule(amount, config);

        emit VestingCreated(beneficiary, amount, vestingDuration);
    }

    /**
     * @notice Claim vested tokens
     */
    function claimVested() external returns (uint256 claimed) {
        claimed = vestingSchedules[msg.sender].claimVested();

        if (claimed > 0) {
            // Transfer vested tokens
            // Note: In production, transfer actual tokens
            emit VestingClaimed(msg.sender, claimed);
        }
    }

    /**
     * @notice Get claimable vested amount
     * @param user User address
     */
    function getClaimableVested(address user) external view returns (uint256) {
        return vestingSchedules[user].calculateClaimable();
    }

    /**
     * @notice Get total vested amount
     * @param user User address
     */
    function getVestedAmount(address user) external view returns (uint256) {
        return vestingSchedules[user].calculateVestedAmount();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user staking stats for a pool
     * @param poolId Pool ID
     * @param user User address
     */
    function getUserPoolStats(uint256 poolId, address user)
        external
        view
        validPool(poolId)
        returns (StakingLib.StakerStats memory)
    {
        return stakingPools[poolId].getStakerStats(user);
    }

    /**
     * @notice Get pending rewards for user
     * @param poolId Pool ID
     * @param user User address
     */
    function getPendingRewards(uint256 poolId, address user)
        external
        view
        validPool(poolId)
        returns (uint256)
    {
        return stakingPools[poolId].pendingRewards(user);
    }

    /**
     * @notice Get user's current tier
     * @param user User address
     */
    function getUserTier(address user) external view returns (uint256) {
        return tieredRewards.userTiers[user];
    }

    /**
     * @notice Get user's current multiplier
     * @param user User address
     */
    function getUserMultiplier(address user) external view returns (uint256) {
        return userMultipliers[user].calculateMultiplier(multiplierConfig);
    }

    /**
     * @notice Get tier info
     * @param tierIndex Tier index
     */
    function getTierInfo(uint256 tierIndex) external view returns (RewardLib.RewardTier memory) {
        require(tierIndex < tieredRewards.tiers.length, "Invalid tier");
        return tieredRewards.tiers[tierIndex];
    }

    /**
     * @notice Get current epoch
     */
    function getCurrentEpoch() external view returns (uint256) {
        return epochRewards.currentEpoch;
    }

    /**
     * @notice Calculate boost for lock duration
     * @param lockDuration Lock duration in seconds
     */
    function calculateLockBoost(uint256 lockDuration) external view returns (uint256) {
        return StakingLib.calculateBoostMultiplier(lockDuration, lockSchedule);
    }

    /**
     * @notice Get pool APR
     * @param poolId Pool ID
     */
    function getPoolAPR(uint256 poolId) external view validPool(poolId) returns (uint256) {
        return StakingLib.calculateAPR(
            stakingPools[poolId].config.rewardRate,
            stakingPools[poolId].config.totalStaked
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function _updateUserTier(address user, uint256 poolId) internal {
        uint256 userStake = stakingPools[poolId].stakes[user].amount;
        (uint256 oldTier, uint256 newTier) = tieredRewards.updateUserTier(user, userStake);

        if (oldTier != newTier) {
            emit TierUpgraded(user, oldTier, newTier);
        }
    }

    function _transferIn(address token, uint256 amount) internal {
        (bool success,) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                amount
            )
        );
        if (!success) revert TransferFailed();
    }

    function _transferOut(address token, uint256 amount) internal {
        (bool success,) = token.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender,
                amount
            )
        );
        if (!success) revert TransferFailed();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        ValidatorsLib.requireNonZeroAddress(newOwner);
        owner = newOwner;
    }
}
