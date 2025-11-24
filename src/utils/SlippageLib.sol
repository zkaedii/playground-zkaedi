// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SlippageLib
 * @notice Comprehensive slippage calculation and protection library for DeFi
 * @dev Implements slippage checks, price impact calculations, and MEV protection
 */
library SlippageLib {
    // ============ ERRORS ============
    error SlippageExceeded(uint256 expected, uint256 actual, uint256 maxSlippage);
    error InvalidSlippageTolerance(uint256 slippage);
    error PriceImpactTooHigh(uint256 impact, uint256 maxImpact);
    error MinAmountNotMet(uint256 minAmount, uint256 actualAmount);
    error MaxAmountExceeded(uint256 maxAmount, uint256 actualAmount);
    error StalePrice(uint256 priceTimestamp, uint256 maxAge);
    error InvalidPrice(uint256 price);
    error SandwichDetected(uint256 prePrice, uint256 postPrice, uint256 threshold);

    // ============ CONSTANTS ============
    uint256 internal constant BPS = 10000;          // 100% in basis points
    uint256 internal constant WAD = 1e18;           // 18 decimal precision
    uint256 internal constant MAX_SLIPPAGE_BPS = 5000;  // 50% maximum slippage
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 50; // 0.5% default

    // Common slippage presets (in basis points)
    uint256 internal constant SLIPPAGE_TIGHT = 10;      // 0.1%
    uint256 internal constant SLIPPAGE_NORMAL = 50;     // 0.5%
    uint256 internal constant SLIPPAGE_RELAXED = 100;   // 1%
    uint256 internal constant SLIPPAGE_HIGH = 300;      // 3%
    uint256 internal constant SLIPPAGE_VOLATILE = 500;  // 5%

    // Price impact thresholds
    uint256 internal constant IMPACT_LOW = 100;         // 1%
    uint256 internal constant IMPACT_MEDIUM = 300;      // 3%
    uint256 internal constant IMPACT_HIGH = 500;        // 5%
    uint256 internal constant IMPACT_SEVERE = 1000;     // 10%

    // ============ TYPES ============
    struct SlippageConfig {
        uint256 maxSlippageBps;
        uint256 maxPriceImpactBps;
        uint256 priceMaxAge;
        bool enableMEVProtection;
    }

    struct SwapParams {
        uint256 amountIn;
        uint256 expectedAmountOut;
        uint256 minAmountOut;
        uint256 maxSlippageBps;
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint8 decimals;
    }

    struct SlippageResult {
        uint256 actualSlippageBps;
        uint256 priceImpactBps;
        bool withinTolerance;
        uint256 lostValue;
    }

    // ============ EVENTS ============
    event SlippageWarning(uint256 expectedAmount, uint256 actualAmount, uint256 slippageBps);
    event HighPriceImpact(uint256 impactBps, uint256 threshold);
    event MEVProtectionTriggered(uint256 prePrice, uint256 postPrice);

    // ============ BASIC SLIPPAGE FUNCTIONS ============

    /**
     * @notice Calculate minimum amount out with slippage tolerance
     * @param expectedAmount The expected output amount
     * @param slippageBps Slippage tolerance in basis points
     * @return minAmount The minimum acceptable amount
     */
    function calculateMinOut(
        uint256 expectedAmount,
        uint256 slippageBps
    ) internal pure returns (uint256 minAmount) {
        if (slippageBps > MAX_SLIPPAGE_BPS) revert InvalidSlippageTolerance(slippageBps);
        minAmount = (expectedAmount * (BPS - slippageBps)) / BPS;
    }

    /**
     * @notice Calculate maximum amount in with slippage tolerance
     * @param expectedAmount The expected input amount
     * @param slippageBps Slippage tolerance in basis points
     * @return maxAmount The maximum acceptable amount
     */
    function calculateMaxIn(
        uint256 expectedAmount,
        uint256 slippageBps
    ) internal pure returns (uint256 maxAmount) {
        if (slippageBps > MAX_SLIPPAGE_BPS) revert InvalidSlippageTolerance(slippageBps);
        maxAmount = (expectedAmount * (BPS + slippageBps)) / BPS;
    }

    /**
     * @notice Calculate actual slippage in basis points
     * @param expected The expected amount
     * @param actual The actual amount
     * @return slippageBps The actual slippage in basis points
     */
    function calculateSlippage(
        uint256 expected,
        uint256 actual
    ) internal pure returns (uint256 slippageBps) {
        if (expected == 0) return 0;
        if (actual >= expected) return 0; // Positive slippage (favorable)

        slippageBps = ((expected - actual) * BPS) / expected;
    }

    /**
     * @notice Check if slippage is within tolerance
     * @param expected The expected amount
     * @param actual The actual amount
     * @param maxSlippageBps Maximum allowed slippage in basis points
     * @return withinTolerance True if slippage is acceptable
     */
    function isWithinSlippage(
        uint256 expected,
        uint256 actual,
        uint256 maxSlippageBps
    ) internal pure returns (bool withinTolerance) {
        if (actual >= expected) return true;
        uint256 slippage = calculateSlippage(expected, actual);
        return slippage <= maxSlippageBps;
    }

    /**
     * @notice Require slippage within tolerance (revert if exceeded)
     * @param expected The expected amount
     * @param actual The actual amount
     * @param maxSlippageBps Maximum allowed slippage in basis points
     */
    function requireSlippageWithin(
        uint256 expected,
        uint256 actual,
        uint256 maxSlippageBps
    ) internal pure {
        if (actual < expected) {
            uint256 slippage = calculateSlippage(expected, actual);
            if (slippage > maxSlippageBps) {
                revert SlippageExceeded(expected, actual, maxSlippageBps);
            }
        }
    }

    /**
     * @notice Require minimum amount received
     * @param minAmount The minimum acceptable amount
     * @param actualAmount The actual amount received
     */
    function requireMinAmount(
        uint256 minAmount,
        uint256 actualAmount
    ) internal pure {
        if (actualAmount < minAmount) {
            revert MinAmountNotMet(minAmount, actualAmount);
        }
    }

    // ============ PRICE IMPACT FUNCTIONS ============

    /**
     * @notice Calculate price impact of a trade
     * @param reserveIn Input token reserve
     * @param reserveOut Output token reserve
     * @param amountIn Amount being traded in
     * @return impactBps Price impact in basis points
     */
    function calculatePriceImpact(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 amountIn
    ) internal pure returns (uint256 impactBps) {
        if (reserveIn == 0 || reserveOut == 0) return BPS;

        // Constant product: (reserveIn + amountIn) * newReserveOut = reserveIn * reserveOut
        // Price impact = 1 - (newReserveOut / reserveOut) * (reserveIn / (reserveIn + amountIn))
        // Simplified: impactBps ≈ amountIn * BPS / (reserveIn + amountIn)
        impactBps = (amountIn * BPS) / (reserveIn + amountIn);
    }

    /**
     * @notice Calculate price impact from quotes
     * @param spotPrice The current spot price (WAD precision)
     * @param executionPrice The actual execution price (WAD precision)
     * @return impactBps Price impact in basis points
     */
    function calculatePriceImpactFromQuotes(
        uint256 spotPrice,
        uint256 executionPrice
    ) internal pure returns (uint256 impactBps) {
        if (spotPrice == 0) revert InvalidPrice(spotPrice);
        if (executionPrice >= spotPrice) return 0;

        impactBps = ((spotPrice - executionPrice) * BPS) / spotPrice;
    }

    /**
     * @notice Check if price impact is acceptable
     * @param impactBps The calculated price impact
     * @param maxImpactBps Maximum acceptable impact
     */
    function requireAcceptablePriceImpact(
        uint256 impactBps,
        uint256 maxImpactBps
    ) internal pure {
        if (impactBps > maxImpactBps) {
            revert PriceImpactTooHigh(impactBps, maxImpactBps);
        }
    }

    /**
     * @notice Get price impact severity level
     * @param impactBps The price impact in basis points
     * @return level 0=negligible, 1=low, 2=medium, 3=high, 4=severe
     */
    function getPriceImpactLevel(uint256 impactBps) internal pure returns (uint8 level) {
        if (impactBps <= IMPACT_LOW) return 1;
        if (impactBps <= IMPACT_MEDIUM) return 2;
        if (impactBps <= IMPACT_HIGH) return 3;
        return 4;
    }

    // ============ SWAP VALIDATION ============

    /**
     * @notice Validate swap parameters
     * @param params The swap parameters
     * @return minOut The calculated minimum output
     */
    function validateSwap(
        SwapParams memory params
    ) internal pure returns (uint256 minOut) {
        if (params.maxSlippageBps > MAX_SLIPPAGE_BPS) {
            revert InvalidSlippageTolerance(params.maxSlippageBps);
        }

        minOut = calculateMinOut(params.expectedAmountOut, params.maxSlippageBps);

        // Use the higher of calculated min or user-specified min
        if (params.minAmountOut > minOut) {
            minOut = params.minAmountOut;
        }
    }

    /**
     * @notice Analyze swap result
     * @param expected Expected amount out
     * @param actual Actual amount out
     * @param maxSlippageBps Maximum allowed slippage
     * @return result The slippage analysis result
     */
    function analyzeSwapResult(
        uint256 expected,
        uint256 actual,
        uint256 maxSlippageBps
    ) internal pure returns (SlippageResult memory result) {
        result.actualSlippageBps = calculateSlippage(expected, actual);
        result.withinTolerance = result.actualSlippageBps <= maxSlippageBps;

        if (actual < expected) {
            result.lostValue = expected - actual;
        }
    }

    // ============ MEV PROTECTION ============

    /**
     * @notice Check for potential sandwich attack
     * @param prePriceWad Price before transaction (WAD)
     * @param postPriceWad Price after transaction (WAD)
     * @param thresholdBps Maximum acceptable price change
     * @return isSandwich True if sandwich attack detected
     */
    function detectSandwich(
        uint256 prePriceWad,
        uint256 postPriceWad,
        uint256 thresholdBps
    ) internal pure returns (bool isSandwich) {
        if (prePriceWad == 0) return false;

        uint256 priceDiff;
        if (postPriceWad > prePriceWad) {
            priceDiff = postPriceWad - prePriceWad;
        } else {
            priceDiff = prePriceWad - postPriceWad;
        }

        uint256 changePercent = (priceDiff * BPS) / prePriceWad;
        return changePercent > thresholdBps;
    }

    /**
     * @notice Require no sandwich attack detected
     * @param prePriceWad Price before transaction
     * @param postPriceWad Price after transaction
     * @param thresholdBps Maximum acceptable price change
     */
    function requireNoSandwich(
        uint256 prePriceWad,
        uint256 postPriceWad,
        uint256 thresholdBps
    ) internal pure {
        if (detectSandwich(prePriceWad, postPriceWad, thresholdBps)) {
            revert SandwichDetected(prePriceWad, postPriceWad, thresholdBps);
        }
    }

    /**
     * @notice Check price staleness
     * @param priceData The price data
     * @param maxAge Maximum acceptable age in seconds
     */
    function requireFreshPrice(
        PriceData memory priceData,
        uint256 maxAge
    ) internal view {
        if (block.timestamp > priceData.timestamp + maxAge) {
            revert StalePrice(priceData.timestamp, maxAge);
        }
    }

    // ============ DYNAMIC SLIPPAGE ============

    /**
     * @notice Calculate dynamic slippage based on trade size
     * @param tradeSize The trade size
     * @param liquidity The available liquidity
     * @param baseSlippageBps Base slippage tolerance
     * @return dynamicSlippageBps Adjusted slippage tolerance
     */
    function calculateDynamicSlippage(
        uint256 tradeSize,
        uint256 liquidity,
        uint256 baseSlippageBps
    ) internal pure returns (uint256 dynamicSlippageBps) {
        if (liquidity == 0) return MAX_SLIPPAGE_BPS;

        // Larger trades relative to liquidity need higher slippage tolerance
        uint256 sizeRatio = (tradeSize * BPS) / liquidity;

        // Scale slippage: base + (sizeRatio * base / 100)
        dynamicSlippageBps = baseSlippageBps + (sizeRatio * baseSlippageBps) / 100;

        // Cap at maximum
        if (dynamicSlippageBps > MAX_SLIPPAGE_BPS) {
            dynamicSlippageBps = MAX_SLIPPAGE_BPS;
        }
    }

    /**
     * @notice Get recommended slippage for token volatility
     * @param volatilityBps Token's recent volatility in basis points
     * @return recommendedBps Recommended slippage tolerance
     */
    function getRecommendedSlippage(
        uint256 volatilityBps
    ) internal pure returns (uint256 recommendedBps) {
        // Higher volatility = higher slippage tolerance needed
        if (volatilityBps <= 100) return SLIPPAGE_TIGHT;
        if (volatilityBps <= 300) return SLIPPAGE_NORMAL;
        if (volatilityBps <= 500) return SLIPPAGE_RELAXED;
        if (volatilityBps <= 1000) return SLIPPAGE_HIGH;
        return SLIPPAGE_VOLATILE;
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Convert slippage percentage to basis points
     * @param percentage Slippage as percentage (e.g., 5 for 0.5%)
     * @param decimals Decimal places in percentage
     * @return bps Slippage in basis points
     */
    function percentToBps(
        uint256 percentage,
        uint8 decimals
    ) internal pure returns (uint256 bps) {
        // percentage with `decimals` decimals to basis points
        // e.g., 50 with 1 decimal = 5.0% = 500 bps
        bps = (percentage * 100) / (10 ** decimals);
    }

    /**
     * @notice Convert basis points to WAD for precise calculations
     * @param bps Basis points
     * @return wadValue The WAD representation
     */
    function bpsToWad(uint256 bps) internal pure returns (uint256 wadValue) {
        return (bps * WAD) / BPS;
    }

    /**
     * @notice Get default slippage config
     * @return config The default configuration
     */
    function getDefaultConfig() internal pure returns (SlippageConfig memory config) {
        return SlippageConfig({
            maxSlippageBps: DEFAULT_SLIPPAGE_BPS,
            maxPriceImpactBps: IMPACT_MEDIUM,
            priceMaxAge: 5 minutes,
            enableMEVProtection: true
        });
    }

    /**
     * @notice Apply slippage to get range
     * @param amount The base amount
     * @param slippageBps Slippage in basis points
     * @return minAmount Minimum amount
     * @return maxAmount Maximum amount
     */
    function getSlippageRange(
        uint256 amount,
        uint256 slippageBps
    ) internal pure returns (uint256 minAmount, uint256 maxAmount) {
        minAmount = calculateMinOut(amount, slippageBps);
        maxAmount = calculateMaxIn(amount, slippageBps);
    }
}
