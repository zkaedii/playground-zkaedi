// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EntropyHarvesterLib
 * @author playground-zkaedi
 * @notice Advanced on-chain entropy collection from multiple blockchain sources
 * @dev Harvests unpredictable data from block properties, transaction context, and historical state
 *
 * ╔═══════════════════════════════════════════════════════════════════════════════════╗
 * ║  ███████╗███╗   ██╗████████╗██████╗  ██████╗ ██████╗ ██╗   ██╗                    ║
 * ║  ██╔════╝████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██╔══██╗╚██╗ ██╔╝                    ║
 * ║  █████╗  ██╔██╗ ██║   ██║   ██████╔╝██║   ██║██████╔╝ ╚████╔╝                     ║
 * ║  ██╔══╝  ██║╚██╗██║   ██║   ██╔══██╗██║   ██║██╔═══╝   ╚██╔╝                      ║
 * ║  ███████╗██║ ╚████║   ██║   ██║  ██║╚██████╔╝██║        ██║                       ║
 * ║  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝        ╚═╝                       ║
 * ║          ██╗  ██╗ █████╗ ██████╗ ██╗   ██╗███████╗███████╗████████╗███████╗██████╗║
 * ║          ██║  ██║██╔══██╗██╔══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██║
 * ║          ███████║███████║██████╔╝██║   ██║█████╗  ███████╗   ██║   █████╗  ██████╔╝
 * ║          ██╔══██║██╔══██║██╔══██╗╚██╗ ██╔╝██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗║
 * ║          ██║  ██║██║  ██║██║  ██║ ╚████╔╝ ███████╗███████║   ██║   ███████╗██║  ██║║
 * ║          ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝║
 * ╚═══════════════════════════════════════════════════════════════════════════════════╝
 *
 * ⚠️  SECURITY WARNING: On-chain randomness is NEVER truly secure against determined
 *     miners/validators. This library is designed for:
 *     - Non-critical randomness needs (UI effects, cosmetic features)
 *     - Seed generation for commit-reveal schemes
 *     - Entropy mixing for VRF pre-seeds
 *     - Gas-auction based random selection
 *
 * 🛡️  For secure randomness, use Chainlink VRF or similar oracle solutions.
 *
 * Features:
 * - Multi-source entropy aggregation
 * - Historical block hash harvesting
 * - Transaction-specific entropy
 * - Entropy pool management
 * - Bit-level entropy extraction
 * - Entropy quality estimation
 */
library EntropyHarvesterLib {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CUSTOM ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InsufficientEntropy();
    error InvalidRange();
    error BlockHashUnavailable();
    error EntropyPoolExhausted();
    error InvalidBitCount();

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum blocks back for which blockhash is available
    uint256 internal constant MAX_BLOCK_LOOKBACK = 256;

    /// @dev Prime numbers for mixing operations
    uint256 internal constant PRIME_1 = 0xd1b54a32d192ed03;
    uint256 internal constant PRIME_2 = 0x7c50b41e2e1d3a91;
    uint256 internal constant PRIME_3 = 0xa817c7fd41e8ef71;

    /// @dev Bit masks
    uint256 internal constant MASK_64 = 0xFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// @dev Golden ratio constant for mixing
    uint256 internal constant GOLDEN_GAMMA = 0x9e3779b97f4a7c15;

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ENTROPY POOL STRUCT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Represents a pool of accumulated entropy
     * @param state Current entropy state (256 bits)
     * @param accumulator Additional entropy accumulator
     * @param extractionCount Number of times entropy has been extracted
     * @param lastHarvestBlock Block number of last entropy harvest
     * @param qualityScore Estimated entropy quality (0-10000 basis points)
     */
    struct EntropyPool {
        bytes32 state;
        bytes32 accumulator;
        uint64 extractionCount;
        uint64 lastHarvestBlock;
        uint64 qualityScore;
        uint64 _reserved;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BASIC ENTROPY SOURCES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Harvests entropy from current block properties
     * @dev Combines timestamp, difficulty/prevrandao, coinbase, gas limit
     * @return entropy 256-bit entropy value
     */
    function harvestBlockEntropy() internal view returns (bytes32 entropy) {
        assembly {
            // Start with timestamp
            let e := timestamp()

            // Mix in difficulty/prevrandao (post-merge this is beacon chain randomness)
            e := xor(e, difficulty())

            // Mix in coinbase address
            e := xor(e, shl(96, coinbase()))

            // Mix in gas limit
            e := xor(e, shl(192, gaslimit()))

            // Mix in block number
            e := xor(e, shl(64, number()))

            // Final keccak256 mix
            mstore(0x00, e)
            entropy := keccak256(0x00, 0x20)
        }
    }

    /**
     * @notice Harvests entropy from transaction context
     * @dev Combines msg.sender, tx.origin, gas price, gas remaining
     * @return entropy 256-bit entropy value
     */
    function harvestTxEntropy() internal view returns (bytes32 entropy) {
        assembly {
            // Start with msg.sender
            let e := caller()

            // Mix in tx.origin
            e := xor(e, shl(96, origin()))

            // Mix in gas price
            e := xor(e, shl(160, gasprice()))

            // Mix in remaining gas
            e := xor(e, shl(224, gas()))

            // Final keccak256 mix
            mstore(0x00, e)
            entropy := keccak256(0x00, 0x20)
        }
    }

    /**
     * @notice Harvests entropy from a historical block hash
     * @dev Block hashes are only available for the last 256 blocks
     * @param blocksBack Number of blocks back (1-256)
     * @return entropy 256-bit entropy from block hash
     */
    function harvestHistoricalEntropy(uint256 blocksBack) internal view returns (bytes32 entropy) {
        if (blocksBack == 0 || blocksBack > MAX_BLOCK_LOOKBACK) {
            revert BlockHashUnavailable();
        }

        uint256 targetBlock = block.number - blocksBack;
        bytes32 blockHash = blockhash(targetBlock);

        if (blockHash == bytes32(0)) {
            revert BlockHashUnavailable();
        }

        // Mix block hash with block number for additional entropy
        entropy = keccak256(abi.encodePacked(blockHash, targetBlock, block.timestamp));
    }

    /**
     * @notice Harvests entropy from multiple historical blocks
     * @dev Aggregates entropy from several recent blocks
     * @param count Number of blocks to harvest (1-256)
     * @return entropy Aggregated entropy
     */
    function harvestMultiBlockEntropy(uint256 count) internal view returns (bytes32 entropy) {
        if (count == 0 || count > MAX_BLOCK_LOOKBACK) {
            revert InvalidRange();
        }

        entropy = bytes32(0);

        for (uint256 i = 1; i <= count;) {
            bytes32 blockHash = blockhash(block.number - i);
            if (blockHash != bytes32(0)) {
                entropy = keccak256(abi.encodePacked(entropy, blockHash, i));
            }
            unchecked { i++; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         COMBINED ENTROPY HARVESTING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Comprehensive entropy harvest from all available sources
     * @dev Maximum entropy quality by combining all sources
     * @return entropy High-quality aggregated entropy
     */
    function harvestFullEntropy() internal view returns (bytes32 entropy) {
        bytes32 blockEntropy = harvestBlockEntropy();
        bytes32 txEntropy = harvestTxEntropy();
        bytes32 historicalEntropy = harvestHistoricalEntropy(1);

        // Chain state entropy (balance, code hash of sender)
        bytes32 stateEntropy;
        assembly {
            mstore(0x00, balance(caller()))
            mstore(0x20, extcodehash(caller()))
            stateEntropy := keccak256(0x00, 0x40)
        }

        // Combine all entropy sources
        entropy = keccak256(abi.encodePacked(
            blockEntropy,
            txEntropy,
            historicalEntropy,
            stateEntropy,
            gasleft()
        ));
    }

    /**
     * @notice Creates a salted entropy value
     * @dev Useful for creating unique entropy per user/action
     * @param salt User-provided salt value
     * @return entropy Salted entropy value
     */
    function harvestSaltedEntropy(bytes32 salt) internal view returns (bytes32 entropy) {
        bytes32 baseEntropy = harvestFullEntropy();
        entropy = keccak256(abi.encodePacked(baseEntropy, salt));
    }

    /**
     * @notice Creates entropy specific to a user address
     * @param user The user address to create entropy for
     * @return entropy User-specific entropy
     */
    function harvestUserEntropy(address user) internal view returns (bytes32 entropy) {
        bytes32 baseEntropy = harvestFullEntropy();
        entropy = keccak256(abi.encodePacked(baseEntropy, user, user.balance));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ENTROPY POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes a new entropy pool
     * @param pool The pool to initialize
     * @param initialSeed Optional initial seed (use 0 for fresh start)
     */
    function initializePool(EntropyPool storage pool, bytes32 initialSeed) internal {
        bytes32 harvestedEntropy = harvestFullEntropy();

        pool.state = keccak256(abi.encodePacked(harvestedEntropy, initialSeed));
        pool.accumulator = harvestedEntropy;
        pool.extractionCount = 0;
        pool.lastHarvestBlock = uint64(block.number);
        pool.qualityScore = 8000; // Start with 80% quality
    }

    /**
     * @notice Refreshes an entropy pool with new entropy
     * @param pool The pool to refresh
     */
    function refreshPool(EntropyPool storage pool) internal {
        bytes32 newEntropy = harvestFullEntropy();

        // Mix new entropy into state
        pool.state = keccak256(abi.encodePacked(pool.state, newEntropy));

        // Update accumulator
        pool.accumulator = keccak256(abi.encodePacked(pool.accumulator, newEntropy));

        // Update metadata
        pool.lastHarvestBlock = uint64(block.number);

        // Boost quality score
        uint64 currentQuality = pool.qualityScore;
        if (currentQuality < 9500) {
            pool.qualityScore = currentQuality + 500;
        }
    }

    /**
     * @notice Extracts entropy from pool (consumes entropy)
     * @dev Each extraction reduces entropy quality slightly
     * @param pool The pool to extract from
     * @return entropy Extracted entropy value
     */
    function extractFromPool(EntropyPool storage pool) internal returns (bytes32 entropy) {
        // Check if pool needs refresh
        if (pool.extractionCount > 100 || pool.qualityScore < 2000) {
            revert EntropyPoolExhausted();
        }

        // Generate entropy from current state
        entropy = keccak256(abi.encodePacked(
            pool.state,
            pool.accumulator,
            pool.extractionCount,
            block.timestamp
        ));

        // Update pool state (forward secrecy)
        pool.state = keccak256(abi.encodePacked(pool.state, entropy));

        // Increment extraction count
        pool.extractionCount++;

        // Decay quality
        if (pool.qualityScore >= 100) {
            pool.qualityScore -= 100;
        }
    }

    /**
     * @notice Stirs additional entropy into the pool
     * @param pool The pool to stir
     * @param additionalEntropy External entropy to add
     */
    function stirPool(EntropyPool storage pool, bytes32 additionalEntropy) internal {
        pool.state = keccak256(abi.encodePacked(pool.state, additionalEntropy));
        pool.accumulator = keccak256(abi.encodePacked(pool.accumulator, additionalEntropy));

        // Stirring improves quality
        if (pool.qualityScore < 9800) {
            pool.qualityScore += 200;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BIT-LEVEL EXTRACTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extracts a specific number of random bits
     * @param entropy Source entropy
     * @param bitCount Number of bits to extract (1-256)
     * @param offset Bit offset to start from (0-255)
     * @return bits Extracted bits (right-aligned)
     */
    function extractBits(
        bytes32 entropy,
        uint256 bitCount,
        uint256 offset
    ) internal pure returns (uint256 bits) {
        if (bitCount == 0 || bitCount > 256 || offset + bitCount > 256) {
            revert InvalidBitCount();
        }

        uint256 entropyUint = uint256(entropy);
        uint256 mask = (1 << bitCount) - 1;
        bits = (entropyUint >> offset) & mask;
    }

    /**
     * @notice Splits entropy into multiple chunks
     * @param entropy Source entropy (256 bits)
     * @return chunk1 First 64 bits
     * @return chunk2 Second 64 bits
     * @return chunk3 Third 64 bits
     * @return chunk4 Fourth 64 bits
     */
    function splitEntropy(bytes32 entropy) internal pure returns (
        uint64 chunk1,
        uint64 chunk2,
        uint64 chunk3,
        uint64 chunk4
    ) {
        uint256 e = uint256(entropy);
        chunk1 = uint64(e);
        chunk2 = uint64(e >> 64);
        chunk3 = uint64(e >> 128);
        chunk4 = uint64(e >> 192);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         RANDOM NUMBER GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generates a random number in range [0, max)
     * @dev Uses modulo bias reduction for fair distribution
     * @param entropy Source entropy
     * @param max Upper bound (exclusive)
     * @return Random number in range
     */
    function randomInRange(bytes32 entropy, uint256 max) internal pure returns (uint256) {
        if (max == 0) revert InvalidRange();
        if (max == 1) return 0;

        uint256 e = uint256(entropy);

        // Reduce modulo bias by rejection sampling
        // The threshold eliminates the biased range at the top
        uint256 threshold = type(uint256).max - (type(uint256).max % max);

        // If e >= threshold, we would have bias, so we remix
        // In practice, this almost never happens for reasonable max values
        if (e >= threshold) {
            e = uint256(keccak256(abi.encodePacked(entropy, "bias_reduction")));
        }

        return e % max;
    }

    /**
     * @notice Generates a random number in range [min, max]
     * @param entropy Source entropy
     * @param min Lower bound (inclusive)
     * @param max Upper bound (inclusive)
     * @return Random number in range
     */
    function randomInRangeInclusive(
        bytes32 entropy,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (min > max) revert InvalidRange();
        if (min == max) return min;

        uint256 range = max - min + 1;
        return min + randomInRange(entropy, range);
    }

    /**
     * @notice Generates a random boolean
     * @param entropy Source entropy
     * @return Random true/false
     */
    function randomBool(bytes32 entropy) internal pure returns (bool) {
        return uint256(entropy) & 1 == 1;
    }

    /**
     * @notice Generates a random address
     * @param entropy Source entropy
     * @return Random address (NOT a valid EOA/contract, just random bits)
     */
    function randomAddress(bytes32 entropy) internal pure returns (address) {
        return address(uint160(uint256(entropy)));
    }

    /**
     * @notice Generates multiple random values from single entropy
     * @dev Expands entropy using hash chain
     * @param entropy Source entropy
     * @param count Number of values to generate (max 16)
     * @return values Array of random values
     */
    function expandEntropy(
        bytes32 entropy,
        uint256 count
    ) internal pure returns (bytes32[16] memory values) {
        if (count > 16) count = 16;

        values[0] = entropy;
        for (uint256 i = 1; i < count;) {
            values[i] = keccak256(abi.encodePacked(entropy, i));
            unchecked { i++; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ENTROPY MIXING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mixes two entropy sources together
     * @param a First entropy source
     * @param b Second entropy source
     * @return mixed Combined entropy
     */
    function mixEntropy(bytes32 a, bytes32 b) internal pure returns (bytes32 mixed) {
        mixed = keccak256(abi.encodePacked(a, b));
    }

    /**
     * @notice Advanced entropy mixing using XOR and rotation
     * @param a First entropy source
     * @param b Second entropy source
     * @return mixed Combined entropy with better bit distribution
     */
    function advancedMix(bytes32 a, bytes32 b) internal pure returns (bytes32 mixed) {
        uint256 ua = uint256(a);
        uint256 ub = uint256(b);

        // XOR with rotated versions
        uint256 result = ua ^ ub;
        result ^= (ua << 13) | (ua >> (256 - 13));
        result ^= (ub << 37) | (ub >> (256 - 37));

        // Mix with primes
        result = result * PRIME_1;
        result ^= result >> 47;
        result = result * PRIME_2;
        result ^= result >> 43;

        mixed = bytes32(result);
    }

    /**
     * @notice Whitens entropy to improve bit distribution
     * @dev Uses multiple rounds of mixing to reduce patterns
     * @param entropy Input entropy
     * @return whitened Entropy with improved statistical properties
     */
    function whitenEntropy(bytes32 entropy) internal pure returns (bytes32 whitened) {
        uint256 e = uint256(entropy);

        // SplitMix64-style mixing (adapted for 256 bits)
        e ^= e >> 30;
        e *= PRIME_1;
        e ^= e >> 27;
        e *= PRIME_2;
        e ^= e >> 31;

        // Additional golden ratio mixing
        e ^= GOLDEN_GAMMA;
        e *= PRIME_3;

        whitened = bytes32(e);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ENTROPY QUALITY ANALYSIS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Estimates the quality of entropy based on bit distribution
     * @dev Counts bit patterns and measures deviation from ideal
     * @param entropy The entropy to analyze
     * @return score Quality score (0-10000 basis points)
     */
    function estimateQuality(bytes32 entropy) internal pure returns (uint256 score) {
        uint256 e = uint256(entropy);

        // Count set bits (popcount)
        uint256 ones = popcount(e);

        // Ideal is 128 ones in 256 bits (50%)
        // Score based on deviation from ideal
        uint256 deviation = ones > 128 ? ones - 128 : 128 - ones;

        // Perfect score at 128 ones, decreasing with deviation
        // Each bit off from ideal loses ~39 points (5000/128)
        score = deviation > 128 ? 0 : 10000 - (deviation * 78);

        // Check for runs (consecutive same bits)
        uint256 maxRun = longestRun(e);

        // Penalize long runs (expected max run ≈ 8 for random data)
        if (maxRun > 12) {
            uint256 penalty = (maxRun - 12) * 200;
            score = penalty > score ? 0 : score - penalty;
        }
    }

    /**
     * @notice Counts number of set bits (population count)
     * @param x The value to analyze
     * @return count Number of 1 bits
     */
    function popcount(uint256 x) internal pure returns (uint256 count) {
        // Parallel bit counting algorithm
        unchecked {
            x = x - ((x >> 1) & 0x5555555555555555555555555555555555555555555555555555555555555555);
            x = (x & 0x3333333333333333333333333333333333333333333333333333333333333333) +
                ((x >> 2) & 0x3333333333333333333333333333333333333333333333333333333333333333);
            x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;

            // Sum all bytes
            count = 0;
            for (uint256 i = 0; i < 32; i++) {
                count += (x >> (i * 8)) & 0xFF;
            }
        }
    }

    /**
     * @notice Finds the longest run of consecutive same bits
     * @param x The value to analyze
     * @return maxRun Length of longest run
     */
    function longestRun(uint256 x) internal pure returns (uint256 maxRun) {
        maxRun = 0;
        uint256 currentRun = 1;
        bool lastBit = x & 1 == 1;

        for (uint256 i = 1; i < 256; i++) {
            bool bit = (x >> i) & 1 == 1;
            if (bit == lastBit) {
                currentRun++;
            } else {
                if (currentRun > maxRun) maxRun = currentRun;
                currentRun = 1;
                lastBit = bit;
            }
        }

        if (currentRun > maxRun) maxRun = currentRun;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         COMMIT-REVEAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Creates a commitment hash for commit-reveal scheme
     * @param secret The secret value to commit
     * @param salt Random salt for the commitment
     * @return commitment The hash commitment
     */
    function createCommitment(
        bytes32 secret,
        bytes32 salt
    ) internal pure returns (bytes32 commitment) {
        commitment = keccak256(abi.encodePacked(secret, salt));
    }

    /**
     * @notice Verifies a commitment reveal
     * @param commitment The original commitment
     * @param secret The revealed secret
     * @param salt The revealed salt
     * @return valid True if the reveal matches the commitment
     */
    function verifyCommitment(
        bytes32 commitment,
        bytes32 secret,
        bytes32 salt
    ) internal pure returns (bool valid) {
        return commitment == keccak256(abi.encodePacked(secret, salt));
    }

    /**
     * @notice Generates a pre-seed for VRF or other oracle systems
     * @param nonce Unique nonce for this request
     * @param requester Address of the requester
     * @return preSeed Pre-seed value to send to oracle
     */
    function generateVRFPreSeed(
        uint256 nonce,
        address requester
    ) internal view returns (bytes32 preSeed) {
        preSeed = keccak256(abi.encodePacked(
            harvestBlockEntropy(),
            nonce,
            requester,
            block.number
        ));
    }
}
