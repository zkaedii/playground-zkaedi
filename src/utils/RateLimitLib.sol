// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RateLimitLib
 * @notice Rate limiting utilities using token bucket and sliding window algorithms
 * @dev Provides configurable rate limiters for protecting DeFi protocols
 */
library RateLimitLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Token bucket rate limiter (smooth refill)
    struct TokenBucket {
        uint128 tokens;           // Current available tokens
        uint128 capacity;         // Maximum bucket capacity
        uint64 lastRefillTime;    // Last refill timestamp
        uint64 refillRate;        // Tokens per second to refill
        uint128 minTokens;        // Minimum tokens to keep
    }

    /// @notice Fixed window rate limiter
    struct FixedWindow {
        uint128 count;            // Operations in current window
        uint128 limit;            // Maximum operations per window
        uint64 windowStart;       // Current window start time
        uint32 windowDuration;    // Window size in seconds
    }

    /// @notice Sliding window rate limiter (more accurate)
    struct SlidingWindow {
        uint128 previousCount;    // Count from previous window
        uint128 currentCount;     // Count in current window
        uint128 limit;            // Maximum operations per window
        uint64 windowStart;       // Current window start time
        uint32 windowDuration;    // Window size in seconds
    }

    /// @notice Per-user rate limiter configuration
    struct UserRateLimit {
        uint128 tokens;           // User's available tokens
        uint64 lastRefillTime;    // User's last refill
    }

    /// @notice Tiered rate limiter (different limits per tier)
    struct TieredLimit {
        uint128 baseLimit;        // Base tier limit
        uint128 silverLimit;      // Silver tier limit
        uint128 goldLimit;        // Gold tier limit
        uint128 platinumLimit;    // Platinum tier limit
        uint32 windowDuration;    // Window size in seconds
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error RateLimitExceeded(uint256 requested, uint256 available);
    error InvalidCapacity();
    error InvalidRefillRate();
    error InvalidWindowDuration();
    error InvalidLimit();
    error InsufficientTokens(uint256 requested, uint256 available);

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN BUCKET IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize a token bucket rate limiter
     * @param bucket Bucket storage
     * @param capacity Maximum tokens in bucket
     * @param refillRate Tokens added per second
     * @param initialTokens Starting tokens (usually == capacity)
     */
    function initialize(
        TokenBucket storage bucket,
        uint128 capacity,
        uint64 refillRate,
        uint128 initialTokens
    ) internal {
        if (capacity == 0) revert InvalidCapacity();
        if (refillRate == 0) revert InvalidRefillRate();

        bucket.capacity = capacity;
        bucket.refillRate = refillRate;
        bucket.tokens = initialTokens > capacity ? capacity : initialTokens;
        bucket.lastRefillTime = uint64(block.timestamp);
        bucket.minTokens = 0;
    }

    /**
     * @notice Initialize with minimum tokens requirement
     */
    function initializeWithMin(
        TokenBucket storage bucket,
        uint128 capacity,
        uint64 refillRate,
        uint128 initialTokens,
        uint128 minTokens
    ) internal {
        initialize(bucket, capacity, refillRate, initialTokens);
        bucket.minTokens = minTokens;
    }

    /**
     * @notice Refill bucket based on elapsed time
     * @param bucket Bucket storage
     */
    function refill(TokenBucket storage bucket) internal {
        uint64 currentTime = uint64(block.timestamp);
        uint64 elapsed = currentTime - bucket.lastRefillTime;

        if (elapsed > 0) {
            uint256 tokensToAdd = uint256(elapsed) * bucket.refillRate;
            uint256 newTokens = uint256(bucket.tokens) + tokensToAdd;

            bucket.tokens = newTokens > bucket.capacity
                ? bucket.capacity
                : uint128(newTokens);
            bucket.lastRefillTime = currentTime;
        }
    }

    /**
     * @notice Check if tokens can be consumed
     * @param bucket Bucket storage
     * @param amount Tokens to consume
     * @return True if consumption is allowed
     */
    function canConsume(TokenBucket storage bucket, uint128 amount) internal returns (bool) {
        refill(bucket);
        return bucket.tokens >= amount + bucket.minTokens;
    }

    /**
     * @notice Try to consume tokens
     * @param bucket Bucket storage
     * @param amount Tokens to consume
     * @return success True if consumed
     * @return remaining Tokens remaining after operation
     */
    function tryConsume(
        TokenBucket storage bucket,
        uint128 amount
    ) internal returns (bool success, uint128 remaining) {
        refill(bucket);

        if (bucket.tokens >= amount + bucket.minTokens) {
            bucket.tokens -= amount;
            return (true, bucket.tokens);
        }

        return (false, bucket.tokens);
    }

    /**
     * @notice Consume tokens, revert if insufficient
     * @param bucket Bucket storage
     * @param amount Tokens to consume
     */
    function consume(TokenBucket storage bucket, uint128 amount) internal {
        refill(bucket);

        uint128 available = bucket.tokens > bucket.minTokens
            ? bucket.tokens - bucket.minTokens
            : 0;

        if (available < amount) {
            revert InsufficientTokens(amount, available);
        }

        bucket.tokens -= amount;
    }

    /**
     * @notice Get current available tokens
     * @param bucket Bucket storage
     * @return Available tokens (after accounting for minTokens)
     */
    function available(TokenBucket storage bucket) internal view returns (uint128) {
        uint64 elapsed = uint64(block.timestamp) - bucket.lastRefillTime;
        uint256 tokensWithRefill = uint256(bucket.tokens) + uint256(elapsed) * bucket.refillRate;
        uint128 total = tokensWithRefill > bucket.capacity
            ? bucket.capacity
            : uint128(tokensWithRefill);

        return total > bucket.minTokens ? total - bucket.minTokens : 0;
    }

    /**
     * @notice Get time until bucket will have enough tokens
     * @param bucket Bucket storage
     * @param amount Required tokens
     * @return Seconds until available (0 if already available)
     */
    function timeUntilAvailable(TokenBucket storage bucket, uint128 amount) internal view returns (uint256) {
        uint128 currentAvailable = available(bucket);
        if (currentAvailable >= amount) return 0;

        uint128 needed = amount - currentAvailable;
        return (uint256(needed) + bucket.refillRate - 1) / bucket.refillRate;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FIXED WINDOW IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize fixed window rate limiter
     */
    function initializeFixed(
        FixedWindow storage window,
        uint128 limit,
        uint32 windowDuration
    ) internal {
        if (limit == 0) revert InvalidLimit();
        if (windowDuration == 0) revert InvalidWindowDuration();

        window.limit = limit;
        window.windowDuration = windowDuration;
        window.windowStart = uint64(block.timestamp);
        window.count = 0;
    }

    /**
     * @notice Check and potentially reset window
     */
    function _updateFixedWindow(FixedWindow storage window) private {
        if (block.timestamp >= window.windowStart + window.windowDuration) {
            window.windowStart = uint64(block.timestamp);
            window.count = 0;
        }
    }

    /**
     * @notice Check if operation is allowed
     */
    function canProceedFixed(FixedWindow storage window, uint128 amount) internal returns (bool) {
        _updateFixedWindow(window);
        return window.count + amount <= window.limit;
    }

    /**
     * @notice Record operation in fixed window
     */
    function recordFixed(FixedWindow storage window, uint128 amount) internal {
        _updateFixedWindow(window);

        if (window.count + amount > window.limit) {
            revert RateLimitExceeded(amount, window.limit - window.count);
        }

        window.count += amount;
    }

    /**
     * @notice Get remaining capacity in window
     */
    function remainingFixed(FixedWindow storage window) internal view returns (uint128) {
        if (block.timestamp >= window.windowStart + window.windowDuration) {
            return window.limit;
        }
        return window.limit > window.count ? window.limit - window.count : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SLIDING WINDOW IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize sliding window rate limiter
     */
    function initializeSliding(
        SlidingWindow storage window,
        uint128 limit,
        uint32 windowDuration
    ) internal {
        if (limit == 0) revert InvalidLimit();
        if (windowDuration == 0) revert InvalidWindowDuration();

        window.limit = limit;
        window.windowDuration = windowDuration;
        window.windowStart = uint64(block.timestamp);
        window.previousCount = 0;
        window.currentCount = 0;
    }

    /**
     * @notice Update sliding window state
     */
    function _updateSlidingWindow(SlidingWindow storage window) private {
        uint64 currentTime = uint64(block.timestamp);
        uint64 windowEnd = window.windowStart + window.windowDuration;

        if (currentTime >= windowEnd) {
            // Calculate how many windows have passed
            uint256 windowsPassed = (currentTime - window.windowStart) / window.windowDuration;

            if (windowsPassed >= 2) {
                // More than 2 windows passed, reset both
                window.previousCount = 0;
                window.currentCount = 0;
            } else {
                // Exactly 1 window passed
                window.previousCount = window.currentCount;
                window.currentCount = 0;
            }

            window.windowStart = uint64(currentTime - (currentTime % window.windowDuration));
        }
    }

    /**
     * @notice Calculate weighted count using sliding window
     */
    function _slidingCount(SlidingWindow storage window) private view returns (uint128) {
        uint64 currentTime = uint64(block.timestamp);
        uint64 windowEnd = window.windowStart + window.windowDuration;

        if (currentTime >= windowEnd) {
            return 0; // Will be reset on next update
        }

        // Weight of previous window based on time remaining
        uint256 elapsed = currentTime - window.windowStart;
        uint256 previousWeight = window.windowDuration - elapsed;

        // Weighted sum: (previous * weight / duration) + current
        uint256 weightedPrevious = (uint256(window.previousCount) * previousWeight) / window.windowDuration;
        return uint128(weightedPrevious + window.currentCount);
    }

    /**
     * @notice Check if operation is allowed with sliding window
     */
    function canProceedSliding(SlidingWindow storage window, uint128 amount) internal returns (bool) {
        _updateSlidingWindow(window);
        uint128 currentUsage = _slidingCount(window);
        return currentUsage + amount <= window.limit;
    }

    /**
     * @notice Record operation with sliding window
     */
    function recordSliding(SlidingWindow storage window, uint128 amount) internal {
        _updateSlidingWindow(window);
        uint128 currentUsage = _slidingCount(window);

        if (currentUsage + amount > window.limit) {
            revert RateLimitExceeded(amount, window.limit - currentUsage);
        }

        window.currentCount += amount;
    }

    /**
     * @notice Get approximate remaining capacity
     */
    function remainingSliding(SlidingWindow storage window) internal view returns (uint128) {
        uint128 currentUsage = _slidingCount(window);
        return window.limit > currentUsage ? window.limit - currentUsage : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PER-USER RATE LIMITING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check and consume from user's rate limit
     * @param userLimit User's rate limit state
     * @param capacity Global bucket capacity
     * @param refillRate Global refill rate
     * @param amount Amount to consume
     * @return True if consumption succeeded
     */
    function tryConsumeUser(
        UserRateLimit storage userLimit,
        uint128 capacity,
        uint64 refillRate,
        uint128 amount
    ) internal returns (bool) {
        // Refill user's bucket
        uint64 currentTime = uint64(block.timestamp);
        uint64 elapsed = currentTime - userLimit.lastRefillTime;

        if (userLimit.lastRefillTime == 0) {
            // First use - initialize
            userLimit.tokens = capacity;
            userLimit.lastRefillTime = currentTime;
        } else if (elapsed > 0) {
            uint256 tokensToAdd = uint256(elapsed) * refillRate;
            uint256 newTokens = uint256(userLimit.tokens) + tokensToAdd;
            userLimit.tokens = newTokens > capacity ? capacity : uint128(newTokens);
            userLimit.lastRefillTime = currentTime;
        }

        if (userLimit.tokens >= amount) {
            userLimit.tokens -= amount;
            return true;
        }

        return false;
    }

    /**
     * @notice Get user's available tokens
     */
    function availableUser(
        UserRateLimit storage userLimit,
        uint128 capacity,
        uint64 refillRate
    ) internal view returns (uint128) {
        if (userLimit.lastRefillTime == 0) {
            return capacity;
        }

        uint64 elapsed = uint64(block.timestamp) - userLimit.lastRefillTime;
        uint256 tokensWithRefill = uint256(userLimit.tokens) + uint256(elapsed) * refillRate;

        return tokensWithRefill > capacity ? capacity : uint128(tokensWithRefill);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIERED RATE LIMITING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice User tier levels
    enum Tier { BASE, SILVER, GOLD, PLATINUM }

    /**
     * @notice Initialize tiered rate limiter
     */
    function initializeTiered(
        TieredLimit storage tiered,
        uint128 baseLimit,
        uint128 silverLimit,
        uint128 goldLimit,
        uint128 platinumLimit,
        uint32 windowDuration
    ) internal {
        tiered.baseLimit = baseLimit;
        tiered.silverLimit = silverLimit;
        tiered.goldLimit = goldLimit;
        tiered.platinumLimit = platinumLimit;
        tiered.windowDuration = windowDuration;
    }

    /**
     * @notice Get limit for a specific tier
     */
    function getLimitForTier(TieredLimit storage tiered, Tier tier) internal view returns (uint128) {
        if (tier == Tier.PLATINUM) return tiered.platinumLimit;
        if (tier == Tier.GOLD) return tiered.goldLimit;
        if (tier == Tier.SILVER) return tiered.silverLimit;
        return tiered.baseLimit;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate tokens needed for a given rate
     * @param operationsPerSecond Desired operations per second
     * @param burstMultiplier Burst capacity multiplier (e.g., 10 = 10x burst)
     * @return capacity Recommended bucket capacity
     * @return refillRate Recommended refill rate
     */
    function calculateBucketParams(
        uint64 operationsPerSecond,
        uint64 burstMultiplier
    ) internal pure returns (uint128 capacity, uint64 refillRate) {
        refillRate = operationsPerSecond;
        capacity = uint128(operationsPerSecond) * burstMultiplier;
    }

    /**
     * @notice Calculate window parameters from rate
     * @param operationsPerMinute Desired operations per minute
     * @param windowMinutes Window duration in minutes
     * @return limit Operations allowed per window
     * @return windowDuration Window duration in seconds
     */
    function calculateWindowParams(
        uint128 operationsPerMinute,
        uint32 windowMinutes
    ) internal pure returns (uint128 limit, uint32 windowDuration) {
        limit = operationsPerMinute * windowMinutes;
        windowDuration = windowMinutes * 60;
    }
}
