// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RewardLib
 * @notice Comprehensive reward distribution utilities for DeFi protocols
 * @dev Provides mechanisms for reward calculation, distribution scheduling,
 *      vesting, multipliers, and multi-token reward management
 */
library RewardLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev RAY precision (27 decimals)
    uint256 internal constant RAY = 1e27;

    /// @dev Seconds per day
    uint256 internal constant SECONDS_PER_DAY = 86400;

    /// @dev Seconds per year (365.25 days)
    uint256 internal constant SECONDS_PER_YEAR = 31557600;

    /// @dev Maximum reward tokens per pool
    uint256 internal constant MAX_REWARD_TOKENS = 10;

    /// @dev Maximum tiers for tiered rewards
    uint256 internal constant MAX_TIERS = 20;

    /// @dev Minimum reward amount to distribute
    uint256 internal constant MIN_REWARD_AMOUNT = 1e12;

    /// @dev Maximum multiplier (10x)
    uint256 internal constant MAX_MULTIPLIER = 10 * WAD;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error NoRewardsAvailable();
    error RewardAlreadyClaimed(bytes32 rewardId);
    error RewardNotClaimable(bytes32 rewardId);
    error RewardExpired(bytes32 rewardId);
    error InvalidRewardAmount(uint256 amount);
    error InvalidRewardRate(uint256 rate);
    error RewardPeriodNotStarted(uint256 startTime);
    error RewardPeriodEnded(uint256 endTime);
    error InsufficientRewardBalance(uint256 required, uint256 available);
    error MaxRewardTokensExceeded(uint256 count);
    error RewardTokenAlreadyAdded(address token);
    error RewardTokenNotFound(address token);
    error InvalidVestingSchedule();
    error VestingNotStarted(uint256 startTime);
    error NothingToVest();
    error InvalidMultiplier(uint256 multiplier);
    error InvalidTier(uint256 tier);
    error MaxTiersExceeded(uint256 count);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidDistributionWeights();
    error DistributionFailed(address recipient);
    error CliffNotReached(uint256 cliffEnd);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Reward distribution type
    enum DistributionType {
        Instant,
        Linear,
        Exponential,
        Tiered,
        Epoch,
        Custom
    }

    /// @notice Reward claim status
    enum ClaimStatus {
        Unclaimed,
        PartialClaimed,
        FullyClaimed,
        Expired,
        Forfeited
    }

    /// @notice Single reward token configuration
    struct RewardToken {
        address token;
        uint256 rewardRate; // tokens per second
        uint256 totalDistributed;
        uint256 totalClaimed;
        uint256 accRewardPerShare;
        uint256 lastUpdateTime;
        bool isActive;
    }

    /// @notice Multi-token reward pool
    struct RewardPool {
        RewardToken[] rewardTokens;
        mapping(address => uint256) tokenIndex;
        uint256 totalShares;
        uint256 periodStart;
        uint256 periodEnd;
        bool isActive;
    }

    /// @notice User reward state for a single token
    struct UserRewardState {
        uint256 shares;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 claimedRewards;
        uint256 lastClaimTime;
    }

    /// @notice User rewards across all tokens
    struct UserRewards {
        mapping(address => UserRewardState) tokenStates;
        uint256 totalValueClaimed;
        uint256 multiplier;
    }

    /// @notice Vesting schedule
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 claimed;
        uint256 lastClaimTime;
        bool revocable;
        bool revoked;
    }

    /// @notice Vesting configuration
    struct VestingConfig {
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 slicePeriod; // Minimum claim period
        bool revocable;
    }

    /// @notice Reward tier configuration
    struct RewardTier {
        uint256 threshold; // Minimum requirement for this tier
        uint256 multiplierBps; // Reward multiplier in basis points
        uint256 bonusAmount; // Fixed bonus amount
    }

    /// @notice Tiered reward system
    struct TieredRewards {
        RewardTier[] tiers;
        mapping(address => uint256) userTiers;
        uint256 activeTiers;
    }

    /// @notice Epoch-based reward distribution
    struct EpochRewards {
        uint256 epochDuration;
        uint256 currentEpoch;
        uint256 epochStartTime;
        uint256 rewardsPerEpoch;
        mapping(uint256 => uint256) epochRewards;
        mapping(uint256 => mapping(address => bool)) epochClaimed;
        mapping(uint256 => mapping(address => uint256)) epochShares;
        mapping(uint256 => uint256) epochTotalShares;
    }

    /// @notice Reward distribution record
    struct DistributionRecord {
        bytes32 distributionId;
        address token;
        uint256 amount;
        uint256 timestamp;
        uint256 recipientCount;
        DistributionType distributionType;
    }

    /// @notice Reward multiplier configuration
    struct MultiplierConfig {
        uint256 baseMultiplier; // WAD
        uint256 maxMultiplier; // WAD
        uint256 boostPerUnit; // WAD
        uint256 decayRate; // WAD per second
        uint256 lastUpdateTime;
    }

    /// @notice User multiplier state
    struct UserMultiplier {
        uint256 currentMultiplier;
        uint256 boostExpiry;
        uint256 accumulatedBoost;
        uint256 lastUpdateTime;
    }

    /// @notice Reward emission schedule
    struct EmissionSchedule {
        uint256[] timestamps;
        uint256[] rates;
        uint256 currentIndex;
    }

    /// @notice Reward statistics
    struct RewardStats {
        uint256 totalDistributed;
        uint256 totalClaimed;
        uint256 totalPending;
        uint256 averageClaimTime;
        uint256 uniqueClaimers;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARD POOL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize a reward pool
    /// @param pool Reward pool storage
    /// @param periodStart Start time for rewards
    /// @param periodEnd End time for rewards
    function initializePool(
        RewardPool storage pool,
        uint256 periodStart,
        uint256 periodEnd
    ) internal {
        pool.periodStart = periodStart;
        pool.periodEnd = periodEnd;
        pool.isActive = true;
    }

    /// @notice Add a reward token to the pool
    /// @param pool Reward pool storage
    /// @param token Token address
    /// @param rewardRate Reward rate per second
    function addRewardToken(
        RewardPool storage pool,
        address token,
        uint256 rewardRate
    ) internal {
        if (token == address(0)) revert ZeroAddress();
        if (pool.rewardTokens.length >= MAX_REWARD_TOKENS) {
            revert MaxRewardTokensExceeded(pool.rewardTokens.length);
        }

        // Check if already exists
        for (uint256 i; i < pool.rewardTokens.length;) {
            if (pool.rewardTokens[i].token == token) {
                revert RewardTokenAlreadyAdded(token);
            }
            unchecked { ++i; }
        }

        pool.rewardTokens.push(RewardToken({
            token: token,
            rewardRate: rewardRate,
            totalDistributed: 0,
            totalClaimed: 0,
            accRewardPerShare: 0,
            lastUpdateTime: block.timestamp,
            isActive: true
        }));

        pool.tokenIndex[token] = pool.rewardTokens.length - 1;
    }

    /// @notice Update all reward tokens in pool
    /// @param pool Reward pool storage
    function updatePool(RewardPool storage pool) internal {
        if (pool.totalShares == 0) {
            for (uint256 i; i < pool.rewardTokens.length;) {
                pool.rewardTokens[i].lastUpdateTime = block.timestamp;
                unchecked { ++i; }
            }
            return;
        }

        for (uint256 i; i < pool.rewardTokens.length;) {
            _updateRewardToken(pool, i);
            unchecked { ++i; }
        }
    }

    /// @dev Update single reward token
    function _updateRewardToken(RewardPool storage pool, uint256 index) private {
        RewardToken storage reward = pool.rewardTokens[index];
        if (!reward.isActive) return;

        uint256 currentTime = block.timestamp;
        if (currentTime > pool.periodEnd) {
            currentTime = pool.periodEnd;
        }

        if (currentTime <= reward.lastUpdateTime) return;

        uint256 timeElapsed = currentTime - reward.lastUpdateTime;
        uint256 rewardAmount = timeElapsed * reward.rewardRate;

        reward.accRewardPerShare += (rewardAmount * WAD) / pool.totalShares;
        reward.totalDistributed += rewardAmount;
        reward.lastUpdateTime = currentTime;
    }

    /// @notice Set reward rate for a token
    /// @param pool Reward pool storage
    /// @param token Token address
    /// @param newRate New reward rate
    function setRewardRate(
        RewardPool storage pool,
        address token,
        uint256 newRate
    ) internal {
        uint256 index = pool.tokenIndex[token];
        if (index >= pool.rewardTokens.length || pool.rewardTokens[index].token != token) {
            revert RewardTokenNotFound(token);
        }

        updatePool(pool);
        pool.rewardTokens[index].rewardRate = newRate;
    }

    /// @notice Calculate pending rewards for user
    /// @param pool Reward pool storage
    /// @param userRewards User rewards storage
    /// @param token Reward token address
    /// @return pending Pending reward amount
    function pendingReward(
        RewardPool storage pool,
        UserRewards storage userRewards,
        address token
    ) internal view returns (uint256 pending) {
        uint256 index = pool.tokenIndex[token];
        if (index >= pool.rewardTokens.length) return 0;

        RewardToken storage reward = pool.rewardTokens[index];
        UserRewardState storage state = userRewards.tokenStates[token];

        uint256 accRewardPerShare = reward.accRewardPerShare;

        if (block.timestamp > reward.lastUpdateTime && pool.totalShares > 0) {
            uint256 currentTime = block.timestamp;
            if (currentTime > pool.periodEnd) {
                currentTime = pool.periodEnd;
            }

            uint256 timeElapsed = currentTime - reward.lastUpdateTime;
            uint256 rewardAmount = timeElapsed * reward.rewardRate;
            accRewardPerShare += (rewardAmount * WAD) / pool.totalShares;
        }

        uint256 accumulated = (state.shares * accRewardPerShare) / WAD;
        uint256 multiplied = (accumulated * userRewards.multiplier) / WAD;

        pending = multiplied > state.rewardDebt ? multiplied - state.rewardDebt : 0;
        pending += state.pendingRewards;
    }

    /// @notice Claim rewards for user
    /// @param pool Reward pool storage
    /// @param userRewards User rewards storage
    /// @param token Token to claim
    /// @return claimed Amount claimed
    function claimReward(
        RewardPool storage pool,
        UserRewards storage userRewards,
        address token
    ) internal returns (uint256 claimed) {
        updatePool(pool);

        uint256 index = pool.tokenIndex[token];
        RewardToken storage reward = pool.rewardTokens[index];
        UserRewardState storage state = userRewards.tokenStates[token];

        uint256 accumulated = (state.shares * reward.accRewardPerShare) / WAD;
        uint256 multiplied = (accumulated * userRewards.multiplier) / WAD;

        claimed = multiplied > state.rewardDebt ? multiplied - state.rewardDebt : 0;
        claimed += state.pendingRewards;

        if (claimed == 0) revert NoRewardsAvailable();

        state.rewardDebt = multiplied;
        state.pendingRewards = 0;
        state.claimedRewards += claimed;
        state.lastClaimTime = block.timestamp;

        reward.totalClaimed += claimed;
        userRewards.totalValueClaimed += claimed;
    }

    /// @notice Update user shares
    /// @param pool Reward pool storage
    /// @param userRewards User rewards storage
    /// @param newShares New share amount
    function updateUserShares(
        RewardPool storage pool,
        UserRewards storage userRewards,
        uint256 newShares
    ) internal {
        updatePool(pool);

        // Store pending rewards for all tokens
        for (uint256 i; i < pool.rewardTokens.length;) {
            address token = pool.rewardTokens[i].token;
            UserRewardState storage state = userRewards.tokenStates[token];

            uint256 accumulated = (state.shares * pool.rewardTokens[i].accRewardPerShare) / WAD;
            uint256 multiplied = (accumulated * userRewards.multiplier) / WAD;

            if (multiplied > state.rewardDebt) {
                state.pendingRewards += multiplied - state.rewardDebt;
            }

            state.shares = newShares;
            state.rewardDebt = (newShares * pool.rewardTokens[i].accRewardPerShare * userRewards.multiplier) / (WAD * WAD);

            unchecked { ++i; }
        }

        pool.totalShares = pool.totalShares - userRewards.tokenStates[pool.rewardTokens[0].token].shares + newShares;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VESTING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a vesting schedule
    /// @param totalAmount Total amount to vest
    /// @param config Vesting configuration
    /// @return schedule Created vesting schedule
    function createVestingSchedule(
        uint256 totalAmount,
        VestingConfig memory config
    ) internal view returns (VestingSchedule memory schedule) {
        if (totalAmount == 0) revert ZeroAmount();
        if (config.vestingDuration == 0) revert InvalidVestingSchedule();

        schedule = VestingSchedule({
            totalAmount: totalAmount,
            startTime: block.timestamp,
            cliffDuration: config.cliffDuration,
            vestingDuration: config.vestingDuration,
            claimed: 0,
            lastClaimTime: 0,
            revocable: config.revocable,
            revoked: false
        });
    }

    /// @notice Calculate vested amount
    /// @param schedule Vesting schedule
    /// @return vested Amount vested so far
    function calculateVestedAmount(
        VestingSchedule storage schedule
    ) internal view returns (uint256 vested) {
        if (schedule.revoked) {
            return schedule.claimed;
        }

        uint256 cliffEnd = schedule.startTime + schedule.cliffDuration;
        if (block.timestamp < cliffEnd) {
            return 0;
        }

        uint256 vestingEnd = schedule.startTime + schedule.cliffDuration + schedule.vestingDuration;

        if (block.timestamp >= vestingEnd) {
            return schedule.totalAmount;
        }

        uint256 timeVested = block.timestamp - cliffEnd;
        vested = (schedule.totalAmount * timeVested) / schedule.vestingDuration;
    }

    /// @notice Calculate claimable vested amount
    /// @param schedule Vesting schedule
    /// @return claimable Amount available to claim
    function calculateClaimable(
        VestingSchedule storage schedule
    ) internal view returns (uint256 claimable) {
        uint256 vested = calculateVestedAmount(schedule);
        claimable = vested > schedule.claimed ? vested - schedule.claimed : 0;
    }

    /// @notice Claim vested tokens
    /// @param schedule Vesting schedule storage
    /// @return claimed Amount claimed
    function claimVested(
        VestingSchedule storage schedule
    ) internal returns (uint256 claimed) {
        uint256 cliffEnd = schedule.startTime + schedule.cliffDuration;
        if (block.timestamp < cliffEnd) {
            revert CliffNotReached(cliffEnd);
        }

        claimed = calculateClaimable(schedule);
        if (claimed == 0) revert NothingToVest();

        schedule.claimed += claimed;
        schedule.lastClaimTime = block.timestamp;
    }

    /// @notice Revoke a vesting schedule
    /// @param schedule Vesting schedule storage
    /// @return unvested Amount not yet vested (returned to grantor)
    function revokeVesting(
        VestingSchedule storage schedule
    ) internal returns (uint256 unvested) {
        if (!schedule.revocable) revert InvalidVestingSchedule();
        if (schedule.revoked) revert InvalidVestingSchedule();

        uint256 vested = calculateVestedAmount(schedule);
        unvested = schedule.totalAmount - vested;

        schedule.revoked = true;
        schedule.totalAmount = vested;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIERED REWARD FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add a reward tier
    /// @param tiered Tiered rewards storage
    /// @param threshold Minimum threshold for tier
    /// @param multiplierBps Reward multiplier in basis points
    /// @param bonusAmount Fixed bonus amount
    function addTier(
        TieredRewards storage tiered,
        uint256 threshold,
        uint256 multiplierBps,
        uint256 bonusAmount
    ) internal {
        if (tiered.tiers.length >= MAX_TIERS) {
            revert MaxTiersExceeded(tiered.tiers.length);
        }

        tiered.tiers.push(RewardTier({
            threshold: threshold,
            multiplierBps: multiplierBps,
            bonusAmount: bonusAmount
        }));

        unchecked {
            ++tiered.activeTiers;
        }
    }

    /// @notice Determine user's tier based on value
    /// @param tiered Tiered rewards storage
    /// @param value User's qualifying value
    /// @return tierIndex Index of qualifying tier
    function determineTier(
        TieredRewards storage tiered,
        uint256 value
    ) internal view returns (uint256 tierIndex) {
        for (uint256 i = tiered.tiers.length; i > 0;) {
            unchecked { --i; }
            if (value >= tiered.tiers[i].threshold) {
                return i;
            }
        }
        return 0;
    }

    /// @notice Calculate tiered reward
    /// @param tiered Tiered rewards storage
    /// @param baseReward Base reward amount
    /// @param userValue User's qualifying value
    /// @return reward Calculated reward with tier bonus
    function calculateTieredReward(
        TieredRewards storage tiered,
        uint256 baseReward,
        uint256 userValue
    ) internal view returns (uint256 reward) {
        uint256 tierIndex = determineTier(tiered, userValue);
        RewardTier storage tier = tiered.tiers[tierIndex];

        reward = (baseReward * tier.multiplierBps) / BPS_DENOMINATOR;
        reward += tier.bonusAmount;
    }

    /// @notice Update user's tier
    /// @param tiered Tiered rewards storage
    /// @param user User address
    /// @param newValue New qualifying value
    /// @return oldTier Previous tier
    /// @return newTier New tier
    function updateUserTier(
        TieredRewards storage tiered,
        address user,
        uint256 newValue
    ) internal returns (uint256 oldTier, uint256 newTier) {
        oldTier = tiered.userTiers[user];
        newTier = determineTier(tiered, newValue);
        tiered.userTiers[user] = newTier;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EPOCH REWARD FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize epoch rewards
    /// @param epoch Epoch rewards storage
    /// @param epochDuration Duration of each epoch
    /// @param rewardsPerEpoch Rewards distributed per epoch
    function initializeEpochRewards(
        EpochRewards storage epoch,
        uint256 epochDuration,
        uint256 rewardsPerEpoch
    ) internal {
        epoch.epochDuration = epochDuration;
        epoch.rewardsPerEpoch = rewardsPerEpoch;
        epoch.currentEpoch = 0;
        epoch.epochStartTime = block.timestamp;
    }

    /// @notice Advance to next epoch if needed
    /// @param epoch Epoch rewards storage
    /// @return advanced True if epoch advanced
    function advanceEpochIfNeeded(
        EpochRewards storage epoch
    ) internal returns (bool advanced) {
        uint256 epochsPassed = (block.timestamp - epoch.epochStartTime) / epoch.epochDuration;

        if (epochsPassed > epoch.currentEpoch) {
            epoch.currentEpoch = epochsPassed;
            epoch.epochRewards[epochsPassed] = epoch.rewardsPerEpoch;
            return true;
        }

        return false;
    }

    /// @notice Record user shares for current epoch
    /// @param epoch Epoch rewards storage
    /// @param user User address
    /// @param shares User's shares
    function recordEpochShares(
        EpochRewards storage epoch,
        address user,
        uint256 shares
    ) internal {
        advanceEpochIfNeeded(epoch);

        epoch.epochShares[epoch.currentEpoch][user] = shares;
        epoch.epochTotalShares[epoch.currentEpoch] += shares;
    }

    /// @notice Calculate epoch reward for user
    /// @param epoch Epoch rewards storage
    /// @param user User address
    /// @param epochIndex Epoch to calculate for
    /// @return reward User's reward for epoch
    function calculateEpochReward(
        EpochRewards storage epoch,
        address user,
        uint256 epochIndex
    ) internal view returns (uint256 reward) {
        if (epoch.epochClaimed[epochIndex][user]) {
            return 0;
        }

        uint256 userShares = epoch.epochShares[epochIndex][user];
        uint256 totalShares = epoch.epochTotalShares[epochIndex];

        if (totalShares == 0) return 0;

        reward = (epoch.epochRewards[epochIndex] * userShares) / totalShares;
    }

    /// @notice Claim epoch reward
    /// @param epoch Epoch rewards storage
    /// @param user User address
    /// @param epochIndex Epoch to claim from
    /// @return reward Claimed reward amount
    function claimEpochReward(
        EpochRewards storage epoch,
        address user,
        uint256 epochIndex
    ) internal returns (uint256 reward) {
        if (epochIndex >= epoch.currentEpoch) {
            revert RewardPeriodNotStarted(epoch.epochStartTime + epochIndex * epoch.epochDuration);
        }

        if (epoch.epochClaimed[epochIndex][user]) {
            revert RewardAlreadyClaimed(bytes32(epochIndex));
        }

        reward = calculateEpochReward(epoch, user, epochIndex);
        if (reward == 0) revert NoRewardsAvailable();

        epoch.epochClaimed[epochIndex][user] = true;
    }

    /// @notice Claim multiple epochs
    /// @param epoch Epoch rewards storage
    /// @param user User address
    /// @param startEpoch First epoch to claim
    /// @param endEpoch Last epoch to claim
    /// @return totalReward Total rewards claimed
    function claimMultipleEpochs(
        EpochRewards storage epoch,
        address user,
        uint256 startEpoch,
        uint256 endEpoch
    ) internal returns (uint256 totalReward) {
        for (uint256 i = startEpoch; i <= endEpoch;) {
            if (!epoch.epochClaimed[i][user] && i < epoch.currentEpoch) {
                uint256 reward = calculateEpochReward(epoch, user, i);
                if (reward > 0) {
                    epoch.epochClaimed[i][user] = true;
                    totalReward += reward;
                }
            }
            unchecked { ++i; }
        }

        if (totalReward == 0) revert NoRewardsAvailable();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTIPLIER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize multiplier configuration
    /// @param config Multiplier config storage
    /// @param baseMultiplier Base multiplier (WAD)
    /// @param maxMultiplier Maximum multiplier (WAD)
    /// @param boostPerUnit Boost per unit (WAD)
    /// @param decayRate Decay rate per second (WAD)
    function initializeMultiplier(
        MultiplierConfig storage config,
        uint256 baseMultiplier,
        uint256 maxMultiplier,
        uint256 boostPerUnit,
        uint256 decayRate
    ) internal {
        if (maxMultiplier > MAX_MULTIPLIER) {
            revert InvalidMultiplier(maxMultiplier);
        }

        config.baseMultiplier = baseMultiplier;
        config.maxMultiplier = maxMultiplier;
        config.boostPerUnit = boostPerUnit;
        config.decayRate = decayRate;
        config.lastUpdateTime = block.timestamp;
    }

    /// @notice Calculate current multiplier with decay
    /// @param userMult User multiplier storage
    /// @param config Multiplier configuration
    /// @return multiplier Current multiplier (WAD)
    function calculateMultiplier(
        UserMultiplier storage userMult,
        MultiplierConfig memory config
    ) internal view returns (uint256 multiplier) {
        if (userMult.currentMultiplier == 0) {
            return config.baseMultiplier;
        }

        uint256 timeElapsed = block.timestamp - userMult.lastUpdateTime;
        uint256 decay = (config.decayRate * timeElapsed) / WAD;

        if (decay >= userMult.currentMultiplier - config.baseMultiplier) {
            return config.baseMultiplier;
        }

        multiplier = userMult.currentMultiplier - decay;

        if (multiplier < config.baseMultiplier) {
            multiplier = config.baseMultiplier;
        }
    }

    /// @notice Apply boost to multiplier
    /// @param userMult User multiplier storage
    /// @param config Multiplier configuration
    /// @param boostUnits Number of boost units
    function applyBoost(
        UserMultiplier storage userMult,
        MultiplierConfig memory config,
        uint256 boostUnits
    ) internal {
        uint256 currentMult = calculateMultiplier(userMult, config);
        uint256 boost = (config.boostPerUnit * boostUnits) / WAD;

        uint256 newMultiplier = currentMult + boost;
        if (newMultiplier > config.maxMultiplier) {
            newMultiplier = config.maxMultiplier;
        }

        userMult.currentMultiplier = newMultiplier;
        userMult.accumulatedBoost += boost;
        userMult.lastUpdateTime = block.timestamp;
    }

    /// @notice Update and return current multiplier
    /// @param userMult User multiplier storage
    /// @param config Multiplier configuration
    /// @return multiplier Updated multiplier
    function updateMultiplier(
        UserMultiplier storage userMult,
        MultiplierConfig memory config
    ) internal returns (uint256 multiplier) {
        multiplier = calculateMultiplier(userMult, config);
        userMult.currentMultiplier = multiplier;
        userMult.lastUpdateTime = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMISSION SCHEDULE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current emission rate from schedule
    /// @param schedule Emission schedule
    /// @return rate Current emission rate
    function getCurrentEmissionRate(
        EmissionSchedule storage schedule
    ) internal view returns (uint256 rate) {
        if (schedule.timestamps.length == 0) return 0;

        for (uint256 i = schedule.timestamps.length; i > 0;) {
            unchecked { --i; }
            if (block.timestamp >= schedule.timestamps[i]) {
                return schedule.rates[i];
            }
        }

        return schedule.rates[0];
    }

    /// @notice Add emission rate change
    /// @param schedule Emission schedule storage
    /// @param timestamp When rate takes effect
    /// @param rate New emission rate
    function addEmissionChange(
        EmissionSchedule storage schedule,
        uint256 timestamp,
        uint256 rate
    ) internal {
        schedule.timestamps.push(timestamp);
        schedule.rates.push(rate);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate reward for duration
    /// @param rate Reward rate per second
    /// @param duration Duration in seconds
    /// @param shares User shares
    /// @param totalShares Total shares
    /// @return reward Calculated reward
    function calculateRewardForDuration(
        uint256 rate,
        uint256 duration,
        uint256 shares,
        uint256 totalShares
    ) internal pure returns (uint256 reward) {
        if (totalShares == 0) return 0;
        return (rate * duration * shares) / totalShares;
    }

    /// @notice Calculate APR from reward rate
    /// @param rewardRate Reward rate per second
    /// @param totalValue Total staked value
    /// @param rewardPrice Price of reward token
    /// @param stakingPrice Price of staking token
    /// @return apr Annual percentage rate (WAD)
    function calculateAPR(
        uint256 rewardRate,
        uint256 totalValue,
        uint256 rewardPrice,
        uint256 stakingPrice
    ) internal pure returns (uint256 apr) {
        if (totalValue == 0 || stakingPrice == 0) return 0;

        uint256 yearlyRewards = rewardRate * SECONDS_PER_YEAR;
        uint256 rewardValue = (yearlyRewards * rewardPrice) / WAD;

        apr = (rewardValue * WAD) / ((totalValue * stakingPrice) / WAD);
    }

    /// @notice Calculate boost from lock duration
    /// @param lockDuration Lock duration in seconds
    /// @param maxLockDuration Maximum lock duration
    /// @param maxBoost Maximum boost (WAD)
    /// @return boost Calculated boost multiplier (WAD)
    function calculateLockBoost(
        uint256 lockDuration,
        uint256 maxLockDuration,
        uint256 maxBoost
    ) internal pure returns (uint256 boost) {
        if (lockDuration >= maxLockDuration) {
            return WAD + maxBoost;
        }

        uint256 ratio = (lockDuration * WAD) / maxLockDuration;
        boost = WAD + (ratio * maxBoost) / WAD;
    }

    /// @notice Check if reward period is active
    /// @param startTime Period start time
    /// @param endTime Period end time
    /// @return active True if currently in reward period
    function isRewardPeriodActive(
        uint256 startTime,
        uint256 endTime
    ) internal view returns (bool active) {
        return block.timestamp >= startTime && block.timestamp <= endTime;
    }

    /// @notice Calculate pro-rata reward
    /// @param totalReward Total reward amount
    /// @param userShare User's share
    /// @param totalShares Total shares
    /// @return reward User's pro-rata reward
    function calculateProRataReward(
        uint256 totalReward,
        uint256 userShare,
        uint256 totalShares
    ) internal pure returns (uint256 reward) {
        if (totalShares == 0) return 0;
        return (totalReward * userShare) / totalShares;
    }

    /// @notice Calculate time-weighted reward
    /// @param amount Base amount
    /// @param startTime Start time
    /// @param endTime End time
    /// @param currentTime Current time
    /// @return weighted Time-weighted amount
    function calculateTimeWeightedReward(
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime
    ) internal pure returns (uint256 weighted) {
        if (currentTime <= startTime) return 0;
        if (currentTime >= endTime) return amount;

        uint256 duration = endTime - startTime;
        uint256 elapsed = currentTime - startTime;

        weighted = (amount * elapsed) / duration;
    }

    /// @notice Generate distribution ID
    /// @param token Reward token
    /// @param amount Distribution amount
    /// @param nonce Unique nonce
    /// @return distributionId Generated ID
    function generateDistributionId(
        address token,
        uint256 amount,
        uint256 nonce
    ) internal view returns (bytes32 distributionId) {
        return keccak256(abi.encode(token, amount, nonce, block.timestamp, block.chainid));
    }
}
