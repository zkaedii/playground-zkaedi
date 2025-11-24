// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StakingLib
 * @notice Comprehensive staking mechanism utilities for DeFi protocols
 * @dev Provides staking pool management, lock mechanisms, delegation,
 *      slashing, and compound staking calculations
 */
library StakingLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev RAY precision (27 decimals) for high-precision calculations
    uint256 internal constant RAY = 1e27;

    /// @dev Seconds per year (365.25 days)
    uint256 internal constant SECONDS_PER_YEAR = 31557600;

    /// @dev Minimum stake amount (to prevent dust)
    uint256 internal constant MIN_STAKE_AMOUNT = 1e15; // 0.001 tokens (18 decimals)

    /// @dev Maximum lock duration (4 years)
    uint256 internal constant MAX_LOCK_DURATION = 4 * 365 days;

    /// @dev Maximum slashing percentage (100%)
    uint256 internal constant MAX_SLASH_BPS = 10000;

    /// @dev Maximum boost multiplier (4x)
    uint256 internal constant MAX_BOOST_MULTIPLIER = 4 * WAD;

    /// @dev Cooldown period for unstaking
    uint256 internal constant DEFAULT_COOLDOWN = 7 days;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InsufficientStake(uint256 requested, uint256 available);
    error StakeBelowMinimum(uint256 amount, uint256 minimum);
    error StakeLocked(uint256 unlockTime, uint256 currentTime);
    error StakeNotFound(address staker);
    error CooldownNotComplete(uint256 remainingTime);
    error CooldownNotInitiated();
    error InvalidLockDuration(uint256 duration);
    error InvalidBoostMultiplier(uint256 multiplier);
    error SlashAmountTooHigh(uint256 amount, uint256 maximum);
    error PoolNotActive();
    error PoolCapReached(uint256 cap);
    error DelegationNotAllowed();
    error SelfDelegation();
    error AlreadyDelegated(address delegatee);
    error NotDelegated();
    error InvalidSlashPercentage(uint256 percentage);
    error UnstakeWindowClosed();
    error InvalidWithdrawalAmount(uint256 amount);
    error ZeroAddress();
    error ZeroAmount();
    error StakeAlreadyExists(address staker);
    error InvalidCheckpoint();
    error CheckpointNotFound(uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Staking pool status
    enum PoolStatus {
        Inactive,
        Active,
        Paused,
        Deprecated
    }

    /// @notice Stake lock type
    enum LockType {
        None,
        TimeLock,
        VotingEscrow,
        Vesting
    }

    /// @notice Delegation status
    enum DelegationStatus {
        None,
        Active,
        Pending,
        Revoked
    }

    /// @notice Individual stake position
    struct StakePosition {
        uint256 amount;
        uint256 shares;
        uint256 stakedAt;
        uint256 lockEndTime;
        uint256 lastClaimTime;
        uint256 rewardDebt;
        LockType lockType;
        uint256 boostMultiplier;
    }

    /// @notice Staking pool configuration
    struct PoolConfig {
        address stakingToken;
        address rewardToken;
        uint256 rewardRate; // Rewards per second
        uint256 totalStaked;
        uint256 totalShares;
        uint256 accRewardPerShare;
        uint256 lastUpdateTime;
        uint256 poolCap;
        uint256 minStakeAmount;
        uint256 cooldownPeriod;
        uint256 unstakeWindow;
        PoolStatus status;
        bool allowDelegation;
    }

    /// @notice Staking pool storage
    struct StakingPool {
        PoolConfig config;
        mapping(address => StakePosition) stakes;
        mapping(address => address) delegations;
        mapping(address => uint256) delegatedPower;
        mapping(address => CooldownState) cooldowns;
        mapping(uint256 => Checkpoint) checkpoints;
        uint256 checkpointCount;
    }

    /// @notice Cooldown state for unstaking
    struct CooldownState {
        uint256 amount;
        uint256 startTime;
        bool isActive;
    }

    /// @notice Voting power checkpoint
    struct Checkpoint {
        uint256 timestamp;
        uint256 totalPower;
        mapping(address => uint256) userPower;
    }

    /// @notice Lock schedule for time-locked staking
    struct LockSchedule {
        uint256 baseMultiplier; // WAD
        uint256 maxMultiplier; // WAD
        uint256 minLockDuration;
        uint256 maxLockDuration;
    }

    /// @notice Slashing configuration
    struct SlashConfig {
        uint256 maxSlashBps;
        uint256 slashCooldown;
        uint256 lastSlashTime;
        address slashReceiver;
        bool isEnabled;
    }

    /// @notice Slashing record
    struct SlashRecord {
        bytes32 slashId;
        address staker;
        uint256 amount;
        uint256 timestamp;
        bytes32 reason;
    }

    /// @notice Delegation info
    struct DelegationInfo {
        address delegator;
        address delegatee;
        uint256 amount;
        uint256 delegatedAt;
        DelegationStatus status;
    }

    /// @notice Compound staking parameters
    struct CompoundParams {
        uint256 frequency;
        uint256 lastCompound;
        uint256 minCompoundAmount;
        bool autoCompound;
    }

    /// @notice Staker statistics
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
    // POOL MANAGEMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize a staking pool
    /// @param pool Staking pool storage
    /// @param stakingToken Token to stake
    /// @param rewardToken Token for rewards
    /// @param rewardRate Reward rate per second
    /// @param poolCap Maximum pool capacity
    function initializePool(
        StakingPool storage pool,
        address stakingToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 poolCap
    ) internal {
        if (stakingToken == address(0) || rewardToken == address(0)) {
            revert ZeroAddress();
        }

        pool.config.stakingToken = stakingToken;
        pool.config.rewardToken = rewardToken;
        pool.config.rewardRate = rewardRate;
        pool.config.poolCap = poolCap;
        pool.config.minStakeAmount = MIN_STAKE_AMOUNT;
        pool.config.cooldownPeriod = DEFAULT_COOLDOWN;
        pool.config.unstakeWindow = 3 days;
        pool.config.lastUpdateTime = block.timestamp;
        pool.config.status = PoolStatus.Active;
    }

    /// @notice Update pool rewards
    /// @param pool Staking pool storage
    function updatePool(StakingPool storage pool) internal {
        if (pool.config.totalShares == 0) {
            pool.config.lastUpdateTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.config.lastUpdateTime;
        if (timeElapsed == 0) return;

        uint256 rewards = timeElapsed * pool.config.rewardRate;
        pool.config.accRewardPerShare += (rewards * WAD) / pool.config.totalShares;
        pool.config.lastUpdateTime = block.timestamp;
    }

    /// @notice Set pool status
    /// @param pool Staking pool storage
    /// @param status New status
    function setPoolStatus(StakingPool storage pool, PoolStatus status) internal {
        pool.config.status = status;
    }

    /// @notice Update reward rate
    /// @param pool Staking pool storage
    /// @param newRate New reward rate
    function setRewardRate(StakingPool storage pool, uint256 newRate) internal {
        updatePool(pool);
        pool.config.rewardRate = newRate;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Stake tokens
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @param amount Amount to stake
    /// @return shares Shares received
    function stake(
        StakingPool storage pool,
        address staker,
        uint256 amount
    ) internal returns (uint256 shares) {
        if (pool.config.status != PoolStatus.Active) {
            revert PoolNotActive();
        }
        if (amount < pool.config.minStakeAmount) {
            revert StakeBelowMinimum(amount, pool.config.minStakeAmount);
        }
        if (pool.config.poolCap > 0 && pool.config.totalStaked + amount > pool.config.poolCap) {
            revert PoolCapReached(pool.config.poolCap);
        }

        updatePool(pool);

        // Calculate shares
        if (pool.config.totalShares == 0) {
            shares = amount;
        } else {
            shares = (amount * pool.config.totalShares) / pool.config.totalStaked;
        }

        StakePosition storage position = pool.stakes[staker];

        // Claim pending rewards if existing stake
        if (position.shares > 0) {
            uint256 pending = _pendingRewards(pool, staker);
            if (pending > 0) {
                position.lastClaimTime = block.timestamp;
            }
        }

        position.amount += amount;
        position.shares += shares;
        position.stakedAt = block.timestamp;
        position.rewardDebt = (position.shares * pool.config.accRewardPerShare) / WAD;
        position.boostMultiplier = WAD; // 1x by default

        pool.config.totalStaked += amount;
        pool.config.totalShares += shares;

        _updateCheckpoint(pool, staker, position.shares);
    }

    /// @notice Stake with time lock
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @param amount Amount to stake
    /// @param lockDuration Lock duration in seconds
    /// @param schedule Lock schedule configuration
    /// @return shares Shares received
    function stakeWithLock(
        StakingPool storage pool,
        address staker,
        uint256 amount,
        uint256 lockDuration,
        LockSchedule memory schedule
    ) internal returns (uint256 shares) {
        if (lockDuration < schedule.minLockDuration || lockDuration > schedule.maxLockDuration) {
            revert InvalidLockDuration(lockDuration);
        }

        shares = stake(pool, staker, amount);

        StakePosition storage position = pool.stakes[staker];
        position.lockEndTime = block.timestamp + lockDuration;
        position.lockType = LockType.TimeLock;

        // Calculate boost multiplier based on lock duration
        uint256 lockRatio = (lockDuration * WAD) / schedule.maxLockDuration;
        uint256 boostRange = schedule.maxMultiplier - schedule.baseMultiplier;
        position.boostMultiplier = schedule.baseMultiplier + (lockRatio * boostRange) / WAD;

        if (position.boostMultiplier > MAX_BOOST_MULTIPLIER) {
            position.boostMultiplier = MAX_BOOST_MULTIPLIER;
        }
    }

    /// @notice Initiate unstake cooldown
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @param amount Amount to unstake
    function initiateCooldown(
        StakingPool storage pool,
        address staker,
        uint256 amount
    ) internal {
        StakePosition storage position = pool.stakes[staker];

        if (position.amount == 0) {
            revert StakeNotFound(staker);
        }
        if (amount > position.amount) {
            revert InsufficientStake(amount, position.amount);
        }
        if (position.lockEndTime > block.timestamp) {
            revert StakeLocked(position.lockEndTime, block.timestamp);
        }

        CooldownState storage cooldown = pool.cooldowns[staker];
        cooldown.amount = amount;
        cooldown.startTime = block.timestamp;
        cooldown.isActive = true;
    }

    /// @notice Complete unstake after cooldown
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return amount Amount unstaked
    /// @return rewards Pending rewards claimed
    function unstake(
        StakingPool storage pool,
        address staker
    ) internal returns (uint256 amount, uint256 rewards) {
        CooldownState storage cooldown = pool.cooldowns[staker];

        if (!cooldown.isActive) {
            revert CooldownNotInitiated();
        }

        uint256 cooldownEnd = cooldown.startTime + pool.config.cooldownPeriod;
        if (block.timestamp < cooldownEnd) {
            revert CooldownNotComplete(cooldownEnd - block.timestamp);
        }

        uint256 unstakeDeadline = cooldownEnd + pool.config.unstakeWindow;
        if (block.timestamp > unstakeDeadline) {
            revert UnstakeWindowClosed();
        }

        updatePool(pool);

        amount = cooldown.amount;
        StakePosition storage position = pool.stakes[staker];

        // Calculate shares to remove
        uint256 sharesToRemove = (amount * position.shares) / position.amount;

        // Calculate pending rewards
        rewards = _pendingRewards(pool, staker);

        // Update position
        position.amount -= amount;
        position.shares -= sharesToRemove;
        position.rewardDebt = (position.shares * pool.config.accRewardPerShare) / WAD;
        position.lastClaimTime = block.timestamp;

        // Update pool totals
        pool.config.totalStaked -= amount;
        pool.config.totalShares -= sharesToRemove;

        // Clear cooldown
        cooldown.isActive = false;
        cooldown.amount = 0;
        cooldown.startTime = 0;

        _updateCheckpoint(pool, staker, position.shares);
    }

    /// @notice Claim pending rewards
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return rewards Amount of rewards claimed
    function claimRewards(
        StakingPool storage pool,
        address staker
    ) internal returns (uint256 rewards) {
        updatePool(pool);

        rewards = _pendingRewards(pool, staker);

        if (rewards > 0) {
            StakePosition storage position = pool.stakes[staker];
            position.rewardDebt = (position.shares * pool.config.accRewardPerShare) / WAD;
            position.lastClaimTime = block.timestamp;
        }
    }

    /// @notice Calculate pending rewards for staker
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return pending Pending reward amount
    function pendingRewards(
        StakingPool storage pool,
        address staker
    ) internal view returns (uint256 pending) {
        return _pendingRewards(pool, staker);
    }

    /// @dev Internal pending rewards calculation
    function _pendingRewards(
        StakingPool storage pool,
        address staker
    ) private view returns (uint256) {
        StakePosition storage position = pool.stakes[staker];
        if (position.shares == 0) return 0;

        uint256 accRewardPerShare = pool.config.accRewardPerShare;

        if (block.timestamp > pool.config.lastUpdateTime && pool.config.totalShares > 0) {
            uint256 timeElapsed = block.timestamp - pool.config.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.config.rewardRate;
            accRewardPerShare += (rewards * WAD) / pool.config.totalShares;
        }

        uint256 accumulated = (position.shares * accRewardPerShare) / WAD;
        uint256 boosted = (accumulated * position.boostMultiplier) / WAD;

        return boosted > position.rewardDebt ? boosted - position.rewardDebt : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DELEGATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Delegate staking power
    /// @param pool Staking pool storage
    /// @param delegator Address of delegator
    /// @param delegatee Address to delegate to
    function delegate(
        StakingPool storage pool,
        address delegator,
        address delegatee
    ) internal {
        if (!pool.config.allowDelegation) {
            revert DelegationNotAllowed();
        }
        if (delegatee == address(0)) {
            revert ZeroAddress();
        }
        if (delegator == delegatee) {
            revert SelfDelegation();
        }

        StakePosition storage position = pool.stakes[delegator];
        if (position.shares == 0) {
            revert StakeNotFound(delegator);
        }

        address currentDelegatee = pool.delegations[delegator];

        // Remove power from old delegatee
        if (currentDelegatee != address(0)) {
            pool.delegatedPower[currentDelegatee] -= position.shares;
        }

        // Add power to new delegatee
        pool.delegations[delegator] = delegatee;
        pool.delegatedPower[delegatee] += position.shares;
    }

    /// @notice Remove delegation
    /// @param pool Staking pool storage
    /// @param delegator Address of delegator
    function undelegate(StakingPool storage pool, address delegator) internal {
        address currentDelegatee = pool.delegations[delegator];
        if (currentDelegatee == address(0)) {
            revert NotDelegated();
        }

        StakePosition storage position = pool.stakes[delegator];
        pool.delegatedPower[currentDelegatee] -= position.shares;
        pool.delegations[delegator] = address(0);
    }

    /// @notice Get voting power including delegations
    /// @param pool Staking pool storage
    /// @param account Address to check
    /// @return power Total voting power
    function getVotingPower(
        StakingPool storage pool,
        address account
    ) internal view returns (uint256 power) {
        StakePosition storage position = pool.stakes[account];

        // Own stake power (if not delegated)
        if (pool.delegations[account] == address(0)) {
            power = (position.shares * position.boostMultiplier) / WAD;
        }

        // Add delegated power
        power += pool.delegatedPower[account];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SLASHING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Slash staker's stake
    /// @param pool Staking pool storage
    /// @param slashConfig Slashing configuration
    /// @param staker Address to slash
    /// @param percentageBps Slash percentage in basis points
    /// @param reason Reason for slash
    /// @return slashedAmount Amount slashed
    function slash(
        StakingPool storage pool,
        SlashConfig storage slashConfig,
        address staker,
        uint256 percentageBps,
        bytes32 reason
    ) internal returns (uint256 slashedAmount) {
        if (!slashConfig.isEnabled) {
            revert PoolNotActive();
        }
        if (percentageBps > slashConfig.maxSlashBps) {
            revert InvalidSlashPercentage(percentageBps);
        }
        if (block.timestamp < slashConfig.lastSlashTime + slashConfig.slashCooldown) {
            revert CooldownNotComplete(
                slashConfig.lastSlashTime + slashConfig.slashCooldown - block.timestamp
            );
        }

        StakePosition storage position = pool.stakes[staker];
        if (position.amount == 0) {
            revert StakeNotFound(staker);
        }

        updatePool(pool);

        slashedAmount = (position.amount * percentageBps) / BPS_DENOMINATOR;
        uint256 sharesToRemove = (position.shares * percentageBps) / BPS_DENOMINATOR;

        position.amount -= slashedAmount;
        position.shares -= sharesToRemove;
        position.rewardDebt = (position.shares * pool.config.accRewardPerShare) / WAD;

        pool.config.totalStaked -= slashedAmount;
        pool.config.totalShares -= sharesToRemove;

        slashConfig.lastSlashTime = block.timestamp;

        _updateCheckpoint(pool, staker, position.shares);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPOUND STAKING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Compound rewards back into stake
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @param params Compound parameters
    /// @return compoundedAmount Amount compounded
    function compound(
        StakingPool storage pool,
        address staker,
        CompoundParams storage params
    ) internal returns (uint256 compoundedAmount) {
        if (params.frequency > 0 && block.timestamp < params.lastCompound + params.frequency) {
            return 0;
        }

        uint256 rewards = claimRewards(pool, staker);

        if (rewards < params.minCompoundAmount) {
            return 0;
        }

        // Stake the rewards
        uint256 shares = stake(pool, staker, rewards);
        compoundedAmount = rewards;

        params.lastCompound = block.timestamp;
    }

    /// @notice Calculate APY with compounding
    /// @param principalAmount Initial stake amount
    /// @param rewardRate Reward rate per second
    /// @param compoundsPerYear Number of compounds per year
    /// @return apy Annual percentage yield (WAD precision)
    function calculateCompoundAPY(
        uint256 principalAmount,
        uint256 rewardRate,
        uint256 compoundsPerYear
    ) internal pure returns (uint256 apy) {
        if (principalAmount == 0 || compoundsPerYear == 0) return 0;

        // Simple rate per period
        uint256 ratePerPeriod = (rewardRate * SECONDS_PER_YEAR) / compoundsPerYear;
        uint256 ratePerPeriodWad = (ratePerPeriod * WAD) / principalAmount;

        // Compound: (1 + r/n)^n - 1
        // Simplified approximation for on-chain calculation
        uint256 base = WAD + ratePerPeriodWad;
        uint256 result = WAD;

        for (uint256 i; i < compoundsPerYear && i < 365;) {
            result = (result * base) / WAD;
            unchecked { ++i; }
        }

        apy = result - WAD;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHECKPOINT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Update checkpoint for voting power tracking
    function _updateCheckpoint(
        StakingPool storage pool,
        address account,
        uint256 newPower
    ) private {
        uint256 checkpointId = pool.checkpointCount;
        Checkpoint storage checkpoint = pool.checkpoints[checkpointId];

        if (checkpoint.timestamp != block.timestamp) {
            // Create new checkpoint
            unchecked {
                ++pool.checkpointCount;
            }
            checkpoint = pool.checkpoints[pool.checkpointCount];
            checkpoint.timestamp = block.timestamp;

            // Copy previous total if exists
            if (checkpointId > 0) {
                checkpoint.totalPower = pool.checkpoints[checkpointId].totalPower;
            }
        }

        // Update user power in checkpoint
        uint256 oldPower = checkpoint.userPower[account];
        checkpoint.userPower[account] = newPower;
        checkpoint.totalPower = checkpoint.totalPower - oldPower + newPower;
    }

    /// @notice Get voting power at specific timestamp
    /// @param pool Staking pool storage
    /// @param account Account to check
    /// @param timestamp Timestamp to query
    /// @return power Voting power at timestamp
    function getPastVotingPower(
        StakingPool storage pool,
        address account,
        uint256 timestamp
    ) internal view returns (uint256 power) {
        if (timestamp >= block.timestamp) {
            return getVotingPower(pool, account);
        }

        // Binary search for checkpoint
        uint256 low = 0;
        uint256 high = pool.checkpointCount;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (pool.checkpoints[mid].timestamp <= timestamp) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        if (low == 0 && pool.checkpoints[0].timestamp > timestamp) {
            return 0;
        }

        return pool.checkpoints[low].userPower[account];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get staker statistics
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return stats Staker statistics
    function getStakerStats(
        StakingPool storage pool,
        address staker
    ) internal view returns (StakerStats memory stats) {
        StakePosition storage position = pool.stakes[staker];

        stats.totalStaked = position.amount;
        stats.currentRewards = _pendingRewards(pool, staker);
        stats.lockEndTime = position.lockEndTime;
        stats.boostMultiplier = position.boostMultiplier;
        stats.votingPower = (position.shares * position.boostMultiplier) / WAD;
        stats.delegatedPower = pool.delegatedPower[staker];
    }

    /// @notice Get stake position
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return position Stake position
    function getStakePosition(
        StakingPool storage pool,
        address staker
    ) internal view returns (StakePosition storage position) {
        return pool.stakes[staker];
    }

    /// @notice Check if stake is locked
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return isLocked True if stake is locked
    function isStakeLocked(
        StakingPool storage pool,
        address staker
    ) internal view returns (bool isLocked) {
        return pool.stakes[staker].lockEndTime > block.timestamp;
    }

    /// @notice Get remaining lock time
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return remaining Remaining lock time in seconds
    function getRemainingLockTime(
        StakingPool storage pool,
        address staker
    ) internal view returns (uint256 remaining) {
        uint256 lockEnd = pool.stakes[staker].lockEndTime;
        return lockEnd > block.timestamp ? lockEnd - block.timestamp : 0;
    }

    /// @notice Calculate share value
    /// @param pool Staking pool storage
    /// @param shares Number of shares
    /// @return value Value in staked tokens
    function shareValue(
        StakingPool storage pool,
        uint256 shares
    ) internal view returns (uint256 value) {
        if (pool.config.totalShares == 0) return shares;
        return (shares * pool.config.totalStaked) / pool.config.totalShares;
    }

    /// @notice Get cooldown status
    /// @param pool Staking pool storage
    /// @param staker Address of staker
    /// @return isActive Cooldown active status
    /// @return remainingTime Time until cooldown completes
    /// @return amount Amount in cooldown
    function getCooldownStatus(
        StakingPool storage pool,
        address staker
    ) internal view returns (bool isActive, uint256 remainingTime, uint256 amount) {
        CooldownState storage cooldown = pool.cooldowns[staker];
        isActive = cooldown.isActive;
        amount = cooldown.amount;

        if (isActive) {
            uint256 cooldownEnd = cooldown.startTime + pool.config.cooldownPeriod;
            remainingTime = cooldownEnd > block.timestamp ? cooldownEnd - block.timestamp : 0;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate boost multiplier for lock duration
    /// @param lockDuration Lock duration in seconds
    /// @param schedule Lock schedule configuration
    /// @return multiplier Boost multiplier (WAD precision)
    function calculateBoostMultiplier(
        uint256 lockDuration,
        LockSchedule memory schedule
    ) internal pure returns (uint256 multiplier) {
        if (lockDuration < schedule.minLockDuration) {
            return schedule.baseMultiplier;
        }

        if (lockDuration >= schedule.maxLockDuration) {
            return schedule.maxMultiplier;
        }

        uint256 lockRatio = ((lockDuration - schedule.minLockDuration) * WAD) /
            (schedule.maxLockDuration - schedule.minLockDuration);

        uint256 boostRange = schedule.maxMultiplier - schedule.baseMultiplier;
        multiplier = schedule.baseMultiplier + (lockRatio * boostRange) / WAD;
    }

    /// @notice Calculate simple APR
    /// @param rewardRate Reward rate per second
    /// @param totalStaked Total staked amount
    /// @return apr Annual percentage rate (WAD precision)
    function calculateAPR(
        uint256 rewardRate,
        uint256 totalStaked
    ) internal pure returns (uint256 apr) {
        if (totalStaked == 0) return 0;
        return (rewardRate * SECONDS_PER_YEAR * WAD) / totalStaked;
    }

    /// @notice Calculate rewards for duration
    /// @param shares Number of shares
    /// @param rewardRate Reward rate per second
    /// @param totalShares Total shares in pool
    /// @param duration Duration in seconds
    /// @return rewards Expected rewards
    function calculateRewardsForDuration(
        uint256 shares,
        uint256 rewardRate,
        uint256 totalShares,
        uint256 duration
    ) internal pure returns (uint256 rewards) {
        if (totalShares == 0) return 0;
        return (shares * rewardRate * duration) / totalShares;
    }
}
