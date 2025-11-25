// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RingBufferLib
 * @author playground-zkaedi
 * @notice Gas-efficient fixed-size circular buffer for on-chain history tracking
 * @dev Implements ring buffer (circular buffer) data structure with O(1) operations
 *
 * ╔══════════════════════════════════════════════════════════════════════════════════╗
 * ║  ██████╗ ██╗███╗   ██╗ ██████╗     ██████╗ ██╗   ██╗███████╗███████╗███████╗██████╗ ║
 * ║  ██╔══██╗██║████╗  ██║██╔════╝     ██╔══██╗██║   ██║██╔════╝██╔════╝██╔════╝██╔══██╗║
 * ║  ██████╔╝██║██╔██╗ ██║██║  ███╗    ██████╔╝██║   ██║█████╗  █████╗  █████╗  ██████╔╝║
 * ║  ██╔══██╗██║██║╚██╗██║██║   ██║    ██╔══██╗██║   ██║██╔══╝  ██╔══╝  ██╔══╝  ██╔══██╗║
 * ║  ██║  ██║██║██║ ╚████║╚██████╔╝    ██████╔╝╚██████╔╝██║     ██║     ███████╗██║  ██║║
 * ║  ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚═════╝  ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝  ╚═╝║
 * ╚══════════════════════════════════════════════════════════════════════════════════╝
 *
 * Use Cases:
 * - Price history tracking (TWAP calculations)
 * - Recent transaction logs
 * - Rolling window statistics
 * - Event history with bounded storage
 * - Audit trails with automatic pruning
 *
 * Features:
 * - O(1) push, peek, and access operations
 * - Automatic overwrite of oldest entries when full
 * - Multiple buffer types (uint256, bytes32, address, packed entries)
 * - Statistical functions (sum, average, min, max)
 * - Iterator pattern for traversal
 * - Storage-efficient packing options
 */
library RingBufferLib {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CUSTOM ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error BufferEmpty();
    error BufferNotInitialized();
    error InvalidCapacity();
    error IndexOutOfBounds();
    error CapacityMismatch();

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum buffer capacity (to prevent excessive gas usage)
    uint256 internal constant MAX_CAPACITY = 1000;

    /// @dev Minimum buffer capacity
    uint256 internal constant MIN_CAPACITY = 2;

    // ═══════════════════════════════════════════════════════════════════════════
    //                         UINT256 RING BUFFER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Ring buffer for uint256 values
     * @param data The circular array storage
     * @param head Index of the next write position
     * @param count Number of elements currently in buffer
     * @param capacity Maximum capacity of the buffer
     */
    struct Uint256Buffer {
        mapping(uint256 => uint256) data;
        uint256 head;
        uint256 count;
        uint256 capacity;
    }

    /**
     * @notice Initializes a uint256 ring buffer
     * @param buffer The buffer to initialize
     * @param capacity Maximum number of elements
     */
    function init(Uint256Buffer storage buffer, uint256 capacity) internal {
        if (capacity < MIN_CAPACITY || capacity > MAX_CAPACITY) {
            revert InvalidCapacity();
        }
        buffer.head = 0;
        buffer.count = 0;
        buffer.capacity = capacity;
    }

    /**
     * @notice Pushes a new value into the buffer
     * @dev Overwrites oldest value if buffer is full
     * @param buffer The buffer to push to
     * @param value The value to push
     * @return overwritten The overwritten value (0 if buffer wasn't full)
     */
    function push(Uint256Buffer storage buffer, uint256 value) internal returns (uint256 overwritten) {
        if (buffer.capacity == 0) revert BufferNotInitialized();

        // Store the value that will be overwritten (if any)
        if (buffer.count == buffer.capacity) {
            overwritten = buffer.data[buffer.head];
        }

        // Write new value at head position
        buffer.data[buffer.head] = value;

        // Move head forward (wrapping around)
        buffer.head = (buffer.head + 1) % buffer.capacity;

        // Increment count if not at capacity
        if (buffer.count < buffer.capacity) {
            buffer.count++;
        }
    }

    /**
     * @notice Returns the most recently pushed value
     * @param buffer The buffer to peek
     * @return value The most recent value
     */
    function peekLatest(Uint256Buffer storage buffer) internal view returns (uint256 value) {
        if (buffer.count == 0) revert BufferEmpty();

        // Head points to next write position, so latest is one before
        uint256 latestIndex = buffer.head == 0 ? buffer.capacity - 1 : buffer.head - 1;
        return buffer.data[latestIndex];
    }

    /**
     * @notice Returns the oldest value in the buffer
     * @param buffer The buffer to peek
     * @return value The oldest value
     */
    function peekOldest(Uint256Buffer storage buffer) internal view returns (uint256 value) {
        if (buffer.count == 0) revert BufferEmpty();

        if (buffer.count < buffer.capacity) {
            // Buffer not full yet, oldest is at index 0
            return buffer.data[0];
        } else {
            // Buffer full, oldest is at head (will be overwritten next)
            return buffer.data[buffer.head];
        }
    }

    /**
     * @notice Gets value at a specific position from oldest (0) to newest (count-1)
     * @param buffer The buffer to read from
     * @param index Position from oldest (0 = oldest, count-1 = newest)
     * @return value The value at that position
     */
    function at(Uint256Buffer storage buffer, uint256 index) internal view returns (uint256 value) {
        if (index >= buffer.count) revert IndexOutOfBounds();

        uint256 actualIndex;
        if (buffer.count < buffer.capacity) {
            // Buffer not full, oldest is at 0
            actualIndex = index;
        } else {
            // Buffer full, oldest is at head
            actualIndex = (buffer.head + index) % buffer.capacity;
        }

        return buffer.data[actualIndex];
    }

    /**
     * @notice Gets value at index from newest (0 = most recent)
     * @param buffer The buffer to read from
     * @param reverseIndex Position from newest (0 = newest)
     * @return value The value at that position
     */
    function fromLatest(Uint256Buffer storage buffer, uint256 reverseIndex) internal view returns (uint256 value) {
        if (reverseIndex >= buffer.count) revert IndexOutOfBounds();
        return at(buffer, buffer.count - 1 - reverseIndex);
    }

    /**
     * @notice Returns all values in order from oldest to newest
     * @param buffer The buffer to read from
     * @return values Array of all values
     */
    function toArray(Uint256Buffer storage buffer) internal view returns (uint256[] memory values) {
        values = new uint256[](buffer.count);

        for (uint256 i = 0; i < buffer.count; i++) {
            values[i] = at(buffer, i);
        }
    }

    /**
     * @notice Calculates the sum of all values in the buffer
     * @param buffer The buffer to sum
     * @return total Sum of all values
     */
    function sum(Uint256Buffer storage buffer) internal view returns (uint256 total) {
        total = 0;
        for (uint256 i = 0; i < buffer.count; i++) {
            total += at(buffer, i);
        }
    }

    /**
     * @notice Calculates the average of all values
     * @param buffer The buffer to average
     * @return avg Average value (rounded down)
     */
    function average(Uint256Buffer storage buffer) internal view returns (uint256 avg) {
        if (buffer.count == 0) return 0;
        return sum(buffer) / buffer.count;
    }

    /**
     * @notice Finds the minimum value in the buffer
     * @param buffer The buffer to search
     * @return minVal Minimum value
     * @return minIndex Index of minimum value (from oldest)
     */
    function min(Uint256Buffer storage buffer) internal view returns (uint256 minVal, uint256 minIndex) {
        if (buffer.count == 0) revert BufferEmpty();

        minVal = at(buffer, 0);
        minIndex = 0;

        for (uint256 i = 1; i < buffer.count; i++) {
            uint256 val = at(buffer, i);
            if (val < minVal) {
                minVal = val;
                minIndex = i;
            }
        }
    }

    /**
     * @notice Finds the maximum value in the buffer
     * @param buffer The buffer to search
     * @return maxVal Maximum value
     * @return maxIndex Index of maximum value (from oldest)
     */
    function max(Uint256Buffer storage buffer) internal view returns (uint256 maxVal, uint256 maxIndex) {
        if (buffer.count == 0) revert BufferEmpty();

        maxVal = at(buffer, 0);
        maxIndex = 0;

        for (uint256 i = 1; i < buffer.count; i++) {
            uint256 val = at(buffer, i);
            if (val > maxVal) {
                maxVal = val;
                maxIndex = i;
            }
        }
    }

    /**
     * @notice Checks if buffer is full
     * @param buffer The buffer to check
     * @return True if at capacity
     */
    function isFull(Uint256Buffer storage buffer) internal view returns (bool) {
        return buffer.count == buffer.capacity;
    }

    /**
     * @notice Checks if buffer is empty
     * @param buffer The buffer to check
     * @return True if empty
     */
    function isEmpty(Uint256Buffer storage buffer) internal view returns (bool) {
        return buffer.count == 0;
    }

    /**
     * @notice Returns remaining capacity
     * @param buffer The buffer to check
     * @return remaining Space remaining
     */
    function remaining(Uint256Buffer storage buffer) internal view returns (uint256) {
        return buffer.capacity - buffer.count;
    }

    /**
     * @notice Clears the buffer
     * @param buffer The buffer to clear
     */
    function clear(Uint256Buffer storage buffer) internal {
        buffer.head = 0;
        buffer.count = 0;
        // Note: doesn't zero out storage for gas efficiency
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BYTES32 RING BUFFER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Ring buffer for bytes32 values (hashes, identifiers)
     */
    struct Bytes32Buffer {
        mapping(uint256 => bytes32) data;
        uint256 head;
        uint256 count;
        uint256 capacity;
    }

    function init(Bytes32Buffer storage buffer, uint256 capacity) internal {
        if (capacity < MIN_CAPACITY || capacity > MAX_CAPACITY) {
            revert InvalidCapacity();
        }
        buffer.head = 0;
        buffer.count = 0;
        buffer.capacity = capacity;
    }

    function push(Bytes32Buffer storage buffer, bytes32 value) internal returns (bytes32 overwritten) {
        if (buffer.capacity == 0) revert BufferNotInitialized();

        if (buffer.count == buffer.capacity) {
            overwritten = buffer.data[buffer.head];
        }

        buffer.data[buffer.head] = value;
        buffer.head = (buffer.head + 1) % buffer.capacity;

        if (buffer.count < buffer.capacity) {
            buffer.count++;
        }
    }

    function peekLatest(Bytes32Buffer storage buffer) internal view returns (bytes32 value) {
        if (buffer.count == 0) revert BufferEmpty();
        uint256 latestIndex = buffer.head == 0 ? buffer.capacity - 1 : buffer.head - 1;
        return buffer.data[latestIndex];
    }

    function at(Bytes32Buffer storage buffer, uint256 index) internal view returns (bytes32 value) {
        if (index >= buffer.count) revert IndexOutOfBounds();

        uint256 actualIndex;
        if (buffer.count < buffer.capacity) {
            actualIndex = index;
        } else {
            actualIndex = (buffer.head + index) % buffer.capacity;
        }

        return buffer.data[actualIndex];
    }

    function contains(Bytes32Buffer storage buffer, bytes32 value) internal view returns (bool found, uint256 index) {
        for (uint256 i = 0; i < buffer.count; i++) {
            if (at(buffer, i) == value) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function isEmpty(Bytes32Buffer storage buffer) internal view returns (bool) {
        return buffer.count == 0;
    }

    function isFull(Bytes32Buffer storage buffer) internal view returns (bool) {
        return buffer.count == buffer.capacity;
    }

    function clear(Bytes32Buffer storage buffer) internal {
        buffer.head = 0;
        buffer.count = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ADDRESS RING BUFFER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Ring buffer for address values (participants, authorized users)
     */
    struct AddressBuffer {
        mapping(uint256 => address) data;
        uint256 head;
        uint256 count;
        uint256 capacity;
    }

    function init(AddressBuffer storage buffer, uint256 capacity) internal {
        if (capacity < MIN_CAPACITY || capacity > MAX_CAPACITY) {
            revert InvalidCapacity();
        }
        buffer.head = 0;
        buffer.count = 0;
        buffer.capacity = capacity;
    }

    function push(AddressBuffer storage buffer, address value) internal returns (address overwritten) {
        if (buffer.capacity == 0) revert BufferNotInitialized();

        if (buffer.count == buffer.capacity) {
            overwritten = buffer.data[buffer.head];
        }

        buffer.data[buffer.head] = value;
        buffer.head = (buffer.head + 1) % buffer.capacity;

        if (buffer.count < buffer.capacity) {
            buffer.count++;
        }
    }

    function peekLatest(AddressBuffer storage buffer) internal view returns (address value) {
        if (buffer.count == 0) revert BufferEmpty();
        uint256 latestIndex = buffer.head == 0 ? buffer.capacity - 1 : buffer.head - 1;
        return buffer.data[latestIndex];
    }

    function at(AddressBuffer storage buffer, uint256 index) internal view returns (address value) {
        if (index >= buffer.count) revert IndexOutOfBounds();

        uint256 actualIndex;
        if (buffer.count < buffer.capacity) {
            actualIndex = index;
        } else {
            actualIndex = (buffer.head + index) % buffer.capacity;
        }

        return buffer.data[actualIndex];
    }

    function contains(AddressBuffer storage buffer, address value) internal view returns (bool found, uint256 index) {
        for (uint256 i = 0; i < buffer.count; i++) {
            if (at(buffer, i) == value) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function toArray(AddressBuffer storage buffer) internal view returns (address[] memory values) {
        values = new address[](buffer.count);
        for (uint256 i = 0; i < buffer.count; i++) {
            values[i] = at(buffer, i);
        }
    }

    function isEmpty(AddressBuffer storage buffer) internal view returns (bool) {
        return buffer.count == 0;
    }

    function isFull(AddressBuffer storage buffer) internal view returns (bool) {
        return buffer.count == buffer.capacity;
    }

    function clear(AddressBuffer storage buffer) internal {
        buffer.head = 0;
        buffer.count = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                     TIMESTAMPED ENTRY RING BUFFER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Entry with timestamp and value (for time-series data)
     */
    struct TimestampedEntry {
        uint64 timestamp;
        uint192 value;
    }

    /**
     * @dev Ring buffer for timestamped entries
     */
    struct TimestampedBuffer {
        mapping(uint256 => TimestampedEntry) data;
        uint256 head;
        uint256 count;
        uint256 capacity;
    }

    function init(TimestampedBuffer storage buffer, uint256 capacity) internal {
        if (capacity < MIN_CAPACITY || capacity > MAX_CAPACITY) {
            revert InvalidCapacity();
        }
        buffer.head = 0;
        buffer.count = 0;
        buffer.capacity = capacity;
    }

    function push(
        TimestampedBuffer storage buffer,
        uint192 value
    ) internal returns (TimestampedEntry memory overwritten) {
        if (buffer.capacity == 0) revert BufferNotInitialized();

        if (buffer.count == buffer.capacity) {
            overwritten = buffer.data[buffer.head];
        }

        buffer.data[buffer.head] = TimestampedEntry({
            timestamp: uint64(block.timestamp),
            value: value
        });

        buffer.head = (buffer.head + 1) % buffer.capacity;

        if (buffer.count < buffer.capacity) {
            buffer.count++;
        }
    }

    function pushWithTimestamp(
        TimestampedBuffer storage buffer,
        uint64 timestamp,
        uint192 value
    ) internal returns (TimestampedEntry memory overwritten) {
        if (buffer.capacity == 0) revert BufferNotInitialized();

        if (buffer.count == buffer.capacity) {
            overwritten = buffer.data[buffer.head];
        }

        buffer.data[buffer.head] = TimestampedEntry({
            timestamp: timestamp,
            value: value
        });

        buffer.head = (buffer.head + 1) % buffer.capacity;

        if (buffer.count < buffer.capacity) {
            buffer.count++;
        }
    }

    function peekLatest(TimestampedBuffer storage buffer) internal view returns (TimestampedEntry memory entry) {
        if (buffer.count == 0) revert BufferEmpty();
        uint256 latestIndex = buffer.head == 0 ? buffer.capacity - 1 : buffer.head - 1;
        return buffer.data[latestIndex];
    }

    function at(TimestampedBuffer storage buffer, uint256 index) internal view returns (TimestampedEntry memory entry) {
        if (index >= buffer.count) revert IndexOutOfBounds();

        uint256 actualIndex;
        if (buffer.count < buffer.capacity) {
            actualIndex = index;
        } else {
            actualIndex = (buffer.head + index) % buffer.capacity;
        }

        return buffer.data[actualIndex];
    }

    /**
     * @notice Calculates time-weighted average value
     * @param buffer The buffer to average
     * @return twav Time-weighted average
     */
    function timeWeightedAverage(TimestampedBuffer storage buffer) internal view returns (uint256 twav) {
        if (buffer.count < 2) {
            if (buffer.count == 1) return at(buffer, 0).value;
            return 0;
        }

        uint256 totalWeight = 0;
        uint256 weightedSum = 0;

        for (uint256 i = 0; i < buffer.count - 1; i++) {
            TimestampedEntry memory current = at(buffer, i);
            TimestampedEntry memory next = at(buffer, i + 1);

            uint256 duration = next.timestamp - current.timestamp;
            weightedSum += uint256(current.value) * duration;
            totalWeight += duration;
        }

        // Include the latest value with duration from now
        TimestampedEntry memory latest = peekLatest(buffer);
        uint256 latestDuration = block.timestamp - latest.timestamp;
        if (latestDuration > 0) {
            weightedSum += uint256(latest.value) * latestDuration;
            totalWeight += latestDuration;
        }

        if (totalWeight == 0) return latest.value;
        return weightedSum / totalWeight;
    }

    /**
     * @notice Gets entries within a time range
     * @param buffer The buffer to search
     * @param startTime Start timestamp (inclusive)
     * @param endTime End timestamp (inclusive)
     * @return entries Entries within the range
     * @return count Number of matching entries
     */
    function getInTimeRange(
        TimestampedBuffer storage buffer,
        uint64 startTime,
        uint64 endTime
    ) internal view returns (TimestampedEntry[] memory entries, uint256 count) {
        // First pass: count matching entries
        count = 0;
        for (uint256 i = 0; i < buffer.count; i++) {
            TimestampedEntry memory entry = at(buffer, i);
            if (entry.timestamp >= startTime && entry.timestamp <= endTime) {
                count++;
            }
        }

        // Second pass: collect entries
        entries = new TimestampedEntry[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < buffer.count && idx < count; i++) {
            TimestampedEntry memory entry = at(buffer, i);
            if (entry.timestamp >= startTime && entry.timestamp <= endTime) {
                entries[idx] = entry;
                idx++;
            }
        }
    }

    function isEmpty(TimestampedBuffer storage buffer) internal view returns (bool) {
        return buffer.count == 0;
    }

    function isFull(TimestampedBuffer storage buffer) internal view returns (bool) {
        return buffer.count == buffer.capacity;
    }

    function clear(TimestampedBuffer storage buffer) internal {
        buffer.head = 0;
        buffer.count = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         PACKED RING BUFFER
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Ultra gas-efficient buffer storing 4 uint64 values per slot
     * Useful for storing many small values (timestamps, counters, etc.)
     */
    struct PackedUint64Buffer {
        mapping(uint256 => uint256) packedData; // 4 x uint64 per slot
        uint256 head;
        uint256 count;
        uint256 capacity;
    }

    function init(PackedUint64Buffer storage buffer, uint256 capacity) internal {
        if (capacity < MIN_CAPACITY || capacity > MAX_CAPACITY) {
            revert InvalidCapacity();
        }
        buffer.head = 0;
        buffer.count = 0;
        buffer.capacity = capacity;
    }

    function push(PackedUint64Buffer storage buffer, uint64 value) internal returns (uint64 overwritten) {
        if (buffer.capacity == 0) revert BufferNotInitialized();

        uint256 slotIndex = buffer.head / 4;
        uint256 posInSlot = buffer.head % 4;
        uint256 shift = posInSlot * 64;

        // Read current slot
        uint256 slot = buffer.packedData[slotIndex];

        // Extract overwritten value if buffer is full
        if (buffer.count == buffer.capacity) {
            uint256 oldSlotIndex = buffer.head / 4;
            uint256 oldPosInSlot = buffer.head % 4;
            uint256 oldShift = oldPosInSlot * 64;
            overwritten = uint64(buffer.packedData[oldSlotIndex] >> oldShift);
        }

        // Clear the position and write new value
        uint256 mask = ~(uint256(0xFFFFFFFFFFFFFFFF) << shift);
        slot = (slot & mask) | (uint256(value) << shift);
        buffer.packedData[slotIndex] = slot;

        // Move head forward
        buffer.head = (buffer.head + 1) % buffer.capacity;

        if (buffer.count < buffer.capacity) {
            buffer.count++;
        }
    }

    function at(PackedUint64Buffer storage buffer, uint256 index) internal view returns (uint64 value) {
        if (index >= buffer.count) revert IndexOutOfBounds();

        uint256 actualIndex;
        if (buffer.count < buffer.capacity) {
            actualIndex = index;
        } else {
            actualIndex = (buffer.head + index) % buffer.capacity;
        }

        uint256 slotIndex = actualIndex / 4;
        uint256 posInSlot = actualIndex % 4;
        uint256 shift = posInSlot * 64;

        return uint64(buffer.packedData[slotIndex] >> shift);
    }

    function peekLatest(PackedUint64Buffer storage buffer) internal view returns (uint64 value) {
        if (buffer.count == 0) revert BufferEmpty();
        uint256 latestIndex = buffer.head == 0 ? buffer.capacity - 1 : buffer.head - 1;

        uint256 slotIndex = latestIndex / 4;
        uint256 posInSlot = latestIndex % 4;
        uint256 shift = posInSlot * 64;

        return uint64(buffer.packedData[slotIndex] >> shift);
    }

    function sum(PackedUint64Buffer storage buffer) internal view returns (uint256 total) {
        total = 0;
        for (uint256 i = 0; i < buffer.count; i++) {
            total += at(buffer, i);
        }
    }

    function average(PackedUint64Buffer storage buffer) internal view returns (uint64 avg) {
        if (buffer.count == 0) return 0;
        return uint64(sum(buffer) / buffer.count);
    }

    function isEmpty(PackedUint64Buffer storage buffer) internal view returns (bool) {
        return buffer.count == 0;
    }

    function isFull(PackedUint64Buffer storage buffer) internal view returns (bool) {
        return buffer.count == buffer.capacity;
    }

    function clear(PackedUint64Buffer storage buffer) internal {
        buffer.head = 0;
        buffer.count = 0;
    }
}
