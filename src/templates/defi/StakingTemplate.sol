// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StakingTemplate
 * @notice Production-ready staking contract template with flexible rewards
 * @dev Implements time-locked staking, reward distribution, and compound functionality
 *
 * TEMPLATE INSTRUCTIONS:
 * 1. Search and replace "StakingTemplate" with your contract name
 * 2. Configure STAKING_TOKEN and REWARD_TOKEN addresses
 * 3. Set REWARD_RATE, MIN_STAKE, and lock periods
 * 4. Customize reward calculations as needed
 * 5. Add additional lock tiers if required
 */

import {AccessControlLib} from "../utils/AccessControlLib.sol";
import {PausableLib} from "../utils/PausableLib.sol";
import {ReentrancyGuardLib} from "../utils/ReentrancyGuardLib.sol";
import {MathUtils} from "../utils/MathUtils.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract StakingTemplate {
    using MathUtils for uint256;

    // ============ CONSTANTS ============
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // Lock period options (in seconds)
    uint256 public constant LOCK_FLEXIBLE = 0;
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Bonus multipliers (in basis points, 10000 = 1x)
    uint256 public constant BONUS_FLEXIBLE = 10000;     // 1x
    uint256 public constant BONUS_30_DAYS = 11000;      // 1.1x
    uint256 public constant BONUS_90_DAYS = 12500;      // 1.25x
    uint256 public constant BONUS_180_DAYS = 15000;     // 1.5x
    uint256 public constant BONUS_365_DAYS = 20000;     // 2x

    // ============ ERRORS ============
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 available, uint256 required);
    error StakeLocked(uint256 unlockTime);
    error InvalidLockPeriod(uint256 period);
    error NoRewardsToClaim();
    error TransferFailed();
    error StakingPaused();
    error MinimumStakeNotMet(uint256 minimum);
    error MaxStakeExceeded(uint256 maximum);
    error EmergencyWithdrawDisabled();
    error CooldownNotExpired(uint256 cooldownEnd);
    error NoActiveStake();

    // ============ TYPES ============
    struct StakeInfo {
        uint256 amount;              // Staked amount
        uint256 rewardDebt;          // Reward debt for accurate calculation
        uint256 pendingRewards;      // Accumulated pending rewards
        uint256 stakedAt;            // Stake timestamp
        uint256 lockEndTime;         // Lock end timestamp (0 = flexible)
        uint256 lockPeriod;          // Original lock period
        uint256 bonusMultiplier;     // Bonus multiplier in basis points
        uint256 lastClaimTime;       // Last reward claim timestamp
    }

    struct PoolInfo {
        uint256 totalStaked;         // Total staked in pool
        uint256 rewardPerSecond;     // Rewards distributed per second
        uint256 accRewardPerShare;   // Accumulated rewards per share
        uint256 lastRewardTime;      // Last reward calculation timestamp
        uint256 startTime;           // Pool start time
        uint256 endTime;             // Pool end time (0 = no end)
    }

    // ============ STATE ============
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    PoolInfo public pool;
    mapping(address => StakeInfo) public stakes;
    mapping(address => uint256) public userStakeCount;

    uint256 public minStakeAmount;
    uint256 public maxStakeAmount;
    uint256 public cooldownPeriod;
    mapping(address => uint256) public unstakeCooldown;

    bool public emergencyWithdrawEnabled;
    uint256 public emergencyWithdrawPenalty; // In basis points

    AccessControlLib.AccessControlStorage internal _accessControl;
    PausableLib.PauseState internal _pauseState;
    ReentrancyGuardLib.ReentrancyGuard internal _reentrancyGuard;

    // ============ EVENTS ============
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod, uint256 bonusMultiplier);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsCompounded(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount, uint256 penalty);
    event PoolUpdated(uint256 rewardPerSecond, uint256 startTime, uint256 endTime);
    event RewardsAdded(uint256 amount);
    event CooldownStarted(address indexed user, uint256 cooldownEnd);

    // ============ CONSTRUCTOR ============
    constructor(
        address admin,
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardPerSecond,
        uint256 _minStakeAmount
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (_stakingToken == address(0)) revert ZeroAddress();
        if (_rewardToken == address(0)) revert ZeroAddress();

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);

        pool = PoolInfo({
            totalStaked: 0,
            rewardPerSecond: _rewardPerSecond,
            accRewardPerShare: 0,
            lastRewardTime: block.timestamp,
            startTime: block.timestamp,
            endTime: 0
        });

        minStakeAmount = _minStakeAmount;
        maxStakeAmount = type(uint256).max;
        cooldownPeriod = 0;
        emergencyWithdrawPenalty = 1000; // 10% default penalty

        // Initialize access control
        AccessControlLib.initializeStandardRoles(_accessControl, admin);

        // Initialize reentrancy guard
        ReentrancyGuardLib.initialize(_reentrancyGuard);
    }

    // ============ STAKING FUNCTIONS ============

    /**
     * @notice Stake tokens with optional lock period
     * @param amount Amount to stake
     * @param lockPeriod Lock period in seconds (use constants)
     */
    function stake(uint256 amount, uint256 lockPeriod) external {
        ReentrancyGuardLib.enter(_reentrancyGuard);
        _requireNotPaused();

        if (amount == 0) revert ZeroAmount();
        if (amount < minStakeAmount) revert MinimumStakeNotMet(minStakeAmount);
        if (stakes[msg.sender].amount + amount > maxStakeAmount) {
            revert MaxStakeExceeded(maxStakeAmount);
        }

        uint256 bonusMultiplier = _getLockBonus(lockPeriod);

        _updatePool();
        _updateUserRewards(msg.sender);

        // Transfer tokens
        if (!stakingToken.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        StakeInfo storage userStake = stakes[msg.sender];

        // If extending existing stake, use longer lock period
        if (userStake.amount > 0) {
            uint256 newLockEnd = block.timestamp + lockPeriod;
            if (newLockEnd > userStake.lockEndTime) {
                userStake.lockEndTime = newLockEnd;
                userStake.lockPeriod = lockPeriod;
                userStake.bonusMultiplier = bonusMultiplier;
            }
        } else {
            userStake.stakedAt = block.timestamp;
            userStake.lockEndTime = lockPeriod > 0 ? block.timestamp + lockPeriod : 0;
            userStake.lockPeriod = lockPeriod;
            userStake.bonusMultiplier = bonusMultiplier;
            userStake.lastClaimTime = block.timestamp;
            userStakeCount[msg.sender]++;
        }

        userStake.amount += amount;
        userStake.rewardDebt = (userStake.amount * pool.accRewardPerShare) / PRECISION;

        pool.totalStaked += amount;

        emit Staked(msg.sender, amount, lockPeriod, bonusMultiplier);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Unstake tokens (subject to lock period)
     * @param amount Amount to unstake
     */
    function unstake(uint256 amount) external {
        ReentrancyGuardLib.enter(_reentrancyGuard);

        StakeInfo storage userStake = stakes[msg.sender];

        if (amount == 0) revert ZeroAmount();
        if (userStake.amount < amount) {
            revert InsufficientBalance(userStake.amount, amount);
        }
        if (userStake.lockEndTime > 0 && block.timestamp < userStake.lockEndTime) {
            revert StakeLocked(userStake.lockEndTime);
        }

        // Check cooldown
        if (cooldownPeriod > 0) {
            if (unstakeCooldown[msg.sender] == 0) {
                unstakeCooldown[msg.sender] = block.timestamp + cooldownPeriod;
                emit CooldownStarted(msg.sender, unstakeCooldown[msg.sender]);
                ReentrancyGuardLib.exit(_reentrancyGuard);
                return;
            }
            if (block.timestamp < unstakeCooldown[msg.sender]) {
                revert CooldownNotExpired(unstakeCooldown[msg.sender]);
            }
            unstakeCooldown[msg.sender] = 0;
        }

        _updatePool();
        _updateUserRewards(msg.sender);

        userStake.amount -= amount;
        userStake.rewardDebt = (userStake.amount * pool.accRewardPerShare) / PRECISION;
        pool.totalStaked -= amount;

        if (!stakingToken.transfer(msg.sender, amount)) {
            revert TransferFailed();
        }

        emit Unstaked(msg.sender, amount);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external {
        ReentrancyGuardLib.enter(_reentrancyGuard);

        _updatePool();
        _updateUserRewards(msg.sender);

        StakeInfo storage userStake = stakes[msg.sender];
        uint256 pending = userStake.pendingRewards;

        if (pending == 0) revert NoRewardsToClaim();

        userStake.pendingRewards = 0;
        userStake.lastClaimTime = block.timestamp;

        if (!rewardToken.transfer(msg.sender, pending)) {
            revert TransferFailed();
        }

        emit RewardsClaimed(msg.sender, pending);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Compound rewards back into stake
     */
    function compound() external {
        ReentrancyGuardLib.enter(_reentrancyGuard);
        _requireNotPaused();

        // Only works if staking and reward tokens are the same
        require(address(stakingToken) == address(rewardToken), "Cannot compound different tokens");

        _updatePool();
        _updateUserRewards(msg.sender);

        StakeInfo storage userStake = stakes[msg.sender];
        uint256 pending = userStake.pendingRewards;

        if (pending == 0) revert NoRewardsToClaim();

        userStake.pendingRewards = 0;
        userStake.amount += pending;
        userStake.rewardDebt = (userStake.amount * pool.accRewardPerShare) / PRECISION;
        userStake.lastClaimTime = block.timestamp;

        pool.totalStaked += pending;

        emit RewardsCompounded(msg.sender, pending);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Emergency withdraw with penalty
     */
    function emergencyWithdraw() external {
        ReentrancyGuardLib.enter(_reentrancyGuard);

        if (!emergencyWithdrawEnabled) revert EmergencyWithdrawDisabled();

        StakeInfo storage userStake = stakes[msg.sender];
        if (userStake.amount == 0) revert NoActiveStake();

        uint256 amount = userStake.amount;
        uint256 penalty = (amount * emergencyWithdrawPenalty) / 10000;
        uint256 amountAfterPenalty = amount - penalty;

        // Reset user stake
        userStake.amount = 0;
        userStake.rewardDebt = 0;
        userStake.pendingRewards = 0;
        pool.totalStaked -= amount;

        if (!stakingToken.transfer(msg.sender, amountAfterPenalty)) {
            revert TransferFailed();
        }

        emit EmergencyWithdraw(msg.sender, amountAfterPenalty, penalty);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get pending rewards for a user
     * @param user User address
     * @return Pending reward amount
     */
    function pendingRewards(address user) external view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (userStake.amount == 0) return userStake.pendingRewards;

        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalStaked > 0) {
            uint256 timeElapsed = _getRewardTime() - pool.lastRewardTime;
            uint256 reward = timeElapsed * pool.rewardPerSecond;
            accRewardPerShare += (reward * PRECISION) / pool.totalStaked;
        }

        uint256 baseReward = (userStake.amount * accRewardPerShare) / PRECISION - userStake.rewardDebt;
        uint256 bonusReward = (baseReward * userStake.bonusMultiplier) / 10000;

        return userStake.pendingRewards + bonusReward;
    }

    /**
     * @notice Get stake info for a user
     * @param user User address
     * @return info Stake information
     */
    function getStakeInfo(address user) external view returns (StakeInfo memory info) {
        return stakes[user];
    }

    /**
     * @notice Get APY for a lock period
     * @param lockPeriod Lock period in seconds
     * @return apy APY in basis points
     */
    function getAPY(uint256 lockPeriod) external view returns (uint256 apy) {
        if (pool.totalStaked == 0) return 0;

        uint256 yearlyRewards = pool.rewardPerSecond * SECONDS_PER_YEAR;
        uint256 baseAPY = (yearlyRewards * 10000) / pool.totalStaked;
        uint256 bonus = _getLockBonus(lockPeriod);

        return (baseAPY * bonus) / 10000;
    }

    // ============ ADMIN FUNCTIONS ============

    function setRewardPerSecond(uint256 _rewardPerSecond) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        _updatePool();
        pool.rewardPerSecond = _rewardPerSecond;
        emit PoolUpdated(_rewardPerSecond, pool.startTime, pool.endTime);
    }

    function setPoolEndTime(uint256 _endTime) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        pool.endTime = _endTime;
        emit PoolUpdated(pool.rewardPerSecond, pool.startTime, _endTime);
    }

    function setMinMaxStake(uint256 _min, uint256 _max) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        minStakeAmount = _min;
        maxStakeAmount = _max;
    }

    function setCooldownPeriod(uint256 _cooldown) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        cooldownPeriod = _cooldown;
    }

    function setEmergencyWithdraw(bool enabled, uint256 penalty) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        require(penalty <= 5000, "Max 50% penalty");
        emergencyWithdrawEnabled = enabled;
        emergencyWithdrawPenalty = penalty;
    }

    function addRewards(uint256 amount) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        if (!rewardToken.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }
        emit RewardsAdded(amount);
    }

    function pause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.pause(_pauseState, "Admin pause");
    }

    function unpause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.unpause(_pauseState);
    }

    function recoverTokens(address token, uint256 amount) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        require(token != address(stakingToken), "Cannot recover staking token");
        IERC20(token).transfer(msg.sender, amount);
    }

    // ============ ROLE MANAGEMENT ============
    function grantRole(bytes32 role, address account) external {
        AccessControlLib.checkRoleAdmin(_accessControl, role);
        AccessControlLib.grantRole(_accessControl, role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        AccessControlLib.checkRoleAdmin(_accessControl, role);
        AccessControlLib.revokeRole(_accessControl, role, account);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return AccessControlLib.hasRole(_accessControl, role, account);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _updatePool() internal {
        if (block.timestamp <= pool.lastRewardTime) return;

        if (pool.totalStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 rewardTime = _getRewardTime();
        uint256 timeElapsed = rewardTime - pool.lastRewardTime;
        uint256 reward = timeElapsed * pool.rewardPerSecond;

        pool.accRewardPerShare += (reward * PRECISION) / pool.totalStaked;
        pool.lastRewardTime = rewardTime;
    }

    function _updateUserRewards(address user) internal {
        StakeInfo storage userStake = stakes[user];
        if (userStake.amount == 0) return;

        uint256 baseReward = (userStake.amount * pool.accRewardPerShare) / PRECISION - userStake.rewardDebt;
        uint256 bonusReward = (baseReward * userStake.bonusMultiplier) / 10000;

        userStake.pendingRewards += bonusReward;
        userStake.rewardDebt = (userStake.amount * pool.accRewardPerShare) / PRECISION;
    }

    function _getRewardTime() internal view returns (uint256) {
        if (pool.endTime == 0) return block.timestamp;
        return block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
    }

    function _getLockBonus(uint256 lockPeriod) internal pure returns (uint256) {
        if (lockPeriod == LOCK_FLEXIBLE) return BONUS_FLEXIBLE;
        if (lockPeriod == LOCK_30_DAYS) return BONUS_30_DAYS;
        if (lockPeriod == LOCK_90_DAYS) return BONUS_90_DAYS;
        if (lockPeriod == LOCK_180_DAYS) return BONUS_180_DAYS;
        if (lockPeriod == LOCK_365_DAYS) return BONUS_365_DAYS;
        revert InvalidLockPeriod(lockPeriod);
    }

    function _requireRole(bytes32 role) internal view {
        AccessControlLib.checkRole(_accessControl, role, msg.sender);
    }

    function _requireNotPaused() internal view {
        if (PausableLib.isPausedView(_pauseState)) {
            revert StakingPaused();
        }
    }
}
