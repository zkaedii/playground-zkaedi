// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MathUtils
 * @notice Advanced mathematical utilities for DeFi operations
 * @dev Provides wad/ray arithmetic, rounding modes, saturating operations, and percentage calculations
 */
library MathUtils {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev 18-decimal fixed point (1e18) - standard for most DeFi protocols
    uint256 internal constant WAD = 1e18;

    /// @dev 27-decimal fixed point (1e27) - used by Aave and other lending protocols
    uint256 internal constant RAY = 1e27;

    /// @dev Half WAD for rounding
    uint256 internal constant HALF_WAD = 0.5e18;

    /// @dev Half RAY for rounding
    uint256 internal constant HALF_RAY = 0.5e27;

    /// @dev Conversion factor from WAD to RAY
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /// @dev Maximum basis points (100%)
    uint256 internal constant MAX_BPS = 10_000;

    /// @dev Percentage scalar (100%)
    uint256 internal constant PERCENTAGE_FACTOR = 1e4;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error MathOverflow();
    error DivisionByZero();
    error InvalidPercentage();

    // ═══════════════════════════════════════════════════════════════════════════
    // WAD ARITHMETIC (18 decimals)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Multiply two wad values and divide by WAD
     * @param a First wad value
     * @param b Second wad value
     * @return Result rounded down
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / WAD;
    }

    /**
     * @notice Multiply two wad values with rounding up
     * @param a First wad value
     * @param b Second wad value
     * @return Result rounded up
     */
    function wadMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b + WAD - 1) / WAD;
    }

    /**
     * @notice Divide two wad values
     * @param a Numerator
     * @param b Denominator
     * @return Result in wad precision
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a * WAD) / b;
    }

    /**
     * @notice Divide two wad values with rounding up
     * @param a Numerator
     * @param b Denominator
     * @return Result rounded up
     */
    function wadDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a * WAD + b - 1) / b;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RAY ARITHMETIC (27 decimals)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Multiply two ray values and divide by RAY
     * @param a First ray value
     * @param b Second ray value
     * @return Result rounded down
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / RAY;
    }

    /**
     * @notice Multiply two ray values with rounding up
     * @param a First ray value
     * @param b Second ray value
     * @return Result rounded up
     */
    function rayMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b + RAY - 1) / RAY;
    }

    /**
     * @notice Divide two ray values
     * @param a Numerator
     * @param b Denominator
     * @return Result in ray precision
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a * RAY) / b;
    }

    /**
     * @notice Divide two ray values with rounding up
     * @param a Numerator
     * @param b Denominator
     * @return Result rounded up
     */
    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a * RAY + b - 1) / b;
    }

    /**
     * @notice Convert wad to ray
     * @param a Wad value
     * @return Ray value
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }

    /**
     * @notice Convert ray to wad (truncates)
     * @param a Ray value
     * @return Wad value
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        return a / WAD_RAY_RATIO;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SATURATING ARITHMETIC
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add two numbers, capping at max uint256
     * @param a First number
     * @param b Second number
     * @return Sum capped at type(uint256).max
     */
    function saturatingAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            uint256 c = a + b;
            return c >= a ? c : type(uint256).max;
        }
    }

    /**
     * @notice Subtract two numbers, flooring at zero
     * @param a First number
     * @param b Second number
     * @return Difference floored at 0
     */
    function saturatingSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : 0;
        }
    }

    /**
     * @notice Multiply two numbers, capping at max uint256
     * @param a First number
     * @param b Second number
     * @return Product capped at type(uint256).max
     */
    function saturatingMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        unchecked {
            uint256 c = a * b;
            return c / a == b ? c : type(uint256).max;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROUNDING UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Round up division
     * @param a Numerator
     * @param b Denominator
     * @return Quotient rounded up
     */
    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a + b - 1) / b;
    }

    /**
     * @notice Round to nearest (half up)
     * @param a Numerator
     * @param b Denominator
     * @return Quotient rounded to nearest
     */
    function divRound(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a + b / 2) / b;
    }

    /**
     * @notice Calculate multiplication then division with full precision intermediate
     * @param a First multiplicand
     * @param b Second multiplicand
     * @param c Divisor
     * @return Result of (a * b) / c
     */
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (c == 0) revert DivisionByZero();
        return (a * b) / c;
    }

    /**
     * @notice Calculate multiplication then division, rounding up
     * @param a First multiplicand
     * @param b Second multiplicand
     * @param c Divisor
     * @return Result of (a * b) / c rounded up
     */
    function mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (c == 0) revert DivisionByZero();
        uint256 result = a * b;
        return (result + c - 1) / c;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PERCENTAGE & BASIS POINTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate percentage of a value
     * @param value Base value
     * @param bps Basis points (1 bps = 0.01%)
     * @return Result of (value * bps) / 10000
     */
    function bpsMul(uint256 value, uint256 bps) internal pure returns (uint256) {
        return (value * bps) / MAX_BPS;
    }

    /**
     * @notice Calculate percentage with rounding up
     * @param value Base value
     * @param bps Basis points
     * @return Result rounded up
     */
    function bpsMulUp(uint256 value, uint256 bps) internal pure returns (uint256) {
        return (value * bps + MAX_BPS - 1) / MAX_BPS;
    }

    /**
     * @notice Deduct basis points from a value
     * @param value Base value
     * @param bps Basis points to deduct
     * @return Value after deduction
     */
    function bpsDeduct(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps > MAX_BPS) revert InvalidPercentage();
        return (value * (MAX_BPS - bps)) / MAX_BPS;
    }

    /**
     * @notice Calculate what percentage one value is of another
     * @param part The part value
     * @param whole The whole value
     * @return Percentage in basis points
     */
    function percentageOf(uint256 part, uint256 whole) internal pure returns (uint256) {
        if (whole == 0) return 0;
        return (part * MAX_BPS) / whole;
    }

    /**
     * @notice Calculate percentage change between two values
     * @param oldValue Original value
     * @param newValue New value
     * @return change Change in basis points (can be negative via bool)
     * @return isNegative Whether the change is negative
     */
    function percentageChange(
        uint256 oldValue,
        uint256 newValue
    ) internal pure returns (uint256 change, bool isNegative) {
        if (oldValue == 0) {
            return (newValue > 0 ? MAX_BPS : 0, false);
        }
        if (newValue >= oldValue) {
            change = ((newValue - oldValue) * MAX_BPS) / oldValue;
            isNegative = false;
        } else {
            change = ((oldValue - newValue) * MAX_BPS) / oldValue;
            isNegative = true;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MIN / MAX / CLAMP
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Return minimum of two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Return maximum of two values
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Clamp value between min and max
     * @param value Value to clamp
     * @param minValue Minimum bound
     * @param maxValue Maximum bound
     * @return Clamped value
     */
    function clamp(uint256 value, uint256 minValue, uint256 maxValue) internal pure returns (uint256) {
        return min(max(value, minValue), maxValue);
    }

    /**
     * @notice Check if value is within tolerance
     * @param value Value to check
     * @param target Target value
     * @param toleranceBps Tolerance in basis points
     * @return True if within tolerance
     */
    function isWithinTolerance(
        uint256 value,
        uint256 target,
        uint256 toleranceBps
    ) internal pure returns (bool) {
        if (target == 0) return value == 0;
        uint256 tolerance = (target * toleranceBps) / MAX_BPS;
        return value >= target - min(tolerance, target) && value <= target + tolerance;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AVERAGING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate average of two values without overflow
     * @param a First value
     * @param b Second value
     * @return Average (rounded down)
     */
    function avg(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @notice Calculate weighted average of two values
     * @param a First value
     * @param b Second value
     * @param weightA Weight of first value (out of total weight)
     * @param totalWeight Total weight
     * @return Weighted average
     */
    function weightedAvg(
        uint256 a,
        uint256 b,
        uint256 weightA,
        uint256 totalWeight
    ) internal pure returns (uint256) {
        if (totalWeight == 0) revert DivisionByZero();
        return (a * weightA + b * (totalWeight - weightA)) / totalWeight;
    }

    /**
     * @notice Linear interpolation between two values
     * @param a Start value
     * @param b End value
     * @param t Progress (0 = a, WAD = b)
     * @return Interpolated value
     */
    function lerp(uint256 a, uint256 b, uint256 t) internal pure returns (uint256) {
        if (t >= WAD) return b;
        if (t == 0) return a;
        if (b >= a) {
            return a + wadMul(b - a, t);
        } else {
            return a - wadMul(a - b, t);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SQRT (Babylonian method)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate square root using Babylonian method
     * @param x Value to take sqrt of
     * @return y Square root rounded down
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Calculate sqrt in wad precision
     * @param x Value in wad
     * @return Square root in wad
     */
    function wadSqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        return sqrt(x * WAD);
    }
}
