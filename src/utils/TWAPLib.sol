// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TWAPLib
 * @notice Time-Weighted Average Price (TWAP) calculation library
 * @dev Provides robust TWAP calculations for DeFi protocols to:
 *      - Calculate manipulation-resistant average prices
 *      - Store and manage price observations
 *      - Support multiple time windows and granularities
 *
 *      TWAP is calculated as: ∫price(t)dt / Δt over a time window
 */
library TWAPLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Precision for price calculations
    uint256 internal constant PRECISION = 1e18;

    /// @dev Maximum observations to store (approx 2 weeks at 1 obs/min)
    uint256 internal constant MAX_OBSERVATIONS = 20160;

    /// @dev Minimum time between observations to prevent spam
    uint256 internal constant MIN_OBSERVATION_INTERVAL = 1 minutes;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Single price observation with timestamp
     */
    struct Observation {
        uint32 timestamp;
        uint224 priceCumulative; // Cumulative price * time (for TWAP calculation)
    }

    /**
     * @dev Oracle configuration and state
     */
    struct Oracle {
        Observation[] observations;
        uint256 observationIndex;    // Current write position (circular buffer)
        uint256 observationCount;    // Total observations stored
        uint32 lastTimestamp;        // Last observation timestamp
        uint224 lastPriceCumulative; // Last cumulative price
        uint256 lastPrice;           // Most recent spot price
    }

    /**
     * @dev Compact observation using packed storage
     */
    struct PackedObservation {
        uint32 timestamp;
        uint112 price0Cumulative;
        uint112 price1Cumulative;
    }

    /**
     * @dev Dual-asset oracle (for AMM pairs)
     */
    struct PairOracle {
        PackedObservation[] observations;
        uint256 observationIndex;
        uint256 observationCount;
        uint32 lastTimestamp;
    }

    /**
     * @dev TWAP query result
     */
    struct TWAPResult {
        uint256 twap;           // The calculated TWAP
        uint256 startPrice;     // Price at start of window
        uint256 endPrice;       // Price at end of window
        uint32 actualWindow;    // Actual time window used
        bool valid;             // Whether result is valid
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error ObservationTooFrequent();
    error InsufficientObservations();
    error InvalidTimeWindow();
    error StalePrice();
    error PriceOverflow();
    error ZeroPrice();

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes a new oracle
     * @param oracle The oracle storage to initialize
     * @param initialPrice The starting price
     */
    function initialize(Oracle storage oracle, uint256 initialPrice) internal {
        if (initialPrice == 0) revert ZeroPrice();

        oracle.observations.push(Observation({
            timestamp: uint32(block.timestamp),
            priceCumulative: 0
        }));

        oracle.observationIndex = 0;
        oracle.observationCount = 1;
        oracle.lastTimestamp = uint32(block.timestamp);
        oracle.lastPriceCumulative = 0;
        oracle.lastPrice = initialPrice;
    }

    /**
     * @notice Records a new price observation
     * @param oracle The oracle to update
     * @param price The current price
     * @return updated True if observation was recorded
     */
    function observe(Oracle storage oracle, uint256 price) internal returns (bool updated) {
        if (price == 0) revert ZeroPrice();

        uint32 currentTime = uint32(block.timestamp);
        uint32 timeElapsed = currentTime - oracle.lastTimestamp;

        // Enforce minimum interval
        if (timeElapsed < MIN_OBSERVATION_INTERVAL) {
            // Just update spot price without new observation
            oracle.lastPrice = price;
            return false;
        }

        // Calculate new cumulative price
        // cumulative += price * timeElapsed
        uint256 priceDelta = oracle.lastPrice * timeElapsed;
        uint224 newCumulative = oracle.lastPriceCumulative + uint224(priceDelta);

        // Write observation (circular buffer)
        uint256 newIndex = (oracle.observationIndex + 1) % MAX_OBSERVATIONS;

        if (oracle.observations.length < MAX_OBSERVATIONS) {
            oracle.observations.push(Observation({
                timestamp: currentTime,
                priceCumulative: newCumulative
            }));
        } else {
            oracle.observations[newIndex] = Observation({
                timestamp: currentTime,
                priceCumulative: newCumulative
            });
        }

        oracle.observationIndex = newIndex;
        if (oracle.observationCount < MAX_OBSERVATIONS) {
            oracle.observationCount++;
        }

        oracle.lastTimestamp = currentTime;
        oracle.lastPriceCumulative = newCumulative;
        oracle.lastPrice = price;

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TWAP CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates TWAP over a specified time window
     * @param oracle The oracle to query
     * @param windowSeconds The time window for TWAP calculation
     * @return result The TWAP calculation result
     */
    function getTWAP(
        Oracle storage oracle,
        uint32 windowSeconds
    ) internal view returns (TWAPResult memory result) {
        if (windowSeconds == 0) revert InvalidTimeWindow();
        if (oracle.observationCount < 2) revert InsufficientObservations();

        uint32 targetTime = uint32(block.timestamp) - windowSeconds;

        // Find observation at or before target time
        (uint256 startIndex, bool found) = findObservation(oracle, targetTime);

        if (!found) {
            // Not enough history, use oldest available
            startIndex = getOldestIndex(oracle);
        }

        Observation memory startObs = oracle.observations[startIndex];

        // Get current cumulative (interpolated to now)
        uint32 timeSinceLast = uint32(block.timestamp) - oracle.lastTimestamp;
        uint256 currentCumulative = uint256(oracle.lastPriceCumulative) +
                                    (oracle.lastPrice * timeSinceLast);

        // Calculate TWAP
        uint32 actualWindow = uint32(block.timestamp) - startObs.timestamp;
        if (actualWindow == 0) {
            result.twap = oracle.lastPrice;
            result.valid = true;
            return result;
        }

        uint256 cumulativeDelta = currentCumulative - uint256(startObs.priceCumulative);
        result.twap = cumulativeDelta / actualWindow;
        result.startPrice = getSpotAtIndex(oracle, startIndex);
        result.endPrice = oracle.lastPrice;
        result.actualWindow = actualWindow;
        result.valid = true;
    }

    /**
     * @notice Gets TWAP with multiple time windows
     * @param oracle The oracle to query
     * @param windows Array of time windows to calculate
     * @return twaps Array of TWAP values for each window
     */
    function getMultipleTWAPs(
        Oracle storage oracle,
        uint32[] memory windows
    ) internal view returns (uint256[] memory twaps) {
        twaps = new uint256[](windows.length);
        for (uint256 i = 0; i < windows.length; i++) {
            TWAPResult memory result = getTWAP(oracle, windows[i]);
            twaps[i] = result.valid ? result.twap : 0;
        }
    }

    /**
     * @notice Calculates exponentially-weighted moving average price
     * @dev More recent prices have higher weight
     * @param oracle The oracle to query
     * @param alpha Decay factor (PRECISION = no decay, 0 = instant)
     * @param periods Number of periods to consider
     * @return ewma The EWMA price
     */
    function getEWMA(
        Oracle storage oracle,
        uint256 alpha,
        uint256 periods
    ) internal view returns (uint256 ewma) {
        if (oracle.observationCount == 0) revert InsufficientObservations();
        if (periods > oracle.observationCount) {
            periods = oracle.observationCount;
        }

        ewma = oracle.lastPrice;
        uint256 weight = PRECISION;
        uint256 totalWeight = PRECISION;

        uint256 idx = oracle.observationIndex;
        for (uint256 i = 1; i < periods; i++) {
            // Move to previous observation
            if (idx == 0) {
                idx = oracle.observations.length - 1;
            } else {
                idx--;
            }

            // Decay the weight
            weight = (weight * alpha) / PRECISION;

            uint256 price = getSpotAtIndex(oracle, idx);
            ewma = ((ewma * totalWeight) + (price * weight)) / (totalWeight + weight);
            totalWeight += weight;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUERY HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Gets the current spot price
     */
    function getSpotPrice(Oracle storage oracle) internal view returns (uint256) {
        return oracle.lastPrice;
    }

    /**
     * @notice Gets observation count
     */
    function getObservationCount(Oracle storage oracle) internal view returns (uint256) {
        return oracle.observationCount;
    }

    /**
     * @notice Gets the oldest available timestamp
     */
    function getOldestTimestamp(Oracle storage oracle) internal view returns (uint32) {
        if (oracle.observationCount == 0) return 0;
        uint256 oldestIndex = getOldestIndex(oracle);
        return oracle.observations[oldestIndex].timestamp;
    }

    /**
     * @notice Checks if oracle has enough data for a time window
     */
    function hasEnoughHistory(
        Oracle storage oracle,
        uint32 windowSeconds
    ) internal view returns (bool) {
        if (oracle.observationCount < 2) return false;
        uint32 oldestTime = getOldestTimestamp(oracle);
        return (uint32(block.timestamp) - oldestTime) >= windowSeconds;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Binary search for observation at or before target time
     */
    function findObservation(
        Oracle storage oracle,
        uint32 targetTime
    ) internal view returns (uint256 index, bool found) {
        uint256 count = oracle.observationCount;
        if (count == 0) return (0, false);

        // Linear search (can be optimized to binary search for large arrays)
        uint256 oldestIndex = getOldestIndex(oracle);

        for (uint256 i = 0; i < count; i++) {
            uint256 idx = (oldestIndex + i) % count;
            if (idx >= oracle.observations.length) continue;

            if (oracle.observations[idx].timestamp <= targetTime) {
                // Check if next observation is after target
                uint256 nextIdx = (idx + 1) % count;
                if (nextIdx < oracle.observations.length &&
                    oracle.observations[nextIdx].timestamp > targetTime) {
                    return (idx, true);
                }
                index = idx;
                found = true;
            }
        }
    }

    /**
     * @dev Gets the oldest observation index
     */
    function getOldestIndex(Oracle storage oracle) internal view returns (uint256) {
        if (oracle.observationCount < MAX_OBSERVATIONS) {
            return 0;
        }
        return (oracle.observationIndex + 1) % MAX_OBSERVATIONS;
    }

    /**
     * @dev Estimates spot price at a given observation index
     */
    function getSpotAtIndex(
        Oracle storage oracle,
        uint256 index
    ) internal view returns (uint256) {
        if (index == oracle.observationIndex) {
            return oracle.lastPrice;
        }

        // Estimate from cumulative difference
        uint256 nextIndex = (index + 1) % oracle.observations.length;
        if (nextIndex >= oracle.observations.length) {
            return oracle.lastPrice;
        }

        Observation memory current = oracle.observations[index];
        Observation memory next = oracle.observations[nextIndex];

        uint32 timeDelta = next.timestamp - current.timestamp;
        if (timeDelta == 0) return oracle.lastPrice;

        uint256 cumulativeDelta = uint256(next.priceCumulative) - uint256(current.priceCumulative);
        return cumulativeDelta / timeDelta;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE DEVIATION & VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if spot price deviates significantly from TWAP
     * @param oracle The oracle to check
     * @param windowSeconds TWAP window for comparison
     * @param maxDeviationBps Maximum allowed deviation in basis points
     * @return isValid True if price is within acceptable deviation
     * @return deviation The actual deviation in basis points
     */
    function validatePrice(
        Oracle storage oracle,
        uint32 windowSeconds,
        uint256 maxDeviationBps
    ) internal view returns (bool isValid, uint256 deviation) {
        TWAPResult memory twapResult = getTWAP(oracle, windowSeconds);
        if (!twapResult.valid) return (false, type(uint256).max);

        uint256 spot = oracle.lastPrice;
        uint256 twap = twapResult.twap;

        if (twap == 0) return (false, type(uint256).max);

        // Calculate deviation: |spot - twap| / twap * 10000
        if (spot > twap) {
            deviation = ((spot - twap) * 10000) / twap;
        } else {
            deviation = ((twap - spot) * 10000) / twap;
        }

        isValid = deviation <= maxDeviationBps;
    }

    /**
     * @notice Calculates price volatility over a time window
     * @param oracle The oracle to query
     * @param windowSeconds Time window for volatility calculation
     * @return volatility Standard deviation approximation in basis points
     */
    function getVolatility(
        Oracle storage oracle,
        uint32 windowSeconds
    ) internal view returns (uint256 volatility) {
        TWAPResult memory result = getTWAP(oracle, windowSeconds);
        if (!result.valid) return 0;

        // Simple volatility: max deviation from TWAP
        uint256 maxDev = 0;

        if (result.startPrice > result.twap) {
            uint256 dev = ((result.startPrice - result.twap) * 10000) / result.twap;
            if (dev > maxDev) maxDev = dev;
        } else {
            uint256 dev = ((result.twap - result.startPrice) * 10000) / result.twap;
            if (dev > maxDev) maxDev = dev;
        }

        if (result.endPrice > result.twap) {
            uint256 dev = ((result.endPrice - result.twap) * 10000) / result.twap;
            if (dev > maxDev) maxDev = dev;
        } else {
            uint256 dev = ((result.twap - result.endPrice) * 10000) / result.twap;
            if (dev > maxDev) maxDev = dev;
        }

        volatility = maxDev;
    }
}
