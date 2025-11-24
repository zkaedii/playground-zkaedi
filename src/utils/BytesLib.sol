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

    /// @notice Extract a slice from bytes data
    /// @param data Source bytes
    /// @param start Starting index
    /// @param length Number of bytes to extract
    /// @return result The sliced bytes
    function slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory result) {
        if (start + length > data.length) {
            revert SliceOutOfBounds(start, length, data.length);
        }

        result = new bytes(length);

        assembly {
            // Copy length bytes from data[start] to result
            let src := add(add(data, 32), start)
            let dst := add(result, 32)

            // Copy in 32-byte chunks
            for { let i := 0 } lt(i, length) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
    }

    /// @notice Extract slice from start to end of data
    function sliceFrom(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        if (start > data.length) {
            revert SliceOutOfBounds(start, 0, data.length);
        }
        return slice(data, start, data.length - start);
    }

    /// @notice Extract slice from beginning to index
    function sliceTo(bytes memory data, uint256 end) internal pure returns (bytes memory) {
        if (end > data.length) {
            revert SliceOutOfBounds(0, end, data.length);
        }
        return slice(data, 0, end);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALUE EXTRACTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Extract a single byte at index
    function at(bytes memory data, uint256 index) internal pure returns (bytes1) {
        if (index >= data.length) {
            revert IndexOutOfBounds(index, data.length);
        }
        return data[index];
    }

    /// @notice Extract uint8 from bytes at offset
    function toUint8(bytes memory data, uint256 offset) internal pure returns (uint8 result) {
        if (offset + 1 > data.length) {
            revert InsufficientLength(offset + 1, data.length);
        }
        assembly {
            result := mload(add(add(data, 1), offset))
        }
    }

    /// @notice Extract uint16 from bytes at offset (big-endian)
    function toUint16(bytes memory data, uint256 offset) internal pure returns (uint16 result) {
        if (offset + 2 > data.length) {
            revert InsufficientLength(offset + 2, data.length);
        }
        assembly {
            result := mload(add(add(data, 2), offset))
        }
    }

    /// @notice Extract uint24 from bytes at offset (big-endian)
    function toUint24(bytes memory data, uint256 offset) internal pure returns (uint24 result) {
        if (offset + 3 > data.length) {
            revert InsufficientLength(offset + 3, data.length);
        }
        assembly {
            result := mload(add(add(data, 3), offset))
        }
    }

    /// @notice Extract uint32 from bytes at offset (big-endian)
    function toUint32(bytes memory data, uint256 offset) internal pure returns (uint32 result) {
        if (offset + 4 > data.length) {
            revert InsufficientLength(offset + 4, data.length);
        }
        assembly {
            result := mload(add(add(data, 4), offset))
        }
    }

    /// @notice Extract uint64 from bytes at offset (big-endian)
    function toUint64(bytes memory data, uint256 offset) internal pure returns (uint64 result) {
        if (offset + 8 > data.length) {
            revert InsufficientLength(offset + 8, data.length);
        }
        assembly {
            result := mload(add(add(data, 8), offset))
        }
    }

    /// @notice Extract uint128 from bytes at offset (big-endian)
    function toUint128(bytes memory data, uint256 offset) internal pure returns (uint128 result) {
        if (offset + 16 > data.length) {
            revert InsufficientLength(offset + 16, data.length);
        }
        assembly {
            result := mload(add(add(data, 16), offset))
        }
    }

    /// @notice Extract uint256 from bytes at offset (big-endian)
    function toUint256(bytes memory data, uint256 offset) internal pure returns (uint256 result) {
        if (offset + 32 > data.length) {
            revert InsufficientLength(offset + 32, data.length);
        }
        assembly {
            result := mload(add(add(data, 32), offset))
        }
    }

    /// @notice Extract bytes32 from bytes at offset
    function toBytes32(bytes memory data, uint256 offset) internal pure returns (bytes32 result) {
        if (offset + 32 > data.length) {
            revert InsufficientLength(offset + 32, data.length);
        }
        assembly {
            result := mload(add(add(data, 32), offset))
        }
    }

    /// @notice Extract address from bytes at offset
    function toAddress(bytes memory data, uint256 offset) internal pure returns (address result) {
        if (offset + 20 > data.length) {
            revert InsufficientLength(offset + 20, data.length);
        }
        assembly {
            result := mload(add(add(data, 20), offset))
        }
    }

    /// @notice Extract bytes4 (function selector) from bytes at offset
    function toBytes4(bytes memory data, uint256 offset) internal pure returns (bytes4 result) {
        if (offset + 4 > data.length) {
            revert InsufficientLength(offset + 4, data.length);
        }
        assembly {
            result := mload(add(add(data, 32), offset))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONCATENATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Concatenate two bytes arrays
    function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory result) {
        result = new bytes(a.length + b.length);

        assembly {
            let totalLen := add(mload(a), mload(b))
            let dst := add(result, 32)

            // Copy a
            let src := add(a, 32)
            let len := mload(a)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }

            // Copy b
            dst := add(dst, len)
            src := add(b, 32)
            len := mload(b)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
    }

    /// @notice Concatenate three bytes arrays
    function concat(
        bytes memory a,
        bytes memory b,
        bytes memory c
    ) internal pure returns (bytes memory) {
        return concat(concat(a, b), c);
    }

    /// @notice Concatenate bytes with bytes32
    function concat(bytes memory a, bytes32 b) internal pure returns (bytes memory result) {
        result = new bytes(a.length + 32);

        assembly {
            let dst := add(result, 32)
            let src := add(a, 32)
            let len := mload(a)

            // Copy a
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }

            // Append b
            mstore(add(dst, len), b)
        }
    }

    /// @notice Concatenate bytes with address
    function concat(bytes memory a, address b) internal pure returns (bytes memory) {
        return concat(a, bytes20(b));
    }

    /// @notice Concatenate bytes with bytes20
    function concat(bytes memory a, bytes20 b) internal pure returns (bytes memory result) {
        result = new bytes(a.length + 20);

        assembly {
            let dst := add(result, 32)
            let src := add(a, 32)
            let len := mload(a)

            // Copy a
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }

            // Append b (20 bytes)
            mstore(add(dst, len), b)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Check if two bytes arrays are equal
    function equal(bytes memory a, bytes memory b) internal pure returns (bool) {
        if (a.length != b.length) return false;
        return keccak256(a) == keccak256(b);
    }

    /// @notice Check if bytes starts with prefix
    function startsWith(bytes memory data, bytes memory prefix) internal pure returns (bool) {
        if (prefix.length > data.length) return false;

        for (uint256 i; i < prefix.length; ++i) {
            if (data[i] != prefix[i]) return false;
        }
        return true;
    }

    /// @notice Check if bytes ends with suffix
    function endsWith(bytes memory data, bytes memory suffix) internal pure returns (bool) {
        if (suffix.length > data.length) return false;

        uint256 offset = data.length - suffix.length;
        for (uint256 i; i < suffix.length; ++i) {
            if (data[offset + i] != suffix[i]) return false;
        }
        return true;
    }

    /// @notice Find index of sub-bytes in data (-1 if not found)
    function indexOf(bytes memory data, bytes memory search) internal pure returns (int256) {
        if (search.length == 0 || search.length > data.length) return -1;

        uint256 maxIdx = data.length - search.length;
        for (uint256 i; i <= maxIdx; ++i) {
            bool found = true;
            for (uint256 j; j < search.length; ++j) {
                if (data[i + j] != search[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return int256(i);
        }
        return -1;
    }

    /// @notice Check if data contains search bytes
    function contains(bytes memory data, bytes memory search) internal pure returns (bool) {
        return indexOf(data, search) >= 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ENCODING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Pack multiple uint8 values into bytes
    function packUint8(uint8[] memory values) internal pure returns (bytes memory result) {
        result = new bytes(values.length);
        unchecked {
            for (uint256 i; i < values.length; ++i) {
                result[i] = bytes1(values[i]);
            }
        }
    }

    /// @notice Unpack bytes into uint8 array
    function unpackUint8(bytes memory data) internal pure returns (uint8[] memory result) {
        result = new uint8[](data.length);
        unchecked {
            for (uint256 i; i < data.length; ++i) {
                result[i] = uint8(data[i]);
            }
        }
    }

    /// @notice Pack uint16 array into bytes (big-endian)
    function packUint16(uint16[] memory values) internal pure returns (bytes memory result) {
        result = new bytes(values.length * 2);
        unchecked {
            for (uint256 i; i < values.length; ++i) {
                result[i * 2] = bytes1(uint8(values[i] >> 8));
                result[i * 2 + 1] = bytes1(uint8(values[i]));
            }
        }
    }

    /// @notice Pack uint32 array into bytes (big-endian)
    function packUint32(uint32[] memory values) internal pure returns (bytes memory result) {
        result = new bytes(values.length * 4);
        unchecked {
            for (uint256 i; i < values.length; ++i) {
                uint256 offset = i * 4;
                result[offset] = bytes1(uint8(values[i] >> 24));
                result[offset + 1] = bytes1(uint8(values[i] >> 16));
                result[offset + 2] = bytes1(uint8(values[i] >> 8));
                result[offset + 3] = bytes1(uint8(values[i]));
            }
        }
    }

    /// @notice Pack address array into bytes
    function packAddresses(address[] memory addrs) internal pure returns (bytes memory result) {
        result = new bytes(addrs.length * 20);
        assembly {
            let len := mload(addrs)
            let dst := add(result, 32)
            let src := add(addrs, 32)

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                // Load address and store as 20 bytes
                let addr := mload(add(src, mul(i, 32)))
                mstore(add(dst, mul(i, 20)), shl(96, addr))
            }
        }
    }

    /// @notice Unpack bytes into address array
    function unpackAddresses(bytes memory data) internal pure returns (address[] memory result) {
        if (data.length % 20 != 0) {
            revert LengthMismatch(data.length - (data.length % 20) + 20, data.length);
        }

        uint256 count = data.length / 20;
        result = new address[](count);

        unchecked {
            for (uint256 i; i < count; ++i) {
                result[i] = toAddress(data, i * 20);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PADDING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Left-pad bytes to target length with zeros
    function padLeft(bytes memory data, uint256 length) internal pure returns (bytes memory result) {
        if (data.length >= length) return data;

        result = new bytes(length);
        uint256 padding = length - data.length;

        assembly {
            let src := add(data, 32)
            let dst := add(add(result, 32), padding)
            let len := mload(data)

            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
    }

    /// @notice Right-pad bytes to target length with zeros
    function padRight(bytes memory data, uint256 length) internal pure returns (bytes memory result) {
        if (data.length >= length) return data;

        result = new bytes(length);

        assembly {
            let src := add(data, 32)
            let dst := add(result, 32)
            let len := mload(data)

            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
    }

    /// @notice Trim leading zeros from bytes
    function trimLeft(bytes memory data) internal pure returns (bytes memory) {
        uint256 start;
        for (; start < data.length && data[start] == 0; ++start) {}

        if (start == 0) return data;
        return slice(data, start, data.length - start);
    }

    /// @notice Trim trailing zeros from bytes
    function trimRight(bytes memory data) internal pure returns (bytes memory) {
        uint256 end = data.length;
        for (; end > 0 && data[end - 1] == 0; --end) {}

        if (end == data.length) return data;
        return slice(data, 0, end);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REVERSAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Reverse bytes array
    function reverse(bytes memory data) internal pure returns (bytes memory result) {
        result = new bytes(data.length);
        unchecked {
            for (uint256 i; i < data.length; ++i) {
                result[data.length - 1 - i] = data[i];
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLDATA HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Extract function selector from calldata
    function getSelector(bytes calldata data) internal pure returns (bytes4) {
        if (data.length < 4) revert InsufficientLength(4, data.length);
        return bytes4(data[:4]);
    }

    /// @notice Extract function arguments from calldata (excludes selector)
    function getCallArgs(bytes calldata data) internal pure returns (bytes calldata) {
        if (data.length < 4) revert InsufficientLength(4, data.length);
        return data[4:];
    }

    /// @notice Create calldata from selector and arguments
    function encodeCall(bytes4 selector, bytes memory args) internal pure returns (bytes memory) {
        return abi.encodePacked(selector, args);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HASH HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Compute keccak256 hash of bytes
    function keccak(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }

    /// @notice Compute keccak256 hash of concatenated bytes
    function keccakConcat(bytes memory a, bytes memory b) internal pure returns (bytes32) {
        return keccak256(concat(a, b));
    }

    /// @notice Compute keccak256 of bytes slice
    function keccakSlice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes32) {
        return keccak256(slice(data, start, length));
    }
}
