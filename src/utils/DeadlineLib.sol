// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeadlineLib
 * @notice Comprehensive deadline and expiry management library for DeFi protocols
 * @dev Implements deadline validation, grace periods, and time-based state management
 */
library DeadlineLib {
    // ============ ERRORS ============
    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error DeadlineNotExpired(uint256 deadline, uint256 currentTime);
    error InvalidDeadline(uint256 deadline);
    error DeadlineTooSoon(uint256 deadline, uint256 minDeadline);
    error DeadlineTooFar(uint256 deadline, uint256 maxDeadline);
    error GracePeriodActive(uint256 expiresAt);
    error GracePeriodExpired(uint256 expiredAt);
    error InvalidDuration(uint256 duration);
    error OrderExpired(bytes32 orderId, uint256 deadline);
    error PermitExpired(uint256 deadline);

    // ============ CONSTANTS ============
    uint256 internal constant MIN_DEADLINE_OFFSET = 1 minutes;
    uint256 internal constant MAX_DEADLINE_OFFSET = 365 days;
    uint256 internal constant DEFAULT_GRACE_PERIOD = 1 hours;
    uint256 internal constant PERMIT_DEADLINE_BUFFER = 5 minutes;

    // Standard deadline presets
    uint256 internal constant DEADLINE_5_MINUTES = 5 minutes;
    uint256 internal constant DEADLINE_15_MINUTES = 15 minutes;
    uint256 internal constant DEADLINE_30_MINUTES = 30 minutes;
    uint256 internal constant DEADLINE_1_HOUR = 1 hours;
    uint256 internal constant DEADLINE_4_HOURS = 4 hours;
    uint256 internal constant DEADLINE_24_HOURS = 24 hours;
    uint256 internal constant DEADLINE_7_DAYS = 7 days;
    uint256 internal constant DEADLINE_30_DAYS = 30 days;

    // ============ TYPES ============
    struct DeadlineConfig {
        uint256 minOffset;      // Minimum time from now
        uint256 maxOffset;      // Maximum time from now
        uint256 gracePeriod;    // Grace period after deadline
        bool allowInfinite;     // Allow type(uint256).max as deadline
    }

    struct TimedOrder {
        bytes32 orderId;
        uint256 createdAt;
        uint256 deadline;
        uint256 gracePeriodEnd;
        bool executed;
        bool cancelled;
    }

    struct ExpiryTracker {
        mapping(bytes32 => uint256) expirations;
        uint256 defaultDuration;
        uint256 gracePeriod;
    }

    // ============ EVENTS ============
    event DeadlineSet(bytes32 indexed id, uint256 deadline);
    event DeadlineExtended(bytes32 indexed id, uint256 oldDeadline, uint256 newDeadline);
    event GracePeriodStarted(bytes32 indexed id, uint256 gracePeriodEnd);
    event OrderExpiredEvent(bytes32 indexed orderId, uint256 deadline);

    // ============ BASIC DEADLINE CHECKS ============

    /**
     * @notice Check if a deadline has passed
     * @param deadline The deadline timestamp
     * @return True if the deadline has passed
     */
    function isExpired(uint256 deadline) internal view returns (bool) {
        return block.timestamp > deadline;
    }

    /**
     * @notice Check if a deadline is still valid
     * @param deadline The deadline timestamp
     * @return True if the deadline has not passed
     */
    function isValid(uint256 deadline) internal view returns (bool) {
        return block.timestamp <= deadline;
    }

    /**
     * @notice Require deadline has not passed
     * @param deadline The deadline timestamp
     */
    function requireNotExpired(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert DeadlineExpired(deadline, block.timestamp);
        }
    }

    /**
     * @notice Require deadline has passed
     * @param deadline The deadline timestamp
     */
    function requireExpired(uint256 deadline) internal view {
        if (block.timestamp <= deadline) {
            revert DeadlineNotExpired(deadline, block.timestamp);
        }
    }

    /**
     * @notice Validate deadline is within acceptable range
     * @param deadline The deadline timestamp
     * @param config The deadline configuration
     */
    function validateDeadline(
        uint256 deadline,
        DeadlineConfig memory config
    ) internal view {
        // Check for infinite deadline
        if (deadline == type(uint256).max) {
            if (!config.allowInfinite) revert InvalidDeadline(deadline);
            return;
        }

        // Must be in the future
        if (deadline <= block.timestamp) {
            revert DeadlineExpired(deadline, block.timestamp);
        }

        uint256 offset = deadline - block.timestamp;

        // Check minimum offset
        if (offset < config.minOffset) {
            revert DeadlineTooSoon(deadline, block.timestamp + config.minOffset);
        }

        // Check maximum offset
        if (offset > config.maxOffset) {
            revert DeadlineTooFar(deadline, block.timestamp + config.maxOffset);
        }
    }

    /**
     * @notice Validate deadline with default config
     * @param deadline The deadline timestamp
     */
    function validateDeadlineDefault(uint256 deadline) internal view {
        validateDeadline(deadline, getDefaultConfig());
    }

    // ============ DEADLINE CREATION ============

    /**
     * @notice Create a deadline from duration
     * @param duration Duration in seconds from now
     * @return deadline The deadline timestamp
     */
    function fromDuration(uint256 duration) internal view returns (uint256 deadline) {
        if (duration == 0) revert InvalidDuration(duration);
        deadline = block.timestamp + duration;
    }

    /**
     * @notice Create a deadline with validation
     * @param duration Duration in seconds from now
     * @param config The deadline configuration
     * @return deadline The deadline timestamp
     */
    function createDeadline(
        uint256 duration,
        DeadlineConfig memory config
    ) internal view returns (uint256 deadline) {
        if (duration < config.minOffset) {
            revert DeadlineTooSoon(block.timestamp + duration, block.timestamp + config.minOffset);
        }
        if (duration > config.maxOffset) {
            revert DeadlineTooFar(block.timestamp + duration, block.timestamp + config.maxOffset);
        }
        deadline = block.timestamp + duration;
    }

    /**
     * @notice Create deadline from preset
     * @param preset One of the DEADLINE_* constants
     * @return deadline The deadline timestamp
     */
    function fromPreset(uint256 preset) internal view returns (uint256 deadline) {
        return block.timestamp + preset;
    }

    /**
     * @notice Get infinite deadline (never expires)
     * @return type(uint256).max
     */
    function infinite() internal pure returns (uint256) {
        return type(uint256).max;
    }

    // ============ GRACE PERIOD FUNCTIONS ============

    /**
     * @notice Check if in grace period
     * @param deadline The original deadline
     * @param gracePeriod The grace period duration
     * @return True if currently in grace period
     */
    function isInGracePeriod(
        uint256 deadline,
        uint256 gracePeriod
    ) internal view returns (bool) {
        if (block.timestamp <= deadline) return false;
        return block.timestamp <= deadline + gracePeriod;
    }

    /**
     * @notice Get time remaining in grace period
     * @param deadline The original deadline
     * @param gracePeriod The grace period duration
     * @return remaining Time remaining (0 if not in grace period)
     */
    function gracePeriodRemaining(
        uint256 deadline,
        uint256 gracePeriod
    ) internal view returns (uint256 remaining) {
        uint256 gracePeriodEnd = deadline + gracePeriod;
        if (block.timestamp <= deadline) {
            return gracePeriod; // Full grace period available
        }
        if (block.timestamp >= gracePeriodEnd) {
            return 0;
        }
        return gracePeriodEnd - block.timestamp;
    }

    /**
     * @notice Require action within grace period
     * @param deadline The original deadline
     * @param gracePeriod The grace period duration
     */
    function requireWithinGracePeriod(
        uint256 deadline,
        uint256 gracePeriod
    ) internal view {
        uint256 gracePeriodEnd = deadline + gracePeriod;
        if (block.timestamp > gracePeriodEnd) {
            revert GracePeriodExpired(gracePeriodEnd);
        }
    }

    // ============ TIME CALCULATIONS ============

    /**
     * @notice Get time remaining until deadline
     * @param deadline The deadline timestamp
     * @return remaining Time remaining in seconds (0 if expired)
     */
    function timeRemaining(uint256 deadline) internal view returns (uint256 remaining) {
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    /**
     * @notice Get time since deadline passed
     * @param deadline The deadline timestamp
     * @return elapsed Time since deadline (0 if not expired)
     */
    function timeSinceExpiry(uint256 deadline) internal view returns (uint256 elapsed) {
        if (block.timestamp <= deadline) return 0;
        return block.timestamp - deadline;
    }

    /**
     * @notice Calculate percentage of time remaining
     * @param createdAt When the deadline was set
     * @param deadline The deadline timestamp
     * @return percentage Percentage remaining (0-100), in basis points for precision
     */
    function percentageRemaining(
        uint256 createdAt,
        uint256 deadline
    ) internal view returns (uint256 percentage) {
        if (block.timestamp >= deadline) return 0;
        if (createdAt >= deadline) return 0;

        uint256 totalDuration = deadline - createdAt;
        uint256 remaining = deadline - block.timestamp;

        return (remaining * 10000) / totalDuration; // Returns in basis points
    }

    // ============ EXTENSION FUNCTIONS ============

    /**
     * @notice Extend a deadline
     * @param currentDeadline The current deadline
     * @param extension Duration to extend by
     * @param maxDeadline Maximum allowed deadline
     * @return newDeadline The new deadline
     */
    function extend(
        uint256 currentDeadline,
        uint256 extension,
        uint256 maxDeadline
    ) internal view returns (uint256 newDeadline) {
        newDeadline = currentDeadline + extension;
        if (newDeadline > maxDeadline) {
            newDeadline = maxDeadline;
        }
    }

    /**
     * @notice Extend deadline from now (reset)
     * @param duration New duration from now
     * @return newDeadline The new deadline
     */
    function reset(uint256 duration) internal view returns (uint256 newDeadline) {
        return block.timestamp + duration;
    }

    // ============ ORDER TRACKING ============

    /**
     * @notice Create a timed order
     * @param orderId The order identifier
     * @param duration Duration until expiry
     * @param gracePeriod Grace period duration
     * @return order The timed order struct
     */
    function createTimedOrder(
        bytes32 orderId,
        uint256 duration,
        uint256 gracePeriod
    ) internal view returns (TimedOrder memory order) {
        uint256 deadline = block.timestamp + duration;
        return TimedOrder({
            orderId: orderId,
            createdAt: block.timestamp,
            deadline: deadline,
            gracePeriodEnd: deadline + gracePeriod,
            executed: false,
            cancelled: false
        });
    }

    /**
     * @notice Check if order can be executed
     * @param order The timed order
     * @return True if order is valid for execution
     */
    function canExecute(TimedOrder memory order) internal view returns (bool) {
        if (order.executed || order.cancelled) return false;
        return block.timestamp <= order.deadline;
    }

    /**
     * @notice Check if order can be cancelled with refund (in grace period)
     * @param order The timed order
     * @return True if order can be cancelled
     */
    function canCancel(TimedOrder memory order) internal view returns (bool) {
        if (order.executed || order.cancelled) return false;
        return block.timestamp <= order.gracePeriodEnd;
    }

    /**
     * @notice Get order status
     * @param order The timed order
     * @return status 0=active, 1=expired, 2=inGracePeriod, 3=fullyExpired, 4=executed, 5=cancelled
     */
    function getOrderStatus(TimedOrder memory order) internal view returns (uint8 status) {
        if (order.executed) return 4;
        if (order.cancelled) return 5;
        if (block.timestamp <= order.deadline) return 0; // Active
        if (block.timestamp <= order.gracePeriodEnd) return 2; // In grace period
        return 3; // Fully expired
    }

    // ============ EXPIRY TRACKER ============

    /**
     * @notice Set expiration for an item
     * @param tracker The expiry tracker storage
     * @param id The item identifier
     * @param duration Duration until expiry
     */
    function setExpiration(
        ExpiryTracker storage tracker,
        bytes32 id,
        uint256 duration
    ) internal {
        uint256 deadline = block.timestamp + duration;
        tracker.expirations[id] = deadline;
        emit DeadlineSet(id, deadline);
    }

    /**
     * @notice Check if item is expired
     * @param tracker The expiry tracker storage
     * @param id The item identifier
     * @return True if expired
     */
    function isItemExpired(
        ExpiryTracker storage tracker,
        bytes32 id
    ) internal view returns (bool) {
        uint256 expiration = tracker.expirations[id];
        if (expiration == 0) return true; // Never set = expired
        return block.timestamp > expiration;
    }

    /**
     * @notice Extend item expiration
     * @param tracker The expiry tracker storage
     * @param id The item identifier
     * @param extension Additional duration
     */
    function extendExpiration(
        ExpiryTracker storage tracker,
        bytes32 id,
        uint256 extension
    ) internal {
        uint256 oldDeadline = tracker.expirations[id];
        uint256 newDeadline = oldDeadline + extension;
        tracker.expirations[id] = newDeadline;
        emit DeadlineExtended(id, oldDeadline, newDeadline);
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Get default deadline configuration
     * @return config The default configuration
     */
    function getDefaultConfig() internal pure returns (DeadlineConfig memory config) {
        return DeadlineConfig({
            minOffset: MIN_DEADLINE_OFFSET,
            maxOffset: MAX_DEADLINE_OFFSET,
            gracePeriod: DEFAULT_GRACE_PERIOD,
            allowInfinite: false
        });
    }

    /**
     * @notice Get swap/trade deadline configuration
     * @return config Configuration for swap operations
     */
    function getSwapConfig() internal pure returns (DeadlineConfig memory config) {
        return DeadlineConfig({
            minOffset: 1 minutes,
            maxOffset: 30 minutes,
            gracePeriod: 0,
            allowInfinite: false
        });
    }

    /**
     * @notice Get governance deadline configuration
     * @return config Configuration for governance operations
     */
    function getGovernanceConfig() internal pure returns (DeadlineConfig memory config) {
        return DeadlineConfig({
            minOffset: 1 days,
            maxOffset: 30 days,
            gracePeriod: 2 days,
            allowInfinite: false
        });
    }

    /**
     * @notice Convert deadline to human-readable components
     * @param deadline The deadline timestamp
     * @return days_ Days until deadline
     * @return hours_ Hours component
     * @return minutes_ Minutes component
     */
    function toComponents(
        uint256 deadline
    ) internal view returns (uint256 days_, uint256 hours_, uint256 minutes_) {
        if (block.timestamp >= deadline) return (0, 0, 0);

        uint256 remaining = deadline - block.timestamp;
        days_ = remaining / 1 days;
        remaining = remaining % 1 days;
        hours_ = remaining / 1 hours;
        remaining = remaining % 1 hours;
        minutes_ = remaining / 1 minutes;
    }

    /**
     * @notice Check if deadline is reasonable for permit
     * @param deadline The permit deadline
     * @return True if deadline is acceptable
     */
    function isValidPermitDeadline(uint256 deadline) internal view returns (bool) {
        if (deadline <= block.timestamp) return false;
        // Permits should not be too far in the future
        return deadline <= block.timestamp + 1 hours;
    }

    /**
     * @notice Get safe permit deadline
     * @return deadline A reasonable permit deadline
     */
    function getSafePermitDeadline() internal view returns (uint256 deadline) {
        return block.timestamp + PERMIT_DEADLINE_BUFFER;
    }
}
