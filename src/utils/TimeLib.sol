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

    uint256 internal constant MAX_BPS = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Linear vesting schedule
    struct VestingSchedule {
        uint64 startTime;         // Vesting start
        uint64 cliffDuration;     // Cliff period before any vesting
        uint64 totalDuration;     // Total vesting duration
        uint128 totalAmount;      // Total amount to vest
        uint128 claimedAmount;    // Amount already claimed
    }

    /// @notice Stepped vesting (discrete unlocks)
    struct SteppedVesting {
        uint64 startTime;
        uint64 stepDuration;      // Duration of each step
        uint16 totalSteps;        // Total number of steps
        uint16 claimedSteps;      // Steps already claimed
        uint128 amountPerStep;    // Amount unlocked per step
    }

    /// @notice Per-user cooldown tracker
    struct Cooldown {
        uint64 lastActionTime;    // Last action timestamp
        uint64 cooldownDuration;  // Required wait time
    }

    /// @notice Lockup with early unlock penalty
    struct Lockup {
        uint64 lockTime;          // When locked
        uint64 unlockTime;        // When fully unlocked
        uint128 amount;           // Locked amount
        uint16 earlyPenaltyBps;   // Penalty for early unlock (basis points)
    }

    /// @notice Scheduled action
    struct ScheduledAction {
        uint64 scheduledTime;     // When action can be executed
        uint64 expiryTime;        // When action expires
        bytes32 actionHash;       // Hash of the action
        bool executed;            // Whether action was executed
    }

    /// @notice Lease/rental period
    struct Lease {
        uint64 startTime;
        uint64 endTime;
        uint128 totalRent;
        uint128 paidRent;
        bool active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error NotYetUnlocked(uint256 unlockTime, uint256 currentTime);
    error AlreadyExpired(uint256 expiryTime, uint256 currentTime);
    error CooldownActive(uint256 availableAt, uint256 currentTime);
    error CliffNotReached(uint256 cliffEnd, uint256 currentTime);
    error NothingToClaim();
    error InvalidDuration();
    error InvalidSchedule();
    error ActionAlreadyExecuted();
    error LeaseNotActive();
    error LeaseExpired();

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current timestamp
     */
    function now_() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    /**
     * @notice Calculate elapsed time since timestamp
     */
    function elapsed(uint64 since) internal view returns (uint256) {
        if (block.timestamp <= since) return 0;
        return block.timestamp - since;
    }

    /**
     * @notice Calculate remaining time until timestamp
     */
    function remaining(uint64 until) internal view returns (uint256) {
        if (block.timestamp >= until) return 0;
        return until - block.timestamp;
    }

    /**
     * @notice Check if timestamp has passed
     */
    function hasPassed(uint64 timestamp) internal view returns (bool) {
        return block.timestamp >= timestamp;
    }

    /**
     * @notice Check if time is within range
     */
    function isWithinRange(uint64 start, uint64 end) internal view returns (bool) {
        return block.timestamp >= start && block.timestamp <= end;
    }

    /**
     * @notice Add duration to timestamp safely
     */
    function addDuration(uint64 timestamp, uint64 duration) internal pure returns (uint64) {
        return timestamp + duration;
    }

    /**
     * @notice Calculate percentage of time elapsed
     * @return Progress in basis points (0-10000)
     */
    function progressBps(uint64 start, uint64 end) internal view returns (uint256) {
        if (block.timestamp <= start) return 0;
        if (block.timestamp >= end) return MAX_BPS;

        uint256 totalDuration = end - start;
        uint256 elapsedTime = block.timestamp - start;
        return (elapsedTime * MAX_BPS) / totalDuration;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LINEAR VESTING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize a linear vesting schedule
     */
    function initVesting(
        VestingSchedule storage schedule,
        uint64 startTime,
        uint64 cliffDuration,
        uint64 totalDuration,
        uint128 totalAmount
    ) internal {
        if (totalDuration == 0) revert InvalidDuration();
        if (cliffDuration > totalDuration) revert InvalidSchedule();

        schedule.startTime = startTime;
        schedule.cliffDuration = cliffDuration;
        schedule.totalDuration = totalDuration;
        schedule.totalAmount = totalAmount;
        schedule.claimedAmount = 0;
    }

    /**
     * @notice Calculate vested amount (before claiming)
     */
    function vestedAmount(VestingSchedule storage schedule) internal view returns (uint128) {
        if (block.timestamp < schedule.startTime) return 0;

        uint64 cliffEnd = schedule.startTime + schedule.cliffDuration;
        if (block.timestamp < cliffEnd) return 0;

        uint64 vestingEnd = schedule.startTime + schedule.totalDuration;
        if (block.timestamp >= vestingEnd) {
            return schedule.totalAmount;
        }

        // Linear vesting calculation
        uint256 elapsedTime = block.timestamp - schedule.startTime;
        return uint128((uint256(schedule.totalAmount) * elapsedTime) / schedule.totalDuration);
    }

    /**
     * @notice Calculate claimable amount (vested - already claimed)
     */
    function claimableAmount(VestingSchedule storage schedule) internal view returns (uint128) {
        uint128 vested = vestedAmount(schedule);
        if (vested <= schedule.claimedAmount) return 0;
        return vested - schedule.claimedAmount;
    }

    /**
     * @notice Claim vested tokens
     * @return Amount claimed
     */
    function claim(VestingSchedule storage schedule) internal returns (uint128) {
        uint128 claimable = claimableAmount(schedule);
        if (claimable == 0) revert NothingToClaim();

        schedule.claimedAmount += claimable;
        return claimable;
    }

    /**
     * @notice Check if vesting is complete
     */
    function isFullyVested(VestingSchedule storage schedule) internal view returns (bool) {
        return block.timestamp >= schedule.startTime + schedule.totalDuration;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STEPPED VESTING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize stepped vesting
     */
    function initSteppedVesting(
        SteppedVesting storage vesting,
        uint64 startTime,
        uint64 stepDuration,
        uint16 totalSteps,
        uint128 amountPerStep
    ) internal {
        if (stepDuration == 0 || totalSteps == 0) revert InvalidSchedule();

        vesting.startTime = startTime;
        vesting.stepDuration = stepDuration;
        vesting.totalSteps = totalSteps;
        vesting.amountPerStep = amountPerStep;
        vesting.claimedSteps = 0;
    }

    /**
     * @notice Get number of unlocked steps
     */
    function unlockedSteps(SteppedVesting storage vesting) internal view returns (uint16) {
        if (block.timestamp < vesting.startTime) return 0;

        uint256 elapsedTime = block.timestamp - vesting.startTime;
        uint256 steps = elapsedTime / vesting.stepDuration;

        return steps > vesting.totalSteps ? vesting.totalSteps : uint16(steps);
    }

    /**
     * @notice Get claimable steps
     */
    function claimableSteps(SteppedVesting storage vesting) internal view returns (uint16) {
        uint16 unlocked = unlockedSteps(vesting);
        if (unlocked <= vesting.claimedSteps) return 0;
        return unlocked - vesting.claimedSteps;
    }

    /**
     * @notice Claim stepped vesting
     */
    function claimStepped(SteppedVesting storage vesting) internal returns (uint128) {
        uint16 claimable = claimableSteps(vesting);
        if (claimable == 0) revert NothingToClaim();

        vesting.claimedSteps += claimable;
        return uint128(claimable) * vesting.amountPerStep;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COOLDOWNS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize cooldown
     */
    function initCooldown(Cooldown storage cd, uint64 duration) internal {
        cd.cooldownDuration = duration;
        cd.lastActionTime = 0;
    }

    /**
     * @notice Check if cooldown is active
     */
    function isOnCooldown(Cooldown storage cd) internal view returns (bool) {
        if (cd.lastActionTime == 0) return false;
        return block.timestamp < cd.lastActionTime + cd.cooldownDuration;
    }

    /**
     * @notice Get time until cooldown ends
     */
    function cooldownRemaining(Cooldown storage cd) internal view returns (uint256) {
        if (cd.lastActionTime == 0) return 0;
        uint256 endTime = cd.lastActionTime + cd.cooldownDuration;
        if (block.timestamp >= endTime) return 0;
        return endTime - block.timestamp;
    }

    /**
     * @notice Trigger cooldown (call after action)
     */
    function triggerCooldown(Cooldown storage cd) internal {
        cd.lastActionTime = uint64(block.timestamp);
    }

    /**
     * @notice Require cooldown to be inactive
     */
    function requireNotOnCooldown(Cooldown storage cd) internal view {
        if (isOnCooldown(cd)) {
            revert CooldownActive(cd.lastActionTime + cd.cooldownDuration, block.timestamp);
        }
    }

    /**
     * @notice Execute action with cooldown
     */
    function executeWithCooldown(Cooldown storage cd) internal {
        requireNotOnCooldown(cd);
        triggerCooldown(cd);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOCKUPS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new lockup
     */
    function createLockup(
        Lockup storage lock,
        uint64 duration,
        uint128 amount,
        uint16 earlyPenaltyBps
    ) internal {
        lock.lockTime = uint64(block.timestamp);
        lock.unlockTime = uint64(block.timestamp) + duration;
        lock.amount = amount;
        lock.earlyPenaltyBps = earlyPenaltyBps;
    }

    /**
     * @notice Check if lockup has matured
     */
    function isUnlocked(Lockup storage lock) internal view returns (bool) {
        return block.timestamp >= lock.unlockTime;
    }

    /**
     * @notice Calculate penalty for early unlock
     */
    function earlyUnlockPenalty(Lockup storage lock) internal view returns (uint128) {
        if (isUnlocked(lock)) return 0;

        // Linear penalty decay
        uint256 totalDuration = lock.unlockTime - lock.lockTime;
        uint256 elapsedTime = block.timestamp - lock.lockTime;
        uint256 remainingRatio = ((totalDuration - elapsedTime) * MAX_BPS) / totalDuration;

        uint256 penalty = (uint256(lock.amount) * lock.earlyPenaltyBps * remainingRatio) / (MAX_BPS * MAX_BPS);
        return uint128(penalty);
    }

    /**
     * @notice Calculate amount receivable on early unlock
     */
    function earlyUnlockAmount(Lockup storage lock) internal view returns (uint128) {
        return lock.amount - earlyUnlockPenalty(lock);
    }

    /**
     * @notice Unlock and return amount (with penalty if early)
     */
    function unlock(Lockup storage lock) internal returns (uint128 received, uint128 penalty) {
        if (isUnlocked(lock)) {
            received = lock.amount;
            penalty = 0;
        } else {
            penalty = earlyUnlockPenalty(lock);
            received = lock.amount - penalty;
        }
        lock.amount = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SCHEDULED ACTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Schedule an action
     */
    function scheduleAction(
        ScheduledAction storage action,
        bytes32 actionHash,
        uint64 delay,
        uint64 validityPeriod
    ) internal {
        action.scheduledTime = uint64(block.timestamp) + delay;
        action.expiryTime = action.scheduledTime + validityPeriod;
        action.actionHash = actionHash;
        action.executed = false;
    }

    /**
     * @notice Check if action is ready to execute
     */
    function isActionReady(ScheduledAction storage action) internal view returns (bool) {
        return !action.executed &&
               block.timestamp >= action.scheduledTime &&
               block.timestamp <= action.expiryTime;
    }

    /**
     * @notice Execute scheduled action
     */
    function executeAction(ScheduledAction storage action, bytes32 actionHash) internal {
        if (action.executed) revert ActionAlreadyExecuted();
        if (block.timestamp < action.scheduledTime) {
            revert NotYetUnlocked(action.scheduledTime, block.timestamp);
        }
        if (block.timestamp > action.expiryTime) {
            revert AlreadyExpired(action.expiryTime, block.timestamp);
        }
        if (action.actionHash != actionHash) revert InvalidSchedule();

        action.executed = true;
    }

    /**
     * @notice Cancel scheduled action
     */
    function cancelAction(ScheduledAction storage action) internal {
        action.executed = true; // Mark as executed to prevent future execution
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LEASE/RENTAL
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a lease
     */
    function createLease(
        Lease storage lease,
        uint64 duration,
        uint128 totalRent
    ) internal {
        lease.startTime = uint64(block.timestamp);
        lease.endTime = uint64(block.timestamp) + duration;
        lease.totalRent = totalRent;
        lease.paidRent = 0;
        lease.active = true;
    }

    /**
     * @notice Check if lease is active and not expired
     */
    function isLeaseActive(Lease storage lease) internal view returns (bool) {
        return lease.active && block.timestamp <= lease.endTime;
    }

    /**
     * @notice Calculate rent due up to current time
     */
    function rentDue(Lease storage lease) internal view returns (uint128) {
        if (!lease.active) return 0;

        uint64 effectiveEnd = block.timestamp > lease.endTime
            ? lease.endTime
            : uint64(block.timestamp);

        uint256 totalDuration = lease.endTime - lease.startTime;
        uint256 elapsedDuration = effectiveEnd - lease.startTime;

        uint128 totalDue = uint128((uint256(lease.totalRent) * elapsedDuration) / totalDuration);
        if (totalDue <= lease.paidRent) return 0;
        return totalDue - lease.paidRent;
    }

    /**
     * @notice Pay rent
     */
    function payRent(Lease storage lease, uint128 amount) internal {
        if (!lease.active) revert LeaseNotActive();
        lease.paidRent += amount;
    }

    /**
     * @notice Extend lease
     */
    function extendLease(Lease storage lease, uint64 additionalDuration, uint128 additionalRent) internal {
        if (!lease.active) revert LeaseNotActive();
        lease.endTime += additionalDuration;
        lease.totalRent += additionalRent;
    }

    /**
     * @notice Terminate lease
     */
    function terminateLease(Lease storage lease) internal {
        lease.active = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert days to seconds
     */
    function daysToSeconds(uint256 days_) internal pure returns (uint256) {
        return days_ * SECONDS_PER_DAY;
    }

    /**
     * @notice Convert hours to seconds
     */
    function hoursToSeconds(uint256 hours_) internal pure returns (uint256) {
        return hours_ * SECONDS_PER_HOUR;
    }

    /**
     * @notice Convert minutes to seconds
     */
    function minutesToSeconds(uint256 minutes_) internal pure returns (uint256) {
        return minutes_ * SECONDS_PER_MINUTE;
    }

    /**
     * @notice Get timestamp for N days from now
     */
    function daysFromNow(uint256 days_) internal view returns (uint64) {
        return uint64(block.timestamp + daysToSeconds(days_));
    }

    /**
     * @notice Get timestamp for N hours from now
     */
    function hoursFromNow(uint256 hours_) internal view returns (uint64) {
        return uint64(block.timestamp + hoursToSeconds(hours_));
    }
}
