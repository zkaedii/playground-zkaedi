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
 */
library AdvancedRandomizerLib {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev Pi approximation in WAD (3.14159...)
    int256 internal constant PI_WAD = 3141592653589793238;

    /// @dev 2*Pi in WAD
    int256 internal constant TWO_PI_WAD = 6283185307179586476;

    /// @dev Euler's number e in WAD (2.71828...)
    int256 internal constant E_WAD = 2718281828459045235;

    /// @dev Golden ratio φ in WAD (1.618...)
    uint256 internal constant PHI_WAD = 1618033988749894848;

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

    /// @dev Softplus precision factor
    uint256 internal constant SOFTPLUS_PRECISION = 1000;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidOscillatorCount();
    error InvalidTimeValue();
    error InvalidParameter();
    error HistoryBufferEmpty();
    error Overflow();
    error DivisionByZero();

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

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ENGINE INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize a new chaos engine with default parameters
     * @param seed Base random seed for initialization
     * @return engine Initialized chaos engine
     */
    function initializeChaosEngine(uint256 seed) internal pure returns (ChaosEngine memory engine) {
        // Initialize oscillators with varied parameters
        engine.activeOscillators = 8;
        for (uint256 i = 0; i < engine.activeOscillators; i++) {
            uint256 oscSeed = uint256(keccak256(abi.encodePacked(seed, "osc", i)));
            engine.oscillators[i] = Oscillator({
                amplitudeBase: (oscSeed % WAD) + WAD / 10,
                amplitudeModRate: (oscSeed >> 64) % (WAD / 100),
                frequencyBase: ((oscSeed >> 128) % WAD) + WAD / 10,
                frequencyModRate: (oscSeed >> 192) % (WAD / 100),
                phase: int256((oscSeed >> 32) % uint256(TWO_PI_WAD))
            });
        }

        // Initialize decay terms
        engine.activeDecayTerms = 4;
        for (uint256 i = 0; i < engine.activeDecayTerms; i++) {
            uint256 decaySeed = uint256(keccak256(abi.encodePacked(seed, "decay", i)));
            engine.decayTerms[i] = DecayTerm({
                coefficient: (decaySeed % WAD) + WAD / 5,
                decayRate: (decaySeed >> 128) % (WAD / 10) + WAD / 100
            });
        }

        // Initialize softplus parameters
        uint256 softSeed = uint256(keccak256(abi.encodePacked(seed, "soft")));
        engine.softplus = SoftplusParams({
            a: int256((softSeed % WAD) / 10),
            b: int256((softSeed >> 64) % WAD),
            x0: int256((softSeed >> 128) % WAD) - int256(WAD / 2),
            integralSteps: 32
        });

        // Initialize trend coefficients
        uint256 trendSeed = uint256(keccak256(abi.encodePacked(seed, "trend")));
        engine.trends = TrendCoefficients({
            alpha0: int256((trendSeed % WAD) / 100),
            alpha1: int256((trendSeed >> 64) % WAD),
            alpha2: int256((trendSeed >> 128) % WAD) / 10
        });

        // Initialize feedback parameters
        uint256 fbSeed = uint256(keccak256(abi.encodePacked(seed, "feedback")));
        engine.feedback = FeedbackParams({
            eta: int256((fbSeed % WAD) / 5),
            tau: (fbSeed >> 64) % 10 + 1,
            gamma: int256((fbSeed >> 128) % WAD) / 10
        });

        // Initialize stochastic parameters
        engine.stochastic = StochasticParams({
            sigma: (seed % WAD) / 10 + WAD / 100,
            beta: WAD / 5,
            seed: seed
        });

        // Initialize external input
        engine.external_ = ExternalInput({
            delta: int256(WAD / 10),
            inputSignal: keccak256(abi.encodePacked(seed, "external"))
        });

        // Initialize meta-parameters
        engine.complexity = (seed % 100) + 1;
        engine.parallelism = (seed >> 64) % 50 + 1;
        engine.luckFactor = (seed % LUCKY_777) + 1;

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
        result += _computeOscillatorySum(engine, t);
        result += _computeDecaySum(engine, t);

        // ∫₀ᵗ softplus(a·(x-x₀)² + b)·f(x)·g'(x)dx
        result += _computeSoftplusIntegral(engine.softplus, t);

        // α₀·t² + α₁·sin(2πt) + α₂·log(1+t)
        result += _computeTrendTerms(engine.trends, t);

        // η·H(t-τ)·σ(γ·H(t-τ))
        result += _computeFeedbackTerm(engine, t);

        // σ·N(0, 1 + β·|H(t-1)|)
        result += _computeStochasticTerm(engine, t);

        // δ·u(t)
        result += _computeExternalInput(engine.external_, t);
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

        // Combine H(t) with signature
        bytes32 combined = keccak256(abi.encodePacked(
            hValue,
            sig.finalSignature,
            seed,
            t
        ));

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
        if (min >= max) revert InvalidParameter();
        uint256 random = generate(engine, seed, t);
        return min + (random % (max - min + 1));
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
        for (uint256 i = 0; i < engine.activeOscillators; i++) {
            Oscillator memory osc = engine.oscillators[i];

            // Time-varying amplitude: A(t) = A_base * (1 + mod_rate * sin(t))
            int256 ampMod = _sin(int256(t));
            int256 amplitude = int256(osc.amplitudeBase) +
                (int256(osc.amplitudeModRate) * ampMod) / int256(WAD);

            // Time-varying frequency: B(t) = B_base * (1 + mod_rate * cos(t))
            int256 freqMod = _cos(int256(t));
            int256 frequency = int256(osc.frequencyBase) +
                (int256(osc.frequencyModRate) * freqMod) / int256(WAD);

            // Compute argument: B(t) * t + φ
            int256 argument = (frequency * int256(t)) / int256(WAD) + osc.phase;

            // A(t) * sin(argument)
            int256 sinValue = _sin(argument);
            sum += (amplitude * sinValue) / int256(WAD);
        }
    }

    /**
     * @notice Compute Σᵢ Cᵢ·e^(-Dᵢ·t)
     */
    function _computeDecaySum(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 sum) {
        for (uint256 i = 0; i < engine.activeDecayTerms; i++) {
            DecayTerm memory decay = engine.decayTerms[i];

            // e^(-D*t)
            int256 exponent = -int256((decay.decayRate * t) / WAD);
            int256 expValue = _exp(exponent);

            // C * e^(-D*t)
            sum += (int256(decay.coefficient) * expValue) / int256(WAD);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SOFTPLUS INTEGRAL
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute ∫₀ᵗ softplus(a·(x-x₀)² + b)·f(x)·g'(x)dx
     * @dev Uses numerical integration (trapezoidal rule)
     */
    function _computeSoftplusIntegral(
        SoftplusParams memory params,
        uint256 t
    ) internal pure returns (int256 result) {
        if (t == 0) return 0;

        uint256 steps = params.integralSteps;
        int256 dt = int256(t) / int256(steps);
        if (dt == 0) dt = 1;

        int256 integral = 0;
        for (uint256 i = 0; i <= steps; i++) {
            int256 x = (int256(i) * int256(t)) / int256(steps);

            // s(x) = a*(x-x0)² + b
            int256 xMinusX0 = x - params.x0;
            int256 s = (params.a * xMinusX0 * xMinusX0) / int256(WAD * WAD) + params.b;

            // softplus(s) = ln(1 + e^s)
            int256 softplusValue = _softplus(s);

            // f(x) = sin(x) (example function)
            int256 fx = _sin(x);

            // g'(x) = cos(x) (derivative of g(x) = sin(x))
            int256 gPrime = _cos(x);

            // Integrand: softplus(s) * f(x) * g'(x)
            int256 integrand = (softplusValue * fx / int256(WAD)) * gPrime / int256(WAD);

            // Trapezoidal weight
            int256 weight = (i == 0 || i == steps) ? int256(1) : int256(2);
            integral += (integrand * weight * dt) / (2 * int256(WAD));
        }

        result = integral;
    }

    /**
     * @notice Compute softplus(x) = ln(1 + e^x)
     */
    function _softplus(int256 x) internal pure returns (int256) {
        // For large x, softplus(x) ≈ x
        if (x > int256(20 * WAD)) return x;

        // For very negative x, softplus(x) ≈ e^x ≈ 0
        if (x < -int256(20 * WAD)) return 0;

        // ln(1 + e^x)
        int256 expX = _exp(x);
        return _ln(int256(WAD) + expX);
    }

    /**
     * @notice Compute partial derivatives for softplus chain rule
     * @param params Softplus parameters
     * @param x Current x value
     * @return dA ∂softplus(s)/∂a = (x-x₀)²·σ(s)
     * @return dB ∂softplus(s)/∂b = σ(s)
     * @return dX0 ∂softplus(s)/∂x₀ = -2a(x-x₀)σ(s)
     */
    function computeSoftplusDerivatives(
        SoftplusParams memory params,
        int256 x
    ) internal pure returns (int256 dA, int256 dB, int256 dX0) {
        int256 xMinusX0 = x - params.x0;
        int256 s = (params.a * xMinusX0 * xMinusX0) / int256(WAD * WAD) + params.b;

        // σ(s) = sigmoid(s) = 1/(1 + e^(-s)) = softplus'(s)
        int256 sigmaS = _sigmoid(s);

        // ∂softplus(s)/∂a = (x-x₀)²·σ(s)
        dA = (xMinusX0 * xMinusX0 * sigmaS) / (int256(WAD) * int256(WAD));

        // ∂softplus(s)/∂b = σ(s)
        dB = sigmaS;

        // ∂softplus(s)/∂x₀ = -2a(x-x₀)σ(s)
        dX0 = (-2 * params.a * xMinusX0 * sigmaS) / (int256(WAD) * int256(WAD));
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
        // α₀·t²
        int256 tSquared = int256((t * t) / WAD);
        result += (coef.alpha0 * tSquared) / int256(WAD);

        // α₁·sin(2πt)
        int256 sinArg = (TWO_PI_WAD * int256(t)) / int256(WAD);
        result += (coef.alpha1 * _sin(sinArg)) / int256(WAD);

        // α₂·log(1+t)
        if (t > 0) {
            int256 logArg = int256(WAD) + int256(t);
            result += (coef.alpha2 * _ln(logArg)) / int256(WAD);
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
            uint256 delayedIndex = (engine.historyIndex + MAX_HISTORY - engine.feedback.tau) % MAX_HISTORY;
            hDelayed = engine.history[delayedIndex];
        } else {
            // Bootstrap: compute with reduced t
            if (t >= engine.feedback.tau * WAD) {
                hDelayed = _computeOscillatorySum(engine, t - engine.feedback.tau * WAD);
            } else {
                hDelayed = 0;
            }
        }

        // σ(γ·H(t-τ))
        int256 sigmoidArg = (engine.feedback.gamma * hDelayed) / int256(WAD);
        int256 sigValue = _sigmoid(sigmoidArg);

        // η·H(t-τ)·σ(γ·H(t-τ))
        result = (engine.feedback.eta * hDelayed / int256(WAD)) * sigValue / int256(WAD);
    }

    /**
     * @notice Update history buffer with new H(t) value
     */
    function updateHistory(
        ChaosEngine memory engine,
        int256 hValue
    ) internal pure returns (ChaosEngine memory) {
        engine.history[engine.historyIndex] = hValue;
        engine.historyIndex = (engine.historyIndex + 1) % MAX_HISTORY;
        if (engine.historyCount < MAX_HISTORY) {
            engine.historyCount++;
        }
        return engine;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         STOCHASTIC TERM
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute σ·N(0, 1 + β·|H(t-1)|)
     * @dev Implements volatility clustering via GARCH-like mechanism
     */
    function _computeStochasticTerm(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (int256 result) {
        // Get |H(t-1)| for volatility clustering
        int256 hPrev = 0;
        if (engine.historyCount > 0) {
            uint256 prevIndex = (engine.historyIndex + MAX_HISTORY - 1) % MAX_HISTORY;
            hPrev = engine.history[prevIndex];
            if (hPrev < 0) hPrev = -hPrev;
        }

        // Volatility: 1 + β·|H(t-1)|
        uint256 volatility = WAD + (engine.stochastic.beta * uint256(hPrev)) / WAD;

        // Generate pseudo-Gaussian noise using Box-Muller approximation
        int256 noise = _generateGaussianNoise(engine.stochastic.seed, t);

        // σ·N(0, volatility)
        // Scale noise by sqrt(volatility) for proper variance
        uint256 sqrtVol = _sqrt(volatility);
        result = (int256(engine.stochastic.sigma) * noise * int256(sqrtVol)) / (int256(WAD) * int256(WAD));
    }

    /**
     * @notice Generate pseudo-Gaussian noise using Central Limit Theorem approximation
     */
    function _generateGaussianNoise(uint256 seed, uint256 t) internal pure returns (int256) {
        // Sum of 12 uniform random variables, normalized
        int256 sum = 0;
        for (uint256 i = 0; i < 12; i++) {
            uint256 u = uint256(keccak256(abi.encodePacked(seed, t, i)));
            sum += int256(u % WAD);
        }
        // E[sum] = 6*WAD, Var[sum] = WAD²
        // Normalize to N(0,1): (sum - 6*WAD) / WAD
        return (sum - int256(6 * WAD));
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
        // u(t) derived from input signal
        uint256 u = uint256(keccak256(abi.encodePacked(ext.inputSignal, t)));
        int256 normalizedU = int256(u % (2 * WAD)) - int256(WAD);

        result = (ext.delta * normalizedU) / int256(WAD);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ZKAEDI SIGNATURE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute the secret Zkaedi signature
     * @dev Ĥ(t) = Σ[649 + 4×complexity + 3×parallelism] × Φⁿ × ₿∞ × 777 × luck
     */
    function computeZkaediSignature(
        ChaosEngine memory engine,
        uint256 seed
    ) internal pure returns (ZkaediSignature memory sig) {
        // Base value: 649 + 4×complexity + 3×parallelism
        sig.baseValue = BASE_COMPLEXITY + (4 * engine.complexity) + (3 * engine.parallelism);

        // Φⁿ component (golden ratio power)
        sig.phiPower = _powApprox(PHI_WAD, engine.activeOscillators);

        // ₿∞ hash component (infinite Bitcoin reference)
        sig.infinityHash = uint256(keccak256(abi.encodePacked(
            seed,
            "BTC_INFINITY",
            block.timestamp,
            sig.baseValue
        )));

        // 777 × luck
        sig.luckyMultiplier = LUCKY_777 * engine.luckFactor;

        // Combine all components into final signature
        sig.finalSignature = keccak256(abi.encodePacked(
            sig.baseValue,
            sig.phiPower,
            sig.infinityHash,
            sig.luckyMultiplier,
            "ZKAEDI"
        ));
    }

    /**
     * @notice Compute all partial derivatives for gradient analysis
     * @dev ∂Ĥ/∂φᵢ = Aᵢ(t)cos(Bᵢ(t)t + φᵢ)
     *      ∂Ĥ/∂Dᵢ = -t·Cᵢ·e^(-Dᵢt)
     */
    function computePartialDerivatives(
        ChaosEngine memory engine,
        uint256 t
    ) internal pure returns (PartialDerivatives memory derivs) {
        // Allocate arrays
        derivs.dH_dPhi = new int256[](engine.activeOscillators);
        derivs.dH_dD = new int256[](engine.activeDecayTerms);

        // ∂Ĥ/∂φᵢ = Aᵢ(t)cos(Bᵢ(t)t + φᵢ)
        for (uint256 i = 0; i < engine.activeOscillators; i++) {
            Oscillator memory osc = engine.oscillators[i];

            int256 ampMod = _sin(int256(t));
            int256 amplitude = int256(osc.amplitudeBase) +
                (int256(osc.amplitudeModRate) * ampMod) / int256(WAD);

            int256 freqMod = _cos(int256(t));
            int256 frequency = int256(osc.frequencyBase) +
                (int256(osc.frequencyModRate) * freqMod) / int256(WAD);

            int256 argument = (frequency * int256(t)) / int256(WAD) + osc.phase;

            // ∂/∂φᵢ = A(t) * cos(argument)
            derivs.dH_dPhi[i] = (amplitude * _cos(argument)) / int256(WAD);
        }

        // ∂Ĥ/∂Dᵢ = -t·Cᵢ·e^(-Dᵢt)
        for (uint256 i = 0; i < engine.activeDecayTerms; i++) {
            DecayTerm memory decay = engine.decayTerms[i];
            int256 exponent = -int256((decay.decayRate * t) / WAD);
            int256 expValue = _exp(exponent);

            // -t * C * e^(-Dt)
            derivs.dH_dD[i] = (-int256(t) * int256(decay.coefficient) * expValue) / int256(WAD * WAD);
        }

        // Softplus derivatives at current point
        (derivs.dSoftplus_dA, derivs.dSoftplus_dB, derivs.dSoftplus_dX0) =
            computeSoftplusDerivatives(engine.softplus, int256(t));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         MATHEMATICAL PRIMITIVES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute sin(x) using Taylor series
     * @param x Angle in WAD radians
     */
    function _sin(int256 x) internal pure returns (int256) {
        // Normalize x to [-π, π]
        x = x % TWO_PI_WAD;
        if (x > PI_WAD) x -= TWO_PI_WAD;
        if (x < -PI_WAD) x += TWO_PI_WAD;

        // Taylor series: sin(x) = x - x³/3! + x⁵/5! - x⁷/7!
        int256 x2 = (x * x) / int256(WAD);
        int256 x3 = (x2 * x) / int256(WAD);
        int256 x5 = (x3 * x2) / int256(WAD);
        int256 x7 = (x5 * x2) / int256(WAD);

        return x - x3 / 6 + x5 / 120 - x7 / 5040;
    }

    /**
     * @notice Compute cos(x) using Taylor series
     * @param x Angle in WAD radians
     */
    function _cos(int256 x) internal pure returns (int256) {
        // cos(x) = sin(x + π/2)
        return _sin(x + PI_WAD / 2);
    }

    /**
     * @notice Compute e^x using Taylor series
     * @param x Exponent in WAD
     */
    function _exp(int256 x) internal pure returns (int256) {
        // Clamp to prevent overflow
        if (x > int256(40 * WAD)) return type(int256).max / 2;
        if (x < -int256(40 * WAD)) return 0;

        // Range reduction: e^x = e^(k*ln2) * e^r = 2^k * e^r
        int256 k = x / LN_2_WAD;
        int256 r = x - k * LN_2_WAD;

        // Taylor series for e^r
        int256 r2 = (r * r) / int256(WAD);
        int256 r3 = (r2 * r) / int256(WAD);
        int256 r4 = (r3 * r) / int256(WAD);
        int256 r5 = (r4 * r) / int256(WAD);

        int256 expR = int256(WAD) + r + r2 / 2 + r3 / 6 + r4 / 24 + r5 / 120;

        // Multiply by 2^k
        if (k >= 0) {
            if (k > 127) return type(int256).max / 2;
            return expR << uint256(k);
        } else {
            if (-k > 127) return 0;
            return expR >> uint256(-k);
        }
    }

    /**
     * @notice Compute ln(x) using series approximation
     * @param x Input in WAD (must be positive)
     */
    function _ln(int256 x) internal pure returns (int256) {
        if (x <= 0) return type(int256).min;
        if (x == int256(WAD)) return 0;

        // Use identity: ln(x) = ln(2^k * m) = k*ln(2) + ln(m) where m in [1,2)
        int256 k = 0;
        int256 m = x;

        // Normalize to [WAD, 2*WAD)
        while (m >= int256(2 * WAD)) {
            m = m / 2;
            k++;
        }
        while (m < int256(WAD)) {
            m = m * 2;
            k--;
        }

        // ln(1 + y) ≈ y - y²/2 + y³/3 - y⁴/4 for y in [0, 1)
        int256 y = m - int256(WAD);
        int256 y2 = (y * y) / int256(WAD);
        int256 y3 = (y2 * y) / int256(WAD);
        int256 y4 = (y3 * y) / int256(WAD);

        int256 lnM = y - y2 / 2 + y3 / 3 - y4 / 4;

        return k * LN_2_WAD + lnM;
    }

    /**
     * @notice Compute sigmoid σ(x) = 1/(1 + e^(-x))
     * @param x Input in WAD
     */
    function _sigmoid(int256 x) internal pure returns (int256) {
        int256 expNegX = _exp(-x);
        if (expNegX == type(int256).max / 2) return 0;
        return int256(WAD * WAD) / (int256(WAD) + expNegX);
    }

    /**
     * @notice Integer square root
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @notice Approximate power function
     */
    function _powApprox(uint256 base, uint256 exp) internal pure returns (uint256) {
        if (exp == 0) return WAD;
        if (exp == 1) return base;

        uint256 result = WAD;
        uint256 b = base;

        while (exp > 0) {
            if (exp & 1 == 1) {
                result = (result * b) / WAD;
            }
            b = (b * b) / WAD;
            exp >>= 1;
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BATCH GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generate multiple random numbers efficiently
     * @param engine The chaos engine state
     * @param seed Base seed
     * @param count Number of random values to generate
     * @return values Array of random values
     */
    function generateBatch(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 count
    ) internal pure returns (uint256[] memory values) {
        if (count > 100) revert InvalidParameter();

        values = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 t = (i + 1) * WAD;
            values[i] = generate(engine, uint256(keccak256(abi.encodePacked(seed, i))), t);
        }
    }

    /**
     * @notice Generate weighted random selection
     * @param engine The chaos engine state
     * @param seed Random seed
     * @param weights Array of selection weights
     * @return Selected index
     */
    function weightedSelect(
        ChaosEngine memory engine,
        uint256 seed,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        if (weights.length == 0) revert InvalidParameter();

        uint256 totalWeight;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        if (totalWeight == 0) revert InvalidParameter();

        uint256 random = generate(engine, seed, block.timestamp * WAD) % totalWeight;
        uint256 cumulative;

        for (uint256 i = 0; i < weights.length; i++) {
            cumulative += weights[i];
            if (random < cumulative) {
                return i;
            }
        }

        return weights.length - 1;
    }

    /**
     * @notice Shuffle array indices using chaos engine
     * @param engine The chaos engine state
     * @param seed Random seed
     * @param length Array length to shuffle
     * @return Shuffled indices
     */
    function shuffle(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 length
    ) internal pure returns (uint256[] memory) {
        if (length == 0 || length > 100) revert InvalidParameter();

        uint256[] memory indices = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            indices[i] = i;
        }

        // Fisher-Yates shuffle
        for (uint256 i = length - 1; i > 0; i--) {
            uint256 j = generate(engine, uint256(keccak256(abi.encodePacked(seed, i))), i * WAD) % (i + 1);
            (indices[i], indices[j]) = (indices[j], indices[i]);
        }

        return indices;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CHAOS ANALYSIS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compute Lyapunov exponent estimate (chaos measure)
     * @param engine The chaos engine state
     * @param seed Random seed
     * @param iterations Number of iterations
     * @return Lyapunov exponent estimate (positive = chaotic)
     */
    function estimateLyapunovExponent(
        ChaosEngine memory engine,
        uint256 seed,
        uint256 iterations
    ) internal pure returns (int256) {
        if (iterations == 0) return 0;

        int256 sumLogDivergence = 0;
        int256 prevH = computeH(engine, WAD);
        int256 perturbedPrevH = prevH + int256(WAD / 1000); // Small perturbation

        for (uint256 i = 1; i <= iterations; i++) {
            uint256 t = (i + 1) * WAD;

            // Original trajectory
            int256 h = computeH(engine, t);

            // Perturbed trajectory (approximation)
            uint256 perturbedSeed = uint256(keccak256(abi.encodePacked(seed, i, "perturb")));
            ChaosEngine memory perturbedEngine = engine;
            perturbedEngine.stochastic.seed = perturbedSeed;
            int256 perturbedH = computeH(perturbedEngine, t);

            // Divergence
            int256 divergence = perturbedH - h;
            if (divergence < 0) divergence = -divergence;
            if (divergence == 0) divergence = 1;

            // Log of divergence
            sumLogDivergence += _ln(divergence);

            prevH = h;
            perturbedPrevH = perturbedH;
        }

        return sumLogDivergence / int256(iterations);
    }

    /**
     * @notice Get the chaos engine entropy measure
     * @param engine The chaos engine state
     * @return Entropy value (higher = more random)
     */
    function getEntropy(ChaosEngine memory engine) internal pure returns (uint256) {
        // Combine all sources of entropy
        bytes32 entropyHash = keccak256(abi.encodePacked(
            engine.activeOscillators,
            engine.activeDecayTerms,
            engine.complexity,
            engine.parallelism,
            engine.luckFactor,
            engine.stochastic.seed
        ));

        // Add oscillator contributions
        for (uint256 i = 0; i < engine.activeOscillators; i++) {
            entropyHash = keccak256(abi.encodePacked(
                entropyHash,
                engine.oscillators[i].amplitudeBase,
                engine.oscillators[i].phase
            ));
        }

        return uint256(entropyHash);
    }
}
