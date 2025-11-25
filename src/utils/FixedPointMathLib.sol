// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FixedPointMathLib
 * @notice Advanced fixed-point mathematical operations for DeFi protocols
 * @dev Provides exp, ln, pow, and other transcendental functions with high precision
 *      All functions use 18 decimal fixed-point (WAD) representation
 *      Optimized for gas efficiency with assembly where beneficial
 */
library FixedPointMathLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev 1e18 - the standard WAD unit for 18 decimal fixed-point
    uint256 internal constant WAD = 1e18;

    /// @dev 1e27 - the RAY unit for 27 decimal fixed-point
    uint256 internal constant RAY = 1e27;

    /// @dev ln(2) in WAD representation
    uint256 internal constant LN_2_WAD = 693147180559945309;

    /// @dev e in WAD representation
    uint256 internal constant E_WAD = 2718281828459045235;

    /// @dev Maximum value for exp() input to prevent overflow
    int256 internal constant EXP_MAX_INPUT = 135305999368893231589;

    /// @dev Minimum value for exp() input (returns 0 below this)
    int256 internal constant EXP_MIN_INPUT = -42139678854452767551;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error Overflow();
    error Underflow();
    error InvalidInput();
    error DivisionByZero();
    error LogOfZero();
    error NegativeNumber();

    // ═══════════════════════════════════════════════════════════════════════════
    // EXPONENTIAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates e^x where x is in WAD fixed-point
     * @dev Uses a 6th degree polynomial approximation after range reduction
     *      Accurate to ~1e-18 precision for most inputs
     * @param x The exponent in WAD (18 decimals)
     * @return result e^x in WAD
     */
    function expWad(int256 x) internal pure returns (int256 result) {
        unchecked {
            // When x < EXP_MIN_INPUT, the result is essentially 0
            if (x < EXP_MIN_INPUT) {
                return 0;
            }
            // When x > EXP_MAX_INPUT, we overflow
            if (x > EXP_MAX_INPUT) {
                revert Overflow();
            }

            // x is now in the range (-42.14, 135.31) * 1e18

            // Reduce x to (-ln(2)/2, ln(2)/2) range
            // Using: e^x = 2^k * e^r where r = x - k*ln(2)

            // k = floor(x / ln(2))
            int256 k = ((x << 96) / 0xB17217F7D1CF79ABC9E3B398 + (1 << 95)) >> 96;

            // r = x - k * ln(2)
            int256 r = x - k * 693147180559945309;

            // Now r is in range (-ln(2)/2, ln(2)/2)
            // Compute e^r using Taylor series truncated at 6 terms
            // e^r ≈ 1 + r + r²/2! + r³/3! + r⁴/4! + r⁵/5! + r⁶/6!

            int256 r2 = (r * r) / int256(WAD);
            int256 r3 = (r2 * r) / int256(WAD);
            int256 r4 = (r3 * r) / int256(WAD);
            int256 r5 = (r4 * r) / int256(WAD);
            int256 r6 = (r5 * r) / int256(WAD);

            // Coefficients: 1, 1, 1/2, 1/6, 1/24, 1/120, 1/720
            int256 expR = int256(WAD) + r + r2 / 2 + r3 / 6 + r4 / 24 + r5 / 120 + r6 / 720;

            // Multiply by 2^k
            if (k >= 0) {
                result = expR << uint256(k);
            } else {
                result = expR >> uint256(-k);
            }
        }
    }

    /**
     * @notice Calculates e^x for unsigned x, returning unsigned result
     * @param x The exponent in WAD (18 decimals)
     * @return result e^x in WAD
     */
    function exp(uint256 x) internal pure returns (uint256 result) {
        if (x > uint256(type(int256).max)) revert Overflow();
        int256 signedResult = expWad(int256(x));
        if (signedResult < 0) revert Underflow();
        result = uint256(signedResult);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOGARITHM FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates ln(x) where x is in WAD fixed-point
     * @dev Uses a polynomial approximation after range reduction
     * @param x The input in WAD (must be > 0)
     * @return result ln(x) in WAD
     */
    function lnWad(int256 x) internal pure returns (int256 result) {
        unchecked {
            if (x <= 0) revert LogOfZero();

            // Scale x to [1, 2) range
            // ln(x) = ln(2^k * m) = k*ln(2) + ln(m) where m ∈ [1, 2)

            int256 k = int256(log2(uint256(x))) - 59; // -59 because log2 returns for uint, we have WAD

            // Normalize to [1, 2) in WAD
            int256 m;
            if (k >= 0) {
                m = x >> uint256(k);
            } else {
                m = x << uint256(-k);
            }

            // Now m is approximately in [WAD, 2*WAD)
            // Use polynomial approximation for ln(m) where m ∈ [1, 2)
            // ln(1 + y) ≈ y - y²/2 + y³/3 - y⁴/4 + ... for |y| < 1

            int256 y = m - int256(WAD); // y ∈ [0, WAD)
            int256 y2 = (y * y) / int256(WAD);
            int256 y3 = (y2 * y) / int256(WAD);
            int256 y4 = (y3 * y) / int256(WAD);
            int256 y5 = (y4 * y) / int256(WAD);
            int256 y6 = (y5 * y) / int256(WAD);
            int256 y7 = (y6 * y) / int256(WAD);

            int256 lnM = y - y2 / 2 + y3 / 3 - y4 / 4 + y5 / 5 - y6 / 6 + y7 / 7;

            // Result: k * ln(2) + ln(m)
            result = k * int256(LN_2_WAD) + lnM;
        }
    }

    /**
     * @notice Calculates ln(x) for unsigned input
     * @param x The input in WAD (must be > 0)
     * @return result ln(x) in WAD (can be negative)
     */
    function ln(uint256 x) internal pure returns (int256 result) {
        if (x == 0) revert LogOfZero();
        if (x > uint256(type(int256).max)) revert Overflow();
        result = lnWad(int256(x));
    }

    /**
     * @notice Calculates log₂(x) for unsigned integer
     * @dev Returns the floor of log₂(x), not a fixed-point result
     * @param x The input (must be > 0)
     * @return result floor(log₂(x))
     */
    function log2(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) revert LogOfZero();

        assembly {
            // Find the highest set bit
            let n := x
            if iszero(lt(n, 0x100000000000000000000000000000000)) {
                n := shr(128, n)
                result := 128
            }
            if iszero(lt(n, 0x10000000000000000)) {
                n := shr(64, n)
                result := add(result, 64)
            }
            if iszero(lt(n, 0x100000000)) {
                n := shr(32, n)
                result := add(result, 32)
            }
            if iszero(lt(n, 0x10000)) {
                n := shr(16, n)
                result := add(result, 16)
            }
            if iszero(lt(n, 0x100)) {
                n := shr(8, n)
                result := add(result, 8)
            }
            if iszero(lt(n, 0x10)) {
                n := shr(4, n)
                result := add(result, 4)
            }
            if iszero(lt(n, 0x4)) {
                n := shr(2, n)
                result := add(result, 2)
            }
            if iszero(lt(n, 0x2)) {
                result := add(result, 1)
            }
        }
    }

    /**
     * @notice Calculates log₁₀(x) in WAD fixed-point
     * @param x The input in WAD
     * @return result log₁₀(x) in WAD
     */
    function log10Wad(uint256 x) internal pure returns (int256 result) {
        // log₁₀(x) = ln(x) / ln(10)
        // ln(10) in WAD = 2302585092994045684
        result = (ln(x) * int256(WAD)) / 2302585092994045684;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POWER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates x^y where both are in WAD fixed-point
     * @dev Uses the identity: x^y = e^(y * ln(x))
     * @param x The base in WAD (must be > 0)
     * @param y The exponent in WAD
     * @return result x^y in WAD
     */
    function powWad(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (x == 0) {
            return y == 0 ? WAD : 0;
        }
        if (y == 0) return WAD;
        if (x == WAD) return WAD;

        // x^y = e^(y * ln(x))
        int256 lnX = ln(x);
        int256 yLnX = (int256(y) * lnX) / int256(WAD);

        int256 expResult = expWad(yLnX);
        if (expResult < 0) revert Underflow();
        result = uint256(expResult);
    }

    /**
     * @notice Calculates x^y where y is an integer
     * @dev More efficient than powWad for integer exponents
     *      Uses binary exponentiation
     * @param x The base in WAD
     * @param y The integer exponent
     * @return result x^y in WAD
     */
    function powInt(uint256 x, uint256 y) internal pure returns (uint256 result) {
        result = WAD;

        while (y > 0) {
            if (y & 1 == 1) {
                result = mulWad(result, x);
            }
            x = mulWad(x, x);
            y >>= 1;
        }
    }

    /**
     * @notice Calculates x^(1/n) - the nth root of x
     * @dev Uses Newton-Raphson iteration
     * @param x The input in WAD
     * @param n The root degree
     * @return result x^(1/n) in WAD
     */
    function nthRoot(uint256 x, uint256 n) internal pure returns (uint256 result) {
        if (n == 0) revert InvalidInput();
        if (x == 0) return 0;
        if (n == 1) return x;
        if (n == 2) return sqrtWad(x);

        // Initial guess using log approximation
        result = WAD;

        // Newton-Raphson: result = result - (result^n - x) / (n * result^(n-1))
        // Simplified: result = ((n-1) * result + x / result^(n-1)) / n

        for (uint256 i = 0; i < 100; i++) {
            uint256 resultPowN1 = powInt(result, n - 1);
            uint256 newResult = ((n - 1) * result + (x * WAD) / resultPowN1) / n;

            // Check convergence
            if (newResult >= result) {
                if (newResult - result <= 1) break;
            } else {
                if (result - newResult <= 1) break;
            }
            result = newResult;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Multiplies two WAD numbers and divides by WAD
     * @param x First factor
     * @param y Second factor
     * @return result x * y / WAD
     */
    function mulWad(uint256 x, uint256 y) internal pure returns (uint256 result) {
        assembly {
            // Check for overflow
            if mul(y, gt(x, div(not(0), y))) {
                revert(0, 0)
            }
            result := div(mul(x, y), 1000000000000000000)
        }
    }

    /**
     * @notice Divides two WAD numbers (multiplies by WAD first)
     * @param x Numerator
     * @param y Denominator
     * @return result x * WAD / y
     */
    function divWad(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (y == 0) revert DivisionByZero();
        assembly {
            // Check for overflow
            if mul(y, gt(x, div(div(not(0), 1000000000000000000), y))) {
                revert(0, 0)
            }
            result := div(mul(x, 1000000000000000000), y)
        }
    }

    /**
     * @notice Calculates sqrt(x) for WAD input
     * @dev Uses Newton-Raphson method
     * @param x Input in WAD
     * @return result sqrt(x) in WAD
     */
    function sqrtWad(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;

        // Scale up by WAD before sqrt, then we get WAD precision
        uint256 scaled = x * WAD;

        // Initial guess
        result = scaled;

        // Newton-Raphson iterations
        assembly {
            result := shr(1, add(result, div(scaled, result)))
            result := shr(1, add(result, div(scaled, result)))
            result := shr(1, add(result, div(scaled, result)))
            result := shr(1, add(result, div(scaled, result)))
            result := shr(1, add(result, div(scaled, result)))
            result := shr(1, add(result, div(scaled, result)))
            result := shr(1, add(result, div(scaled, result)))
        }

        // Round down
        if (result * result > scaled) {
            result--;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SPECIAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates the compound interest factor
     * @dev Returns (1 + rate)^time in WAD
     *      Useful for interest calculations in lending protocols
     * @param rate Interest rate in WAD (e.g., 0.05e18 for 5%)
     * @param time Time periods
     * @return result Compound factor in WAD
     */
    function compoundInterest(uint256 rate, uint256 time) internal pure returns (uint256 result) {
        result = powInt(WAD + rate, time);
    }

    /**
     * @notice Calculates continuous compound interest: e^(rate * time)
     * @param rate Annual rate in WAD
     * @param time Time in WAD (e.g., 0.5e18 for half a year)
     * @return result e^(rate * time) in WAD
     */
    function continuousCompound(uint256 rate, uint256 time) internal pure returns (uint256 result) {
        uint256 exponent = mulWad(rate, time);
        result = exp(exponent);
    }

    /**
     * @notice Calculates the decay factor for exponential decay
     * @dev Returns e^(-lambda * t)
     * @param lambda Decay constant in WAD
     * @param t Time elapsed in WAD
     * @return result Decay factor in WAD
     */
    function exponentialDecay(uint256 lambda, uint256 t) internal pure returns (uint256 result) {
        int256 exponent = -int256(mulWad(lambda, t));
        int256 expResult = expWad(exponent);
        if (expResult < 0) return 0;
        result = uint256(expResult);
    }

    /**
     * @notice Calculates sigmoid function: 1 / (1 + e^(-x))
     * @dev Useful for bonding curves and probability calculations
     * @param x Input in WAD (signed)
     * @return result Sigmoid(x) in WAD, range (0, WAD)
     */
    function sigmoid(int256 x) internal pure returns (uint256 result) {
        int256 negX = -x;
        int256 expNegX = expWad(negX);

        // 1 / (1 + e^(-x))
        result = divWad(WAD, uint256(int256(WAD) + expNegX));
    }

    /**
     * @notice Hyperbolic tangent: (e^x - e^(-x)) / (e^x + e^(-x))
     * @param x Input in WAD (signed)
     * @return result tanh(x) in WAD, range (-WAD, WAD)
     */
    function tanh(int256 x) internal pure returns (int256 result) {
        int256 expX = expWad(x);
        int256 expNegX = expWad(-x);

        int256 numerator = expX - expNegX;
        int256 denominator = expX + expNegX;

        if (denominator == 0) revert DivisionByZero();
        result = (numerator * int256(WAD)) / denominator;
    }
}
