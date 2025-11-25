// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EnumerableMapLib
 * @notice Gas-efficient enumerable key-value mapping implementation
 * @dev Provides O(1) add, remove, contains operations with enumeration capability
 *      Supports multiple map types: address->uint256, uint256->uint256, bytes32->bytes32
 *      Perfect for tracking token holdings, user balances, or any enumerable mapping needs
 */
library EnumerableMapLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Core map structure using bytes32 for maximum flexibility
     *      Can be cast to more specific types via wrapper functions
     */
    struct Bytes32ToBytes32Map {
        // Storage for key-value pairs
        bytes32[] _keys;
        mapping(bytes32 => bytes32) _values;
        mapping(bytes32 => uint256) _indexes; // key -> index + 1 (0 means not present)
    }

    /**
     * @dev Address to uint256 map - common for token balances, votes, etc.
     */
    struct AddressToUintMap {
        Bytes32ToBytes32Map _inner;
    }

    /**
     * @dev Uint256 to uint256 map - useful for ID-based lookups
     */
    struct UintToUintMap {
        Bytes32ToBytes32Map _inner;
    }

    /**
     * @dev Uint256 to address map - useful for indexed address storage
     */
    struct UintToAddressMap {
        Bytes32ToBytes32Map _inner;
    }

    /**
     * @dev Address to address map - useful for delegates, proxies, etc.
     */
    struct AddressToAddressMap {
        Bytes32ToBytes32Map _inner;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error KeyNotFound(bytes32 key);
    error IndexOutOfBounds(uint256 index, uint256 length);
    error KeyAlreadyExists(bytes32 key);

    // ═══════════════════════════════════════════════════════════════════════════
    // BYTES32 -> BYTES32 MAP (CORE IMPLEMENTATION)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Adds or updates a key-value pair
     * @param map The map to modify
     * @param key The key to set
     * @param value The value to associate
     * @return added True if this is a new key, false if updating
     */
    function set(
        Bytes32ToBytes32Map storage map,
        bytes32 key,
        bytes32 value
    ) internal returns (bool added) {
        if (map._indexes[key] == 0) {
            // New key
            map._keys.push(key);
            map._indexes[key] = map._keys.length; // Store index + 1
            added = true;
        }
        map._values[key] = value;
    }

    /**
     * @notice Removes a key-value pair
     * @param map The map to modify
     * @param key The key to remove
     * @return removed True if the key was present and removed
     */
    function remove(
        Bytes32ToBytes32Map storage map,
        bytes32 key
    ) internal returns (bool removed) {
        uint256 keyIndex = map._indexes[key];
        if (keyIndex == 0) {
            return false;
        }

        // Swap with last element and pop
        uint256 lastIndex = map._keys.length - 1;
        uint256 targetIndex = keyIndex - 1;

        if (targetIndex != lastIndex) {
            bytes32 lastKey = map._keys[lastIndex];
            map._keys[targetIndex] = lastKey;
            map._indexes[lastKey] = keyIndex;
        }

        map._keys.pop();
        delete map._values[key];
        delete map._indexes[key];

        return true;
    }

    /**
     * @notice Checks if a key exists in the map
     * @param map The map to check
     * @param key The key to look for
     * @return exists True if the key is present
     */
    function contains(
        Bytes32ToBytes32Map storage map,
        bytes32 key
    ) internal view returns (bool exists) {
        return map._indexes[key] != 0;
    }

    /**
     * @notice Returns the number of key-value pairs
     * @param map The map to query
     * @return count The number of entries
     */
    function length(Bytes32ToBytes32Map storage map) internal view returns (uint256 count) {
        return map._keys.length;
    }

    /**
     * @notice Returns the key-value pair at a given index
     * @param map The map to query
     * @param index The index to retrieve
     * @return key The key at the index
     * @return value The associated value
     */
    function at(
        Bytes32ToBytes32Map storage map,
        uint256 index
    ) internal view returns (bytes32 key, bytes32 value) {
        if (index >= map._keys.length) {
            revert IndexOutOfBounds(index, map._keys.length);
        }
        key = map._keys[index];
        value = map._values[key];
    }

    /**
     * @notice Gets the value for a key
     * @param map The map to query
     * @param key The key to look up
     * @return value The associated value
     */
    function get(
        Bytes32ToBytes32Map storage map,
        bytes32 key
    ) internal view returns (bytes32 value) {
        if (map._indexes[key] == 0) {
            revert KeyNotFound(key);
        }
        return map._values[key];
    }

    /**
     * @notice Gets the value for a key, or a default if not found
     * @param map The map to query
     * @param key The key to look up
     * @param defaultValue Value to return if key not found
     * @return value The associated value or default
     */
    function tryGet(
        Bytes32ToBytes32Map storage map,
        bytes32 key,
        bytes32 defaultValue
    ) internal view returns (bytes32 value) {
        if (map._indexes[key] == 0) {
            return defaultValue;
        }
        return map._values[key];
    }

    /**
     * @notice Returns all keys in the map
     * @param map The map to query
     * @return keys Array of all keys
     */
    function keys(Bytes32ToBytes32Map storage map) internal view returns (bytes32[] memory) {
        return map._keys;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS -> UINT256 MAP
    // ═══════════════════════════════════════════════════════════════════════════

    function set(
        AddressToUintMap storage map,
        address key,
        uint256 value
    ) internal returns (bool) {
        return set(map._inner, bytes32(uint256(uint160(key))), bytes32(value));
    }

    function remove(AddressToUintMap storage map, address key) internal returns (bool) {
        return remove(map._inner, bytes32(uint256(uint160(key))));
    }

    function contains(AddressToUintMap storage map, address key) internal view returns (bool) {
        return contains(map._inner, bytes32(uint256(uint160(key))));
    }

    function length(AddressToUintMap storage map) internal view returns (uint256) {
        return length(map._inner);
    }

    function at(
        AddressToUintMap storage map,
        uint256 index
    ) internal view returns (address key, uint256 value) {
        (bytes32 k, bytes32 v) = at(map._inner, index);
        key = address(uint160(uint256(k)));
        value = uint256(v);
    }

    function get(AddressToUintMap storage map, address key) internal view returns (uint256) {
        return uint256(get(map._inner, bytes32(uint256(uint160(key)))));
    }

    function tryGet(
        AddressToUintMap storage map,
        address key,
        uint256 defaultValue
    ) internal view returns (uint256) {
        return uint256(tryGet(map._inner, bytes32(uint256(uint160(key))), bytes32(defaultValue)));
    }

    /**
     * @notice Returns all addresses in the map
     */
    function allKeys(AddressToUintMap storage map) internal view returns (address[] memory result) {
        bytes32[] memory rawKeys = keys(map._inner);
        result = new address[](rawKeys.length);
        for (uint256 i = 0; i < rawKeys.length; i++) {
            result[i] = address(uint160(uint256(rawKeys[i])));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT256 -> UINT256 MAP
    // ═══════════════════════════════════════════════════════════════════════════

    function set(
        UintToUintMap storage map,
        uint256 key,
        uint256 value
    ) internal returns (bool) {
        return set(map._inner, bytes32(key), bytes32(value));
    }

    function remove(UintToUintMap storage map, uint256 key) internal returns (bool) {
        return remove(map._inner, bytes32(key));
    }

    function contains(UintToUintMap storage map, uint256 key) internal view returns (bool) {
        return contains(map._inner, bytes32(key));
    }

    function length(UintToUintMap storage map) internal view returns (uint256) {
        return length(map._inner);
    }

    function at(
        UintToUintMap storage map,
        uint256 index
    ) internal view returns (uint256 key, uint256 value) {
        (bytes32 k, bytes32 v) = at(map._inner, index);
        key = uint256(k);
        value = uint256(v);
    }

    function get(UintToUintMap storage map, uint256 key) internal view returns (uint256) {
        return uint256(get(map._inner, bytes32(key)));
    }

    function tryGet(
        UintToUintMap storage map,
        uint256 key,
        uint256 defaultValue
    ) internal view returns (uint256) {
        return uint256(tryGet(map._inner, bytes32(key), bytes32(defaultValue)));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT256 -> ADDRESS MAP
    // ═══════════════════════════════════════════════════════════════════════════

    function set(
        UintToAddressMap storage map,
        uint256 key,
        address value
    ) internal returns (bool) {
        return set(map._inner, bytes32(key), bytes32(uint256(uint160(value))));
    }

    function remove(UintToAddressMap storage map, uint256 key) internal returns (bool) {
        return remove(map._inner, bytes32(key));
    }

    function contains(UintToAddressMap storage map, uint256 key) internal view returns (bool) {
        return contains(map._inner, bytes32(key));
    }

    function length(UintToAddressMap storage map) internal view returns (uint256) {
        return length(map._inner);
    }

    function at(
        UintToAddressMap storage map,
        uint256 index
    ) internal view returns (uint256 key, address value) {
        (bytes32 k, bytes32 v) = at(map._inner, index);
        key = uint256(k);
        value = address(uint160(uint256(v)));
    }

    function get(UintToAddressMap storage map, uint256 key) internal view returns (address) {
        return address(uint160(uint256(get(map._inner, bytes32(key)))));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS -> ADDRESS MAP
    // ═══════════════════════════════════════════════════════════════════════════

    function set(
        AddressToAddressMap storage map,
        address key,
        address value
    ) internal returns (bool) {
        return set(map._inner, bytes32(uint256(uint160(key))), bytes32(uint256(uint160(value))));
    }

    function remove(AddressToAddressMap storage map, address key) internal returns (bool) {
        return remove(map._inner, bytes32(uint256(uint160(key))));
    }

    function contains(AddressToAddressMap storage map, address key) internal view returns (bool) {
        return contains(map._inner, bytes32(uint256(uint160(key))));
    }

    function length(AddressToAddressMap storage map) internal view returns (uint256) {
        return length(map._inner);
    }

    function at(
        AddressToAddressMap storage map,
        uint256 index
    ) internal view returns (address key, address value) {
        (bytes32 k, bytes32 v) = at(map._inner, index);
        key = address(uint160(uint256(k)));
        value = address(uint160(uint256(v)));
    }

    function get(AddressToAddressMap storage map, address key) internal view returns (address) {
        return address(uint160(uint256(get(map._inner, bytes32(uint256(uint160(key)))))));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BULK OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets multiple key-value pairs at once
     * @param map The map to modify
     * @param keysToSet Array of keys
     * @param values Array of values (must match keys length)
     */
    function setMany(
        Bytes32ToBytes32Map storage map,
        bytes32[] memory keysToSet,
        bytes32[] memory values
    ) internal {
        require(keysToSet.length == values.length, "Length mismatch");
        for (uint256 i = 0; i < keysToSet.length; i++) {
            set(map, keysToSet[i], values[i]);
        }
    }

    /**
     * @notice Removes multiple keys at once
     * @param map The map to modify
     * @param keysToRemove Array of keys to remove
     */
    function removeMany(
        Bytes32ToBytes32Map storage map,
        bytes32[] memory keysToRemove
    ) internal {
        for (uint256 i = 0; i < keysToRemove.length; i++) {
            remove(map, keysToRemove[i]);
        }
    }

    /**
     * @notice Clears all entries from the map
     * @param map The map to clear
     */
    function clear(Bytes32ToBytes32Map storage map) internal {
        for (uint256 i = map._keys.length; i > 0; i--) {
            bytes32 key = map._keys[i - 1];
            delete map._values[key];
            delete map._indexes[key];
            map._keys.pop();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PAGINATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns a paginated slice of key-value pairs
     * @param map The map to query
     * @param offset Starting index
     * @param limit Maximum number of pairs to return
     * @return keySlice Array of keys
     * @return valueSlice Array of values
     */
    function slice(
        Bytes32ToBytes32Map storage map,
        uint256 offset,
        uint256 limit
    ) internal view returns (bytes32[] memory keySlice, bytes32[] memory valueSlice) {
        uint256 totalLength = map._keys.length;
        if (offset >= totalLength) {
            return (new bytes32[](0), new bytes32[](0));
        }

        uint256 end = offset + limit;
        if (end > totalLength) {
            end = totalLength;
        }
        uint256 resultLength = end - offset;

        keySlice = new bytes32[](resultLength);
        valueSlice = new bytes32[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            keySlice[i] = map._keys[offset + i];
            valueSlice[i] = map._values[keySlice[i]];
        }
    }
}
