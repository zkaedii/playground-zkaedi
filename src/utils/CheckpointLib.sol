// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CheckpointLib
 * @notice Historical value tracking with binary search lookups
 * @dev Provides efficient checkpoint storage for voting power, price history, etc.
 */
library CheckpointLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Single checkpoint with block number and value
    struct Checkpoint {
        uint64 blockNumber;
        uint192 value;
    }

    /// @notice Checkpoint with timestamp instead of block
    struct TimestampCheckpoint {
        uint64 timestamp;
        uint192 value;
    }

    /// @notice History of checkpoints for an account/key
    struct History {
        Checkpoint[] checkpoints;
    }

    /// @notice Timestamp-based history
    struct TimestampHistory {
        TimestampCheckpoint[] checkpoints;
    }

    /// @notice Checkpoint with arbitrary uint256 value
    struct Checkpoint256 {
        uint64 blockNumber;
        uint256 value;
    }

    /// @notice History with uint256 values
    struct History256 {
        Checkpoint256[] checkpoints;
    }

    /// @notice Circular buffer for fixed-size observation history
    struct CircularBuffer {
        uint16 head;              // Next write position
        uint16 size;              // Current number of entries
        uint16 capacity;          // Maximum entries
        uint64[] timestamps;      // Timestamp array
        uint192[] values;         // Value array
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error BlockNumberTooOld(uint256 requested, uint256 oldest);
    error TimestampTooOld(uint256 requested, uint256 oldest);
    error FutureBlockNumber(uint256 requested, uint256 current);
    error FutureTimestamp(uint256 requested, uint256 current);
    error EmptyHistory();
    error InvalidCapacity();

    // ═══════════════════════════════════════════════════════════════════════════
    // BLOCK-BASED CHECKPOINTS (uint192)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Push a new checkpoint
     * @param history History storage
     * @param value New value to checkpoint
     * @return oldValue Previous value (0 if first checkpoint)
     * @return newValue The value that was stored
     */
    function push(
        History storage history,
        uint192 value
    ) internal returns (uint192 oldValue, uint192 newValue) {
        uint256 length = history.checkpoints.length;
        uint64 currentBlock = uint64(block.number);

        if (length > 0) {
            Checkpoint storage last = history.checkpoints[length - 1];
            oldValue = last.value;

            // Same block - update in place
            if (last.blockNumber == currentBlock) {
                last.value = value;
                return (oldValue, value);
            }
        }

        // New block - push new checkpoint
        history.checkpoints.push(Checkpoint({
            blockNumber: currentBlock,
            value: value
        }));

        return (oldValue, value);
    }

    /**
     * @notice Get value at specific block number
     * @param history History storage
     * @param blockNumber Block to query
     * @return Value at that block
     */
    function getAtBlock(
        History storage history,
        uint256 blockNumber
    ) internal view returns (uint192) {
        if (blockNumber > block.number) {
            revert FutureBlockNumber(blockNumber, block.number);
        }

        uint256 length = history.checkpoints.length;
        if (length == 0) return 0;

        // Check if block is before our first checkpoint
        if (blockNumber < history.checkpoints[0].blockNumber) {
            return 0;
        }

        // Check if we can use the latest checkpoint
        Checkpoint storage last = history.checkpoints[length - 1];
        if (blockNumber >= last.blockNumber) {
            return last.value;
        }

        // Binary search
        uint256 low = 0;
        uint256 high = length - 1;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (history.checkpoints[mid].blockNumber <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return history.checkpoints[low].value;
    }

    /**
     * @notice Get the latest value
     * @param history History storage
     * @return Latest value (0 if no checkpoints)
     */
    function latest(History storage history) internal view returns (uint192) {
        uint256 length = history.checkpoints.length;
        return length > 0 ? history.checkpoints[length - 1].value : 0;
    }

    /**
     * @notice Get the latest checkpoint
     * @param history History storage
     * @return blockNumber Block of latest checkpoint
     * @return value Value at latest checkpoint
     */
    function latestCheckpoint(
        History storage history
    ) internal view returns (uint64 blockNumber, uint192 value) {
        uint256 length = history.checkpoints.length;
        if (length == 0) return (0, 0);

        Checkpoint storage cp = history.checkpoints[length - 1];
        return (cp.blockNumber, cp.value);
    }

    /**
     * @notice Get number of checkpoints
     */
    function length(History storage history) internal view returns (uint256) {
        return history.checkpoints.length;
    }

    /**
     * @notice Get checkpoint at index
     */
    function at(
        History storage history,
        uint256 index
    ) internal view returns (uint64 blockNumber, uint192 value) {
        Checkpoint storage cp = history.checkpoints[index];
        return (cp.blockNumber, cp.value);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMESTAMP-BASED CHECKPOINTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Push timestamp-based checkpoint
     */
    function pushTimestamp(
        TimestampHistory storage history,
        uint192 value
    ) internal returns (uint192 oldValue, uint192 newValue) {
        uint256 len = history.checkpoints.length;
        uint64 currentTime = uint64(block.timestamp);

        if (len > 0) {
            TimestampCheckpoint storage last = history.checkpoints[len - 1];
            oldValue = last.value;

            // Same timestamp - update in place
            if (last.timestamp == currentTime) {
                last.value = value;
                return (oldValue, value);
            }
        }

        history.checkpoints.push(TimestampCheckpoint({
            timestamp: currentTime,
            value: value
        }));

        return (oldValue, value);
    }

    /**
     * @notice Get value at specific timestamp
     */
    function getAtTimestamp(
        TimestampHistory storage history,
        uint256 timestamp
    ) internal view returns (uint192) {
        if (timestamp > block.timestamp) {
            revert FutureTimestamp(timestamp, block.timestamp);
        }

        uint256 len = history.checkpoints.length;
        if (len == 0) return 0;

        if (timestamp < history.checkpoints[0].timestamp) {
            return 0;
        }

        TimestampCheckpoint storage last = history.checkpoints[len - 1];
        if (timestamp >= last.timestamp) {
            return last.value;
        }

        // Binary search
        uint256 low = 0;
        uint256 high = len - 1;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (history.checkpoints[mid].timestamp <= timestamp) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return history.checkpoints[low].value;
    }

    /**
     * @notice Get latest timestamp value
     */
    function latestTimestamp(TimestampHistory storage history) internal view returns (uint192) {
        uint256 len = history.checkpoints.length;
        return len > 0 ? history.checkpoints[len - 1].value : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT256 CHECKPOINTS (for larger values)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Push uint256 checkpoint
     */
    function push256(
        History256 storage history,
        uint256 value
    ) internal returns (uint256 oldValue, uint256 newValue) {
        uint256 len = history.checkpoints.length;
        uint64 currentBlock = uint64(block.number);

        if (len > 0) {
            Checkpoint256 storage last = history.checkpoints[len - 1];
            oldValue = last.value;

            if (last.blockNumber == currentBlock) {
                last.value = value;
                return (oldValue, value);
            }
        }

        history.checkpoints.push(Checkpoint256({
            blockNumber: currentBlock,
            value: value
        }));

        return (oldValue, value);
    }

    /**
     * @notice Get uint256 value at block
     */
    function getAtBlock256(
        History256 storage history,
        uint256 blockNumber
    ) internal view returns (uint256) {
        if (blockNumber > block.number) {
            revert FutureBlockNumber(blockNumber, block.number);
        }

        uint256 len = history.checkpoints.length;
        if (len == 0) return 0;

        if (blockNumber < history.checkpoints[0].blockNumber) {
            return 0;
        }

        Checkpoint256 storage last = history.checkpoints[len - 1];
        if (blockNumber >= last.blockNumber) {
            return last.value;
        }

        uint256 low = 0;
        uint256 high = len - 1;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (history.checkpoints[mid].blockNumber <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return history.checkpoints[low].value;
    }

    /**
     * @notice Get latest uint256 value
     */
    function latest256(History256 storage history) internal view returns (uint256) {
        uint256 len = history.checkpoints.length;
        return len > 0 ? history.checkpoints[len - 1].value : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CIRCULAR BUFFER (Fixed-size rolling history)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize circular buffer
     * @param buffer Buffer storage
     * @param capacity Maximum number of entries
     */
    function initBuffer(CircularBuffer storage buffer, uint16 capacity) internal {
        if (capacity == 0) revert InvalidCapacity();

        buffer.capacity = capacity;
        buffer.head = 0;
        buffer.size = 0;
        buffer.timestamps = new uint64[](capacity);
        buffer.values = new uint192[](capacity);
    }

    /**
     * @notice Write new observation to buffer
     * @param buffer Buffer storage
     * @param value Value to record
     */
    function write(CircularBuffer storage buffer, uint192 value) internal {
        buffer.timestamps[buffer.head] = uint64(block.timestamp);
        buffer.values[buffer.head] = value;

        buffer.head = (buffer.head + 1) % buffer.capacity;
        if (buffer.size < buffer.capacity) {
            buffer.size++;
        }
    }

    /**
     * @notice Get observation at relative index (0 = latest)
     * @param buffer Buffer storage
     * @param ago How many observations back (0 = latest)
     * @return timestamp Observation timestamp
     * @return value Observation value
     */
    function observe(
        CircularBuffer storage buffer,
        uint16 ago
    ) internal view returns (uint64 timestamp, uint192 value) {
        if (ago >= buffer.size) revert EmptyHistory();

        // Calculate actual index
        uint16 index;
        if (buffer.head > ago) {
            index = buffer.head - ago - 1;
        } else {
            index = buffer.capacity - (ago - buffer.head) - 1;
        }

        return (buffer.timestamps[index], buffer.values[index]);
    }

    /**
     * @notice Get latest observation
     */
    function latestObservation(
        CircularBuffer storage buffer
    ) internal view returns (uint64 timestamp, uint192 value) {
        if (buffer.size == 0) return (0, 0);
        return observe(buffer, 0);
    }

    /**
     * @notice Get oldest observation
     */
    function oldestObservation(
        CircularBuffer storage buffer
    ) internal view returns (uint64 timestamp, uint192 value) {
        if (buffer.size == 0) return (0, 0);
        return observe(buffer, buffer.size - 1);
    }

    /**
     * @notice Get observation closest to target timestamp
     * @param buffer Buffer storage
     * @param targetTimestamp Target timestamp to search for
     * @return timestamp Closest observation timestamp
     * @return value Observation value
     */
    function observeAt(
        CircularBuffer storage buffer,
        uint64 targetTimestamp
    ) internal view returns (uint64 timestamp, uint192 value) {
        if (buffer.size == 0) return (0, 0);

        // Binary search through buffer
        uint16 low = 0;
        uint16 high = buffer.size - 1;

        // Get oldest timestamp
        (uint64 oldestTs,) = observe(buffer, high);
        if (targetTimestamp <= oldestTs) {
            return observe(buffer, high);
        }

        // Get latest timestamp
        (uint64 latestTs,) = observe(buffer, 0);
        if (targetTimestamp >= latestTs) {
            return observe(buffer, 0);
        }

        // Binary search
        while (low < high) {
            uint16 mid = (low + high) / 2;
            (uint64 midTs,) = observe(buffer, mid);

            if (midTs == targetTimestamp) {
                return observe(buffer, mid);
            } else if (midTs > targetTimestamp) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        return observe(buffer, low);
    }

    /**
     * @notice Calculate time-weighted average over period
     * @param buffer Buffer storage
     * @param duration Lookback duration in seconds
     * @return twap Time-weighted average
     */
    function twap(
        CircularBuffer storage buffer,
        uint64 duration
    ) internal view returns (uint192) {
        if (buffer.size == 0) return 0;

        uint64 currentTime = uint64(block.timestamp);
        uint64 startTime = currentTime > duration ? currentTime - duration : 0;

        uint256 cumulativeValue;
        uint256 totalTime;

        (uint64 prevTimestamp, uint192 prevValue) = observe(buffer, 0);

        for (uint16 i = 1; i < buffer.size; i++) {
            (uint64 obsTimestamp, uint192 obsValue) = observe(buffer, i);

            if (prevTimestamp <= startTime) break;

            uint64 periodStart = obsTimestamp > startTime ? obsTimestamp : startTime;
            uint64 periodEnd = prevTimestamp;

            if (periodEnd > periodStart) {
                uint64 periodDuration = periodEnd - periodStart;
                cumulativeValue += uint256(prevValue) * periodDuration;
                totalTime += periodDuration;
            }

            prevTimestamp = obsTimestamp;
            prevValue = obsValue;
        }

        if (totalTime == 0) return latestObservation(buffer).value;
        return uint192(cumulativeValue / totalTime);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Binary search to find upper bound
     * @param checkpoints Checkpoint array
     * @param blockNumber Target block
     * @return Index of first checkpoint with blockNumber > target
     */
    function upperBound(
        Checkpoint[] storage checkpoints,
        uint256 blockNumber
    ) internal view returns (uint256) {
        uint256 len = checkpoints.length;
        if (len == 0) return 0;

        uint256 low = 0;
        uint256 high = len;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (checkpoints[mid].blockNumber <= blockNumber) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        return low;
    }

    /**
     * @notice Get average value over block range
     * @param history History storage
     * @param startBlock Start block
     * @param endBlock End block
     * @return Average value
     */
    function averageOverRange(
        History storage history,
        uint256 startBlock,
        uint256 endBlock
    ) internal view returns (uint192) {
        if (endBlock <= startBlock) return 0;
        if (history.checkpoints.length == 0) return 0;

        uint256 cumulative;
        uint256 totalBlocks;

        uint256 currentBlock = startBlock;

        for (uint256 i = 0; i < history.checkpoints.length && currentBlock < endBlock; i++) {
            Checkpoint storage cp = history.checkpoints[i];

            if (cp.blockNumber > currentBlock) {
                uint256 blockEnd = cp.blockNumber < endBlock ? cp.blockNumber : endBlock;
                uint192 value = i > 0 ? history.checkpoints[i - 1].value : 0;
                uint256 duration = blockEnd - currentBlock;

                cumulative += uint256(value) * duration;
                totalBlocks += duration;
                currentBlock = blockEnd;
            }
        }

        // Handle remaining blocks after last checkpoint
        if (currentBlock < endBlock) {
            uint192 lastValue = history.checkpoints[history.checkpoints.length - 1].value;
            uint256 duration = endBlock - currentBlock;
            cumulative += uint256(lastValue) * duration;
            totalBlocks += duration;
        }

        if (totalBlocks == 0) return 0;
        return uint192(cumulative / totalBlocks);
    }
}
