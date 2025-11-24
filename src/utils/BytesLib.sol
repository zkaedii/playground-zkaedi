// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BytesLib
 * @notice Safe bytes manipulation utilities with bounds checking
 * @dev Provides slicing, concatenation, extraction, and comparison operations
 */
library BytesLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error SliceOutOfBounds(uint256 start, uint256 length, uint256 dataLength);
    error IndexOutOfBounds(uint256 index, uint256 length);
    error InsufficientLength(uint256 required, uint256 actual);
    error LengthMismatch(uint256 expected, uint256 actual);

    // ═══════════════════════════════════════════════════════════════════════════
    // SLICING OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extract a slice from bytes with bounds checking
     * @param data Source bytes
     * @param start Start index
     * @param length Number of bytes to extract
     * @return Extracted slice
     */
    function slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory) {
        if (start + length > data.length) {
            revert SliceOutOfBounds(start, length, data.length);
        }

        bytes memory result = new bytes(length);
        for (uint256 i; i < length;) {
            result[i] = data[start + i];
            unchecked { ++i; }
        }
        return result;
    }

    /**
     * @notice Extract slice from start to end of data
     * @param data Source bytes
     * @param start Start index
     * @return Slice from start to end
     */
    function sliceFrom(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        if (start > data.length) {
            revert SliceOutOfBounds(start, 0, data.length);
        }
        return slice(data, start, data.length - start);
    }

    /**
     * @notice Extract slice from beginning to specified index
     * @param data Source bytes
     * @param end End index (exclusive)
     * @return Slice from beginning to end
     */
    function sliceTo(bytes memory data, uint256 end) internal pure returns (bytes memory) {
        if (end > data.length) end = data.length;
        return slice(data, 0, end);
    }

    /**
     * @notice Slice calldata bytes (more gas efficient)
     * @param data Source calldata
     * @param start Start index
     * @param length Number of bytes
     * @return result Sliced bytes in memory
     */
    function sliceCalldata(
        bytes calldata data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory result) {
        if (start + length > data.length) {
            revert SliceOutOfBounds(start, length, data.length);
        }
        result = data[start:start + length];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTRACTION OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extract single byte at index
     * @param data Source bytes
     * @param index Index to read
     * @return Byte at index
     */
    function at(bytes memory data, uint256 index) internal pure returns (bytes1) {
        if (index >= data.length) {
            revert IndexOutOfBounds(index, data.length);
        }
        return data[index];
    }

    /**
     * @notice Extract first byte
     */
    function first(bytes memory data) internal pure returns (bytes1) {
        if (data.length == 0) revert InsufficientLength(1, 0);
        return data[0];
    }

    /**
     * @notice Extract last byte
     */
    function last(bytes memory data) internal pure returns (bytes1) {
        if (data.length == 0) revert InsufficientLength(1, 0);
        return data[data.length - 1];
    }

    /**
     * @notice Extract uint8 from bytes at position
     * @param data Source bytes
     * @param offset Position to read from
     * @return Extracted uint8
     */
    function toUint8(bytes memory data, uint256 offset) internal pure returns (uint8) {
        if (offset + 1 > data.length) {
            revert InsufficientLength(offset + 1, data.length);
        }
        return uint8(data[offset]);
    }

    /**
     * @notice Extract uint16 from bytes at position (big-endian)
     */
    function toUint16(bytes memory data, uint256 offset) internal pure returns (uint16 result) {
        if (offset + 2 > data.length) {
            revert InsufficientLength(offset + 2, data.length);
        }
        assembly {
            result := mload(add(add(data, 2), offset))
        }
    }

    /**
     * @notice Extract uint32 from bytes at position (big-endian)
     */
    function toUint32(bytes memory data, uint256 offset) internal pure returns (uint32 result) {
        if (offset + 4 > data.length) {
            revert InsufficientLength(offset + 4, data.length);
        }
        assembly {
            result := mload(add(add(data, 4), offset))
        }
    }

    /**
     * @notice Extract uint64 from bytes at position (big-endian)
     */
    function toUint64(bytes memory data, uint256 offset) internal pure returns (uint64 result) {
        if (offset + 8 > data.length) {
            revert InsufficientLength(offset + 8, data.length);
        }
        assembly {
            result := mload(add(add(data, 8), offset))
        }
    }

    /**
     * @notice Extract uint128 from bytes at position (big-endian)
     */
    function toUint128(bytes memory data, uint256 offset) internal pure returns (uint128 result) {
        if (offset + 16 > data.length) {
            revert InsufficientLength(offset + 16, data.length);
        }
        assembly {
            result := mload(add(add(data, 16), offset))
        }
    }

    /**
     * @notice Extract uint256 from bytes at position (big-endian)
     */
    function toUint256(bytes memory data, uint256 offset) internal pure returns (uint256 result) {
        if (offset + 32 > data.length) {
            revert InsufficientLength(offset + 32, data.length);
        }
        assembly {
            result := mload(add(add(data, 32), offset))
        }
    }

    /**
     * @notice Extract bytes32 from bytes at position
     */
    function toBytes32(bytes memory data, uint256 offset) internal pure returns (bytes32 result) {
        if (offset + 32 > data.length) {
            revert InsufficientLength(offset + 32, data.length);
        }
        assembly {
            result := mload(add(add(data, 32), offset))
        }
    }

    /**
     * @notice Extract bytes4 (function selector) from bytes at position
     */
    function toBytes4(bytes memory data, uint256 offset) internal pure returns (bytes4 result) {
        if (offset + 4 > data.length) {
            revert InsufficientLength(offset + 4, data.length);
        }
        assembly {
            result := mload(add(add(data, 32), offset))
        }
    }

    /**
     * @notice Extract address from bytes at position
     */
    function toAddress(bytes memory data, uint256 offset) internal pure returns (address result) {
        if (offset + 20 > data.length) {
            revert InsufficientLength(offset + 20, data.length);
        }
        assembly {
            result := mload(add(add(data, 20), offset))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONCATENATION OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Concatenate two bytes arrays
     * @param a First bytes
     * @param b Second bytes
     * @return Combined bytes
     */
    function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b);
    }

    /**
     * @notice Concatenate three bytes arrays
     */
    function concat(
        bytes memory a,
        bytes memory b,
        bytes memory c
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b, c);
    }

    /**
     * @notice Concatenate four bytes arrays
     */
    function concat(
        bytes memory a,
        bytes memory b,
        bytes memory c,
        bytes memory d
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b, c, d);
    }

    /**
     * @notice Concatenate array of bytes
     */
    function concatAll(bytes[] memory parts) internal pure returns (bytes memory result) {
        uint256 totalLength;
        for (uint256 i; i < parts.length;) {
            totalLength += parts[i].length;
            unchecked { ++i; }
        }

        result = new bytes(totalLength);
        uint256 offset;
        for (uint256 i; i < parts.length;) {
            bytes memory part = parts[i];
            for (uint256 j; j < part.length;) {
                result[offset + j] = part[j];
                unchecked { ++j; }
            }
            offset += part.length;
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if two bytes arrays are equal
     */
    function equal(bytes memory a, bytes memory b) internal pure returns (bool) {
        if (a.length != b.length) return false;
        return keccak256(a) == keccak256(b);
    }

    /**
     * @notice Check if bytes starts with prefix
     */
    function startsWith(bytes memory data, bytes memory prefix) internal pure returns (bool) {
        if (prefix.length > data.length) return false;
        for (uint256 i; i < prefix.length;) {
            if (data[i] != prefix[i]) return false;
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @notice Check if bytes ends with suffix
     */
    function endsWith(bytes memory data, bytes memory suffix) internal pure returns (bool) {
        if (suffix.length > data.length) return false;
        uint256 offset = data.length - suffix.length;
        for (uint256 i; i < suffix.length;) {
            if (data[offset + i] != suffix[i]) return false;
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @notice Find index of first occurrence of pattern
     * @param data Data to search in
     * @param pattern Pattern to find
     * @return found True if found
     * @return index Position of first occurrence (0 if not found)
     */
    function indexOf(
        bytes memory data,
        bytes memory pattern
    ) internal pure returns (bool found, uint256 index) {
        if (pattern.length == 0 || pattern.length > data.length) {
            return (false, 0);
        }

        uint256 maxStart = data.length - pattern.length;
        for (uint256 i; i <= maxStart;) {
            bool match_ = true;
            for (uint256 j; j < pattern.length;) {
                if (data[i + j] != pattern[j]) {
                    match_ = false;
                    break;
                }
                unchecked { ++j; }
            }
            if (match_) return (true, i);
            unchecked { ++i; }
        }
        return (false, 0);
    }

    /**
     * @notice Check if bytes contains pattern
     */
    function contains(bytes memory data, bytes memory pattern) internal pure returns (bool) {
        (bool found,) = indexOf(data, pattern);
        return found;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PADDING OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Left-pad bytes to specified length
     * @param data Original bytes
     * @param targetLength Target length
     * @return Padded bytes
     */
    function padLeft(bytes memory data, uint256 targetLength) internal pure returns (bytes memory) {
        if (data.length >= targetLength) return data;

        bytes memory result = new bytes(targetLength);
        uint256 padding = targetLength - data.length;
        for (uint256 i; i < data.length;) {
            result[padding + i] = data[i];
            unchecked { ++i; }
        }
        return result;
    }

    /**
     * @notice Right-pad bytes to specified length
     */
    function padRight(bytes memory data, uint256 targetLength) internal pure returns (bytes memory) {
        if (data.length >= targetLength) return data;

        bytes memory result = new bytes(targetLength);
        for (uint256 i; i < data.length;) {
            result[i] = data[i];
            unchecked { ++i; }
        }
        return result;
    }

    /**
     * @notice Trim leading zero bytes
     */
    function trimLeadingZeros(bytes memory data) internal pure returns (bytes memory) {
        uint256 start;
        while (start < data.length && data[start] == 0x00) {
            unchecked { ++start; }
        }
        if (start == 0) return data;
        return sliceFrom(data, start);
    }

    /**
     * @notice Trim trailing zero bytes
     */
    function trimTrailingZeros(bytes memory data) internal pure returns (bytes memory) {
        uint256 end = data.length;
        while (end > 0 && data[end - 1] == 0x00) {
            unchecked { --end; }
        }
        if (end == data.length) return data;
        return sliceTo(data, end);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ENCODING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encode uint256 as minimal bytes (no leading zeros)
     */
    function encodeCompact(uint256 value) internal pure returns (bytes memory) {
        if (value == 0) return hex"00";

        uint256 temp = value;
        uint256 length;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }

        bytes memory result = new bytes(length);
        for (uint256 i = length; i > 0;) {
            unchecked { --i; }
            result[i] = bytes1(uint8(value));
            value >>= 8;
        }
        return result;
    }

    /**
     * @notice Decode compact encoded uint256
     */
    function decodeCompact(bytes memory data) internal pure returns (uint256 result) {
        if (data.length > 32) revert InsufficientLength(32, data.length);

        for (uint256 i; i < data.length;) {
            result = (result << 8) | uint8(data[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Create bytes from uint256 with fixed length
     */
    function fromUint256(uint256 value, uint8 length) internal pure returns (bytes memory result) {
        result = new bytes(length);
        for (uint256 i = length; i > 0;) {
            unchecked { --i; }
            result[i] = bytes1(uint8(value));
            value >>= 8;
        }
    }

    /**
     * @notice Create bytes from address
     */
    function fromAddress(address value) internal pure returns (bytes memory) {
        return abi.encodePacked(value);
    }

    /**
     * @notice Create bytes from bytes32
     */
    function fromBytes32(bytes32 value) internal pure returns (bytes memory) {
        return abi.encodePacked(value);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHECKSUM & HASH UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate simple checksum (sum of all bytes mod 256)
     */
    function checksum(bytes memory data) internal pure returns (uint8 sum) {
        for (uint256 i; i < data.length;) {
            sum += uint8(data[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Calculate keccak256 hash
     */
    function hash(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }

    /**
     * @notice Verify data matches expected hash
     */
    function verifyHash(bytes memory data, bytes32 expectedHash) internal pure returns (bool) {
        return keccak256(data) == expectedHash;
    }
}
