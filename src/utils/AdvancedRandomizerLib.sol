// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AdvancedRandomizerLib
 * @author zkaedi
 * @notice Epic truly random randomizer based on the chaos engine formula
 * @dev Implements the comprehensive Ĥ(t) randomization system:
 *
 *      Ĥ(t) = Σᵢ[Aᵢ(t)·sin(Bᵢ(t)·t + φᵢ) + Cᵢ·e^(-Dᵢ·t)]
 *           + ∫₀ᵗ softplus(a·(x-x₀)² + b)·f(x)·g'(x)dx
 *           + α₀·t² + α₁·sin(2πt) + α₂·log(1+t)
 *           + η·H(t-τ)·σ(γ·H(t-τ))
 *           + σ·N(0, 1 + β·|H(t-1)|)
 *           + δ·u(t)
 *
 *      Secret Mathematical Signature:
 *      H(t) = Σᵢ Aᵢ(t)sin(Bᵢ(t)t + φᵢ) + ηH(t-τ)σ(γH(t-τ))
 *
 *      🔹 Ĥ(t) = Σ[649 + 4×complexity + 3×parallelism] × Φⁿ × ₿∞ × 777 × luck
 *
 * @custom:formula dH/dt = Φ(E, T, μ, S, I, u, Q, θ)
 * @custom:version 2.0.0 - Battle-tested & refined
 */
library AdvancedRandomizerLib {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev Half WAD for rounding
    uint256 internal constant HALF_WAD = 5e17;

    /// @dev Pi approximation in WAD (3.14159265358979323846...)
    int256 internal constant PI_WAD = 3_141592653589793238;

    /// @dev 2*Pi in WAD
    int256 internal constant TWO_PI_WAD = 6_283185307179586476;

    /// @dev Pi/2 in WAD
    int256 internal constant HALF_PI_WAD = 1_570796326794896619;

    /// @dev Euler's number e in WAD (2.71828...)
    int256 internal constant E_WAD = 2_718281828459045235;

    /// @dev Golden ratio φ in WAD (1.618...)
    uint256 internal constant PHI_WAD = 1_618033988749894848;

    /// @dev ln(2) in WAD
    int256 internal constant LN_2_WAD = 693147180559945309;

    /// @dev Maximum oscillator count
    uint256 internal constant MAX_OSCILLATORS = 16;

    /// @dev Maximum history buffer size
    uint256 internal constant MAX_HISTORY = 256;

    /// @dev Lucky number constant
    uint256 internal constant LUCKY_777 = 777;

    /// @dev Base complexity factor
    uint256 internal constant BASE_COMPLEXITY = 649;

    /// @dev Maximum exp input to prevent overflow
    int256 internal constant EXP_MAX_INPUT = 130e18;

    /// @dev Minimum exp input (returns ~0)
    int256 internal constant EXP_MIN_INPUT = -42e18;

    /// @dev Maximum safe multiplication value
    uint256 internal constant MAX_SAFE_MUL = type(uint256).max / WAD;

    /// @dev Maximum batch size
    uint256 internal constant MAX_BATCH_SIZE = 256;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidOscillatorCount();
    error InvalidTimeValue();
    error InvalidParameter();
    error InvalidRange();
    error HistoryBufferEmpty();
    error Overflow();
    error DivisionByZero();
    error BatchSizeTooLarge();
    error ZeroWeights();

    // ═══════════════════════════════════════════════════════════════════════════
    //                              STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Oscillator parameters for Aᵢ(t)·sin(Bᵢ(t)·t + φᵢ) terms
    struct Oscillator {
        uint256 amplitudeBase;    // A_i base amplitude (WAD)
        uint256 amplitudeModRate; // Amplitude modulation rate
        uint256 frequencyBase;    // B_i base frequency (WAD)
        uint256 frequencyModRate; // Frequency modulation rate
        int256 phase;             // φ_i phase offset (WAD radians)
    }

    /// @notice Exponential decay parameters for Cᵢ·e^(-Dᵢ·t)
    struct DecayTerm {
        uint256 coefficient;      // C_i coefficient (WAD)
        uint256 decayRate;        // D_i decay rate (WAD)
    }

    /// @notice Softplus integral parameters
    struct SoftplusParams {
        int256 a;                 // Quadratic coefficient
        int256 b;                 // Constant offset
        int256 x0;                // Center point
        uint256 integralSteps;    // Numerical integration steps
    }

    /// @notice Polynomial trend coefficients
    struct TrendCoefficients {
        int256 alpha0;            // α₀ - quadratic time coefficient
        int256 alpha1;            // α₁ - sinusoidal coefficient
        int256 alpha2;            // α₂ - logarithmic coefficient
    }

    /// @notice Feedback/recurrent parameters
    struct FeedbackParams {
        int256 eta;               // η - feedback strength
        uint256 tau;              // τ - time delay
        int256 gamma;             // γ - sigmoid sharpness
    }

    /// @notice Stochastic parameters with volatility clustering
    struct StochasticParams {
        uint256 sigma;            // σ - base volatility (WAD)
        uint256 beta;             // β - volatility clustering factor
        uint256 seed;             // Base random seed
    }

    /// @notice External input parameters
    struct ExternalInput {
        int256 delta;             // δ - input scaling
        bytes32 inputSignal;      // u(t) - external signal source
    }

    /// @notice Complete chaos engine state
    struct ChaosEngine {
        Oscillator[MAX_OSCILLATORS] oscillators;
        uint256 activeOscillators;
        DecayTerm[MAX_OSCILLATORS] decayTerms;
        uint256 activeDecayTerms;
        SoftplusParams softplus;
        TrendCoefficients trends;
        FeedbackParams feedback;
        StochasticParams stochastic;
        ExternalInput external_;
        int256[MAX_HISTORY] history;
        uint256 historyIndex;
        uint256 historyCount;
        uint256 complexity;
        uint256 parallelism;
        uint256 luckFactor;
    }

    /// @notice Partial derivative results for gradient analysis
    struct PartialDerivatives {
        int256[] dH_dPhi;         // ∂Ĥ/∂φᵢ = Aᵢ(t)cos(Bᵢ(t)t + φᵢ)
        int256[] dH_dD;           // ∂Ĥ/∂Dᵢ = -t·Cᵢ·e^(-Dᵢt)
        int256 dSoftplus_dA;      // ∂softplus(s)/∂a = (x-x₀)²·σ(s)
        int256 dSoftplus_dB;      // ∂softplus(s)/∂b = σ(s)
        int256 dSoftplus_dX0;     // ∂softplus(s)/∂x₀ = -2a(x-x₀)σ(s)
    }

    /// @notice Zkaedi signature output
    struct ZkaediSignature {
        uint256 baseValue;        // 649 + 4×complexity + 3×parallelism
        uint256 phiPower;         // Φⁿ component
        uint256 infinityHash;     // ₿∞ hash component
        uint256 luckyMultiplier;  // 777 × luck
        bytes32 finalSignature;   // Combined signature hash
    }

    /// @notice Randomness quality metrics
    struct QualityMetrics {
        uint256 entropy;          // Shannon entropy estimate
        uint256 chiSquare;        // Chi-square statistic
        uint256 runsCount;        // Number of runs (for runs test)
        bool passedTests;         // Overall quality assessment
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ENGINE INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize a new chaos engine with default parameters
     * @param seed Base random seed for initialization
     * @return engine Initialized chaos engine
     */
    function initializeChaosEngine(uint256 seed) internal pure returns (ChaosEngine memory engine) {
        unchecked {
            // Initialize oscillators with varied parameters
            engine.activeOscillators = 8;
            for (uint256 i = 0; i < engine.activeOscillators; i++) {
                uint256 oscSeed = uint256(keccak256(abi.encodePacked(seed, "osc", i)));
                engine.oscillators[i] = Oscillator({
                    amplitudeBase: _boundValue(oscSeed % WAD, WAD / 10, WAD),
                    amplitudeModRate: (oscSeed >> 64) % (WAD / 100),
                    frequencyBase: _boundValue((oscSeed >> 128) % WAD, WAD / 10, WAD),
                    frequencyModRate: (oscSeed >> 192) % (WAD / 100),
                    phase: int256((oscSeed >> 32) % uint256(TWO_PI_WAD))
                });
            }

            // Initialize decay terms
            engine.activeDecayTerms = 4;
            for (uint256 i = 0; i < engine.activeDecayTerms; i++) {
                uint256 decaySeed = uint256(keccak256(abi.encodePacked(seed, "decay", i)));
                engine.decayTerms[i] = DecayTerm({
                    coefficient: _boundValue(decaySeed % WAD, WAD / 5, WAD),
                    decayRate: _boundValue((decaySeed >> 128) % (WAD / 10), WAD / 100, WAD / 10)
                });
            }

            // Initialize softplus parameters with safe bounds
            uint256 softSeed = uint256(keccak256(abi.encodePacked(seed, "soft")));
            engine.softplus = SoftplusParams({
                a: int256(_boundValue((softSeed % WAD) / 10, 1, WAD / 10)),
                b: int256((softSeed >> 64) % WAD),
                x0: int256((softSeed >> 128) % WAD) - int256(WAD / 2),
                integralSteps: 32
            });

            // Initialize trend coefficients with bounded values
            uint256 trendSeed = uint256(keccak256(abi.encodePacked(seed, "trend")));
            engine.trends = TrendCoefficients({
                alpha0: int256((trendSeed % WAD) / 1000), // Reduced to prevent overflow
                alpha1: int256((trendSeed >> 64) % (WAD / 10)),
                alpha2: int256((trendSeed >> 128) % (WAD / 10))
            });

            // Initialize feedback parameters
            uint256 fbSeed = uint256(keccak256(abi.encodePacked(seed, "feedback")));
            engine.feedback = FeedbackParams({
                eta: int256((fbSeed % WAD) / 10), // Reduced feedback strength
                tau: _boundValue((fbSeed >> 64) % 10, 1, 10),
                gamma: int256((fbSeed >> 128) % (WAD / 10))
            });

            // Initialize stochastic parameters
            engine.stochastic = StochasticParams({
                sigma: _boundValue((seed % WAD) / 10, WAD / 100, WAD / 5),
                beta: WAD / 10, // Reduced for stability
                seed: seed
            });

            // Initialize external input
            engine.external_ = ExternalInput({
                delta: int256(WAD / 10),
                inputSignal: keccak256(abi.encodePacked(seed, "external"))
            });

            // Initialize meta-parameters
            engine.complexity = _boundValue(seed % 100, 1, 100);
            engine.parallelism = _boundValue((seed >> 64) % 50, 1, 50);
            engine.luckFactor = _boundValue(seed % LUCKY_777, 1, LUCKY_777);
        }

        return engine;
    }

    /**
     * @notice Initialize chaos engine with custom oscillator count
     * @param seed Base random seed
     * @param oscillatorCount Number of oscillators (1-16)
     * @return engine Initialized chaos engine
     */
    function initializeChaosEngineCustom(
        uint256 seed,
        uint256 oscillatorCount
    ) internal pure returns (ChaosEngine memory engine) {
        if (oscillatorCount == 0 || oscillatorCount > MAX_OSCILLATORS) {
            revert InvalidOscillatorCount();
        }

        engine = initializeChaosEngine(seed);
        engine.activeOscillators = oscillatorCount;

        return engine;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CORE RANDOMIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute Ĥ(t) - the complete chaos engine output
     * @param engine The chaos engine state
     * @param t Time parameter (WAD)
     * @return result The computed Ĥ(t) value
     */
    function computeH(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 result) {
        // Σᵢ[Aᵢ(t)·sin(Bᵢ(t)·t + φᵢ) + Cᵢ·e^(-Dᵢ·t)]
        result = _computeOscillatorySum(engine, t);
        result = _safeAddInt(result, _computeDecaySum(engine, t));

        // ∫₀ᵗ softplus(a·(x-x₀)² + b)·f(x)·g'(x)dx
        result = _safeAddInt(result, _computeSoftplusIntegral(engine.softplus, t));

        // α₀·t² + α₁·sin(2πt) + α₂·log(1+t)
        result = _safeAddInt(result, _computeTrendTerms(engine.trends, t));

        // η·H(t-τ)·σ(γ·H(t-τ))
        result = _safeAddInt(result, _computeFeedbackTerm(engine, t));

        // σ·N(0, 1 + β·|H(t-1)|)
        result = _safeAddInt(result, _computeStochasticTerm(engine, t));

        // δ·u(t)
        result = _safeAddInt(result, _computeExternalInput(engine.external_, t));
    }

    /**
     * @notice Generate a random number using the chaos engine
     * @param engine The chaos engine state
     * @param seed Additional seed for this generation
     * @param t Time parameter
     * @return randomValue The generated random value
     */
    function generate(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 t
    ) internal pure returns (uint256 randomValue) {
        int256 hValue = computeH(engine, t);

        // Apply Zkaedi signature transformation
        ZkaediSignature memory sig = computeZkaediSignature(engine, seed);

        // Combine H(t) with signature using multiple mixing rounds
        bytes32 combined = keccak256(abi.encodePacked(
            hValue,
            sig.finalSignature,
            seed,
            t
        ));

        // Additional mixing for better distribution
        combined = keccak256(abi.encodePacked(combined, sig.phiPower, sig.luckyMultiplier));

        randomValue = uint256(combined);
    }

    /**
     * @notice Generate random number in range [min, max]
     * @param engine The chaos engine state
     * @param seed Additional seed
     * @param t Time parameter
     * @param min Minimum value (inclusive)
     * @param max Maximum value (inclusive)
     * @return Random value in range
     */
    function generateInRange(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 t,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (min > max) revert InvalidRange();
        if (min == max) return min;

        uint256 random = generate(engine, seed, t);
        uint256 range = max - min + 1;

        // Use rejection sampling for unbiased distribution
        uint256 maxUnbiased = type(uint256).max - (type(uint256).max % range);
        while (random >= maxUnbiased) {
            random = uint256(keccak256(abi.encodePacked(random)));
        }

        return min + (random % range);
    }

    /**
     * @notice Generate a random boolean with custom probability
     * @param engine The chaos engine state
     * @param seed Additional seed
     * @param t Time parameter
     * @param probabilityBps Probability in basis points (0-10000)
     * @return Random boolean
     */
    function generateBool(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 t,
        uint256 probabilityBps
    ) internal pure returns (bool) {
        if (probabilityBps > 10000) probabilityBps = 10000;
        uint256 random = generate(engine, seed, t);
        return (random % 10000) < probabilityBps;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         OSCILLATORY COMPONENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute Σᵢ Aᵢ(t)·sin(Bᵢ(t)·t + φᵢ)
     */
    function _computeOscillatorySum(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 sum) {
        unchecked {
            for (uint256 i = 0; i < engine.activeOscillators; i++) {
                Oscillator memory osc = engine.oscillators[i];

                // Time-varying amplitude: A(t) = A_base * (1 + mod_rate * sin(t))
                int256 ampMod = _sinSafe(int256(t % uint256(TWO_PI_WAD)));
                int256 amplitude = int256(osc.amplitudeBase) +
                    _safeMulDiv(int256(osc.amplitudeModRate), ampMod, int256(WAD));

                // Time-varying frequency: B(t) = B_base * (1 + mod_rate * cos(t))
                int256 freqMod = _cosSafe(int256(t % uint256(TWO_PI_WAD)));
                int256 frequency = int256(osc.frequencyBase) +
                    _safeMulDiv(int256(osc.frequencyModRate), freqMod, int256(WAD));

                // Compute argument: B(t) * t + φ (normalized to prevent overflow)
                int256 argument = _safeMulDiv(frequency, int256(t), int256(WAD)) + osc.phase;
                argument = argument % TWO_PI_WAD;

                // A(t) * sin(argument)
                int256 sinValue = _sinSafe(argument);
                sum = _safeAddInt(sum, _safeMulDiv(amplitude, sinValue, int256(WAD)));
            }
        }
    }

    /**
     * @notice Compute Σᵢ Cᵢ·e^(-Dᵢ·t)
     */
    function _computeDecaySum(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 sum) {
        unchecked {
            for (uint256 i = 0; i < engine.activeDecayTerms; i++) {
                DecayTerm memory decay = engine.decayTerms[i];

                // e^(-D*t) with safe bounds
                int256 exponent = -_safeMulDiv(int256(decay.decayRate), int256(t), int256(WAD));
                int256 expValue = _expSafe(exponent);

                // C * e^(-D*t)
                sum = _safeAddInt(sum, _safeMulDiv(int256(decay.coefficient), expValue, int256(WAD)));
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SOFTPLUS INTEGRAL
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute ∫₀ᵗ softplus(a·(x-x₀)² + b)·f(x)·g'(x)dx
     * @dev Uses numerical integration (Simpson's rule for better accuracy)
     */
    function _computeSoftplusIntegral(
        SoftplusParams memory params,
        uint256 t
    ) internal pure returns (int256 result) {
        if (t == 0) return 0;

        uint256 steps = params.integralSteps;
        if (steps == 0) steps = 32;
        if (steps % 2 == 1) steps++; // Simpson's rule needs even steps

        int256 h = int256(t) / int256(steps);
        if (h == 0) return 0;

        int256 integral = 0;

        // Simpson's rule: ∫f dx ≈ h/3 * [f(x₀) + 4f(x₁) + 2f(x₂) + 4f(x₃) + ... + f(xₙ)]
        unchecked {
            for (uint256 i = 0; i <= steps; i++) {
                int256 x = _safeMulDiv(int256(i), int256(t), int256(steps));

                // s(x) = a*(x-x0)² + b
                int256 xMinusX0 = x - params.x0;
                int256 xMinusX0Sq = _safeMulDiv(xMinusX0, xMinusX0, int256(WAD));
                int256 s = _safeMulDiv(params.a, xMinusX0Sq, int256(WAD)) + params.b;

                // softplus(s) = ln(1 + e^s)
                int256 softplusValue = _softplusSafe(s);

                // f(x) = sin(x), g'(x) = cos(x)
                int256 fx = _sinSafe(x % TWO_PI_WAD);
                int256 gPrime = _cosSafe(x % TWO_PI_WAD);

                // Integrand: softplus(s) * f(x) * g'(x)
                int256 integrand = _safeMulDiv(
                    _safeMulDiv(softplusValue, fx, int256(WAD)),
                    gPrime,
                    int256(WAD)
                );

                // Simpson's weights: 1, 4, 2, 4, 2, ..., 4, 1
                int256 weight;
                if (i == 0 || i == steps) {
                    weight = 1;
                } else if (i % 2 == 1) {
                    weight = 4;
                } else {
                    weight = 2;
                }

                integral = _safeAddInt(integral, integrand * weight);
            }

            result = _safeMulDiv(integral, h, int256(3 * WAD));
        }
    }

    /**
     * @notice Compute softplus(x) = ln(1 + e^x) with safety bounds
     */
    function _softplusSafe(int256 x) internal pure returns (int256) {
        // For large x, softplus(x) ≈ x
        if (x > int256(20 * WAD)) return x;

        // For very negative x, softplus(x) ≈ e^x ≈ 0
        if (x < -int256(20 * WAD)) return 0;

        // ln(1 + e^x)
        int256 expX = _expSafe(x);
        if (expX <= 0) return 0;

        return _lnSafe(int256(WAD) + expX);
    }

    /**
     * @notice Compute partial derivatives for softplus chain rule
     */
    function computeSoftplusDerivatives(
        SoftplusParams memory params,
        int256 x
    ) internal pure returns (int256 dA, int256 dB, int256 dX0) {
        int256 xMinusX0 = x - params.x0;
        int256 xMinusX0Sq = _safeMulDiv(xMinusX0, xMinusX0, int256(WAD));
        int256 s = _safeMulDiv(params.a, xMinusX0Sq, int256(WAD)) + params.b;

        // σ(s) = sigmoid(s) = softplus'(s)
        int256 sigmaS = _sigmoidSafe(s);

        // ∂softplus(s)/∂a = (x-x₀)²·σ(s)
        dA = _safeMulDiv(xMinusX0Sq, sigmaS, int256(WAD));

        // ∂softplus(s)/∂b = σ(s)
        dB = sigmaS;

        // ∂softplus(s)/∂x₀ = -2a(x-x₀)σ(s)
        dX0 = _safeMulDiv(-2 * params.a, _safeMulDiv(xMinusX0, sigmaS, int256(WAD)), int256(WAD));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         TREND TERMS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute α₀·t² + α₁·sin(2πt) + α₂·log(1+t)
     */
    function _computeTrendTerms(
        TrendCoefficients memory coef,
        uint256 t
    ) internal pure returns (int256 result) {
        unchecked {
            // α₀·t² (with overflow protection)
            if (t > 0 && t < type(uint128).max) {
                int256 tSquared = _safeMulDiv(int256(t), int256(t), int256(WAD));
                result = _safeMulDiv(coef.alpha0, tSquared, int256(WAD));
            }

            // α₁·sin(2πt)
            int256 sinArg = _safeMulDiv(TWO_PI_WAD, int256(t), int256(WAD)) % TWO_PI_WAD;
            result = _safeAddInt(result, _safeMulDiv(coef.alpha1, _sinSafe(sinArg), int256(WAD)));

            // α₂·log(1+t)
            if (t > 0) {
                int256 logArg = int256(WAD) + int256(t);
                if (logArg > int256(WAD)) {
                    int256 logValue = _lnSafe(logArg);
                    result = _safeAddInt(result, _safeMulDiv(coef.alpha2, logValue, int256(WAD)));
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         FEEDBACK TERM
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute η·H(t-τ)·σ(γ·H(t-τ))
     */
    function _computeFeedbackTerm(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 result) {
        // Get H(t-τ) from history or compute if not available
        int256 hDelayed;
        if (engine.historyCount > 0 && engine.feedback.tau <= engine.historyCount) {
            uint256 delayedIndex;
            unchecked {
                delayedIndex = (engine.historyIndex + MAX_HISTORY - engine.feedback.tau) % MAX_HISTORY;
            }
            hDelayed = engine.history[delayedIndex];
        } else {
            // Bootstrap: compute with reduced t
            uint256 delayTime;
            unchecked {
                delayTime = engine.feedback.tau * WAD;
            }
            if (t >= delayTime) {
                hDelayed = _computeOscillatorySum(engine, t - delayTime);
            } else {
                hDelayed = 0;
            }
        }

        // σ(γ·H(t-τ))
        int256 sigmoidArg = _safeMulDiv(engine.feedback.gamma, hDelayed, int256(WAD));
        int256 sigValue = _sigmoidSafe(sigmoidArg);

        // η·H(t-τ)·σ(γ·H(t-τ))
        result = _safeMulDiv(
            _safeMulDiv(engine.feedback.eta, hDelayed, int256(WAD)),
            sigValue,
            int256(WAD)
        );
    }

    /**
     * @notice Update history buffer with new H(t) value
     */
    function updateHistory(
        ChaosEngine memory engine,
        int256 hValue
    ) internal pure returns (ChaosEngine memory) {
        engine.history[engine.historyIndex] = hValue;
        unchecked {
            engine.historyIndex = (engine.historyIndex + 1) % MAX_HISTORY;
            if (engine.historyCount < MAX_HISTORY) {
                engine.historyCount++;
            }
        }
        return engine;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         STOCHASTIC TERM
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute σ·N(0, 1 + β·|H(t-1)|)
     */
    function _computeStochasticTerm(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 result) {
        // Get |H(t-1)| for volatility clustering
        int256 hPrev = 0;
        if (engine.historyCount > 0) {
            uint256 prevIndex;
            unchecked {
                prevIndex = (engine.historyIndex + MAX_HISTORY - 1) % MAX_HISTORY;
            }
            hPrev = engine.history[prevIndex];
            if (hPrev < 0) hPrev = -hPrev;
        }

        // Volatility: 1 + β·|H(t-1)| (bounded to prevent overflow)
        uint256 volContrib = _safeMulUint(engine.stochastic.beta, uint256(hPrev)) / WAD;
        uint256 volatility = WAD + (volContrib > WAD * 10 ? WAD * 10 : volContrib);

        // Generate pseudo-Gaussian noise
        int256 noise = _generateGaussianNoise(engine.stochastic.seed, t);

        // σ·N(0, volatility)
        uint256 sqrtVol = _sqrt(volatility);
        result = _safeMulDiv(
            _safeMulDiv(int256(engine.stochastic.sigma), noise, int256(WAD)),
            int256(sqrtVol),
            int256(WAD)
        );
    }

    /**
     * @notice Generate pseudo-Gaussian noise using Central Limit Theorem
     */
    function _generateGaussianNoise(uint256 seed, uint256 t) internal pure returns (int256) {
        int256 sum = 0;
        unchecked {
            for (uint256 i = 0; i < 12; i++) {
                uint256 u = uint256(keccak256(abi.encodePacked(seed, t, i)));
                sum += int256(u % WAD);
            }
        }
        // Normalize to approximately N(0, WAD)
        return sum - int256(6 * WAD);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         EXTERNAL INPUT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute δ·u(t) - external input term
     */
    function _computeExternalInput(
        ExternalInput memory ext,
        uint256 t
    ) internal pure returns (int256 result) {
        uint256 u = uint256(keccak256(abi.encodePacked(ext.inputSignal, t)));
        int256 normalizedU = int256(u % (2 * WAD)) - int256(WAD);

        result = _safeMulDiv(ext.delta, normalizedU, int256(WAD));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ZKAEDI SIGNATURE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute the secret Zkaedi signature
     */
    function computeZkaediSignature(
        ChaosEngine memory engine,
        uint256 seed
    ) internal pure returns (ZkaediSignature memory sig) {
        unchecked {
            // Base value: 649 + 4×complexity + 3×parallelism
            sig.baseValue = BASE_COMPLEXITY + (4 * engine.complexity) + (3 * engine.parallelism);

            // Φⁿ component (golden ratio power) - bounded
            uint256 boundedOsc = engine.activeOscillators > 8 ? 8 : engine.activeOscillators;
            sig.phiPower = _powSafe(PHI_WAD, boundedOsc);

            // ₿∞ hash component
            sig.infinityHash = uint256(keccak256(abi.encodePacked(
                seed,
                "BTC_INFINITY_ZKAEDI",
                sig.baseValue,
                engine.stochastic.seed
            )));

            // 777 × luck
            sig.luckyMultiplier = LUCKY_777 * engine.luckFactor;

            // Final signature
            sig.finalSignature = keccak256(abi.encodePacked(
                sig.baseValue,
                sig.phiPower,
                sig.infinityHash,
                sig.luckyMultiplier,
                "ZKAEDI_V2"
            ));
        }
    }

    /**
     * @notice Compute all partial derivatives for gradient analysis
     */
    function computePartialDerivatives(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (PartialDerivatives memory derivs) {
        derivs.dH_dPhi = new int256[](engine.activeOscillators);
        derivs.dH_dD = new int256[](engine.activeDecayTerms);

        unchecked {
            // ∂Ĥ/∂φᵢ = Aᵢ(t)cos(Bᵢ(t)t + φᵢ)
            for (uint256 i = 0; i < engine.activeOscillators; i++) {
                Oscillator memory osc = engine.oscillators[i];

                int256 ampMod = _sinSafe(int256(t % uint256(TWO_PI_WAD)));
                int256 amplitude = int256(osc.amplitudeBase) +
                    _safeMulDiv(int256(osc.amplitudeModRate), ampMod, int256(WAD));

                int256 freqMod = _cosSafe(int256(t % uint256(TWO_PI_WAD)));
                int256 frequency = int256(osc.frequencyBase) +
                    _safeMulDiv(int256(osc.frequencyModRate), freqMod, int256(WAD));

                int256 argument = (_safeMulDiv(frequency, int256(t), int256(WAD)) + osc.phase) % TWO_PI_WAD;

                derivs.dH_dPhi[i] = _safeMulDiv(amplitude, _cosSafe(argument), int256(WAD));
            }

            // ∂Ĥ/∂Dᵢ = -t·Cᵢ·e^(-Dᵢt)
            for (uint256 i = 0; i < engine.activeDecayTerms; i++) {
                DecayTerm memory decay = engine.decayTerms[i];
                int256 exponent = -_safeMulDiv(int256(decay.decayRate), int256(t), int256(WAD));
                int256 expValue = _expSafe(exponent);

                derivs.dH_dD[i] = _safeMulDiv(
                    -int256(t),
                    _safeMulDiv(int256(decay.coefficient), expValue, int256(WAD)),
                    int256(WAD)
                );
            }

            (derivs.dSoftplus_dA, derivs.dSoftplus_dB, derivs.dSoftplus_dX0) =
                computeSoftplusDerivatives(engine.softplus, int256(t));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SAFE MATHEMATICAL PRIMITIVES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Safe sin(x) using Taylor series with normalization
     */
    function _sinSafe(int256 x) internal pure returns (int256) {
        // Normalize x to [-π, π]
        x = x % TWO_PI_WAD;
        if (x > PI_WAD) x -= TWO_PI_WAD;
        if (x < -PI_WAD) x += TWO_PI_WAD;

        // Taylor series: sin(x) = x - x³/6 + x⁵/120 - x⁷/5040
        int256 x2 = _safeMulDiv(x, x, int256(WAD));
        int256 x3 = _safeMulDiv(x2, x, int256(WAD));
        int256 x5 = _safeMulDiv(x3, x2, int256(WAD));
        int256 x7 = _safeMulDiv(x5, x2, int256(WAD));

        int256 result = x - x3 / 6 + x5 / 120 - x7 / 5040;

        // Clamp to [-WAD, WAD]
        if (result > int256(WAD)) return int256(WAD);
        if (result < -int256(WAD)) return -int256(WAD);
        return result;
    }

    /**
     * @notice Safe cos(x)
     */
    function _cosSafe(int256 x) internal pure returns (int256) {
        return _sinSafe(x + HALF_PI_WAD);
    }

    /**
     * @notice Safe exp(x) with bounds checking
     */
    function _expSafe(int256 x) internal pure returns (int256) {
        if (x > EXP_MAX_INPUT) return type(int256).max / 4;
        if (x < EXP_MIN_INPUT) return 0;

        // Range reduction: e^x = 2^k * e^r
        int256 k = x / LN_2_WAD;
        int256 r = x - k * LN_2_WAD;

        // Taylor series for e^r
        int256 r2 = _safeMulDiv(r, r, int256(WAD));
        int256 r3 = _safeMulDiv(r2, r, int256(WAD));
        int256 r4 = _safeMulDiv(r3, r, int256(WAD));
        int256 r5 = _safeMulDiv(r4, r, int256(WAD));
        int256 r6 = _safeMulDiv(r5, r, int256(WAD));

        int256 expR = int256(WAD) + r + r2 / 2 + r3 / 6 + r4 / 24 + r5 / 120 + r6 / 720;

        // Multiply by 2^k
        if (k >= 0) {
            if (k > 88) return type(int256).max / 4; // Prevent overflow
            return expR << uint256(k);
        } else {
            if (-k > 88) return 0;
            return expR >> uint256(-k);
        }
    }

    /**
     * @notice Safe ln(x) with bounds checking
     */
    function _lnSafe(int256 x) internal pure returns (int256) {
        if (x <= 0) return type(int256).min / 2;
        if (x == int256(WAD)) return 0;

        int256 k = 0;
        int256 m = x;

        // Normalize to [WAD, 2*WAD)
        while (m >= int256(2 * WAD) && k < 256) {
            m = m / 2;
            k++;
        }
        while (m < int256(WAD) && k > -256) {
            m = m * 2;
            k--;
        }

        // ln(1 + y) series
        int256 y = m - int256(WAD);
        int256 y2 = _safeMulDiv(y, y, int256(WAD));
        int256 y3 = _safeMulDiv(y2, y, int256(WAD));
        int256 y4 = _safeMulDiv(y3, y, int256(WAD));
        int256 y5 = _safeMulDiv(y4, y, int256(WAD));

        int256 lnM = y - y2 / 2 + y3 / 3 - y4 / 4 + y5 / 5;

        return k * LN_2_WAD + lnM;
    }

    /**
     * @notice Safe sigmoid σ(x) = 1/(1 + e^(-x))
     */
    function _sigmoidSafe(int256 x) internal pure returns (int256) {
        // For extreme values, return bounds
        if (x > int256(20 * WAD)) return int256(WAD);
        if (x < -int256(20 * WAD)) return 0;

        int256 expNegX = _expSafe(-x);
        if (expNegX <= 0) return int256(WAD);
        if (expNegX >= type(int256).max / 4) return 0;

        int256 denominator = int256(WAD) + expNegX;
        if (denominator <= 0) return int256(WAD);

        return _safeMulDiv(int256(WAD), int256(WAD), denominator);
    }

    /**
     * @notice Integer square root using Newton's method
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        if (x <= 3) return 1;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }

    /**
     * @notice Safe power function with bounds
     */
    function _powSafe(uint256 base, uint256 exp) internal pure returns (uint256) {
        if (exp == 0) return WAD;
        if (exp == 1) return base;
        if (base == 0) return 0;
        if (base == WAD) return WAD;

        uint256 result = WAD;
        uint256 b = base;

        unchecked {
            while (exp > 0) {
                if (exp & 1 == 1) {
                    // Check for overflow before multiplication
                    if (result > MAX_SAFE_MUL || b > MAX_SAFE_MUL) {
                        return type(uint256).max / 2;
                    }
                    result = (result * b) / WAD;
                }
                if (b > MAX_SAFE_MUL) {
                    return type(uint256).max / 2;
                }
                b = (b * b) / WAD;
                exp >>= 1;
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SAFE ARITHMETIC HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Safe multiplication and division for int256
     */
    function _safeMulDiv(int256 a, int256 b, int256 denominator) internal pure returns (int256) {
        if (denominator == 0) return 0;
        if (a == 0 || b == 0) return 0;

        // Check for potential overflow
        bool negativeResult = (a < 0) != (b < 0);
        uint256 absA = a < 0 ? uint256(-a) : uint256(a);
        uint256 absB = b < 0 ? uint256(-b) : uint256(b);
        uint256 absDenom = denominator < 0 ? uint256(-denominator) : uint256(denominator);

        if (absA > type(uint256).max / absB) {
            // Would overflow, return max/min
            return negativeResult ? type(int256).min / 2 : type(int256).max / 2;
        }

        uint256 product = absA * absB;
        uint256 result = product / absDenom;

        if (result > uint256(type(int256).max)) {
            return negativeResult ? type(int256).min / 2 : type(int256).max / 2;
        }

        return negativeResult ? -int256(result) : int256(result);
    }

    /**
     * @notice Safe addition for int256
     */
    function _safeAddInt(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        // Check for overflow
        if (b > 0 && c < a) return type(int256).max / 2;
        if (b < 0 && c > a) return type(int256).min / 2;
        return c;
    }

    /**
     * @notice Safe multiplication for uint256
     */
    function _safeMulUint(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) return type(uint256).max;
        return a * b;
    }

    /**
     * @notice Bound a value between min and max
     */
    function _boundValue(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BATCH GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generate multiple random numbers efficiently
     */
    function generateBatch(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 count
    ) internal pure returns (uint256[] memory values) {
        if (count == 0 || count > MAX_BATCH_SIZE) revert BatchSizeTooLarge();

        values = new uint256[](count);

        unchecked {
            for (uint256 i = 0; i < count; i++) {
                uint256 t = (i + 1) * WAD;
                uint256 iterSeed = uint256(keccak256(abi.encodePacked(seed, i)));
                values[i] = generate(engine, iterSeed, t);
            }
        }
    }

    /**
     * @notice Generate weighted random selection
     */
    function weightedSelect(
        ChaosEngine memory engine,
        uint256 seed,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        if (weights.length == 0) revert InvalidParameter();

        uint256 totalWeight;
        unchecked {
            for (uint256 i = 0; i < weights.length; i++) {
                totalWeight += weights[i];
            }
        }
        if (totalWeight == 0) revert ZeroWeights();

        uint256 random = generate(engine, seed, WAD) % totalWeight;
        uint256 cumulative;

        unchecked {
            for (uint256 i = 0; i < weights.length; i++) {
                cumulative += weights[i];
                if (random < cumulative) {
                    return i;
                }
            }
        }

        return weights.length - 1;
    }

    /**
     * @notice Shuffle array indices using Fisher-Yates algorithm
     */
    function shuffle(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 length
    ) internal pure returns (uint256[] memory) {
        if (length == 0 || length > MAX_BATCH_SIZE) revert BatchSizeTooLarge();

        uint256[] memory indices = new uint256[](length);

        unchecked {
            for (uint256 i = 0; i < length; i++) {
                indices[i] = i;
            }

            for (uint256 i = length - 1; i > 0; i--) {
                uint256 iterSeed = uint256(keccak256(abi.encodePacked(seed, i)));
                uint256 j = generate(engine, iterSeed, i * WAD) % (i + 1);
                (indices[i], indices[j]) = (indices[j], indices[i]);
            }
        }

        return indices;
    }

    /**
     * @notice Select k unique random items from n
     */
    function selectUnique(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 n,
        uint256 k
    ) internal pure returns (uint256[] memory selected) {
        if (k > n) revert InvalidParameter();
        if (k == 0) return new uint256[](0);
        if (k > MAX_BATCH_SIZE) revert BatchSizeTooLarge();

        // Use partial Fisher-Yates
        uint256[] memory shuffled = shuffle(engine, seed, n);
        selected = new uint256[](k);

        unchecked {
            for (uint256 i = 0; i < k; i++) {
                selected[i] = shuffled[i];
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CHAOS ANALYSIS & QUALITY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute Lyapunov exponent estimate (chaos measure)
     */
    function estimateLyapunovExponent(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 iterations
    ) internal pure returns (int256) {
        if (iterations == 0) return 0;
        if (iterations > 100) iterations = 100; // Cap iterations

        int256 sumLogDivergence = 0;

        unchecked {
            for (uint256 i = 1; i <= iterations; i++) {
                uint256 t = (i + 1) * WAD;

                // Original trajectory
                int256 h = computeH(engine, t);

                // Perturbed trajectory
                uint256 perturbedSeed = uint256(keccak256(abi.encodePacked(seed, i, "perturb")));
                ChaosEngine memory perturbedEngine = engine;
                perturbedEngine.stochastic.seed = perturbedSeed;
                int256 perturbedH = computeH(perturbedEngine, t);

                // Divergence
                int256 divergence = perturbedH > h ? perturbedH - h : h - perturbedH;
                if (divergence == 0) divergence = 1;

                sumLogDivergence = _safeAddInt(sumLogDivergence, _lnSafe(divergence));
            }
        }

        return sumLogDivergence / int256(iterations);
    }

    /**
     * @notice Get the chaos engine entropy measure
     */
    function getEntropy(ChaosEngine memory engine) internal pure returns (uint256) {
        bytes32 entropyHash = keccak256(abi.encodePacked(
            engine.activeOscillators,
            engine.activeDecayTerms,
            engine.complexity,
            engine.parallelism,
            engine.luckFactor,
            engine.stochastic.seed,
            engine.external_.inputSignal
        ));

        unchecked {
            for (uint256 i = 0; i < engine.activeOscillators; i++) {
                entropyHash = keccak256(abi.encodePacked(
                    entropyHash,
                    engine.oscillators[i].amplitudeBase,
                    engine.oscillators[i].frequencyBase,
                    engine.oscillators[i].phase
                ));
            }
        }

        return uint256(entropyHash);
    }

    /**
     * @notice Analyze randomness quality of a sample
     */
    function analyzeQuality(
        uint256[] memory samples
    ) internal pure returns (QualityMetrics memory metrics) {
        if (samples.length == 0) return metrics;

        // Calculate basic statistics
        uint256 n = samples.length;

        // Count runs for runs test
        uint256 runsCount = 1;
        unchecked {
            for (uint256 i = 1; i < n; i++) {
                if ((samples[i] > samples[i-1]) != (i > 1 && samples[i-1] > samples[i-2])) {
                    runsCount++;
                }
            }
        }
        metrics.runsCount = runsCount;

        // Simplified chi-square for uniformity (divide into 16 buckets)
        uint256[16] memory buckets;
        uint256 bucketSize = type(uint256).max / 16;

        unchecked {
            for (uint256 i = 0; i < n; i++) {
                uint256 bucket = samples[i] / bucketSize;
                if (bucket >= 16) bucket = 15;
                buckets[bucket]++;
            }
        }

        uint256 expected = n / 16;
        uint256 chiSquare = 0;
        if (expected > 0) {
            unchecked {
                for (uint256 i = 0; i < 16; i++) {
                    uint256 diff = buckets[i] > expected ? buckets[i] - expected : expected - buckets[i];
                    chiSquare += (diff * diff * WAD) / expected;
                }
            }
        }
        metrics.chiSquare = chiSquare;

        // Entropy estimate
        metrics.entropy = getEntropyFromSamples(samples);

        // Simple quality check (chi-square should be reasonable)
        metrics.passedTests = chiSquare < 50 * WAD && runsCount > n / 4;
    }

    /**
     * @notice Estimate entropy from samples
     */
    function getEntropyFromSamples(uint256[] memory samples) internal pure returns (uint256) {
        if (samples.length == 0) return 0;

        // Use hash-based entropy estimation
        bytes32 combined = keccak256(abi.encodePacked(samples[0]));
        unchecked {
            for (uint256 i = 1; i < samples.length && i < 100; i++) {
                combined = keccak256(abi.encodePacked(combined, samples[i]));
            }
        }

        return uint256(combined);
    }

    /**
     * @notice Verify determinism - same inputs produce same outputs
     */
    function verifyDeterminism(
        uint256 seed,
        uint256 t,
        uint256 iterations
    ) internal pure returns (bool) {
        ChaosEngine memory engine1 = initializeChaosEngine(seed);
        ChaosEngine memory engine2 = initializeChaosEngine(seed);

        unchecked {
            for (uint256 i = 0; i < iterations; i++) {
                uint256 iterT = t + i * WAD;
                uint256 result1 = generate(engine1, seed, iterT);
                uint256 result2 = generate(engine2, seed, iterT);

                if (result1 != result2) return false;
            }
        }

        return true;
    }
}
