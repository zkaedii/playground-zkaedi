// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MinHeapLib
 * @notice Gas-efficient min-heap (priority queue) implementation
 * @dev Provides O(log n) insert and extract-min operations
 *      Perfect for:
 *      - Order books (price priority)
 *      - Auction systems
 *      - Task scheduling by deadline/priority
 *      - Finding top-K elements
 *
 *      The heap property: parent <= children (for min-heap)
 */
library MinHeapLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Heap entry with value and associated data
     */
    struct Entry {
        uint256 priority;  // The priority/key for ordering
        bytes32 data;      // Associated data (can encode address, uint, etc.)
    }

    /**
     * @dev Min-heap structure
     */
    struct Heap {
        Entry[] entries;
    }

    /**
     * @dev Uint256 min-heap (simpler, for just priority values)
     */
    struct UintHeap {
        uint256[] values;
    }

    /**
     * @dev Address-keyed heap with priorities
     */
    struct AddressHeap {
        Entry[] entries;
        mapping(address => uint256) indexOf;  // address -> index + 1 (0 = not present)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error HeapEmpty();
    error HeapFull();
    error EntryNotFound();
    error DuplicateEntry();

    // ═══════════════════════════════════════════════════════════════════════════
    // MIN HEAP (ENTRY-BASED)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Inserts an entry into the heap
     * @param heap The heap to modify
     * @param priority The priority (lower = higher priority for min-heap)
     * @param data Associated data
     */
    function insert(Heap storage heap, uint256 priority, bytes32 data) internal {
        // Add to end
        heap.entries.push(Entry(priority, data));

        // Bubble up
        _bubbleUp(heap, heap.entries.length - 1);
    }

    /**
     * @notice Removes and returns the minimum entry
     * @param heap The heap to modify
     * @return priority The minimum priority
     * @return data The associated data
     */
    function extractMin(Heap storage heap) internal returns (uint256 priority, bytes32 data) {
        if (heap.entries.length == 0) revert HeapEmpty();

        Entry memory min = heap.entries[0];
        priority = min.priority;
        data = min.data;

        // Move last element to root
        uint256 lastIndex = heap.entries.length - 1;
        if (lastIndex > 0) {
            heap.entries[0] = heap.entries[lastIndex];
        }
        heap.entries.pop();

        // Bubble down
        if (heap.entries.length > 0) {
            _bubbleDown(heap, 0);
        }
    }

    /**
     * @notice Returns the minimum entry without removing it
     * @param heap The heap to peek
     * @return priority The minimum priority
     * @return data The associated data
     */
    function peekMin(Heap storage heap) internal view returns (uint256 priority, bytes32 data) {
        if (heap.entries.length == 0) revert HeapEmpty();
        Entry memory min = heap.entries[0];
        return (min.priority, min.data);
    }

    /**
     * @notice Returns the number of entries in the heap
     */
    function size(Heap storage heap) internal view returns (uint256) {
        return heap.entries.length;
    }

    /**
     * @notice Checks if the heap is empty
     */
    function isEmpty(Heap storage heap) internal view returns (bool) {
        return heap.entries.length == 0;
    }

    /**
     * @notice Clears all entries from the heap
     */
    function clear(Heap storage heap) internal {
        delete heap.entries;
    }

    /**
     * @dev Bubbles an entry up to maintain heap property
     */
    function _bubbleUp(Heap storage heap, uint256 index) private {
        while (index > 0) {
            uint256 parentIndex = (index - 1) / 2;

            if (heap.entries[index].priority >= heap.entries[parentIndex].priority) {
                break;
            }

            // Swap with parent
            Entry memory temp = heap.entries[index];
            heap.entries[index] = heap.entries[parentIndex];
            heap.entries[parentIndex] = temp;

            index = parentIndex;
        }
    }

    /**
     * @dev Bubbles an entry down to maintain heap property
     */
    function _bubbleDown(Heap storage heap, uint256 index) private {
        uint256 len = heap.entries.length;

        while (true) {
            uint256 smallest = index;
            uint256 left = 2 * index + 1;
            uint256 right = 2 * index + 2;

            if (left < len && heap.entries[left].priority < heap.entries[smallest].priority) {
                smallest = left;
            }

            if (right < len && heap.entries[right].priority < heap.entries[smallest].priority) {
                smallest = right;
            }

            if (smallest == index) break;

            // Swap
            Entry memory temp = heap.entries[index];
            heap.entries[index] = heap.entries[smallest];
            heap.entries[smallest] = temp;

            index = smallest;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT HEAP (SIMPLER)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Inserts a value into the uint heap
     */
    function insert(UintHeap storage heap, uint256 value) internal {
        heap.values.push(value);
        _bubbleUpUint(heap, heap.values.length - 1);
    }

    /**
     * @notice Removes and returns the minimum value
     */
    function extractMin(UintHeap storage heap) internal returns (uint256 value) {
        if (heap.values.length == 0) revert HeapEmpty();

        value = heap.values[0];

        uint256 lastIndex = heap.values.length - 1;
        if (lastIndex > 0) {
            heap.values[0] = heap.values[lastIndex];
        }
        heap.values.pop();

        if (heap.values.length > 0) {
            _bubbleDownUint(heap, 0);
        }
    }

    /**
     * @notice Returns the minimum value without removing it
     */
    function peekMin(UintHeap storage heap) internal view returns (uint256 value) {
        if (heap.values.length == 0) revert HeapEmpty();
        return heap.values[0];
    }

    function size(UintHeap storage heap) internal view returns (uint256) {
        return heap.values.length;
    }

    function isEmpty(UintHeap storage heap) internal view returns (bool) {
        return heap.values.length == 0;
    }

    function _bubbleUpUint(UintHeap storage heap, uint256 index) private {
        while (index > 0) {
            uint256 parentIndex = (index - 1) / 2;
            if (heap.values[index] >= heap.values[parentIndex]) break;

            uint256 temp = heap.values[index];
            heap.values[index] = heap.values[parentIndex];
            heap.values[parentIndex] = temp;

            index = parentIndex;
        }
    }

    function _bubbleDownUint(UintHeap storage heap, uint256 index) private {
        uint256 len = heap.values.length;

        while (true) {
            uint256 smallest = index;
            uint256 left = 2 * index + 1;
            uint256 right = 2 * index + 2;

            if (left < len && heap.values[left] < heap.values[smallest]) {
                smallest = left;
            }
            if (right < len && heap.values[right] < heap.values[smallest]) {
                smallest = right;
            }

            if (smallest == index) break;

            uint256 temp = heap.values[index];
            heap.values[index] = heap.values[smallest];
            heap.values[smallest] = temp;

            index = smallest;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS HEAP (WITH UPDATE SUPPORT)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Inserts an address with priority (or updates if exists)
     */
    function insertOrUpdate(
        AddressHeap storage heap,
        address addr,
        uint256 priority
    ) internal {
        uint256 indexPlusOne = heap.indexOf[addr];

        if (indexPlusOne == 0) {
            // New entry
            heap.entries.push(Entry(priority, bytes32(uint256(uint160(addr)))));
            uint256 newIndex = heap.entries.length - 1;
            heap.indexOf[addr] = newIndex + 1;
            _bubbleUpAddr(heap, newIndex);
        } else {
            // Update existing
            uint256 index = indexPlusOne - 1;
            uint256 oldPriority = heap.entries[index].priority;
            heap.entries[index].priority = priority;

            if (priority < oldPriority) {
                _bubbleUpAddr(heap, index);
            } else if (priority > oldPriority) {
                _bubbleDownAddr(heap, index);
            }
        }
    }

    /**
     * @notice Removes and returns the minimum entry
     */
    function extractMin(AddressHeap storage heap) internal returns (address addr, uint256 priority) {
        if (heap.entries.length == 0) revert HeapEmpty();

        Entry memory min = heap.entries[0];
        addr = address(uint160(uint256(min.data)));
        priority = min.priority;

        // Clear mapping for extracted address
        delete heap.indexOf[addr];

        // Move last element to root
        uint256 lastIndex = heap.entries.length - 1;
        if (lastIndex > 0) {
            Entry memory last = heap.entries[lastIndex];
            heap.entries[0] = last;
            address lastAddr = address(uint160(uint256(last.data)));
            heap.indexOf[lastAddr] = 1;
        }
        heap.entries.pop();

        // Bubble down
        if (heap.entries.length > 0) {
            _bubbleDownAddr(heap, 0);
        }
    }

    /**
     * @notice Returns the minimum entry without removing it
     */
    function peekMin(AddressHeap storage heap) internal view returns (address addr, uint256 priority) {
        if (heap.entries.length == 0) revert HeapEmpty();
        Entry memory min = heap.entries[0];
        addr = address(uint160(uint256(min.data)));
        priority = min.priority;
    }

    /**
     * @notice Checks if an address is in the heap
     */
    function contains(AddressHeap storage heap, address addr) internal view returns (bool) {
        return heap.indexOf[addr] != 0;
    }

    /**
     * @notice Gets the priority of an address
     */
    function getPriority(AddressHeap storage heap, address addr) internal view returns (uint256) {
        uint256 indexPlusOne = heap.indexOf[addr];
        if (indexPlusOne == 0) revert EntryNotFound();
        return heap.entries[indexPlusOne - 1].priority;
    }

    /**
     * @notice Removes a specific address from the heap
     */
    function remove(AddressHeap storage heap, address addr) internal returns (uint256 priority) {
        uint256 indexPlusOne = heap.indexOf[addr];
        if (indexPlusOne == 0) revert EntryNotFound();

        uint256 index = indexPlusOne - 1;
        priority = heap.entries[index].priority;

        // Clear mapping
        delete heap.indexOf[addr];

        // Move last element to the removed position
        uint256 lastIndex = heap.entries.length - 1;
        if (index != lastIndex) {
            Entry memory last = heap.entries[lastIndex];
            heap.entries[index] = last;
            address lastAddr = address(uint160(uint256(last.data)));
            heap.indexOf[lastAddr] = index + 1;

            // Re-heapify
            if (last.priority < priority) {
                _bubbleUpAddr(heap, index);
            } else {
                _bubbleDownAddr(heap, index);
            }
        }
        heap.entries.pop();
    }

    function size(AddressHeap storage heap) internal view returns (uint256) {
        return heap.entries.length;
    }

    function isEmpty(AddressHeap storage heap) internal view returns (bool) {
        return heap.entries.length == 0;
    }

    function _bubbleUpAddr(AddressHeap storage heap, uint256 index) private {
        while (index > 0) {
            uint256 parentIndex = (index - 1) / 2;
            if (heap.entries[index].priority >= heap.entries[parentIndex].priority) break;

            // Swap
            Entry memory temp = heap.entries[index];
            heap.entries[index] = heap.entries[parentIndex];
            heap.entries[parentIndex] = temp;

            // Update indexes
            address childAddr = address(uint160(uint256(temp.data)));
            address parentAddr = address(uint160(uint256(heap.entries[index].data)));
            heap.indexOf[childAddr] = parentIndex + 1;
            heap.indexOf[parentAddr] = index + 1;

            index = parentIndex;
        }
    }

    function _bubbleDownAddr(AddressHeap storage heap, uint256 index) private {
        uint256 len = heap.entries.length;

        while (true) {
            uint256 smallest = index;
            uint256 left = 2 * index + 1;
            uint256 right = 2 * index + 2;

            if (left < len && heap.entries[left].priority < heap.entries[smallest].priority) {
                smallest = left;
            }
            if (right < len && heap.entries[right].priority < heap.entries[smallest].priority) {
                smallest = right;
            }

            if (smallest == index) break;

            // Swap
            Entry memory temp = heap.entries[index];
            heap.entries[index] = heap.entries[smallest];
            heap.entries[smallest] = temp;

            // Update indexes
            address currentAddr = address(uint160(uint256(temp.data)));
            address smallestAddr = address(uint160(uint256(heap.entries[index].data)));
            heap.indexOf[currentAddr] = smallest + 1;
            heap.indexOf[smallestAddr] = index + 1;

            index = smallest;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BULK OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Builds a heap from an array (heapify)
     * @dev O(n) time complexity using bottom-up heapify
     */
    function heapify(UintHeap storage heap, uint256[] memory values) internal {
        // Clear existing
        delete heap.values;

        // Copy values
        for (uint256 i = 0; i < values.length; i++) {
            heap.values.push(values[i]);
        }

        // Bottom-up heapify
        if (heap.values.length > 1) {
            uint256 start = (heap.values.length - 2) / 2;
            for (uint256 i = start + 1; i > 0; ) {
                i--;
                _bubbleDownUint(heap, i);
            }
        }
    }

    /**
     * @notice Extracts the k smallest elements
     */
    function extractKSmallest(
        UintHeap storage heap,
        uint256 k
    ) internal returns (uint256[] memory smallest) {
        uint256 count = k < heap.values.length ? k : heap.values.length;
        smallest = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            smallest[i] = extractMin(heap);
        }
    }

    /**
     * @notice Returns all values as a sorted array (destructive)
     */
    function toSortedArray(UintHeap storage heap) internal returns (uint256[] memory sorted) {
        uint256 len = heap.values.length;
        sorted = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            sorted[i] = extractMin(heap);
        }
    }
}
