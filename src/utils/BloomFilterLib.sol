// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title BloomFilterLib
/// @notice Gas-efficient probabilistic data structure for membership testing
/// @dev Space-efficient set membership with tunable false positive rate
/// @author playground-zkaedi
library BloomFilterLib {
    // ============ Custom Errors ============
    error FilterNotInitialized();
    error InvalidFilterSize();
    error InvalidHashCount();
    error FilterFull();
    error InvalidCapacity();

    // ============ Constants ============
    /// @notice Bits per storage slot (uint256)
    uint256 internal constant BITS_PER_SLOT = 256;

    /// @notice Maximum filter size (in bits)
    uint256 internal constant MAX_FILTER_SIZE = 65536; // 64KB

    /// @notice Maximum number of hash functions
    uint256 internal constant MAX_HASH_COUNT = 16;

    /// @notice Optimal hash count for ~1% false positive rate
    uint256 internal constant OPTIMAL_HASH_COUNT = 7;

    // ============ Structs ============

    /// @notice Configuration for a bloom filter
    struct FilterConfig {
        uint256 bitSize;        // Total number of bits
        uint256 hashCount;      // Number of hash functions
        uint256 expectedItems;  // Expected number of items
        uint256 insertedCount;  // Actual inserted items
    }

    /// @notice The main bloom filter structure
    struct Filter {
        FilterConfig config;
        mapping(uint256 => uint256) bitArray;  // Bit storage
        bool initialized;
    }

    /// @notice Compact filter using fixed storage slots
    struct CompactFilter {
        uint256[8] slots;       // 2048 bits total
        uint8 hashCount;
        uint16 insertedCount;
        bool initialized;
    }

    /// @notice Counting bloom filter (supports removal)
    struct CountingFilter {
        FilterConfig config;
        mapping(uint256 => uint8) counters;    // 4-bit counters per position
        bool initialized;
    }

    // ============ Initialization ============

    /// @notice Initialize a bloom filter with optimal parameters
    /// @param filter The filter storage reference
    /// @param expectedItems Expected number of items to store
    /// @param falsePositiveRate Desired false positive rate (in basis points, e.g., 100 = 1%)
    function initialize(
        Filter storage filter,
        uint256 expectedItems,
        uint256 falsePositiveRate
    ) internal {
        if (expectedItems == 0) revert InvalidCapacity();
        if (falsePositiveRate == 0 || falsePositiveRate > 5000) revert InvalidFilterSize();

        // Calculate optimal bit size: m = -n*ln(p) / (ln(2)^2)
        // Simplified: m ≈ n * (-ln(p/10000)) * 2.08
        uint256 bitSize = _calculateOptimalSize(expectedItems, falsePositiveRate);
        uint256 hashCount = _calculateOptimalHashCount(bitSize, expectedItems);

        if (bitSize > MAX_FILTER_SIZE) bitSize = MAX_FILTER_SIZE;
        if (hashCount > MAX_HASH_COUNT) hashCount = MAX_HASH_COUNT;
        if (hashCount == 0) hashCount = 1;

        filter.config = FilterConfig({
            bitSize: bitSize,
            hashCount: hashCount,
            expectedItems: expectedItems,
            insertedCount: 0
        });

        filter.initialized = true;
    }

    /// @notice Initialize with explicit parameters
    function initializeExplicit(
        Filter storage filter,
        uint256 bitSize,
        uint256 hashCount,
        uint256 expectedItems
    ) internal {
        if (bitSize == 0 || bitSize > MAX_FILTER_SIZE) revert InvalidFilterSize();
        if (hashCount == 0 || hashCount > MAX_HASH_COUNT) revert InvalidHashCount();

        filter.config = FilterConfig({
            bitSize: bitSize,
            hashCount: hashCount,
            expectedItems: expectedItems,
            insertedCount: 0
        });

        filter.initialized = true;
    }

    /// @notice Initialize compact filter
    function initializeCompact(CompactFilter storage filter, uint8 hashCount) internal {
        if (hashCount == 0 || hashCount > MAX_HASH_COUNT) revert InvalidHashCount();
        filter.hashCount = hashCount;
        filter.insertedCount = 0;
        filter.initialized = true;
    }

    /// @notice Initialize counting filter
    function initializeCounting(
        CountingFilter storage filter,
        uint256 bitSize,
        uint256 hashCount,
        uint256 expectedItems
    ) internal {
        if (bitSize == 0 || bitSize > MAX_FILTER_SIZE) revert InvalidFilterSize();
        if (hashCount == 0 || hashCount > MAX_HASH_COUNT) revert InvalidHashCount();

        filter.config = FilterConfig({
            bitSize: bitSize,
            hashCount: hashCount,
            expectedItems: expectedItems,
            insertedCount: 0
        });

        filter.initialized = true;
    }

    // ============ Core Operations ============

    /// @notice Add an element to the filter
    /// @param filter The filter storage reference
    /// @param element The element to add (will be hashed)
    function add(Filter storage filter, bytes32 element) internal {
        _checkInitialized(filter);

        uint256[] memory indices = _getHashIndices(element, filter.config.hashCount, filter.config.bitSize);

        for (uint256 i = 0; i < indices.length; i++) {
            _setBit(filter, indices[i]);
        }

        filter.config.insertedCount++;
    }

    /// @notice Add an address to the filter
    function addAddress(Filter storage filter, address addr) internal {
        add(filter, bytes32(uint256(uint160(addr))));
    }

    /// @notice Add multiple elements at once
    function addBatch(Filter storage filter, bytes32[] memory elements) internal {
        _checkInitialized(filter);

        for (uint256 i = 0; i < elements.length; i++) {
            uint256[] memory indices = _getHashIndices(elements[i], filter.config.hashCount, filter.config.bitSize);
            for (uint256 j = 0; j < indices.length; j++) {
                _setBit(filter, indices[j]);
            }
        }

        filter.config.insertedCount += elements.length;
    }

    /// @notice Check if element might be in the filter
    /// @return True if element might be present (possible false positive), false if definitely not present
    function mightContain(Filter storage filter, bytes32 element) internal view returns (bool) {
        _checkInitialized(filter);

        uint256[] memory indices = _getHashIndices(element, filter.config.hashCount, filter.config.bitSize);

        for (uint256 i = 0; i < indices.length; i++) {
            if (!_getBit(filter, indices[i])) {
                return false;
            }
        }

        return true;
    }

    /// @notice Check if address might be in the filter
    function mightContainAddress(Filter storage filter, address addr) internal view returns (bool) {
        return mightContain(filter, bytes32(uint256(uint160(addr))));
    }

    /// @notice Definitely does NOT contain (inverse of mightContain)
    function definitelyNotContains(Filter storage filter, bytes32 element) internal view returns (bool) {
        return !mightContain(filter, element);
    }

    // ============ Compact Filter Operations ============

    /// @notice Add to compact filter (2048 bits fixed)
    function addCompact(CompactFilter storage filter, bytes32 element) internal {
        if (!filter.initialized) revert FilterNotInitialized();

        uint256[] memory indices = _getHashIndices(element, filter.hashCount, 2048);

        for (uint256 i = 0; i < indices.length; i++) {
            uint256 slotIndex = indices[i] / BITS_PER_SLOT;
            uint256 bitIndex = indices[i] % BITS_PER_SLOT;
            filter.slots[slotIndex] |= (1 << bitIndex);
        }

        filter.insertedCount++;
    }

    /// @notice Check compact filter
    function mightContainCompact(CompactFilter storage filter, bytes32 element) internal view returns (bool) {
        if (!filter.initialized) revert FilterNotInitialized();

        uint256[] memory indices = _getHashIndices(element, filter.hashCount, 2048);

        for (uint256 i = 0; i < indices.length; i++) {
            uint256 slotIndex = indices[i] / BITS_PER_SLOT;
            uint256 bitIndex = indices[i] % BITS_PER_SLOT;
            if ((filter.slots[slotIndex] & (1 << bitIndex)) == 0) {
                return false;
            }
        }

        return true;
    }

    // ============ Counting Filter Operations ============

    /// @notice Add to counting filter
    function addCounting(CountingFilter storage filter, bytes32 element) internal {
        if (!filter.initialized) revert FilterNotInitialized();

        uint256[] memory indices = _getHashIndices(element, filter.config.hashCount, filter.config.bitSize);

        for (uint256 i = 0; i < indices.length; i++) {
            uint8 current = filter.counters[indices[i]];
            if (current < 15) { // 4-bit counter max
                filter.counters[indices[i]] = current + 1;
            }
        }

        filter.config.insertedCount++;
    }

    /// @notice Remove from counting filter
    function removeCounting(CountingFilter storage filter, bytes32 element) internal returns (bool) {
        if (!filter.initialized) revert FilterNotInitialized();

        uint256[] memory indices = _getHashIndices(element, filter.config.hashCount, filter.config.bitSize);

        // First check if element might exist
        for (uint256 i = 0; i < indices.length; i++) {
            if (filter.counters[indices[i]] == 0) {
                return false; // Element definitely not present
            }
        }

        // Decrement counters
        for (uint256 i = 0; i < indices.length; i++) {
            filter.counters[indices[i]]--;
        }

        if (filter.config.insertedCount > 0) {
            filter.config.insertedCount--;
        }

        return true;
    }

    /// @notice Check counting filter
    function mightContainCounting(CountingFilter storage filter, bytes32 element) internal view returns (bool) {
        if (!filter.initialized) revert FilterNotInitialized();

        uint256[] memory indices = _getHashIndices(element, filter.config.hashCount, filter.config.bitSize);

        for (uint256 i = 0; i < indices.length; i++) {
            if (filter.counters[indices[i]] == 0) {
                return false;
            }
        }

        return true;
    }

    // ============ Statistics ============

    /// @notice Get current false positive probability
    /// @dev P = (1 - e^(-kn/m))^k approximated as (1 - (1 - 1/m)^(kn))^k
    function getFalsePositiveRate(Filter storage filter) internal view returns (uint256) {
        _checkInitialized(filter);

        uint256 n = filter.config.insertedCount;
        uint256 m = filter.config.bitSize;
        uint256 k = filter.config.hashCount;

        if (n == 0) return 0;

        // Approximation: (kn/m)^k * 10000 for basis points
        // Simplified calculation for reasonable accuracy
        uint256 fillRatio = (k * n * 10000) / m;
        uint256 probability = fillRatio;

        for (uint256 i = 1; i < k && probability < 10000; i++) {
            probability = (probability * fillRatio) / 10000;
        }

        return probability > 10000 ? 10000 : probability;
    }

    /// @notice Get filter fill ratio
    function getFillRatio(Filter storage filter) internal view returns (uint256) {
        _checkInitialized(filter);
        return (filter.config.insertedCount * 10000) / filter.config.expectedItems;
    }

    /// @notice Get inserted count
    function getInsertedCount(Filter storage filter) internal view returns (uint256) {
        return filter.config.insertedCount;
    }

    /// @notice Get filter configuration
    function getConfig(Filter storage filter) internal view returns (FilterConfig memory) {
        return filter.config;
    }

    /// @notice Check if filter is at capacity
    function isAtCapacity(Filter storage filter) internal view returns (bool) {
        return filter.config.insertedCount >= filter.config.expectedItems;
    }

    // ============ Utility Functions ============

    /// @notice Estimate optimal bit size for given parameters
    function estimateBitSize(uint256 expectedItems, uint256 falsePositiveRateBps) external pure returns (uint256) {
        return _calculateOptimalSize(expectedItems, falsePositiveRateBps);
    }

    /// @notice Estimate optimal hash count
    function estimateHashCount(uint256 bitSize, uint256 expectedItems) external pure returns (uint256) {
        return _calculateOptimalHashCount(bitSize, expectedItems);
    }

    /// @notice Estimate false positive rate for given parameters
    function estimateFalsePositiveRate(
        uint256 bitSize,
        uint256 hashCount,
        uint256 itemCount
    ) external pure returns (uint256) {
        if (itemCount == 0) return 0;

        // (1 - e^(-kn/m))^k ≈ (kn/m)^k for small kn/m
        uint256 ratio = (hashCount * itemCount * 10000) / bitSize;
        uint256 result = ratio;

        for (uint256 i = 1; i < hashCount; i++) {
            result = (result * ratio) / 10000;
        }

        return result > 10000 ? 10000 : result;
    }

    // ============ Internal Helpers ============

    function _checkInitialized(Filter storage filter) private view {
        if (!filter.initialized) revert FilterNotInitialized();
    }

    /// @notice Calculate optimal filter size
    function _calculateOptimalSize(uint256 n, uint256 pBps) private pure returns (uint256) {
        // m = -n * ln(p) / (ln(2)^2)
        // Approximation: m ≈ n * 14.4 * log10(10000/p)
        // Simplified for gas efficiency

        uint256 multiplier;
        if (pBps <= 10) multiplier = 48;       // 0.1% -> 48 bits per item
        else if (pBps <= 50) multiplier = 38;  // 0.5% -> 38 bits per item
        else if (pBps <= 100) multiplier = 29; // 1% -> 29 bits per item (≈10 bits/item)
        else if (pBps <= 500) multiplier = 19; // 5% -> 19 bits per item
        else multiplier = 14;                   // >5% -> 14 bits per item

        return n * multiplier;
    }

    /// @notice Calculate optimal hash count
    function _calculateOptimalHashCount(uint256 m, uint256 n) private pure returns (uint256) {
        // k = (m/n) * ln(2) ≈ (m/n) * 0.693
        // Simplified: k ≈ (m * 7) / (n * 10)
        if (n == 0) return OPTIMAL_HASH_COUNT;

        uint256 k = (m * 7) / (n * 10);
        if (k == 0) k = 1;
        if (k > MAX_HASH_COUNT) k = MAX_HASH_COUNT;

        return k;
    }

    /// @notice Generate hash indices using double hashing
    function _getHashIndices(
        bytes32 element,
        uint256 hashCount,
        uint256 bitSize
    ) private pure returns (uint256[] memory) {
        uint256[] memory indices = new uint256[](hashCount);

        // Double hashing: h(i) = h1 + i*h2
        bytes32 hash1 = keccak256(abi.encodePacked(element));
        bytes32 hash2 = keccak256(abi.encodePacked(element, uint256(1)));

        uint256 h1 = uint256(hash1);
        uint256 h2 = uint256(hash2);

        for (uint256 i = 0; i < hashCount; i++) {
            indices[i] = (h1 + i * h2) % bitSize;
        }

        return indices;
    }

    /// @notice Set a bit in the filter
    function _setBit(Filter storage filter, uint256 index) private {
        uint256 slotIndex = index / BITS_PER_SLOT;
        uint256 bitIndex = index % BITS_PER_SLOT;
        filter.bitArray[slotIndex] |= (1 << bitIndex);
    }

    /// @notice Get a bit from the filter
    function _getBit(Filter storage filter, uint256 index) private view returns (bool) {
        uint256 slotIndex = index / BITS_PER_SLOT;
        uint256 bitIndex = index % BITS_PER_SLOT;
        return (filter.bitArray[slotIndex] & (1 << bitIndex)) != 0;
    }

    // ============ Set Operations ============

    /// @notice Union of two filters (OR operation)
    /// @dev Creates a new filter containing elements from both filters
    function union(
        Filter storage filterA,
        Filter storage filterB,
        Filter storage result
    ) internal {
        require(filterA.config.bitSize == filterB.config.bitSize, "Size mismatch");
        require(filterA.config.hashCount == filterB.config.hashCount, "Hash count mismatch");

        result.config = filterA.config;
        result.config.insertedCount = filterA.config.insertedCount + filterB.config.insertedCount;
        result.initialized = true;

        uint256 slotCount = (filterA.config.bitSize + BITS_PER_SLOT - 1) / BITS_PER_SLOT;

        for (uint256 i = 0; i < slotCount; i++) {
            result.bitArray[i] = filterA.bitArray[i] | filterB.bitArray[i];
        }
    }

    /// @notice Intersection of two filters (AND operation)
    function intersection(
        Filter storage filterA,
        Filter storage filterB,
        Filter storage result
    ) internal {
        require(filterA.config.bitSize == filterB.config.bitSize, "Size mismatch");
        require(filterA.config.hashCount == filterB.config.hashCount, "Hash count mismatch");

        result.config = filterA.config;
        result.config.insertedCount = 0; // Unknown after intersection
        result.initialized = true;

        uint256 slotCount = (filterA.config.bitSize + BITS_PER_SLOT - 1) / BITS_PER_SLOT;

        for (uint256 i = 0; i < slotCount; i++) {
            result.bitArray[i] = filterA.bitArray[i] & filterB.bitArray[i];
        }
    }

    /// @notice Count set bits (population count)
    function popCount(Filter storage filter) internal view returns (uint256) {
        _checkInitialized(filter);

        uint256 count = 0;
        uint256 slotCount = (filter.config.bitSize + BITS_PER_SLOT - 1) / BITS_PER_SLOT;

        for (uint256 i = 0; i < slotCount; i++) {
            count += _popCount256(filter.bitArray[i]);
        }

        return count;
    }

    /// @notice Count bits in a uint256 (parallel bit count algorithm)
    /// @dev Returns the number of 1-bits in x, correctly handling all 256 bits
    function _popCount256(uint256 x) private pure returns (uint256) {
        // Parallel bit count using SWAR algorithm
        // Each step counts bits in progressively larger groups

        // Count bits in pairs (0-2 per pair)
        x = x - ((x >> 1) & 0x5555555555555555555555555555555555555555555555555555555555555555);

        // Count bits in nibbles (0-4 per nibble)
        x = (x & 0x3333333333333333333333333333333333333333333333333333333333333333) +
            ((x >> 2) & 0x3333333333333333333333333333333333333333333333333333333333333333);

        // Count bits in bytes (0-8 per byte)
        x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;

        // Sum all bytes by multiplying by 0x0101... and extracting top byte
        // This works because multiplying by 0x0101...01 (32 bytes of 0x01) sums all bytes
        // into the top byte position
        x = (x * 0x0101010101010101010101010101010101010101010101010101010101010101) >> 248;

        return x;
    }
}
