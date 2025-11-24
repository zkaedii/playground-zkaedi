// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title QueueLib
 * @notice Queue data structures for batch processing and ordered operations
 * @dev Provides FIFO queue, priority queue, and batch processing utilities
 */
library QueueLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error QueueEmpty();
    error QueueFull();
    error InvalidIndex();
    error ItemNotFound();
    error BatchTooLarge();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice FIFO Queue for bytes32 items
    struct Bytes32Queue {
        uint128 front;           // Index of first element
        uint128 back;            // Index after last element
        mapping(uint256 => bytes32) items;
    }

    /// @notice FIFO Queue for uint256 items
    struct Uint256Queue {
        uint128 front;
        uint128 back;
        mapping(uint256 => uint256) items;
    }

    /// @notice FIFO Queue for addresses
    struct AddressQueue {
        uint128 front;
        uint128 back;
        mapping(uint256 => address) items;
    }

    /// @notice Priority item with value and priority
    struct PriorityItem {
        bytes32 value;
        uint256 priority;        // Higher = more priority
    }

    /// @notice Min-heap priority queue (lowest priority = highest priority)
    struct MinPriorityQueue {
        PriorityItem[] heap;
    }

    /// @notice Batch processing state
    struct BatchState {
        uint256 totalItems;
        uint256 processedItems;
        uint256 batchSize;
        uint256 currentBatch;
        bool completed;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BYTES32 QUEUE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add item to back of queue
    function enqueue(Bytes32Queue storage queue, bytes32 item) internal {
        queue.items[queue.back] = item;
        unchecked {
            queue.back++;
        }
    }

    /// @notice Remove and return item from front of queue
    function dequeue(Bytes32Queue storage queue) internal returns (bytes32 item) {
        if (isEmpty(queue)) revert QueueEmpty();

        item = queue.items[queue.front];
        delete queue.items[queue.front];
        unchecked {
            queue.front++;
        }
    }

    /// @notice View front item without removing
    function peek(Bytes32Queue storage queue) internal view returns (bytes32) {
        if (isEmpty(queue)) revert QueueEmpty();
        return queue.items[queue.front];
    }

    /// @notice Check if queue is empty
    function isEmpty(Bytes32Queue storage queue) internal view returns (bool) {
        return queue.front >= queue.back;
    }

    /// @notice Get number of items in queue
    function length(Bytes32Queue storage queue) internal view returns (uint256) {
        return queue.back - queue.front;
    }

    /// @notice Clear the queue
    function clear(Bytes32Queue storage queue) internal {
        queue.front = 0;
        queue.back = 0;
    }

    /// @notice Dequeue multiple items at once
    function dequeueBatch(
        Bytes32Queue storage queue,
        uint256 count
    ) internal returns (bytes32[] memory items) {
        uint256 available = length(queue);
        uint256 toDequeue = count > available ? available : count;

        items = new bytes32[](toDequeue);
        unchecked {
            for (uint256 i; i < toDequeue; ++i) {
                items[i] = queue.items[queue.front + i];
                delete queue.items[queue.front + i];
            }
            queue.front += uint128(toDequeue);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT256 QUEUE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add item to back of queue
    function enqueue(Uint256Queue storage queue, uint256 item) internal {
        queue.items[queue.back] = item;
        unchecked {
            queue.back++;
        }
    }

    /// @notice Remove and return item from front of queue
    function dequeue(Uint256Queue storage queue) internal returns (uint256 item) {
        if (isEmpty(queue)) revert QueueEmpty();

        item = queue.items[queue.front];
        delete queue.items[queue.front];
        unchecked {
            queue.front++;
        }
    }

    /// @notice View front item without removing
    function peek(Uint256Queue storage queue) internal view returns (uint256) {
        if (isEmpty(queue)) revert QueueEmpty();
        return queue.items[queue.front];
    }

    /// @notice Check if queue is empty
    function isEmpty(Uint256Queue storage queue) internal view returns (bool) {
        return queue.front >= queue.back;
    }

    /// @notice Get number of items in queue
    function length(Uint256Queue storage queue) internal view returns (uint256) {
        return queue.back - queue.front;
    }

    /// @notice Clear the queue
    function clear(Uint256Queue storage queue) internal {
        queue.front = 0;
        queue.back = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS QUEUE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add address to back of queue
    function enqueue(AddressQueue storage queue, address item) internal {
        queue.items[queue.back] = item;
        unchecked {
            queue.back++;
        }
    }

    /// @notice Remove and return address from front of queue
    function dequeue(AddressQueue storage queue) internal returns (address item) {
        if (isEmpty(queue)) revert QueueEmpty();

        item = queue.items[queue.front];
        delete queue.items[queue.front];
        unchecked {
            queue.front++;
        }
    }

    /// @notice View front address without removing
    function peek(AddressQueue storage queue) internal view returns (address) {
        if (isEmpty(queue)) revert QueueEmpty();
        return queue.items[queue.front];
    }

    /// @notice Check if queue is empty
    function isEmpty(AddressQueue storage queue) internal view returns (bool) {
        return queue.front >= queue.back;
    }

    /// @notice Get number of items in queue
    function length(AddressQueue storage queue) internal view returns (uint256) {
        return queue.back - queue.front;
    }

    /// @notice Clear the queue
    function clear(AddressQueue storage queue) internal {
        queue.front = 0;
        queue.back = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MIN PRIORITY QUEUE (HEAP) OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Insert item into priority queue
    function insert(
        MinPriorityQueue storage pq,
        bytes32 value,
        uint256 priority
    ) internal {
        pq.heap.push(PriorityItem({value: value, priority: priority}));
        _siftUp(pq, pq.heap.length - 1);
    }

    /// @notice Extract item with lowest priority (min heap)
    function extractMin(MinPriorityQueue storage pq) internal returns (PriorityItem memory item) {
        if (pq.heap.length == 0) revert QueueEmpty();

        item = pq.heap[0];

        // Move last element to root and sift down
        uint256 lastIdx = pq.heap.length - 1;
        if (lastIdx > 0) {
            pq.heap[0] = pq.heap[lastIdx];
            pq.heap.pop();
            _siftDown(pq, 0);
        } else {
            pq.heap.pop();
        }
    }

    /// @notice View minimum priority item without removing
    function peekMin(MinPriorityQueue storage pq) internal view returns (PriorityItem memory) {
        if (pq.heap.length == 0) revert QueueEmpty();
        return pq.heap[0];
    }

    /// @notice Check if priority queue is empty
    function isEmpty(MinPriorityQueue storage pq) internal view returns (bool) {
        return pq.heap.length == 0;
    }

    /// @notice Get number of items in priority queue
    function length(MinPriorityQueue storage pq) internal view returns (uint256) {
        return pq.heap.length;
    }

    /// @notice Update priority of item (requires finding the item first)
    function updatePriority(
        MinPriorityQueue storage pq,
        bytes32 value,
        uint256 newPriority
    ) internal returns (bool found) {
        for (uint256 i; i < pq.heap.length; ++i) {
            if (pq.heap[i].value == value) {
                uint256 oldPriority = pq.heap[i].priority;
                pq.heap[i].priority = newPriority;

                if (newPriority < oldPriority) {
                    _siftUp(pq, i);
                } else {
                    _siftDown(pq, i);
                }
                return true;
            }
        }
        return false;
    }

    /// @dev Sift element up to maintain heap property
    function _siftUp(MinPriorityQueue storage pq, uint256 idx) private {
        while (idx > 0) {
            uint256 parentIdx = (idx - 1) / 2;
            if (pq.heap[idx].priority >= pq.heap[parentIdx].priority) {
                break;
            }
            // Swap with parent
            PriorityItem memory temp = pq.heap[idx];
            pq.heap[idx] = pq.heap[parentIdx];
            pq.heap[parentIdx] = temp;
            idx = parentIdx;
        }
    }

    /// @dev Sift element down to maintain heap property
    function _siftDown(MinPriorityQueue storage pq, uint256 idx) private {
        uint256 len = pq.heap.length;

        while (true) {
            uint256 smallest = idx;
            uint256 left = 2 * idx + 1;
            uint256 right = 2 * idx + 2;

            if (left < len && pq.heap[left].priority < pq.heap[smallest].priority) {
                smallest = left;
            }
            if (right < len && pq.heap[right].priority < pq.heap[smallest].priority) {
                smallest = right;
            }

            if (smallest == idx) break;

            // Swap
            PriorityItem memory temp = pq.heap[idx];
            pq.heap[idx] = pq.heap[smallest];
            pq.heap[smallest] = temp;
            idx = smallest;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH PROCESSING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize batch processing state
    function initBatch(
        uint256 totalItems,
        uint256 batchSize
    ) internal pure returns (BatchState memory state) {
        if (batchSize == 0) revert BatchTooLarge();

        state = BatchState({
            totalItems: totalItems,
            processedItems: 0,
            batchSize: batchSize,
            currentBatch: 0,
            completed: totalItems == 0
        });
    }

    /// @notice Get next batch range
    function getNextBatchRange(BatchState memory state) internal pure returns (
        uint256 start,
        uint256 end,
        bool hasMore
    ) {
        if (state.completed) {
            return (0, 0, false);
        }

        start = state.processedItems;
        end = start + state.batchSize;

        if (end >= state.totalItems) {
            end = state.totalItems;
            hasMore = false;
        } else {
            hasMore = true;
        }
    }

    /// @notice Mark batch as processed
    function completeBatch(BatchState storage state, uint256 itemsProcessed) internal {
        unchecked {
            state.processedItems += itemsProcessed;
            state.currentBatch++;
        }
        if (state.processedItems >= state.totalItems) {
            state.completed = true;
        }
    }

    /// @notice Get batch progress as percentage (0-100)
    function batchProgress(BatchState memory state) internal pure returns (uint256) {
        if (state.totalItems == 0) return 100;
        return (state.processedItems * 100) / state.totalItems;
    }

    /// @notice Get remaining items to process
    function remainingItems(BatchState memory state) internal pure returns (uint256) {
        if (state.processedItems >= state.totalItems) return 0;
        return state.totalItems - state.processedItems;
    }

    /// @notice Estimate remaining batches
    function remainingBatches(BatchState memory state) internal pure returns (uint256) {
        uint256 remaining_ = remainingItems(state);
        return (remaining_ + state.batchSize - 1) / state.batchSize;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CIRCULAR BUFFER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Circular buffer for fixed-size history
    struct CircularBuffer {
        bytes32[] buffer;
        uint256 head;            // Next write position
        uint256 count;           // Number of items (max = buffer.length)
    }

    /// @notice Initialize circular buffer with size
    function initCircularBuffer(uint256 size) internal pure returns (CircularBuffer memory) {
        return CircularBuffer({
            buffer: new bytes32[](size),
            head: 0,
            count: 0
        });
    }

    /// @notice Push item to circular buffer (overwrites oldest if full)
    function push(CircularBuffer storage cb, bytes32 item) internal {
        if (cb.buffer.length == 0) return;

        cb.buffer[cb.head] = item;
        cb.head = (cb.head + 1) % cb.buffer.length;

        if (cb.count < cb.buffer.length) {
            cb.count++;
        }
    }

    /// @notice Get item at index (0 = oldest)
    function at(CircularBuffer storage cb, uint256 index) internal view returns (bytes32) {
        if (index >= cb.count) revert InvalidIndex();

        uint256 actualIdx;
        if (cb.count < cb.buffer.length) {
            actualIdx = index;
        } else {
            actualIdx = (cb.head + index) % cb.buffer.length;
        }
        return cb.buffer[actualIdx];
    }

    /// @notice Get most recent item
    function latest(CircularBuffer storage cb) internal view returns (bytes32) {
        if (cb.count == 0) revert QueueEmpty();
        uint256 idx = cb.head == 0 ? cb.buffer.length - 1 : cb.head - 1;
        return cb.buffer[idx];
    }

    /// @notice Get all items in order (oldest first)
    function toArray(CircularBuffer storage cb) internal view returns (bytes32[] memory result) {
        result = new bytes32[](cb.count);

        for (uint256 i; i < cb.count; ++i) {
            result[i] = at(cb, i);
        }
    }

    /// @notice Check if buffer is full
    function isFull(CircularBuffer storage cb) internal view returns (bool) {
        return cb.count == cb.buffer.length;
    }

    /// @notice Get buffer capacity
    function capacity(CircularBuffer storage cb) internal view returns (uint256) {
        return cb.buffer.length;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEQUE (DOUBLE-ENDED QUEUE) OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add item to front of bytes32 queue
    function enqueueFront(Bytes32Queue storage queue, bytes32 item) internal {
        unchecked {
            queue.front--;
        }
        queue.items[queue.front] = item;
    }

    /// @notice Remove and return item from back of queue
    function dequeueBack(Bytes32Queue storage queue) internal returns (bytes32 item) {
        if (isEmpty(queue)) revert QueueEmpty();

        unchecked {
            queue.back--;
        }
        item = queue.items[queue.back];
        delete queue.items[queue.back];
    }

    /// @notice View back item without removing
    function peekBack(Bytes32Queue storage queue) internal view returns (bytes32) {
        if (isEmpty(queue)) revert QueueEmpty();
        return queue.items[queue.back - 1];
    }
}
