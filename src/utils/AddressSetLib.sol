// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AddressSetLib
 * @notice Gas-efficient enumerable address set library
 * @dev Implements O(1) add, remove, and contains operations with enumeration support
 */
library AddressSetLib {
    // ============ ERRORS ============
    error AddressAlreadyInSet(address addr);
    error AddressNotInSet(address addr);
    error SetIsEmpty();
    error IndexOutOfBounds(uint256 index, uint256 size);
    error InvalidPageSize(uint256 pageSize);
    error ZeroAddress();
    error SetCapacityExceeded(uint256 capacity);

    // ============ CONSTANTS ============
    uint256 internal constant MAX_SET_SIZE = 10000;
    uint256 internal constant DEFAULT_PAGE_SIZE = 100;

    // ============ TYPES ============
    struct AddressSet {
        address[] values;
        mapping(address => uint256) indexes; // 1-indexed (0 means not in set)
    }

    struct PaginatedResult {
        address[] addresses;
        uint256 totalCount;
        uint256 pageNumber;
        uint256 pageSize;
        bool hasMore;
    }

    struct SetStats {
        uint256 size;
        uint256 capacity;
        bool isEmpty;
    }

    // ============ EVENTS ============
    event AddressAdded(address indexed addr);
    event AddressRemoved(address indexed addr);
    event SetCleared(uint256 previousSize);

    // ============ CORE OPERATIONS ============

    /**
     * @notice Add an address to the set
     * @param set The address set storage
     * @param addr The address to add
     * @return True if the address was added (not already present)
     */
    function add(AddressSet storage set, address addr) internal returns (bool) {
        if (addr == address(0)) revert ZeroAddress();
        if (set.indexes[addr] != 0) return false; // Already in set

        if (set.values.length >= MAX_SET_SIZE) {
            revert SetCapacityExceeded(MAX_SET_SIZE);
        }

        set.values.push(addr);
        set.indexes[addr] = set.values.length; // 1-indexed

        return true;
    }

    /**
     * @notice Add an address to the set (reverts if already present)
     * @param set The address set storage
     * @param addr The address to add
     */
    function addStrict(AddressSet storage set, address addr) internal {
        if (addr == address(0)) revert ZeroAddress();
        if (set.indexes[addr] != 0) revert AddressAlreadyInSet(addr);

        if (set.values.length >= MAX_SET_SIZE) {
            revert SetCapacityExceeded(MAX_SET_SIZE);
        }

        set.values.push(addr);
        set.indexes[addr] = set.values.length;

        emit AddressAdded(addr);
    }

    /**
     * @notice Remove an address from the set
     * @param set The address set storage
     * @param addr The address to remove
     * @return True if the address was removed (was present)
     */
    function remove(AddressSet storage set, address addr) internal returns (bool) {
        uint256 valueIndex = set.indexes[addr];
        if (valueIndex == 0) return false; // Not in set

        // Move the last element to the deleted slot
        uint256 lastIndex = set.values.length - 1;
        address lastValue = set.values[lastIndex];

        // Update the moved element's index
        set.values[valueIndex - 1] = lastValue;
        set.indexes[lastValue] = valueIndex;

        // Remove the last element
        set.values.pop();
        delete set.indexes[addr];

        return true;
    }

    /**
     * @notice Remove an address from the set (reverts if not present)
     * @param set The address set storage
     * @param addr The address to remove
     */
    function removeStrict(AddressSet storage set, address addr) internal {
        uint256 valueIndex = set.indexes[addr];
        if (valueIndex == 0) revert AddressNotInSet(addr);

        uint256 lastIndex = set.values.length - 1;
        address lastValue = set.values[lastIndex];

        set.values[valueIndex - 1] = lastValue;
        set.indexes[lastValue] = valueIndex;

        set.values.pop();
        delete set.indexes[addr];

        emit AddressRemoved(addr);
    }

    /**
     * @notice Check if an address is in the set
     * @param set The address set storage
     * @param addr The address to check
     * @return True if the address is in the set
     */
    function contains(AddressSet storage set, address addr) internal view returns (bool) {
        return set.indexes[addr] != 0;
    }

    /**
     * @notice Get the number of addresses in the set
     * @param set The address set storage
     * @return The size of the set
     */
    function size(AddressSet storage set) internal view returns (uint256) {
        return set.values.length;
    }

    /**
     * @notice Check if the set is empty
     * @param set The address set storage
     * @return True if the set is empty
     */
    function isEmpty(AddressSet storage set) internal view returns (bool) {
        return set.values.length == 0;
    }

    // ============ ACCESS FUNCTIONS ============

    /**
     * @notice Get address at a specific index
     * @param set The address set storage
     * @param index The index (0-based)
     * @return The address at the index
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        if (index >= set.values.length) {
            revert IndexOutOfBounds(index, set.values.length);
        }
        return set.values[index];
    }

    /**
     * @notice Get all addresses in the set
     * @param set The address set storage
     * @return Array of all addresses
     */
    function getAll(AddressSet storage set) internal view returns (address[] memory) {
        return set.values;
    }

    /**
     * @notice Get addresses with pagination
     * @param set The address set storage
     * @param offset Starting index
     * @param limit Maximum number of addresses to return
     * @return addresses Array of addresses
     * @return total Total number of addresses in set
     */
    function getPage(
        AddressSet storage set,
        uint256 offset,
        uint256 limit
    ) internal view returns (address[] memory addresses, uint256 total) {
        total = set.values.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 count = remaining < limit ? remaining : limit;

        addresses = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            addresses[i] = set.values[offset + i];
        }
    }

    /**
     * @notice Get paginated result with metadata
     * @param set The address set storage
     * @param pageNumber Page number (0-indexed)
     * @param pageSize Items per page
     * @return result Paginated result with metadata
     */
    function getPaginated(
        AddressSet storage set,
        uint256 pageNumber,
        uint256 pageSize
    ) internal view returns (PaginatedResult memory result) {
        if (pageSize == 0) revert InvalidPageSize(pageSize);

        result.totalCount = set.values.length;
        result.pageNumber = pageNumber;
        result.pageSize = pageSize;

        uint256 offset = pageNumber * pageSize;
        if (offset >= result.totalCount) {
            result.addresses = new address[](0);
            result.hasMore = false;
            return result;
        }

        uint256 remaining = result.totalCount - offset;
        uint256 count = remaining < pageSize ? remaining : pageSize;

        result.addresses = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result.addresses[i] = set.values[offset + i];
        }

        result.hasMore = offset + count < result.totalCount;
    }

    // ============ BULK OPERATIONS ============

    /**
     * @notice Add multiple addresses to the set
     * @param set The address set storage
     * @param addresses Array of addresses to add
     * @return addedCount Number of addresses actually added
     */
    function addMany(
        AddressSet storage set,
        address[] memory addresses
    ) internal returns (uint256 addedCount) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (add(set, addresses[i])) {
                addedCount++;
            }
        }
    }

    /**
     * @notice Remove multiple addresses from the set
     * @param set The address set storage
     * @param addresses Array of addresses to remove
     * @return removedCount Number of addresses actually removed
     */
    function removeMany(
        AddressSet storage set,
        address[] memory addresses
    ) internal returns (uint256 removedCount) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (remove(set, addresses[i])) {
                removedCount++;
            }
        }
    }

    /**
     * @notice Clear all addresses from the set
     * @param set The address set storage
     * @return previousSize The number of addresses that were removed
     */
    function clear(AddressSet storage set) internal returns (uint256 previousSize) {
        previousSize = set.values.length;

        for (uint256 i = 0; i < previousSize; i++) {
            delete set.indexes[set.values[i]];
        }
        delete set.values;

        emit SetCleared(previousSize);
    }

    // ============ SET OPERATIONS ============

    /**
     * @notice Check if set A is a subset of set B
     * @param setA The potential subset
     * @param setB The potential superset
     * @return True if A is a subset of B
     */
    function isSubsetOf(
        AddressSet storage setA,
        AddressSet storage setB
    ) internal view returns (bool) {
        if (setA.values.length > setB.values.length) return false;

        for (uint256 i = 0; i < setA.values.length; i++) {
            if (!contains(setB, setA.values[i])) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Get intersection of two sets
     * @param setA First set
     * @param setB Second set
     * @return intersection Array of addresses in both sets
     */
    function getIntersection(
        AddressSet storage setA,
        AddressSet storage setB
    ) internal view returns (address[] memory intersection) {
        // Use the smaller set for iteration
        AddressSet storage smaller = setA.values.length <= setB.values.length ? setA : setB;
        AddressSet storage larger = setA.values.length <= setB.values.length ? setB : setA;

        address[] memory temp = new address[](smaller.values.length);
        uint256 count = 0;

        for (uint256 i = 0; i < smaller.values.length; i++) {
            if (contains(larger, smaller.values[i])) {
                temp[count] = smaller.values[i];
                count++;
            }
        }

        intersection = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            intersection[i] = temp[i];
        }
    }

    /**
     * @notice Get difference (A - B)
     * @param setA First set
     * @param setB Second set
     * @return difference Array of addresses in A but not in B
     */
    function getDifference(
        AddressSet storage setA,
        AddressSet storage setB
    ) internal view returns (address[] memory difference) {
        address[] memory temp = new address[](setA.values.length);
        uint256 count = 0;

        for (uint256 i = 0; i < setA.values.length; i++) {
            if (!contains(setB, setA.values[i])) {
                temp[count] = setA.values[i];
                count++;
            }
        }

        difference = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            difference[i] = temp[i];
        }
    }

    // ============ QUERY FUNCTIONS ============

    /**
     * @notice Find addresses matching a filter
     * @param set The address set storage
     * @param filter Function that returns true for matching addresses
     * @return matches Array of matching addresses
     */
    function findWhere(
        AddressSet storage set,
        function(address) view returns (bool) filter
    ) internal view returns (address[] memory matches) {
        address[] memory temp = new address[](set.values.length);
        uint256 count = 0;

        for (uint256 i = 0; i < set.values.length; i++) {
            if (filter(set.values[i])) {
                temp[count] = set.values[i];
                count++;
            }
        }

        matches = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            matches[i] = temp[i];
        }
    }

    /**
     * @notice Count addresses matching a filter
     * @param set The address set storage
     * @param filter Function that returns true for matching addresses
     * @return count Number of matching addresses
     */
    function countWhere(
        AddressSet storage set,
        function(address) view returns (bool) filter
    ) internal view returns (uint256 count) {
        for (uint256 i = 0; i < set.values.length; i++) {
            if (filter(set.values[i])) {
                count++;
            }
        }
    }

    /**
     * @notice Get random address from set (pseudo-random based on block data)
     * @param set The address set storage
     * @return addr A pseudo-random address from the set
     */
    function getRandom(AddressSet storage set) internal view returns (address addr) {
        if (set.values.length == 0) revert SetIsEmpty();

        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))
        ) % set.values.length;

        return set.values[randomIndex];
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Get set statistics
     * @param set The address set storage
     * @return stats Set statistics
     */
    function getStats(AddressSet storage set) internal view returns (SetStats memory stats) {
        return SetStats({
            size: set.values.length,
            capacity: MAX_SET_SIZE,
            isEmpty: set.values.length == 0
        });
    }

    /**
     * @notice Get the index of an address in the set
     * @param set The address set storage
     * @param addr The address to find
     * @return index The index (0-based), or type(uint256).max if not found
     */
    function indexOf(
        AddressSet storage set,
        address addr
    ) internal view returns (uint256 index) {
        uint256 storedIndex = set.indexes[addr];
        if (storedIndex == 0) return type(uint256).max;
        return storedIndex - 1; // Convert from 1-indexed to 0-indexed
    }

    /**
     * @notice Check if set contains all given addresses
     * @param set The address set storage
     * @param addresses Array of addresses to check
     * @return True if all addresses are in the set
     */
    function containsAll(
        AddressSet storage set,
        address[] memory addresses
    ) internal view returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!contains(set, addresses[i])) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Check if set contains any of the given addresses
     * @param set The address set storage
     * @param addresses Array of addresses to check
     * @return True if any address is in the set
     */
    function containsAny(
        AddressSet storage set,
        address[] memory addresses
    ) internal view returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (contains(set, addresses[i])) {
                return true;
            }
        }
        return false;
    }
}
