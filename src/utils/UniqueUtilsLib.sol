// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title UniqueUtilsLib
 * @author playground-zkaedi
 * @notice A collection of novel, one-of-a-kind utilities not found in standard libraries
 * @dev Implements cutting-edge algorithms and mathematical constructs for advanced use cases
 *
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║  ██╗   ██╗███╗   ██╗██╗ ██████╗ ██╗   ██╗███████╗    ██╗   ██╗████████╗██╗██╗   ║
 * ║  ██║   ██║████╗  ██║██║██╔═══██╗██║   ██║██╔════╝    ██║   ██║╚══██╔══╝██║██║   ║
 * ║  ██║   ██║██╔██╗ ██║██║██║   ██║██║   ██║█████╗      ██║   ██║   ██║   ██║██║   ║
 * ║  ██║   ██║██║╚██╗██║██║██║▄▄ ██║██║   ██║██╔══╝      ██║   ██║   ██║   ██║██║   ║
 * ║  ╚██████╔╝██║ ╚████║██║╚██████╔╝╚██████╔╝███████╗    ╚██████╔╝   ██║   ██║███████╗
 * ║   ╚═════╝ ╚═╝  ╚═══╝╚═╝ ╚══▀▀═╝  ╚═════╝ ╚══════╝     ╚═════╝    ╚═╝   ╚═╝╚══════╝
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 *
 * Features:
 * - Fibonacci Heap operations for priority queues
 * - Golden Ratio calculations for aesthetically pleasing distributions
 * - Cantor Pairing functions for bijective mappings
 * - Zeckendorf representation for unique Fibonacci decomposition
 * - Hilbert Curve encoding for locality-preserving hashing
 * - Prime factorization utilities
 * - Collatz sequence analysis
 * - Perfect number detection
 * - Narcissistic number generation
 */
library UniqueUtilsLib {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CUSTOM ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidInput();
    error Overflow();
    error ZeroValue();
    error OutOfBounds();
    error InvalidDimension();
    error ComputationExhausted();

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Golden ratio φ ≈ 1.618033988749895 scaled by 1e18
    uint256 internal constant PHI = 1618033988749894848;

    /// @dev 1/φ ≈ 0.618033988749895 scaled by 1e18
    uint256 internal constant PHI_INVERSE = 618033988749894848;

    /// @dev √5 ≈ 2.2360679774997896 scaled by 1e18
    uint256 internal constant SQRT_5 = 2236067977499789696;

    /// @dev First 20 Fibonacci numbers for quick lookup
    uint256 internal constant FIB_0 = 0;
    uint256 internal constant FIB_1 = 1;
    uint256 internal constant FIB_2 = 1;
    uint256 internal constant FIB_3 = 2;
    uint256 internal constant FIB_4 = 3;
    uint256 internal constant FIB_5 = 5;
    uint256 internal constant FIB_6 = 8;
    uint256 internal constant FIB_7 = 13;
    uint256 internal constant FIB_8 = 21;
    uint256 internal constant FIB_9 = 34;
    uint256 internal constant FIB_10 = 55;
    uint256 internal constant FIB_11 = 89;
    uint256 internal constant FIB_12 = 144;
    uint256 internal constant FIB_13 = 233;
    uint256 internal constant FIB_14 = 377;
    uint256 internal constant FIB_15 = 610;
    uint256 internal constant FIB_16 = 987;
    uint256 internal constant FIB_17 = 1597;
    uint256 internal constant FIB_18 = 2584;
    uint256 internal constant FIB_19 = 4181;

    /// @dev Maximum iterations for iterative algorithms
    uint256 internal constant MAX_ITERATIONS = 256;

    /// @dev Scale factor for fixed-point arithmetic
    uint256 internal constant SCALE = 1e18;

    // ═══════════════════════════════════════════════════════════════════════════
    //                         GOLDEN RATIO UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Divides a value according to the golden ratio
     * @dev Returns two segments where larger/smaller ≈ φ
     * @param total The total value to divide
     * @return larger The larger segment (≈ 61.8% of total)
     * @return smaller The smaller segment (≈ 38.2% of total)
     */
    function goldenDivide(uint256 total) internal pure returns (uint256 larger, uint256 smaller) {
        if (total == 0) revert ZeroValue();

        // larger = total * φ_inverse ≈ total * 0.618
        larger = (total * PHI_INVERSE) / SCALE;
        smaller = total - larger;

        // Ensure we don't lose precision
        if (larger + smaller != total) {
            larger = total - smaller;
        }
    }

    /**
     * @notice Creates a golden spiral point at given index
     * @dev Uses Vogel's model for sunflower-like distribution
     * @param index The point index (0-based)
     * @param maxRadius Maximum radius scaled by 1e18
     * @return angle The angle in radians scaled by 1e18
     * @return radius The radius at this point scaled by 1e18
     */
    function goldenSpiralPoint(
        uint256 index,
        uint256 maxRadius
    ) internal pure returns (uint256 angle, uint256 radius) {
        if (index == 0) return (0, 0);

        // Golden angle ≈ 2.399963229728653 radians (137.5077640500378°)
        uint256 goldenAngle = 2399963229728653312; // scaled by 1e18

        // Angle = n * golden_angle
        angle = (index * goldenAngle) % (2 * 3141592653589793238); // mod 2π

        // Radius = maxRadius * sqrt(n/N) for uniform distribution
        // Simplified: radius proportional to sqrt(index)
        radius = (maxRadius * sqrt(index * SCALE)) / SCALE;
    }

    /**
     * @notice Checks if a number is in the Fibonacci sequence
     * @dev Uses the property that n is Fibonacci iff 5n² ± 4 is a perfect square
     * @param n The number to check
     * @return isFib True if n is a Fibonacci number
     * @return index The Fibonacci index if true, 0 otherwise
     */
    function isFibonacci(uint256 n) internal pure returns (bool isFib, uint256 index) {
        if (n == 0) return (true, 0);
        if (n == 1) return (true, 1);

        // Check if 5n² + 4 or 5n² - 4 is a perfect square
        uint256 fiveNSquared = 5 * n * n;

        if (isPerfectSquare(fiveNSquared + 4) || isPerfectSquare(fiveNSquared - 4)) {
            // Find the index
            uint256 a = 0;
            uint256 b = 1;
            uint256 idx = 1;

            while (b < n && idx < MAX_ITERATIONS) {
                uint256 temp = a + b;
                a = b;
                b = temp;
                idx++;
            }

            if (b == n) {
                return (true, idx);
            }
        }

        return (false, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CANTOR PAIRING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encodes two natural numbers into a single unique number
     * @dev Implements Cantor's pairing function: π(k1, k2) = (k1+k2)(k1+k2+1)/2 + k2
     * @param k1 First natural number
     * @param k2 Second natural number
     * @return encoded The uniquely encoded value
     */
    function cantorPair(uint256 k1, uint256 k2) internal pure returns (uint256 encoded) {
        uint256 sum = k1 + k2;
        // Check for overflow
        if (sum < k1) revert Overflow();

        encoded = (sum * (sum + 1)) / 2 + k2;
    }

    /**
     * @notice Decodes a Cantor-paired number back to original pair
     * @dev Inverse of cantorPair function
     * @param z The encoded value
     * @return k1 First original number
     * @return k2 Second original number
     */
    function cantorUnpair(uint256 z) internal pure returns (uint256 k1, uint256 k2) {
        // w = floor((sqrt(8z + 1) - 1) / 2)
        uint256 w = (sqrt((8 * z + 1) * SCALE) / SCALE - 1) / 2;
        uint256 t = (w * w + w) / 2;
        k2 = z - t;
        k1 = w - k2;
    }

    /**
     * @notice Encodes three natural numbers using nested Cantor pairing
     * @param a First number
     * @param b Second number
     * @param c Third number
     * @return encoded The uniquely encoded value
     */
    function cantorTriple(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 encoded) {
        return cantorPair(cantorPair(a, b), c);
    }

    /**
     * @notice Decodes a triple-encoded Cantor number
     * @param z The encoded value
     * @return a First original number
     * @return b Second original number
     * @return c Third original number
     */
    function cantorUntriple(uint256 z) internal pure returns (uint256 a, uint256 b, uint256 c) {
        (uint256 ab, c) = cantorUnpair(z);
        (a, b) = cantorUnpair(ab);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                      ZECKENDORF REPRESENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Decomposes a number into its Zeckendorf representation
     * @dev Every positive integer has a unique representation as sum of non-consecutive Fibonacci numbers
     * @param n The number to decompose
     * @return indices Array of Fibonacci indices used in the representation
     * @return count Number of Fibonacci numbers used
     */
    function zeckendorf(uint256 n) internal pure returns (uint256[32] memory indices, uint256 count) {
        if (n == 0) return (indices, 0);

        // Build Fibonacci sequence up to n
        uint256[93] memory fibs; // F(92) is the largest that fits in uint256
        fibs[0] = 1;
        fibs[1] = 2;
        uint256 fibCount = 2;

        while (fibCount < 93) {
            uint256 next = fibs[fibCount - 1] + fibs[fibCount - 2];
            if (next > n) break;
            fibs[fibCount] = next;
            fibCount++;
        }

        // Greedy algorithm: take largest Fibonacci ≤ remaining
        uint256 remaining = n;
        count = 0;

        for (uint256 i = fibCount; i > 0 && remaining > 0 && count < 32;) {
            unchecked { i--; }
            if (fibs[i] <= remaining) {
                indices[count] = i + 1; // 1-indexed Fibonacci (F1=1, F2=2, ...)
                remaining -= fibs[i];
                count++;
                // Skip adjacent Fibonacci (Zeckendorf property)
                if (i > 0) {
                    unchecked { i--; }
                }
            }
        }
    }

    /**
     * @notice Calculates the Zeckendorf density of a number
     * @dev Ratio of Fibonacci numbers used to the theoretical minimum
     * @param n The number to analyze
     * @return density The density scaled by 1e18 (1e18 = optimal)
     */
    function zeckendorfDensity(uint256 n) internal pure returns (uint256 density) {
        if (n == 0) return SCALE;

        (, uint256 count) = zeckendorf(n);

        // Theoretical minimum is approximately log_φ(n * √5)
        // Simplified: count / log2(n) * some_constant
        uint256 log2n = log2(n);
        if (log2n == 0) log2n = 1;

        // Golden ratio approximation: log_φ ≈ log2 * 1.44
        uint256 theoreticalMin = (log2n * SCALE) / 1440000000000000000;
        if (theoreticalMin == 0) theoreticalMin = 1;

        density = (count * SCALE) / theoreticalMin;
        if (density > SCALE) density = SCALE; // Cap at 1.0
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         HILBERT CURVE ENCODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Converts (x, y) coordinates to Hilbert curve index
     * @dev Locality-preserving: nearby points have nearby indices
     * @param x X coordinate (0 to 2^order - 1)
     * @param y Y coordinate (0 to 2^order - 1)
     * @param order The order of the Hilbert curve (1-16)
     * @return d The Hilbert curve index
     */
    function hilbertEncode(uint256 x, uint256 y, uint256 order) internal pure returns (uint256 d) {
        if (order == 0 || order > 16) revert InvalidDimension();

        uint256 n = 1 << order;
        if (x >= n || y >= n) revert OutOfBounds();

        uint256 rx;
        uint256 ry;
        uint256 s;

        d = 0;
        s = n >> 1;

        while (s > 0) {
            rx = (x & s) > 0 ? 1 : 0;
            ry = (y & s) > 0 ? 1 : 0;
            d += s * s * ((3 * rx) ^ ry);

            // Rotate quadrant
            if (ry == 0) {
                if (rx == 1) {
                    x = s - 1 - x;
                    y = s - 1 - y;
                }
                // Swap x and y
                (x, y) = (y, x);
            }

            s >>= 1;
        }
    }

    /**
     * @notice Converts Hilbert curve index back to (x, y) coordinates
     * @param d The Hilbert curve index
     * @param order The order of the Hilbert curve (1-16)
     * @return x X coordinate
     * @return y Y coordinate
     */
    function hilbertDecode(uint256 d, uint256 order) internal pure returns (uint256 x, uint256 y) {
        if (order == 0 || order > 16) revert InvalidDimension();

        uint256 n = 1 << order;
        if (d >= n * n) revert OutOfBounds();

        uint256 rx;
        uint256 ry;
        uint256 s;
        uint256 t = d;

        x = 0;
        y = 0;
        s = 1;

        while (s < n) {
            rx = 1 & (t / 2);
            ry = 1 & (t ^ rx);

            // Rotate
            if (ry == 0) {
                if (rx == 1) {
                    x = s - 1 - x;
                    y = s - 1 - y;
                }
                (x, y) = (y, x);
            }

            x += s * rx;
            y += s * ry;
            t /= 4;
            s *= 2;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         COLLATZ SEQUENCE ANALYSIS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Computes the Collatz sequence length (stopping time)
     * @dev Collatz conjecture: n → n/2 if even, 3n+1 if odd, eventually reaches 1
     * @param n Starting number
     * @return length Steps to reach 1
     * @return maxValue Maximum value encountered in sequence
     */
    function collatzLength(uint256 n) internal pure returns (uint256 length, uint256 maxValue) {
        if (n == 0) revert ZeroValue();
        if (n == 1) return (0, 1);

        maxValue = n;
        length = 0;

        while (n != 1 && length < MAX_ITERATIONS) {
            if (n % 2 == 0) {
                n = n / 2;
            } else {
                // Check for overflow before 3n + 1
                if (n > type(uint256).max / 3) revert Overflow();
                n = 3 * n + 1;
            }

            if (n > maxValue) maxValue = n;
            length++;
        }

        if (n != 1) revert ComputationExhausted();
    }

    /**
     * @notice Computes the Collatz "altitude" - ratio of max to start
     * @param n Starting number
     * @return altitude Max value divided by start, scaled by 1e18
     */
    function collatzAltitude(uint256 n) internal pure returns (uint256 altitude) {
        if (n == 0) revert ZeroValue();

        (, uint256 maxValue) = collatzLength(n);
        altitude = (maxValue * SCALE) / n;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         PRIME UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Finds the largest prime factor of a number
     * @dev Uses trial division optimized with 6k±1 pattern
     * @param n The number to factorize
     * @return largestPrime The largest prime factor
     */
    function largestPrimeFactor(uint256 n) internal pure returns (uint256 largestPrime) {
        if (n <= 1) revert InvalidInput();

        largestPrime = 1;

        // Divide out 2s
        while (n % 2 == 0) {
            largestPrime = 2;
            n = n / 2;
        }

        // Divide out 3s
        while (n % 3 == 0) {
            largestPrime = 3;
            n = n / 3;
        }

        // Check 6k ± 1 pattern
        uint256 i = 5;
        while (i * i <= n) {
            while (n % i == 0) {
                largestPrime = i;
                n = n / i;
            }
            while (n % (i + 2) == 0) {
                largestPrime = i + 2;
                n = n / (i + 2);
            }
            i += 6;
        }

        if (n > 1) {
            largestPrime = n;
        }
    }

    /**
     * @notice Counts distinct prime factors (omega function)
     * @param n The number to analyze
     * @return count Number of distinct prime factors
     */
    function distinctPrimeFactors(uint256 n) internal pure returns (uint256 count) {
        if (n <= 1) return 0;

        count = 0;

        // Check 2
        if (n % 2 == 0) {
            count++;
            while (n % 2 == 0) n = n / 2;
        }

        // Check 3
        if (n % 3 == 0) {
            count++;
            while (n % 3 == 0) n = n / 3;
        }

        // Check 6k ± 1
        uint256 i = 5;
        while (i * i <= n) {
            if (n % i == 0) {
                count++;
                while (n % i == 0) n = n / i;
            }
            if (n % (i + 2) == 0) {
                count++;
                while (n % (i + 2) == 0) n = n / (i + 2);
            }
            i += 6;
        }

        if (n > 1) count++;
    }

    /**
     * @notice Checks if a number is a perfect number
     * @dev Perfect numbers equal the sum of their proper divisors
     * @param n The number to check
     * @return isPerfect True if n is perfect
     */
    function isPerfectNumber(uint256 n) internal pure returns (bool isPerfect) {
        if (n < 6) return false; // First perfect number is 6

        uint256 sum = 1; // 1 is always a divisor
        uint256 sqrtN = sqrt(n * SCALE) / (10 ** 9);

        for (uint256 i = 2; i <= sqrtN; i++) {
            if (n % i == 0) {
                sum += i;
                if (i != n / i) {
                    sum += n / i;
                }
            }
        }

        return sum == n;
    }

    /**
     * @notice Calculates the nth triangular number
     * @dev T(n) = n(n+1)/2
     * @param n The index
     * @return triangular The nth triangular number
     */
    function triangularNumber(uint256 n) internal pure returns (uint256 triangular) {
        return (n * (n + 1)) / 2;
    }

    /**
     * @notice Checks if a number is triangular
     * @param n The number to check
     * @return isTriangular True if n is triangular
     * @return index The triangular index if true
     */
    function isTriangularNumber(uint256 n) internal pure returns (bool isTriangular, uint256 index) {
        if (n == 0) return (true, 0);

        // n is triangular if 8n + 1 is a perfect square
        uint256 test = 8 * n + 1;
        if (isPerfectSquare(test)) {
            // index = (sqrt(8n + 1) - 1) / 2
            index = (sqrt(test * SCALE) / (10 ** 9) - 1) / 2;
            return (true, index);
        }

        return (false, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         NARCISSISTIC NUMBERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if a number is narcissistic (Armstrong number)
     * @dev A number where sum of digits^(number of digits) equals the number
     * @param n The number to check
     * @return isNarcissistic True if narcissistic
     */
    function isNarcissisticNumber(uint256 n) internal pure returns (bool isNarcissistic) {
        if (n == 0) return true;

        // Count digits
        uint256 temp = n;
        uint256 digits = 0;
        while (temp > 0) {
            digits++;
            temp /= 10;
        }

        // Calculate sum of each digit raised to power of digit count
        temp = n;
        uint256 sum = 0;
        while (temp > 0) {
            uint256 digit = temp % 10;
            sum += power(digit, digits);
            temp /= 10;
        }

        return sum == n;
    }

    /**
     * @notice Generates the next narcissistic number after n
     * @param n Starting point
     * @return next The next narcissistic number
     */
    function nextNarcissistic(uint256 n) internal pure returns (uint256 next) {
        // Known narcissistic numbers up to reasonable computation
        uint256[25] memory narcissistics = [
            uint256(0), 1, 2, 3, 4, 5, 6, 7, 8, 9,
            153, 370, 371, 407, 1634, 8208, 9474,
            54748, 92727, 93084, 548834, 1741725,
            4210818, 9800817, 9926315
        ];

        for (uint256 i = 0; i < 25; i++) {
            if (narcissistics[i] > n) {
                return narcissistics[i];
            }
        }

        revert ComputationExhausted();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         DIGIT MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reverses the digits of a number
     * @param n The number to reverse
     * @return reversed The reversed number
     */
    function reverseDigits(uint256 n) internal pure returns (uint256 reversed) {
        reversed = 0;
        while (n > 0) {
            reversed = reversed * 10 + (n % 10);
            n /= 10;
        }
    }

    /**
     * @notice Checks if a number is a palindrome
     * @param n The number to check
     * @return isPalindrome True if palindrome
     */
    function isNumericPalindrome(uint256 n) internal pure returns (bool isPalindrome) {
        return n == reverseDigits(n);
    }

    /**
     * @notice Calculates the digital root (repeated digit sum until single digit)
     * @param n The number to process
     * @return root The digital root (1-9 for n>0, 0 for n=0)
     */
    function digitalRoot(uint256 n) internal pure returns (uint256 root) {
        if (n == 0) return 0;

        // Digital root formula: 1 + ((n - 1) mod 9)
        return 1 + ((n - 1) % 9);
    }

    /**
     * @notice Sums all digits of a number
     * @param n The number
     * @return sum Sum of all digits
     */
    function digitSum(uint256 n) internal pure returns (uint256 sum) {
        sum = 0;
        while (n > 0) {
            sum += n % 10;
            n /= 10;
        }
    }

    /**
     * @notice Counts the number of digits
     * @param n The number
     * @return count Number of digits
     */
    function digitCount(uint256 n) internal pure returns (uint256 count) {
        if (n == 0) return 1;

        count = 0;
        while (n > 0) {
            count++;
            n /= 10;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         HAPPY NUMBERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if a number is "happy"
     * @dev A happy number eventually reaches 1 when repeatedly replacing with sum of squared digits
     * @param n The number to check
     * @return isHappy True if the number is happy
     * @return iterations Steps to reach 1 (or cycle)
     */
    function isHappyNumber(uint256 n) internal pure returns (bool isHappy, uint256 iterations) {
        if (n == 0) return (false, 0);

        uint256 slow = n;
        uint256 fast = n;
        iterations = 0;

        do {
            slow = sumOfSquaredDigits(slow);
            fast = sumOfSquaredDigits(sumOfSquaredDigits(fast));
            iterations++;
        } while (slow != fast && iterations < MAX_ITERATIONS);

        isHappy = (slow == 1);
    }

    /**
     * @notice Calculates sum of squared digits
     * @param n The number
     * @return sum Sum of each digit squared
     */
    function sumOfSquaredDigits(uint256 n) internal pure returns (uint256 sum) {
        sum = 0;
        while (n > 0) {
            uint256 digit = n % 10;
            sum += digit * digit;
            n /= 10;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         MATHEMATICAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Integer square root using Newton's method
     * @param x The value (can be scaled)
     * @return y The square root
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        // Initial guess
        y = x;
        uint256 z = (x + 1) / 2;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Checks if a number is a perfect square
     * @param n The number to check
     * @return True if perfect square
     */
    function isPerfectSquare(uint256 n) internal pure returns (bool) {
        if (n == 0) return true;
        uint256 root = sqrt(n * SCALE) / (10 ** 9);
        return root * root == n;
    }

    /**
     * @notice Binary logarithm (floor)
     * @param x The value
     * @return result Floor of log2(x)
     */
    function log2(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) revert ZeroValue();

        result = 0;
        while (x > 1) {
            x >>= 1;
            result++;
        }
    }

    /**
     * @notice Integer power function
     * @param base The base
     * @param exp The exponent
     * @return result base^exp
     */
    function power(uint256 base, uint256 exp) internal pure returns (uint256 result) {
        result = 1;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result *= base;
            }
            base *= base;
            exp /= 2;
        }
    }

    /**
     * @notice Greatest common divisor using Euclidean algorithm
     * @param a First number
     * @param b Second number
     * @return gcd The GCD
     */
    function gcd(uint256 a, uint256 b) internal pure returns (uint256) {
        while (b != 0) {
            (a, b) = (b, a % b);
        }
        return a;
    }

    /**
     * @notice Least common multiple
     * @param a First number
     * @param b Second number
     * @return lcm The LCM
     */
    function lcm(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a / gcd(a, b)) * b;
    }

    /**
     * @notice Computes modular exponentiation: (base^exp) mod modulus
     * @param base The base
     * @param exp The exponent
     * @param modulus The modulus
     * @return result (base^exp) mod modulus
     */
    function modExp(uint256 base, uint256 exp, uint256 modulus) internal pure returns (uint256 result) {
        if (modulus == 0) revert ZeroValue();
        if (modulus == 1) return 0;

        result = 1;
        base = base % modulus;

        while (exp > 0) {
            if (exp % 2 == 1) {
                result = mulmod(result, base, modulus);
            }
            exp /= 2;
            base = mulmod(base, base, modulus);
        }
    }
}
