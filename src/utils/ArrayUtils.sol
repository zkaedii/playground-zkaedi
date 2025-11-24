// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ArrayUtils
 * @notice Gas-efficient array manipulation utilities
 * @dev Provides add, remove, search, and batch operations for dynamic arrays
 */
library ArrayUtils {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error IndexOutOfBounds();
    error ElementNotFound();
    error EmptyArray();
    error DuplicateElement();
    error ArrayTooLarge();

    // ═══════════════════════════════════════════════════════════════════════════
    // BYTES32 ARRAY OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if array contains an element
     * @param arr Array to search
     * @param element Element to find
     * @return True if element exists
     */
    function contains(bytes32[] storage arr, bytes32 element) internal view returns (bool) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Find index of element in array
     * @param arr Array to search
     * @param element Element to find
     * @return found True if found
     * @return index Index of element (0 if not found)
     */
    function indexOf(bytes32[] storage arr, bytes32 element) internal view returns (bool found, uint256 index) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) {
                return (true, i);
            }
            unchecked { ++i; }
        }
        return (false, 0);
    }

    /**
     * @notice Add element to array (no duplicate check)
     * @param arr Array to modify
     * @param element Element to add
     */
    function push(bytes32[] storage arr, bytes32 element) internal {
        arr.push(element);
    }

    /**
     * @notice Add element if not already present
     * @param arr Array to modify
     * @param element Element to add
     * @return added True if element was added
     */
    function addUnique(bytes32[] storage arr, bytes32 element) internal returns (bool added) {
        if (!contains(arr, element)) {
            arr.push(element);
            return true;
        }
        return false;
    }

    /**
     * @notice Remove element at index using swap-and-pop (O(1), changes order)
     * @param arr Array to modify
     * @param index Index to remove
     * @return removed The removed element
     */
    function removeAt(bytes32[] storage arr, uint256 index) internal returns (bytes32 removed) {
        uint256 length = arr.length;
        if (index >= length) revert IndexOutOfBounds();

        removed = arr[index];
        uint256 lastIndex = length - 1;

        if (index != lastIndex) {
            arr[index] = arr[lastIndex];
        }
        arr.pop();
    }

    /**
     * @notice Remove element at index maintaining order (O(n), preserves order)
     * @param arr Array to modify
     * @param index Index to remove
     * @return removed The removed element
     */
    function removeAtOrdered(bytes32[] storage arr, uint256 index) internal returns (bytes32 removed) {
        uint256 length = arr.length;
        if (index >= length) revert IndexOutOfBounds();

        removed = arr[index];

        for (uint256 i = index; i < length - 1;) {
            arr[i] = arr[i + 1];
            unchecked { ++i; }
        }
        arr.pop();
    }

    /**
     * @notice Remove first occurrence of element using swap-and-pop
     * @param arr Array to modify
     * @param element Element to remove
     * @return removed True if element was found and removed
     */
    function remove(bytes32[] storage arr, bytes32 element) internal returns (bool removed) {
        (bool found, uint256 index) = indexOf(arr, element);
        if (found) {
            removeAt(arr, index);
            return true;
        }
        return false;
    }

    /**
     * @notice Remove all occurrences of element
     * @param arr Array to modify
     * @param element Element to remove
     * @return count Number of elements removed
     */
    function removeAll(bytes32[] storage arr, bytes32 element) internal returns (uint256 count) {
        uint256 i = arr.length;
        while (i > 0) {
            unchecked { --i; }
            if (arr[i] == element) {
                removeAt(arr, i);
                unchecked { ++count; }
            }
        }
    }

    /**
     * @notice Clear all elements from array
     * @param arr Array to clear
     */
    function clear(bytes32[] storage arr) internal {
        while (arr.length > 0) {
            arr.pop();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS ARRAY OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if array contains an address
     */
    function contains(address[] storage arr, address element) internal view returns (bool) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Find index of address in array
     */
    function indexOf(address[] storage arr, address element) internal view returns (bool found, uint256 index) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) {
                return (true, i);
            }
            unchecked { ++i; }
        }
        return (false, 0);
    }

    /**
     * @notice Add address if not already present
     */
    function addUnique(address[] storage arr, address element) internal returns (bool added) {
        if (!contains(arr, element)) {
            arr.push(element);
            return true;
        }
        return false;
    }

    /**
     * @notice Remove address at index using swap-and-pop
     */
    function removeAt(address[] storage arr, uint256 index) internal returns (address removed) {
        uint256 length = arr.length;
        if (index >= length) revert IndexOutOfBounds();

        removed = arr[index];
        uint256 lastIndex = length - 1;

        if (index != lastIndex) {
            arr[index] = arr[lastIndex];
        }
        arr.pop();
    }

    /**
     * @notice Remove first occurrence of address
     */
    function remove(address[] storage arr, address element) internal returns (bool removed) {
        (bool found, uint256 index) = indexOf(arr, element);
        if (found) {
            removeAt(arr, index);
            return true;
        }
        return false;
    }

    /**
     * @notice Clear all addresses from array
     */
    function clear(address[] storage arr) internal {
        while (arr.length > 0) {
            arr.pop();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT256 ARRAY OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if array contains a uint256
     */
    function contains(uint256[] storage arr, uint256 element) internal view returns (bool) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Find index of uint256 in array
     */
    function indexOf(uint256[] storage arr, uint256 element) internal view returns (bool found, uint256 index) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) {
                return (true, i);
            }
            unchecked { ++i; }
        }
        return (false, 0);
    }

    /**
     * @notice Remove uint256 at index using swap-and-pop
     */
    function removeAt(uint256[] storage arr, uint256 index) internal returns (uint256 removed) {
        uint256 length = arr.length;
        if (index >= length) revert IndexOutOfBounds();

        removed = arr[index];
        uint256 lastIndex = length - 1;

        if (index != lastIndex) {
            arr[index] = arr[lastIndex];
        }
        arr.pop();
    }

    /**
     * @notice Remove first occurrence of uint256
     */
    function remove(uint256[] storage arr, uint256 element) internal returns (bool removed) {
        (bool found, uint256 index) = indexOf(arr, element);
        if (found) {
            removeAt(arr, index);
            return true;
        }
        return false;
    }

    /**
     * @notice Calculate sum of all elements
     */
    function sum(uint256[] storage arr) internal view returns (uint256 total) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            total += arr[i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Find minimum value in array
     */
    function min(uint256[] storage arr) internal view returns (uint256 minVal) {
        uint256 length = arr.length;
        if (length == 0) revert EmptyArray();
        minVal = arr[0];
        for (uint256 i = 1; i < length;) {
            if (arr[i] < minVal) minVal = arr[i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Find maximum value in array
     */
    function max(uint256[] storage arr) internal view returns (uint256 maxVal) {
        uint256 length = arr.length;
        if (length == 0) revert EmptyArray();
        maxVal = arr[0];
        for (uint256 i = 1; i < length;) {
            if (arr[i] > maxVal) maxVal = arr[i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Calculate average of all elements
     */
    function average(uint256[] storage arr) internal view returns (uint256) {
        uint256 length = arr.length;
        if (length == 0) revert EmptyArray();
        return sum(arr) / length;
    }

    /**
     * @notice Clear all uint256s from array
     */
    function clear(uint256[] storage arr) internal {
        while (arr.length > 0) {
            arr.pop();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MEMORY ARRAY UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if memory array contains bytes32
     */
    function containsMem(bytes32[] memory arr, bytes32 element) internal pure returns (bool) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Check if memory array contains address
     */
    function containsMem(address[] memory arr, address element) internal pure returns (bool) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Check if memory array contains uint256
     */
    function containsMem(uint256[] memory arr, uint256 element) internal pure returns (bool) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) return true;
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @notice Find index in memory array
     */
    function indexOfMem(bytes32[] memory arr, bytes32 element) internal pure returns (bool found, uint256 index) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            if (arr[i] == element) {
                return (true, i);
            }
            unchecked { ++i; }
        }
        return (false, 0);
    }

    /**
     * @notice Sum memory array
     */
    function sumMem(uint256[] memory arr) internal pure returns (uint256 total) {
        uint256 length = arr.length;
        for (uint256 i; i < length;) {
            total += arr[i];
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SLICE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get slice of bytes32 array (memory to memory)
     * @param arr Source array
     * @param start Start index
     * @param end End index (exclusive)
     * @return result New array containing slice
     */
    function slice(
        bytes32[] memory arr,
        uint256 start,
        uint256 end
    ) internal pure returns (bytes32[] memory result) {
        if (end > arr.length) end = arr.length;
        if (start >= end) return new bytes32[](0);

        uint256 length = end - start;
        result = new bytes32[](length);
        for (uint256 i; i < length;) {
            result[i] = arr[start + i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Get slice of address array
     */
    function slice(
        address[] memory arr,
        uint256 start,
        uint256 end
    ) internal pure returns (address[] memory result) {
        if (end > arr.length) end = arr.length;
        if (start >= end) return new address[](0);

        uint256 length = end - start;
        result = new address[](length);
        for (uint256 i; i < length;) {
            result[i] = arr[start + i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Get slice of uint256 array
     */
    function slice(
        uint256[] memory arr,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256[] memory result) {
        if (end > arr.length) end = arr.length;
        if (start >= end) return new uint256[](0);

        uint256 length = end - start;
        result = new uint256[](length);
        for (uint256 i; i < length;) {
            result[i] = arr[start + i];
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REVERSE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reverse array in place
     */
    function reverse(bytes32[] memory arr) internal pure {
        uint256 length = arr.length;
        for (uint256 i; i < length / 2;) {
            uint256 j = length - 1 - i;
            (arr[i], arr[j]) = (arr[j], arr[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Reverse address array in place
     */
    function reverse(address[] memory arr) internal pure {
        uint256 length = arr.length;
        for (uint256 i; i < length / 2;) {
            uint256 j = length - 1 - i;
            (arr[i], arr[j]) = (arr[j], arr[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Reverse uint256 array in place
     */
    function reverse(uint256[] memory arr) internal pure {
        uint256 length = arr.length;
        for (uint256 i; i < length / 2;) {
            uint256 j = length - 1 - i;
            (arr[i], arr[j]) = (arr[j], arr[i]);
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEDUPLICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Remove duplicates from memory array (keeps first occurrence)
     * @dev O(n^2) - use only for small arrays
     */
    function deduplicate(bytes32[] memory arr) internal pure returns (bytes32[] memory result) {
        uint256 length = arr.length;
        if (length <= 1) return arr;

        bytes32[] memory temp = new bytes32[](length);
        uint256 uniqueCount;

        for (uint256 i; i < length;) {
            bool isDuplicate;
            for (uint256 j; j < uniqueCount;) {
                if (temp[j] == arr[i]) {
                    isDuplicate = true;
                    break;
                }
                unchecked { ++j; }
            }
            if (!isDuplicate) {
                temp[uniqueCount] = arr[i];
                unchecked { ++uniqueCount; }
            }
            unchecked { ++i; }
        }

        result = new bytes32[](uniqueCount);
        for (uint256 i; i < uniqueCount;) {
            result[i] = temp[i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Remove duplicate addresses
     */
    function deduplicate(address[] memory arr) internal pure returns (address[] memory result) {
        uint256 length = arr.length;
        if (length <= 1) return arr;

        address[] memory temp = new address[](length);
        uint256 uniqueCount;

        for (uint256 i; i < length;) {
            bool isDuplicate;
            for (uint256 j; j < uniqueCount;) {
                if (temp[j] == arr[i]) {
                    isDuplicate = true;
                    break;
                }
                unchecked { ++j; }
            }
            if (!isDuplicate) {
                temp[uniqueCount] = arr[i];
                unchecked { ++uniqueCount; }
            }
            unchecked { ++i; }
        }

        result = new address[](uniqueCount);
        for (uint256 i; i < uniqueCount;) {
            result[i] = temp[i];
            unchecked { ++i; }
        }
    }
}
