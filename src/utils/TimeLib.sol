// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TimeLib
 * @notice Time-based utilities for vesting, lockups, cooldowns, and scheduling
 * @dev Provides comprehensive time management for DeFi protocols
 */
library TimeLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant SECONDS_PER_MINUTE = 60;
    uint256 internal constant SECONDS_PER_HOUR = 3600;
    uint256 internal constant SECONDS_PER_DAY = 86400;
    uint256 internal constant SECONDS_PER_WEEK = 604800;
    uint256 internal constant SECONDS_PER_MONTH = 2592000; // 30 days
    uint256 internal constant SECONDS_PER_YEAR = 31536000; // 365 days

    uint256 internal constant MAX_BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidTimeRange(uint256 start, uint256 end);
    error CooldownNotExpired(uint256 remaining);
    error LockupNotExpired(uint256 remaining);
    error InvalidDuration(uint256 duration);
    error VestingNotStarted();
    error VestingComplete();
    error InvalidVestingParams();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Linear vesting schedule
    struct VestingSchedule {
        uint256 totalAmount;      // Total amount to vest
        uint256 startTime;        // Vesting start time
        uint256 cliffDuration;    // Cliff period before any vesting
        uint256 vestingDuration;  // Total vesting duration after cliff
        uint256 claimed;          // Amount already claimed
    }

    /// @notice Cooldown state
    struct Cooldown {
        uint256 lastAction;       // Timestamp of last action
        uint256 cooldownPeriod;   // Required wait time
    }

    /// @notice Lockup with optional penalty for early withdrawal
    struct Lockup {
        uint256 amount;           // Locked amount
        uint256 lockTime;         // When locked
        uint256 unlockTime;       // When unlockable without penalty
        uint256 penaltyBps;       // Early withdrawal penalty (basis points)
    }

    /// @notice Scheduled action
    struct ScheduledAction {
        bytes32 actionId;         // Unique identifier
        uint256 executeAfter;     // Earliest execution time
        uint256 expiresAt;        // Action expires after this time
        bool executed;            // Whether action was executed
        bool cancelled;           // Whether action was cancelled
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current timestamp
    function now_() internal view returns (uint256) {
        return block.timestamp;
    }

    /// @notice Check if timestamp is in the past
    function isPast(uint256 timestamp) internal view returns (bool) {
        return block.timestamp > timestamp;
    }

    /// @notice Check if timestamp is in the future
    function isFuture(uint256 timestamp) internal view returns (bool) {
        return block.timestamp < timestamp;
    }

    /// @notice Check if current time is within range
    function isWithinRange(uint256 start, uint256 end) internal view returns (bool) {
        return block.timestamp >= start && block.timestamp <= end;
    }

    /// @notice Calculate time elapsed since timestamp
    function elapsed(uint256 since) internal view returns (uint256) {
        if (block.timestamp <= since) return 0;
        return block.timestamp - since;
    }

    /// @notice Calculate time remaining until timestamp
    function remaining(uint256 until) internal view returns (uint256) {
        if (block.timestamp >= until) return 0;
        return until - block.timestamp;
    }

    /// @notice Add duration to current time
    function fromNow(uint256 duration) internal view returns (uint256) {
        return block.timestamp + duration;
    }

    /// @notice Calculate deadline from current time
    function deadline(uint256 duration) internal view returns (uint256) {
        return block.timestamp + duration;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UNIT CONVERSIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Convert minutes to seconds
    function minutes_(uint256 m) internal pure returns (uint256) {
        return m * SECONDS_PER_MINUTE;
    }

    /// @notice Convert hours to seconds
    function hours_(uint256 h) internal pure returns (uint256) {
        return h * SECONDS_PER_HOUR;
    }

    /// @notice Convert days to seconds
    function days_(uint256 d) internal pure returns (uint256) {
        return d * SECONDS_PER_DAY;
    }

    /// @notice Convert weeks to seconds
    function weeks_(uint256 w) internal pure returns (uint256) {
        return w * SECONDS_PER_WEEK;
    }

    /// @notice Convert months to seconds (30 day months)
    function months_(uint256 m) internal pure returns (uint256) {
        return m * SECONDS_PER_MONTH;
    }

    /// @notice Convert years to seconds (365 day years)
    function years_(uint256 y) internal pure returns (uint256) {
        return y * SECONDS_PER_YEAR;
    }

    /// @notice Get number of complete days elapsed
    function toDays(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / SECONDS_PER_DAY;
    }

    /// @notice Get number of complete hours elapsed
    function toHours(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / SECONDS_PER_HOUR;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LINEAR VESTING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a new vesting schedule
    function createVestingSchedule(
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) internal pure returns (VestingSchedule memory) {
        if (vestingDuration == 0) revert InvalidVestingParams();
        if (totalAmount == 0) revert InvalidVestingParams();

        return VestingSchedule({
            totalAmount: totalAmount,
            startTime: startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            claimed: 0
        });
    }

    /// @notice Calculate vested amount at current time
    function vestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        return vestedAmountAt(schedule, block.timestamp);
    }

    /// @notice Calculate vested amount at specific time
    function vestedAmountAt(
        VestingSchedule memory schedule,
        uint256 timestamp
    ) internal pure returns (uint256) {
        // Not started yet
        if (timestamp < schedule.startTime) return 0;

        // Still in cliff period
        uint256 cliffEnd = schedule.startTime + schedule.cliffDuration;
        if (timestamp < cliffEnd) return 0;

        // Calculate time since cliff ended
        uint256 timeAfterCliff = timestamp - cliffEnd;

        // Fully vested
        if (timeAfterCliff >= schedule.vestingDuration) {
            return schedule.totalAmount;
        }

        // Partial vesting (linear)
        return (schedule.totalAmount * timeAfterCliff) / schedule.vestingDuration;
    }

    /// @notice Calculate claimable amount (vested minus already claimed)
    function claimableAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        uint256 vested = vestedAmount(schedule);
        return vested > schedule.claimed ? vested - schedule.claimed : 0;
    }

    /// @notice Calculate unvested amount
    function unvestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        uint256 vested = vestedAmount(schedule);
        return schedule.totalAmount > vested ? schedule.totalAmount - vested : 0;
    }

    /// @notice Calculate vesting progress as basis points (0-10000)
    function vestingProgressBps(VestingSchedule memory schedule) internal view returns (uint256) {
        if (schedule.totalAmount == 0) return MAX_BPS;
        return (vestedAmount(schedule) * MAX_BPS) / schedule.totalAmount;
    }

    /// @notice Check if vesting is complete
    function isVestingComplete(VestingSchedule memory schedule) internal view returns (bool) {
        return vestedAmount(schedule) >= schedule.totalAmount;
    }

    /// @notice Get time remaining until fully vested
    function timeUntilFullyVested(VestingSchedule memory schedule) internal view returns (uint256) {
        uint256 vestingEnd = schedule.startTime + schedule.cliffDuration + schedule.vestingDuration;
        return remaining(vestingEnd);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STEPPED VESTING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate vested amount with periodic releases (e.g., monthly)
    function steppedVestedAmount(
        uint256 totalAmount,
        uint256 startTime,
        uint256 stepDuration,
        uint256 totalSteps
    ) internal view returns (uint256) {
        if (block.timestamp < startTime) return 0;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 completedSteps = timeElapsed / stepDuration;

        if (completedSteps >= totalSteps) return totalAmount;

        return (totalAmount * completedSteps) / totalSteps;
    }

    /// @notice Get number of completed vesting steps
    function completedSteps(
        uint256 startTime,
        uint256 stepDuration,
        uint256 totalSteps
    ) internal view returns (uint256) {
        if (block.timestamp < startTime) return 0;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 steps = timeElapsed / stepDuration;

        return steps > totalSteps ? totalSteps : steps;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COOLDOWNS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a new cooldown
    function createCooldown(uint256 cooldownPeriod) internal view returns (Cooldown memory) {
        return Cooldown({
            lastAction: block.timestamp,
            cooldownPeriod: cooldownPeriod
        });
    }

    /// @notice Check if cooldown has expired
    function isCooldownExpired(Cooldown memory cd) internal view returns (bool) {
        return block.timestamp >= cd.lastAction + cd.cooldownPeriod;
    }

    /// @notice Get remaining cooldown time
    function cooldownRemaining(Cooldown memory cd) internal view returns (uint256) {
        uint256 expiresAt = cd.lastAction + cd.cooldownPeriod;
        return remaining(expiresAt);
    }

    /// @notice Require cooldown expired, revert with remaining time if not
    function requireCooldownExpired(Cooldown memory cd) internal view {
        uint256 remainingTime = cooldownRemaining(cd);
        if (remainingTime > 0) {
            revert CooldownNotExpired(remainingTime);
        }
    }

    /// @notice Reset cooldown (call after successful action)
    function resetCooldown(Cooldown storage cd) internal {
        cd.lastAction = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOCKUPS WITH PENALTIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a new lockup
    function createLockup(
        uint256 amount,
        uint256 lockDuration,
        uint256 penaltyBps
    ) internal view returns (Lockup memory) {
        return Lockup({
            amount: amount,
            lockTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration,
            penaltyBps: penaltyBps
        });
    }

    /// @notice Check if lockup has expired (can withdraw without penalty)
    function isLockupExpired(Lockup memory lock) internal view returns (bool) {
        return block.timestamp >= lock.unlockTime;
    }

    /// @notice Get remaining lock time
    function lockupRemaining(Lockup memory lock) internal view returns (uint256) {
        return remaining(lock.unlockTime);
    }

    /// @notice Calculate early withdrawal penalty amount
    function earlyWithdrawalPenalty(Lockup memory lock) internal view returns (uint256) {
        if (isLockupExpired(lock)) return 0;
        return (lock.amount * lock.penaltyBps) / MAX_BPS;
    }

    /// @notice Calculate amount receivable (after penalty if early)
    function withdrawableAmount(Lockup memory lock) internal view returns (uint256) {
        if (isLockupExpired(lock)) return lock.amount;
        uint256 penalty = earlyWithdrawalPenalty(lock);
        return lock.amount - penalty;
    }

    /// @notice Calculate linear decay penalty (decreases as unlock time approaches)
    function linearDecayPenalty(Lockup memory lock) internal view returns (uint256) {
        if (isLockupExpired(lock)) return 0;

        uint256 totalDuration = lock.unlockTime - lock.lockTime;
        uint256 remaining_ = lock.unlockTime - block.timestamp;

        // Penalty decreases linearly from full penalty to zero
        uint256 currentPenaltyBps = (lock.penaltyBps * remaining_) / totalDuration;
        return (lock.amount * currentPenaltyBps) / MAX_BPS;
    }

    /// @notice Require lockup expired
    function requireLockupExpired(Lockup memory lock) internal view {
        uint256 remainingTime = lockupRemaining(lock);
        if (remainingTime > 0) {
            revert LockupNotExpired(remainingTime);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SCHEDULED ACTIONS (TIMELOCK)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a scheduled action
    function scheduleAction(
        bytes32 actionId,
        uint256 delay,
        uint256 validFor
    ) internal view returns (ScheduledAction memory) {
        return ScheduledAction({
            actionId: actionId,
            executeAfter: block.timestamp + delay,
            expiresAt: block.timestamp + delay + validFor,
            executed: false,
            cancelled: false
        });
    }

    /// @notice Check if action is ready to execute
    function isActionReady(ScheduledAction memory action) internal view returns (bool) {
        return block.timestamp >= action.executeAfter &&
               block.timestamp <= action.expiresAt &&
               !action.executed &&
               !action.cancelled;
    }

    /// @notice Check if action has expired
    function isActionExpired(ScheduledAction memory action) internal view returns (bool) {
        return block.timestamp > action.expiresAt;
    }

    /// @notice Get time until action can be executed
    function timeUntilExecutable(ScheduledAction memory action) internal view returns (uint256) {
        return remaining(action.executeAfter);
    }

    /// @notice Get time remaining until action expires
    function timeUntilExpiry(ScheduledAction memory action) internal view returns (uint256) {
        return remaining(action.expiresAt);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EPOCH CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current epoch number given epoch duration
    function currentEpoch(uint256 epochDuration, uint256 genesisTime) internal view returns (uint256) {
        if (block.timestamp < genesisTime) return 0;
        return (block.timestamp - genesisTime) / epochDuration;
    }

    /// @notice Get epoch start time
    function epochStartTime(
        uint256 epoch,
        uint256 epochDuration,
        uint256 genesisTime
    ) internal pure returns (uint256) {
        return genesisTime + (epoch * epochDuration);
    }

    /// @notice Get epoch end time
    function epochEndTime(
        uint256 epoch,
        uint256 epochDuration,
        uint256 genesisTime
    ) internal pure returns (uint256) {
        return genesisTime + ((epoch + 1) * epochDuration);
    }

    /// @notice Time remaining in current epoch
    function timeRemainingInEpoch(
        uint256 epochDuration,
        uint256 genesisTime
    ) internal view returns (uint256) {
        uint256 epoch = currentEpoch(epochDuration, genesisTime);
        uint256 endTime = epochEndTime(epoch, epochDuration, genesisTime);
        return remaining(endTime);
    }

    /// @notice Get progress through current epoch (0-10000 bps)
    function epochProgressBps(
        uint256 epochDuration,
        uint256 genesisTime
    ) internal view returns (uint256) {
        uint256 epoch = currentEpoch(epochDuration, genesisTime);
        uint256 startTime = epochStartTime(epoch, epochDuration, genesisTime);
        uint256 elapsed_ = block.timestamp - startTime;
        return (elapsed_ * MAX_BPS) / epochDuration;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXPIRATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Check deadline not passed
    function checkDeadline(uint256 deadlineTime) internal view returns (bool) {
        return block.timestamp <= deadlineTime;
    }

    /// @notice Require deadline not passed
    function requireNotExpired(uint256 deadline_) internal view {
        if (block.timestamp > deadline_) {
            revert InvalidTimeRange(block.timestamp, deadline_);
        }
    }

    /// @notice Check if within valid window
    function checkTimeWindow(uint256 start, uint256 end) internal view returns (bool) {
        return block.timestamp >= start && block.timestamp <= end;
    }
}
