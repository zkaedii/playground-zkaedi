// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title QuantumLib
 * @notice Quantum-inspired algorithms and probabilistic utilities
 * @dev Implements quantum-inspired randomness, superposition states, entanglement simulation,
 *      and quantum-inspired optimization patterns for on-chain applications
 */
library QuantumLib {
    // ============ CONSTANTS ============

    /// @notice Fixed-point precision (1000 = 1.0)
    uint256 internal constant PRECISION = 1000;

    /// @notice Maximum probability (100%)
    uint256 internal constant MAX_PROBABILITY = 1000;

    /// @notice Pi approximation scaled by 1000
    uint256 internal constant PI_SCALED = 3142;

    /// @notice Euler's number approximation scaled by 1000
    uint256 internal constant E_SCALED = 2718;

    /// @notice Golden ratio scaled by 1000
    uint256 internal constant PHI_SCALED = 1618;

    // ============ TYPES ============

    /// @notice Quantum state representation (amplitude-like probabilities)
    struct QuantumState {
        uint256[] amplitudes;    // Probability amplitudes (scaled by PRECISION)
        uint256 numStates;       // Number of basis states
        uint256 entropy;         // Entropy measure
    }

    /// @notice Qubit-like state with probability amplitudes
    struct Qubit {
        uint256 alpha;           // |0⟩ amplitude squared (probability, scaled by PRECISION)
        uint256 beta;            // |1⟩ amplitude squared (probability, scaled by PRECISION)
        bool measured;           // Whether state has been measured/collapsed
        bool value;              // Measured value (only valid if measured)
    }

    /// @notice Entangled pair state
    struct EntangledPair {
        bytes32 pairId;          // Unique identifier for the pair
        uint256 correlation;     // Correlation strength (0-1000)
        bool isEntangled;        // Whether pair is still entangled
    }

    /// @notice Quantum walk state for optimization
    struct QuantumWalk {
        uint256 position;        // Current position
        uint256 coin;            // Coin state for walk
        uint256 steps;           // Number of steps taken
        uint256 dimension;       // Walk dimension
    }

    /// @notice Grover-inspired search result
    struct GroverResult {
        uint256 index;           // Found index
        uint256 iterations;      // Iterations performed
        uint256 confidence;      // Confidence level (0-1000)
    }

    // ============ ERRORS ============

    error InvalidProbability();
    error StateAlreadyMeasured();
    error InvalidStateCount();
    error EntanglementBroken();
    error InvalidAmplitudes();

    // ============ QUANTUM STATE CREATION ============

    /**
     * @notice Create a superposition state with equal probabilities
     * @param numStates Number of basis states
     * @param seed Random seed for initial state
     * @return Quantum state in equal superposition
     */
    function createSuperposition(uint256 numStates, uint256 seed) internal pure returns (QuantumState memory) {
        if (numStates == 0 || numStates > 256) revert InvalidStateCount();

        uint256[] memory amps = new uint256[](numStates);
        uint256 equalProb = PRECISION / numStates;
        uint256 remainder = PRECISION % numStates;

        for (uint256 i = 0; i < numStates; i++) {
            amps[i] = equalProb + (i < remainder ? 1 : 0);
        }

        // Calculate entropy
        uint256 entropy = _calculateEntropy(numStates, seed);

        return QuantumState({
            amplitudes: amps,
            numStates: numStates,
            entropy: entropy
        });
    }

    /**
     * @notice Create a biased superposition state
     * @param weights Array of probability weights
     * @param seed Random seed
     * @return Quantum state with weighted probabilities
     */
    function createWeightedSuperposition(uint256[] memory weights, uint256 seed)
        internal
        pure
        returns (QuantumState memory)
    {
        if (weights.length == 0 || weights.length > 256) revert InvalidStateCount();

        uint256 totalWeight;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }

        if (totalWeight == 0) revert InvalidAmplitudes();

        uint256[] memory amps = new uint256[](weights.length);
        for (uint256 i = 0; i < weights.length; i++) {
            amps[i] = (weights[i] * PRECISION) / totalWeight;
        }

        return QuantumState({
            amplitudes: amps,
            numStates: weights.length,
            entropy: _calculateEntropy(weights.length, seed)
        });
    }

    /**
     * @notice Create a qubit in a specific state
     * @param alpha Probability of |0⟩ state (0-1000)
     * @return Initialized qubit
     */
    function createQubit(uint256 alpha) internal pure returns (Qubit memory) {
        if (alpha > PRECISION) revert InvalidProbability();

        return Qubit({
            alpha: alpha,
            beta: PRECISION - alpha,
            measured: false,
            value: false
        });
    }

    /**
     * @notice Create a qubit in the |+⟩ state (equal superposition)
     * @return Qubit in superposition
     */
    function createPlusState() internal pure returns (Qubit memory) {
        return createQubit(500); // 50% each
    }

    /**
     * @notice Create a qubit in the |−⟩ state (equal superposition with phase)
     * @return Qubit with phase difference marker
     */
    function createMinusState() internal pure returns (Qubit memory) {
        // Same probabilities as |+⟩, different phase (represented via entropy)
        return createQubit(500);
    }

    // ============ QUANTUM OPERATIONS ============

    /**
     * @notice Apply Hadamard-like transformation to a qubit
     * @param q Qubit to transform
     * @return Transformed qubit
     */
    function hadamard(Qubit memory q) internal pure returns (Qubit memory) {
        if (q.measured) revert StateAlreadyMeasured();

        // H|0⟩ = |+⟩, H|1⟩ = |−⟩
        // For mixed state: creates superposition
        uint256 newAlpha = (q.alpha + q.beta) / 2;
        uint256 newBeta = PRECISION - newAlpha;

        return Qubit({
            alpha: newAlpha,
            beta: newBeta,
            measured: false,
            value: false
        });
    }

    /**
     * @notice Apply Pauli-X (NOT) gate to qubit
     * @param q Qubit to transform
     * @return Transformed qubit with swapped amplitudes
     */
    function pauliX(Qubit memory q) internal pure returns (Qubit memory) {
        if (q.measured) revert StateAlreadyMeasured();

        return Qubit({
            alpha: q.beta,
            beta: q.alpha,
            measured: false,
            value: false
        });
    }

    /**
     * @notice Apply phase rotation to qubit (simulated)
     * @param q Qubit to rotate
     * @param angle Rotation angle (0-360, scaled by 10)
     * @return Qubit with rotated phase
     */
    function phaseRotate(Qubit memory q, uint256 angle) internal pure returns (Qubit memory) {
        if (q.measured) revert StateAlreadyMeasured();

        // Simulate phase rotation effect on probabilities
        uint256 factor = _cos(angle);
        uint256 newAlpha = (q.alpha * factor) / PRECISION;
        if (newAlpha > PRECISION) newAlpha = PRECISION;

        return Qubit({
            alpha: newAlpha,
            beta: PRECISION - newAlpha,
            measured: false,
            value: false
        });
    }

    /**
     * @notice Apply amplitude amplification (Grover-like)
     * @param state Quantum state to amplify
     * @param targetIndex Index to amplify
     * @param iterations Number of amplification iterations
     * @return Amplified quantum state
     */
    function amplitudeAmplify(
        QuantumState memory state,
        uint256 targetIndex,
        uint256 iterations
    ) internal pure returns (QuantumState memory) {
        if (targetIndex >= state.numStates) revert InvalidStateCount();

        uint256[] memory newAmps = new uint256[](state.numStates);

        // Copy initial amplitudes
        for (uint256 i = 0; i < state.numStates; i++) {
            newAmps[i] = state.amplitudes[i];
        }

        // Perform amplitude amplification iterations
        for (uint256 iter = 0; iter < iterations; iter++) {
            // Calculate mean amplitude
            uint256 mean = 0;
            for (uint256 i = 0; i < state.numStates; i++) {
                mean += newAmps[i];
            }
            mean = mean / state.numStates;

            // Inversion about mean (Grover diffusion)
            for (uint256 i = 0; i < state.numStates; i++) {
                if (i == targetIndex) {
                    // Boost target amplitude
                    newAmps[i] = newAmps[i] + (mean * 2) / state.numStates;
                    if (newAmps[i] > PRECISION) newAmps[i] = PRECISION;
                } else {
                    // Reduce other amplitudes
                    if (newAmps[i] > mean / state.numStates) {
                        newAmps[i] = newAmps[i] - mean / (state.numStates * 2);
                    }
                }
            }

            // Renormalize
            uint256 total = 0;
            for (uint256 i = 0; i < state.numStates; i++) {
                total += newAmps[i];
            }
            if (total > 0) {
                for (uint256 i = 0; i < state.numStates; i++) {
                    newAmps[i] = (newAmps[i] * PRECISION) / total;
                }
            }
        }

        return QuantumState({
            amplitudes: newAmps,
            numStates: state.numStates,
            entropy: state.entropy
        });
    }

    // ============ MEASUREMENT ============

    /**
     * @notice Measure a quantum state (collapse to classical)
     * @param state Quantum state to measure
     * @param randomSeed Source of randomness
     * @return Measured state index
     */
    function measure(QuantumState memory state, uint256 randomSeed) internal pure returns (uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(randomSeed, state.entropy))) % PRECISION;

        uint256 cumulative = 0;
        for (uint256 i = 0; i < state.numStates; i++) {
            cumulative += state.amplitudes[i];
            if (rand < cumulative) {
                return i;
            }
        }

        return state.numStates - 1;
    }

    /**
     * @notice Measure a qubit
     * @param q Qubit to measure
     * @param randomSeed Source of randomness
     * @return Measured qubit with collapsed state
     */
    function measureQubit(Qubit memory q, uint256 randomSeed) internal pure returns (Qubit memory) {
        if (q.measured) return q;

        uint256 rand = uint256(keccak256(abi.encodePacked(randomSeed))) % PRECISION;
        bool result = rand >= q.alpha;

        return Qubit({
            alpha: result ? 0 : PRECISION,
            beta: result ? PRECISION : 0,
            measured: true,
            value: result
        });
    }

    /**
     * @notice Perform multiple measurements and return distribution
     * @param state Quantum state to sample
     * @param numSamples Number of measurements
     * @param baseSeed Base random seed
     * @return counts Array of measurement counts per state
     */
    function sampleDistribution(
        QuantumState memory state,
        uint256 numSamples,
        uint256 baseSeed
    ) internal pure returns (uint256[] memory counts) {
        counts = new uint256[](state.numStates);

        for (uint256 i = 0; i < numSamples; i++) {
            uint256 result = measure(state, uint256(keccak256(abi.encodePacked(baseSeed, i))));
            counts[result]++;
        }
    }

    // ============ ENTANGLEMENT ============

    /**
     * @notice Create an entangled pair
     * @param seed Random seed for pair creation
     * @return Entangled pair state
     */
    function createEntangledPair(uint256 seed) internal pure returns (EntangledPair memory) {
        bytes32 pairId = keccak256(abi.encodePacked(seed, "entangled"));

        return EntangledPair({
            pairId: pairId,
            correlation: PRECISION, // Maximally entangled
            isEntangled: true
        });
    }

    /**
     * @notice Measure one particle of an entangled pair
     * @param pair Entangled pair
     * @param seed Random seed
     * @return result Measurement result
     * @return correlatedResult What the other particle would measure
     */
    function measureEntangled(EntangledPair memory pair, uint256 seed)
        internal
        pure
        returns (bool result, bool correlatedResult)
    {
        if (!pair.isEntangled) revert EntanglementBroken();

        // First measurement is random
        result = uint256(keccak256(abi.encodePacked(seed, pair.pairId))) % 2 == 1;

        // Second measurement is correlated (for Bell state |00⟩ + |11⟩)
        // With perfect correlation, results are always the same
        if (pair.correlation == PRECISION) {
            correlatedResult = result;
        } else {
            // Partial correlation
            uint256 rand = uint256(keccak256(abi.encodePacked(seed, pair.pairId, "corr"))) % PRECISION;
            correlatedResult = rand < pair.correlation ? result : !result;
        }
    }

    /**
     * @notice Simulate Bell state violation (CHSH inequality)
     * @param seed Random seed
     * @param numTrials Number of trials
     * @return violation CHSH value (classical max ~2000, quantum max ~2828)
     */
    function simulateBellTest(uint256 seed, uint256 numTrials) internal pure returns (uint256 violation) {
        // Simulate CHSH game
        uint256 wins = 0;

        for (uint256 i = 0; i < numTrials; i++) {
            uint256 trialSeed = uint256(keccak256(abi.encodePacked(seed, i)));

            // Random measurement bases
            bool aliceBasis = (trialSeed % 2) == 1;
            bool bobBasis = ((trialSeed >> 1) % 2) == 1;

            // Quantum strategy (simplified): XOR of bases predicts XOR of results
            bool predictedXOR = aliceBasis && bobBasis;

            // Simulate quantum correlation
            bool aliceResult = ((trialSeed >> 2) % 2) == 1;
            bool bobResult = predictedXOR ? !aliceResult : aliceResult;

            // Check win condition
            if ((aliceResult != bobResult) == predictedXOR) {
                wins++;
            }
        }

        // Scale to CHSH value (4 * P(win) - 2)
        // Quantum max is ~2.828, classical max is 2
        violation = (wins * 4000) / numTrials;
        if (violation > 2000) {
            violation = 2000 + ((violation - 2000) * 828) / 1000; // Scale quantum advantage
        }
    }

    // ============ QUANTUM-INSPIRED ALGORITHMS ============

    /**
     * @notice Quantum-inspired random number with enhanced entropy
     * @param seed Base seed
     * @param iterations Entropy iterations
     * @return High-entropy random number
     */
    function quantumRandom(uint256 seed, uint256 iterations) internal pure returns (uint256) {
        uint256 state = seed;

        for (uint256 i = 0; i < iterations; i++) {
            // Simulate quantum interference pattern
            uint256 phase1 = uint256(keccak256(abi.encodePacked(state, i)));
            uint256 phase2 = uint256(keccak256(abi.encodePacked(state, i, "phase2")));

            // Interference: constructive and destructive
            state = phase1 ^ phase2;
            state = uint256(keccak256(abi.encodePacked(state)));
        }

        return state;
    }

    /**
     * @notice Quantum-inspired search (Grover-like)
     * @param searchSpace Size of search space
     * @param targetHash Hash to find
     * @param seed Random seed
     * @param maxIterations Maximum iterations
     * @return result Search result with index and confidence
     */
    function quantumSearch(
        uint256 searchSpace,
        bytes32 targetHash,
        uint256 seed,
        uint256 maxIterations
    ) internal pure returns (GroverResult memory result) {
        if (searchSpace == 0) revert InvalidStateCount();

        // Optimal Grover iterations ≈ π/4 * sqrt(N)
        uint256 optimalIters = (PI_SCALED * _sqrt(searchSpace)) / (4 * PRECISION);
        uint256 iterations = optimalIters < maxIterations ? optimalIters : maxIterations;

        // Create superposition
        QuantumState memory state = createSuperposition(searchSpace > 256 ? 256 : searchSpace, seed);

        // Amplify target
        uint256 targetIndex = uint256(targetHash) % searchSpace;
        state = amplitudeAmplify(state, targetIndex % state.numStates, iterations);

        // Measure
        uint256 measuredIndex = measure(state, seed);

        result = GroverResult({
            index: measuredIndex,
            iterations: iterations,
            confidence: state.amplitudes[measuredIndex]
        });
    }

    /**
     * @notice Quantum walk for optimization
     * @param startPosition Starting position
     * @param dimension Walk dimension
     * @param steps Number of steps
     * @param seed Random seed
     * @return Final quantum walk state
     */
    function quantumWalk(
        uint256 startPosition,
        uint256 dimension,
        uint256 steps,
        uint256 seed
    ) internal pure returns (QuantumWalk memory) {
        uint256 position = startPosition;
        uint256 coin = 500; // Start in superposition

        for (uint256 i = 0; i < steps; i++) {
            uint256 stepSeed = uint256(keccak256(abi.encodePacked(seed, i)));

            // Apply Hadamard to coin
            coin = 500; // Maintain superposition

            // Conditional shift based on coin measurement
            bool coinResult = (stepSeed % PRECISION) < coin;

            if (coinResult) {
                position = (position + 1) % dimension;
            } else {
                position = position > 0 ? position - 1 : dimension - 1;
            }

            // Quantum interference effect
            uint256 interference = uint256(keccak256(abi.encodePacked(stepSeed, position)));
            coin = (coin + interference % 200) % PRECISION;
            if (coin < 300) coin = 300;
            if (coin > 700) coin = 700;
        }

        return QuantumWalk({
            position: position,
            coin: coin,
            steps: steps,
            dimension: dimension
        });
    }

    /**
     * @notice Quantum annealing-inspired optimization
     * @param initialState Starting state
     * @param targetState Goal state
     * @param temperature Initial temperature (scaled by PRECISION)
     * @param coolingRate Cooling rate (scaled by PRECISION, e.g., 990 = 0.99)
     * @param iterations Number of iterations
     * @param seed Random seed
     * @return Final state after annealing
     */
    function quantumAnneal(
        uint256 initialState,
        uint256 targetState,
        uint256 temperature,
        uint256 coolingRate,
        uint256 iterations,
        uint256 seed
    ) internal pure returns (uint256) {
        uint256 currentState = initialState;
        uint256 currentEnergy = _distance(currentState, targetState);
        uint256 temp = temperature;

        for (uint256 i = 0; i < iterations && temp > 1; i++) {
            // Generate neighbor state (quantum tunneling simulation)
            uint256 stepSeed = uint256(keccak256(abi.encodePacked(seed, i)));
            uint256 tunnelProbability = (temp * PRECISION) / temperature;

            uint256 neighborState;
            if ((stepSeed % PRECISION) < tunnelProbability) {
                // Quantum tunnel: larger jump
                neighborState = currentState ^ (stepSeed % (1 << 16));
            } else {
                // Classical move: small step
                neighborState = currentState ^ (stepSeed % 256);
            }

            uint256 neighborEnergy = _distance(neighborState, targetState);

            // Accept better states always, worse states with probability
            if (neighborEnergy < currentEnergy) {
                currentState = neighborState;
                currentEnergy = neighborEnergy;
            } else {
                uint256 delta = neighborEnergy - currentEnergy;
                uint256 acceptProb = (temp * PRECISION) / (temp + delta);
                if ((stepSeed >> 8) % PRECISION < acceptProb) {
                    currentState = neighborState;
                    currentEnergy = neighborEnergy;
                }
            }

            // Cool down
            temp = (temp * coolingRate) / PRECISION;
        }

        return currentState;
    }

    // ============ PROBABILITY UTILITIES ============

    /**
     * @notice Sample from discrete probability distribution
     * @param probabilities Array of probabilities (must sum to PRECISION)
     * @param seed Random seed
     * @return Sampled index
     */
    function sampleDiscrete(uint256[] memory probabilities, uint256 seed) internal pure returns (uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(seed))) % PRECISION;

        uint256 cumulative = 0;
        for (uint256 i = 0; i < probabilities.length; i++) {
            cumulative += probabilities[i];
            if (rand < cumulative) {
                return i;
            }
        }

        return probabilities.length - 1;
    }

    /**
     * @notice Generate quantum-inspired noise
     * @param x Input value
     * @param seed Random seed
     * @return Noise value (0-PRECISION)
     */
    function quantumNoise(uint256 x, uint256 seed) internal pure returns (uint256) {
        // Superposition of multiple frequency components
        uint256 noise = 0;

        for (uint256 freq = 1; freq <= 4; freq++) {
            uint256 phase = uint256(keccak256(abi.encodePacked(seed, freq)));
            uint256 component = _sin((x * freq + phase) % 3600);
            noise += component / freq;
        }

        return noise % PRECISION;
    }

    /**
     * @notice Check if two states would be considered "entangled"
     * @param state1 First state hash
     * @param state2 Second state hash
     * @return correlation Correlation measure (0-1000)
     */
    function measureCorrelation(uint256 state1, uint256 state2) internal pure returns (uint256 correlation) {
        // XOR-based correlation measure
        uint256 xored = state1 ^ state2;
        uint256 setBits = _popcount(xored);

        // Fewer differing bits = higher correlation
        correlation = PRECISION - ((setBits * PRECISION) / 256);
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Calculate entropy measure
     */
    function _calculateEntropy(uint256 numStates, uint256 seed) internal pure returns (uint256) {
        // Shannon entropy approximation
        if (numStates <= 1) return 0;
        return (numStates * uint256(keccak256(abi.encodePacked(seed)))) % PRECISION;
    }

    /**
     * @notice Approximate cosine (input: degrees * 10)
     */
    function _cos(uint256 angle) internal pure returns (uint256) {
        angle = angle % 3600;

        // Simple cosine approximation
        if (angle <= 900) {
            return PRECISION - (angle * angle * PRECISION) / (900 * 900 * 2);
        } else if (angle <= 1800) {
            uint256 adj = angle - 900;
            return (adj * adj * PRECISION) / (900 * 900 * 2);
        } else if (angle <= 2700) {
            uint256 adj = angle - 1800;
            return PRECISION - (adj * adj * PRECISION) / (900 * 900 * 2);
        } else {
            uint256 adj = 3600 - angle;
            return PRECISION - (adj * adj * PRECISION) / (900 * 900 * 2);
        }
    }

    /**
     * @notice Approximate sine (input: degrees * 10)
     */
    function _sin(uint256 angle) internal pure returns (uint256) {
        return _cos((2700 + 3600 - angle) % 3600);
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
     * @notice Calculate distance between two values
     */
    function _distance(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /**
     * @notice Count set bits (population count)
     */
    function _popcount(uint256 x) internal pure returns (uint256 count) {
        while (x != 0) {
            count += x & 1;
            x >>= 1;
        }
    }
}
