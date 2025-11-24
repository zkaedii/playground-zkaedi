// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PriceUtils
 * @notice Price calculation utilities for DeFi applications
 * @dev Handles price normalization, impact calculation, and exchange rate operations
 */
library PriceUtils {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Standard price precision (8 decimals like Chainlink)
    uint256 internal constant PRICE_PRECISION = 1e8;

    /// @dev High precision for calculations (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev Maximum basis points (100%)
    uint256 internal constant MAX_BPS = 10_000;

    /// @dev Maximum reasonable decimal places
    uint8 internal constant MAX_DECIMALS = 36;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidDecimals(uint8 decimals);
    error PriceIsZero();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error PriceDeviationTooHigh(uint256 deviation, uint256 maxDeviation);
    error StalePriceData(uint256 timestamp, uint256 maxAge);
    error InvalidPrice(int256 price);
    error Overflow();

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE NORMALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Normalize price to target decimals
     * @param price Price to normalize
     * @param fromDecimals Current decimal places
     * @param toDecimals Target decimal places
     * @return Normalized price
     */
    function normalizePrice(
        uint256 price,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals > MAX_DECIMALS || toDecimals > MAX_DECIMALS) {
            revert InvalidDecimals(fromDecimals > MAX_DECIMALS ? fromDecimals : toDecimals);
        }

        if (fromDecimals == toDecimals) return price;

        if (fromDecimals > toDecimals) {
            uint256 factor = 10 ** (fromDecimals - toDecimals);
            return price / factor;
        } else {
            uint256 factor = 10 ** (toDecimals - fromDecimals);
            return price * factor;
        }
    }

    /**
     * @notice Normalize price to standard 18 decimals (WAD)
     * @param price Price to normalize
     * @param decimals Current decimal places
     * @return Price in WAD (18 decimals)
     */
    function toWad(uint256 price, uint8 decimals) internal pure returns (uint256) {
        return normalizePrice(price, decimals, 18);
    }

    /**
     * @notice Normalize price from WAD to target decimals
     * @param price Price in WAD
     * @param targetDecimals Target decimal places
     * @return Normalized price
     */
    function fromWad(uint256 price, uint8 targetDecimals) internal pure returns (uint256) {
        return normalizePrice(price, 18, targetDecimals);
    }

    /**
     * @notice Convert signed price to unsigned with validation
     * @param price Signed price (from Chainlink)
     * @return Unsigned price
     */
    function safeUnsignedPrice(int256 price) internal pure returns (uint256) {
        if (price <= 0) revert InvalidPrice(price);
        return uint256(price);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXCHANGE RATE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate exchange rate between two tokens using their USD prices
     * @param priceA Price of token A in USD
     * @param priceB Price of token B in USD
     * @param decimalsA Decimals of price A
     * @param decimalsB Decimals of price B
     * @return Rate of A per B (how much A you get for 1 B) in WAD
     */
    function exchangeRate(
        uint256 priceA,
        uint256 priceB,
        uint8 decimalsA,
        uint8 decimalsB
    ) internal pure returns (uint256) {
        if (priceA == 0) revert PriceIsZero();
        if (priceB == 0) revert PriceIsZero();

        // Normalize both to WAD
        uint256 normalizedA = toWad(priceA, decimalsA);
        uint256 normalizedB = toWad(priceB, decimalsB);

        // Rate = priceB / priceA (in WAD)
        return (normalizedB * WAD) / normalizedA;
    }

    /**
     * @notice Calculate output amount for a swap given prices
     * @param amountIn Input amount
     * @param tokenInDecimals Input token decimals
     * @param tokenOutDecimals Output token decimals
     * @param priceIn Input token price
     * @param priceOut Output token price
     * @param priceDecimals Price decimals
     * @return Output amount in output token decimals
     */
    function calculateSwapOutput(
        uint256 amountIn,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals,
        uint256 priceIn,
        uint256 priceOut,
        uint8 priceDecimals
    ) internal pure returns (uint256) {
        if (priceOut == 0) revert PriceIsZero();

        // Convert amount to WAD
        uint256 amountInWad = normalizePrice(amountIn, tokenInDecimals, 18);

        // Normalize prices to WAD
        uint256 priceInWad = toWad(priceIn, priceDecimals);
        uint256 priceOutWad = toWad(priceOut, priceDecimals);

        // Calculate value in USD (WAD)
        uint256 valueInUsd = (amountInWad * priceInWad) / WAD;

        // Calculate output amount in WAD
        uint256 amountOutWad = (valueInUsd * WAD) / priceOutWad;

        // Convert to output decimals
        return normalizePrice(amountOutWad, 18, tokenOutDecimals);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE IMPACT & SLIPPAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate price impact of a swap
     * @param expectedOutput Expected output without slippage
     * @param actualOutput Actual output received
     * @return impactBps Impact in basis points
     * @return isPositive True if actual > expected (positive impact)
     */
    function priceImpact(
        uint256 expectedOutput,
        uint256 actualOutput
    ) internal pure returns (uint256 impactBps, bool isPositive) {
        if (expectedOutput == 0) return (0, true);

        if (actualOutput >= expectedOutput) {
            impactBps = ((actualOutput - expectedOutput) * MAX_BPS) / expectedOutput;
            isPositive = true;
        } else {
            impactBps = ((expectedOutput - actualOutput) * MAX_BPS) / expectedOutput;
            isPositive = false;
        }
    }

    /**
     * @notice Validate slippage is within acceptable bounds
     * @param expected Expected amount
     * @param actual Actual amount
     * @param maxSlippageBps Maximum acceptable slippage in basis points
     */
    function validateSlippage(
        uint256 expected,
        uint256 actual,
        uint256 maxSlippageBps
    ) internal pure {
        if (expected == 0) return;

        uint256 minAcceptable = (expected * (MAX_BPS - maxSlippageBps)) / MAX_BPS;
        if (actual < minAcceptable) {
            revert SlippageExceeded(actual, minAcceptable);
        }
    }

    /**
     * @notice Calculate minimum output with slippage tolerance
     * @param expectedOutput Expected output
     * @param slippageBps Slippage tolerance in basis points
     * @return Minimum acceptable output
     */
    function minOutputWithSlippage(
        uint256 expectedOutput,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        return (expectedOutput * (MAX_BPS - slippageBps)) / MAX_BPS;
    }

    /**
     * @notice Calculate maximum input with slippage tolerance
     * @param expectedInput Expected input
     * @param slippageBps Slippage tolerance in basis points
     * @return Maximum acceptable input
     */
    function maxInputWithSlippage(
        uint256 expectedInput,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        return (expectedInput * (MAX_BPS + slippageBps)) / MAX_BPS;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE DEVIATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate deviation between two prices
     * @param price1 First price
     * @param price2 Second price
     * @return Deviation in basis points
     */
    function priceDeviation(uint256 price1, uint256 price2) internal pure returns (uint256) {
        if (price1 == 0 && price2 == 0) return 0;
        if (price1 == 0 || price2 == 0) return MAX_BPS;

        uint256 larger = price1 > price2 ? price1 : price2;
        uint256 smaller = price1 > price2 ? price2 : price1;

        return ((larger - smaller) * MAX_BPS) / larger;
    }

    /**
     * @notice Validate price deviation is within bounds
     * @param price1 First price
     * @param price2 Second price
     * @param maxDeviationBps Maximum allowed deviation in basis points
     */
    function validateDeviation(
        uint256 price1,
        uint256 price2,
        uint256 maxDeviationBps
    ) internal pure {
        uint256 deviation = priceDeviation(price1, price2);
        if (deviation > maxDeviationBps) {
            revert PriceDeviationTooHigh(deviation, maxDeviationBps);
        }
    }

    /**
     * @notice Check if price is within tolerance of a reference
     * @param price Price to check
     * @param reference Reference price
     * @param toleranceBps Tolerance in basis points
     * @return True if within tolerance
     */
    function isWithinTolerance(
        uint256 price,
        uint256 reference,
        uint256 toleranceBps
    ) internal pure returns (bool) {
        return priceDeviation(price, reference) <= toleranceBps;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE STALENESS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if price data is stale
     * @param updatedAt Last update timestamp
     * @param maxAge Maximum acceptable age in seconds
     * @return True if stale
     */
    function isStale(uint256 updatedAt, uint256 maxAge) internal view returns (bool) {
        return block.timestamp > updatedAt + maxAge;
    }

    /**
     * @notice Validate price data is not stale
     * @param updatedAt Last update timestamp
     * @param maxAge Maximum acceptable age in seconds
     */
    function validateNotStale(uint256 updatedAt, uint256 maxAge) internal view {
        if (isStale(updatedAt, maxAge)) {
            revert StalePriceData(updatedAt, maxAge);
        }
    }

    /**
     * @notice Get price age in seconds
     * @param updatedAt Last update timestamp
     * @return Age in seconds
     */
    function priceAge(uint256 updatedAt) internal view returns (uint256) {
        if (block.timestamp < updatedAt) return 0;
        return block.timestamp - updatedAt;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TWAP CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate time-weighted average from observations
     * @param prices Array of prices
     * @param timestamps Array of timestamps
     * @param startTime Start of TWAP window
     * @param endTime End of TWAP window
     * @return twap Time-weighted average price
     */
    function calculateTwap(
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256 startTime,
        uint256 endTime
    ) internal pure returns (uint256 twap) {
        uint256 length = prices.length;
        if (length == 0 || length != timestamps.length) return 0;
        if (startTime >= endTime) return 0;

        uint256 cumulativePrice;
        uint256 totalTime;

        for (uint256 i; i < length;) {
            // Find time contribution of this price point
            uint256 priceStart = timestamps[i];
            uint256 priceEnd = i + 1 < length ? timestamps[i + 1] : endTime;

            // Clamp to window
            if (priceStart < startTime) priceStart = startTime;
            if (priceEnd > endTime) priceEnd = endTime;

            if (priceEnd > priceStart && priceStart < endTime && priceEnd > startTime) {
                uint256 duration = priceEnd - priceStart;
                cumulativePrice += prices[i] * duration;
                totalTime += duration;
            }

            unchecked { ++i; }
        }

        if (totalTime == 0) return prices[length - 1];
        return cumulativePrice / totalTime;
    }

    /**
     * @notice Calculate simple moving average
     * @param prices Array of prices
     * @return Average price
     */
    function sma(uint256[] memory prices) internal pure returns (uint256) {
        uint256 length = prices.length;
        if (length == 0) return 0;

        uint256 total;
        for (uint256 i; i < length;) {
            total += prices[i];
            unchecked { ++i; }
        }
        return total / length;
    }

    /**
     * @notice Calculate exponential moving average
     * @param currentEma Current EMA value
     * @param newPrice New price to incorporate
     * @param smoothing Smoothing factor (in basis points, e.g., 2000 = 20%)
     * @return New EMA value
     */
    function ema(
        uint256 currentEma,
        uint256 newPrice,
        uint256 smoothing
    ) internal pure returns (uint256) {
        if (currentEma == 0) return newPrice;
        // EMA = (price * k) + (previousEMA * (1 - k))
        // where k = smoothing / MAX_BPS
        return ((newPrice * smoothing) + (currentEma * (MAX_BPS - smoothing))) / MAX_BPS;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALUE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate USD value of token amount
     * @param amount Token amount
     * @param tokenDecimals Token decimals
     * @param price Token price in USD
     * @param priceDecimals Price decimals
     * @return Value in USD with 18 decimals
     */
    function calculateUsdValue(
        uint256 amount,
        uint8 tokenDecimals,
        uint256 price,
        uint8 priceDecimals
    ) internal pure returns (uint256) {
        if (price == 0) return 0;

        uint256 amountWad = toWad(amount, tokenDecimals);
        uint256 priceWad = toWad(price, priceDecimals);

        return (amountWad * priceWad) / WAD;
    }

    /**
     * @notice Calculate token amount from USD value
     * @param usdValue USD value with 18 decimals
     * @param tokenDecimals Token decimals
     * @param price Token price in USD
     * @param priceDecimals Price decimals
     * @return Token amount
     */
    function calculateTokenAmount(
        uint256 usdValue,
        uint8 tokenDecimals,
        uint256 price,
        uint8 priceDecimals
    ) internal pure returns (uint256) {
        if (price == 0) revert PriceIsZero();

        uint256 priceWad = toWad(price, priceDecimals);
        uint256 amountWad = (usdValue * WAD) / priceWad;

        return fromWad(amountWad, tokenDecimals);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE AGGREGATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get median price from array of prices
     * @dev Sorts array internally, modifies input
     * @param prices Array of prices
     * @return Median price
     */
    function median(uint256[] memory prices) internal pure returns (uint256) {
        uint256 length = prices.length;
        if (length == 0) return 0;
        if (length == 1) return prices[0];

        // Simple insertion sort for small arrays
        for (uint256 i = 1; i < length;) {
            uint256 key = prices[i];
            uint256 j = i;
            while (j > 0 && prices[j - 1] > key) {
                prices[j] = prices[j - 1];
                unchecked { --j; }
            }
            prices[j] = key;
            unchecked { ++i; }
        }

        if (length % 2 == 1) {
            return prices[length / 2];
        } else {
            return (prices[length / 2 - 1] + prices[length / 2]) / 2;
        }
    }

    /**
     * @notice Calculate weighted average of prices
     * @param prices Array of prices
     * @param weights Array of weights
     * @return Weighted average price
     */
    function weightedAverage(
        uint256[] memory prices,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        uint256 length = prices.length;
        if (length == 0 || length != weights.length) return 0;

        uint256 weightedSum;
        uint256 totalWeight;

        for (uint256 i; i < length;) {
            weightedSum += prices[i] * weights[i];
            totalWeight += weights[i];
            unchecked { ++i; }
        }

        if (totalWeight == 0) return 0;
        return weightedSum / totalWeight;
    }
}
