// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CircuitBreakerLib
 * @notice Generic circuit breaker pattern for rate limiting and failure protection
 * @dev Implements threshold-based circuit breakers with automatic cooldown and recovery
 */
library CircuitBreakerLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Circuit breaker state
    enum State {
        CLOSED,     // Normal operation
        OPEN,       // Tripped, blocking operations
        HALF_OPEN   // Testing if system recovered
    }

    /// @notice Circuit breaker configuration and state
    struct Breaker {
        State state;              // Current state
        uint32 failureCount;      // Number of consecutive failures
        uint32 successCount;      // Number of consecutive successes (half-open)
        uint32 failureThreshold;  // Failures to trip breaker
        uint32 successThreshold;  // Successes to close from half-open
        uint32 cooldownPeriod;    // Seconds before half-open attempt
        uint32 halfOpenLimit;     // Max operations in half-open state
        uint32 halfOpenAttempts;  // Current half-open attempts
        uint64 lastFailureTime;   // Timestamp of last failure
        uint64 tripTime;          // When breaker was tripped
    }

    /// @notice Sliding window circuit breaker
    struct WindowBreaker {
        State state;              // Current state
        uint32 windowSize;        // Window duration in seconds
        uint32 failureThreshold;  // Max failures in window
        uint32 cooldownPeriod;    // Cooldown after trip
        uint64 windowStart;       // Current window start
        uint64 tripTime;          // When tripped
        uint32 failuresInWindow;  // Failures in current window
        uint32 successThreshold;  // Successes to recover
        uint32 successCount;      // Current success count
    }

    /// @notice Volume-based circuit breaker
    struct VolumeBreaker {
        State state;              // Current state
        uint128 maxVolume;        // Maximum volume per period
        uint128 currentVolume;    // Volume in current period
        uint64 periodStart;       // Current period start
        uint32 periodDuration;    // Period duration in seconds
        uint32 cooldownPeriod;    // Cooldown after breach
        uint64 tripTime;          // When tripped
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error CircuitBreakerOpen();
    error CircuitBreakerHalfOpen();
    error HalfOpenLimitReached();
    error InvalidThreshold();
    error InvalidCooldown();
    error VolumeLimitExceeded(uint256 current, uint256 max);

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS (for use in contracts)
    // ═══════════════════════════════════════════════════════════════════════════

    event CircuitBreakerTripped(bytes32 indexed breakerId, uint256 failureCount);
    event CircuitBreakerReset(bytes32 indexed breakerId);
    event CircuitBreakerHalfOpened(bytes32 indexed breakerId);
    event CircuitBreakerClosed(bytes32 indexed breakerId, uint256 successCount);

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC CIRCUIT BREAKER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize a new circuit breaker
     * @param breaker Breaker storage
     * @param failureThreshold Failures before tripping
     * @param successThreshold Successes to recover from half-open
     * @param cooldownPeriod Seconds before allowing half-open
     * @param halfOpenLimit Max attempts in half-open state
     */
    function initialize(
        Breaker storage breaker,
        uint32 failureThreshold,
        uint32 successThreshold,
        uint32 cooldownPeriod,
        uint32 halfOpenLimit
    ) internal {
        if (failureThreshold == 0) revert InvalidThreshold();
        if (successThreshold == 0) revert InvalidThreshold();
        if (cooldownPeriod == 0) revert InvalidCooldown();

        breaker.state = State.CLOSED;
        breaker.failureThreshold = failureThreshold;
        breaker.successThreshold = successThreshold;
        breaker.cooldownPeriod = cooldownPeriod;
        breaker.halfOpenLimit = halfOpenLimit;
        breaker.failureCount = 0;
        breaker.successCount = 0;
        breaker.halfOpenAttempts = 0;
    }

    /**
     * @notice Check if operation is allowed and update state
     * @param breaker Breaker storage
     * @return True if operation is allowed
     */
    function canProceed(Breaker storage breaker) internal returns (bool) {
        _updateState(breaker);

        if (breaker.state == State.OPEN) {
            return false;
        }

        if (breaker.state == State.HALF_OPEN) {
            if (breaker.halfOpenAttempts >= breaker.halfOpenLimit) {
                return false;
            }
            breaker.halfOpenAttempts++;
        }

        return true;
    }

    /**
     * @notice Check state without allowing modification (view)
     * @param breaker Breaker storage
     * @return True if would be allowed
     */
    function isAllowed(Breaker storage breaker) internal view returns (bool) {
        State currentState = _computeState(breaker);

        if (currentState == State.OPEN) {
            return false;
        }

        if (currentState == State.HALF_OPEN) {
            return breaker.halfOpenAttempts < breaker.halfOpenLimit;
        }

        return true;
    }

    /**
     * @notice Record a successful operation
     * @param breaker Breaker storage
     */
    function recordSuccess(Breaker storage breaker) internal {
        if (breaker.state == State.CLOSED) {
            breaker.failureCount = 0;
            return;
        }

        if (breaker.state == State.HALF_OPEN) {
            breaker.successCount++;
            if (breaker.successCount >= breaker.successThreshold) {
                _close(breaker);
            }
        }
    }

    /**
     * @notice Record a failed operation
     * @param breaker Breaker storage
     */
    function recordFailure(Breaker storage breaker) internal {
        breaker.lastFailureTime = uint64(block.timestamp);

        if (breaker.state == State.HALF_OPEN) {
            _trip(breaker);
            return;
        }

        breaker.failureCount++;
        if (breaker.failureCount >= breaker.failureThreshold) {
            _trip(breaker);
        }
    }

    /**
     * @notice Force trip the circuit breaker
     * @param breaker Breaker storage
     */
    function forceTrip(Breaker storage breaker) internal {
        _trip(breaker);
    }

    /**
     * @notice Force reset the circuit breaker
     * @param breaker Breaker storage
     */
    function forceReset(Breaker storage breaker) internal {
        _close(breaker);
    }

    /**
     * @notice Get current state
     * @param breaker Breaker storage
     * @return Current state
     */
    function getState(Breaker storage breaker) internal view returns (State) {
        return _computeState(breaker);
    }

    /**
     * @notice Get time until half-open is possible
     * @param breaker Breaker storage
     * @return Seconds remaining (0 if already can transition)
     */
    function timeUntilHalfOpen(Breaker storage breaker) internal view returns (uint256) {
        if (breaker.state != State.OPEN) return 0;

        uint256 readyTime = breaker.tripTime + breaker.cooldownPeriod;
        if (block.timestamp >= readyTime) return 0;

        return readyTime - block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SLIDING WINDOW CIRCUIT BREAKER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize window-based breaker
     */
    function initializeWindow(
        WindowBreaker storage breaker,
        uint32 windowSize,
        uint32 failureThreshold,
        uint32 cooldownPeriod,
        uint32 successThreshold
    ) internal {
        if (windowSize == 0 || failureThreshold == 0) revert InvalidThreshold();

        breaker.state = State.CLOSED;
        breaker.windowSize = windowSize;
        breaker.failureThreshold = failureThreshold;
        breaker.cooldownPeriod = cooldownPeriod;
        breaker.successThreshold = successThreshold;
        breaker.windowStart = uint64(block.timestamp);
        breaker.failuresInWindow = 0;
        breaker.successCount = 0;
    }

    /**
     * @notice Check if window breaker allows operation
     */
    function canProceedWindow(WindowBreaker storage breaker) internal returns (bool) {
        _updateWindowState(breaker);
        return breaker.state != State.OPEN;
    }

    /**
     * @notice Record failure in window breaker
     */
    function recordFailureWindow(WindowBreaker storage breaker) internal {
        _updateWindowState(breaker);

        if (breaker.state == State.HALF_OPEN) {
            breaker.state = State.OPEN;
            breaker.tripTime = uint64(block.timestamp);
            breaker.successCount = 0;
            return;
        }

        breaker.failuresInWindow++;
        if (breaker.failuresInWindow >= breaker.failureThreshold) {
            breaker.state = State.OPEN;
            breaker.tripTime = uint64(block.timestamp);
        }
    }

    /**
     * @notice Record success in window breaker
     */
    function recordSuccessWindow(WindowBreaker storage breaker) internal {
        if (breaker.state == State.HALF_OPEN) {
            breaker.successCount++;
            if (breaker.successCount >= breaker.successThreshold) {
                breaker.state = State.CLOSED;
                breaker.failuresInWindow = 0;
                breaker.windowStart = uint64(block.timestamp);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOLUME-BASED CIRCUIT BREAKER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize volume-based breaker
     */
    function initializeVolume(
        VolumeBreaker storage breaker,
        uint128 maxVolume,
        uint32 periodDuration,
        uint32 cooldownPeriod
    ) internal {
        if (maxVolume == 0 || periodDuration == 0) revert InvalidThreshold();

        breaker.state = State.CLOSED;
        breaker.maxVolume = maxVolume;
        breaker.periodDuration = periodDuration;
        breaker.cooldownPeriod = cooldownPeriod;
        breaker.periodStart = uint64(block.timestamp);
        breaker.currentVolume = 0;
    }

    /**
     * @notice Check if volume is within limits
     * @param breaker Breaker storage
     * @param amount Amount to check
     * @return True if amount is allowed
     */
    function canAddVolume(VolumeBreaker storage breaker, uint128 amount) internal returns (bool) {
        _updateVolumeState(breaker);

        if (breaker.state == State.OPEN) {
            return false;
        }

        return breaker.currentVolume + amount <= breaker.maxVolume;
    }

    /**
     * @notice Add volume and check limits
     * @param breaker Breaker storage
     * @param amount Amount to add
     */
    function addVolume(VolumeBreaker storage breaker, uint128 amount) internal {
        _updateVolumeState(breaker);

        if (breaker.state == State.OPEN) {
            revert CircuitBreakerOpen();
        }

        uint128 newVolume = breaker.currentVolume + amount;
        if (newVolume > breaker.maxVolume) {
            breaker.state = State.OPEN;
            breaker.tripTime = uint64(block.timestamp);
            revert VolumeLimitExceeded(newVolume, breaker.maxVolume);
        }

        breaker.currentVolume = newVolume;
    }

    /**
     * @notice Get remaining volume in current period
     */
    function remainingVolume(VolumeBreaker storage breaker) internal view returns (uint128) {
        if (breaker.state == State.OPEN) return 0;

        // Check if period has reset
        if (block.timestamp >= breaker.periodStart + breaker.periodDuration) {
            return breaker.maxVolume;
        }

        return breaker.maxVolume - breaker.currentVolume;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _updateState(Breaker storage breaker) private {
        if (breaker.state == State.OPEN) {
            if (block.timestamp >= breaker.tripTime + breaker.cooldownPeriod) {
                breaker.state = State.HALF_OPEN;
                breaker.halfOpenAttempts = 0;
                breaker.successCount = 0;
            }
        }
    }

    function _computeState(Breaker storage breaker) private view returns (State) {
        if (breaker.state == State.OPEN) {
            if (block.timestamp >= breaker.tripTime + breaker.cooldownPeriod) {
                return State.HALF_OPEN;
            }
        }
        return breaker.state;
    }

    function _trip(Breaker storage breaker) private {
        breaker.state = State.OPEN;
        breaker.tripTime = uint64(block.timestamp);
        breaker.successCount = 0;
        breaker.halfOpenAttempts = 0;
    }

    function _close(Breaker storage breaker) private {
        breaker.state = State.CLOSED;
        breaker.failureCount = 0;
        breaker.successCount = 0;
        breaker.halfOpenAttempts = 0;
    }

    function _updateWindowState(WindowBreaker storage breaker) private {
        // Check if window has rolled over
        if (breaker.state == State.CLOSED) {
            if (block.timestamp >= breaker.windowStart + breaker.windowSize) {
                breaker.windowStart = uint64(block.timestamp);
                breaker.failuresInWindow = 0;
            }
        }
        // Check if cooldown has passed for tripped breaker
        else if (breaker.state == State.OPEN) {
            if (block.timestamp >= breaker.tripTime + breaker.cooldownPeriod) {
                breaker.state = State.HALF_OPEN;
                breaker.successCount = 0;
            }
        }
    }

    function _updateVolumeState(VolumeBreaker storage breaker) private {
        // Check if period has rolled over
        if (breaker.state == State.CLOSED) {
            if (block.timestamp >= breaker.periodStart + breaker.periodDuration) {
                breaker.periodStart = uint64(block.timestamp);
                breaker.currentVolume = 0;
            }
        }
        // Check if cooldown has passed
        else if (breaker.state == State.OPEN) {
            if (block.timestamp >= breaker.tripTime + breaker.cooldownPeriod) {
                breaker.state = State.CLOSED;
                breaker.periodStart = uint64(block.timestamp);
                breaker.currentVolume = 0;
            }
        }
    }
}
