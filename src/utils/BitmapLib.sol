// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BitmapLib
 * @notice Efficient bitmap operations for flags, permissions, and set membership
 * @dev Supports uint256 bitmaps with gas-optimized operations
 */
library BitmapLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error BitIndexOutOfRange(uint256 index, uint256 maxIndex);
    error InvalidBitRange(uint256 start, uint256 end);

    // ═══════════════════════════════════════════════════════════════════════════
    // SINGLE BIT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set a single bit to 1
    /// @param bitmap The bitmap to modify
    /// @param index The bit index (0-255)
    /// @return The modified bitmap
    function setBit(uint256 bitmap, uint256 index) internal pure returns (uint256) {
        if (index >= 256) revert BitIndexOutOfRange(index, 255);
        return bitmap | (1 << index);
    }

    /// @notice Clear a single bit to 0
    /// @param bitmap The bitmap to modify
    /// @param index The bit index (0-255)
    /// @return The modified bitmap
    function clearBit(uint256 bitmap, uint256 index) internal pure returns (uint256) {
        if (index >= 256) revert BitIndexOutOfRange(index, 255);
        return bitmap & ~(1 << index);
    }

    /// @notice Toggle a single bit
    /// @param bitmap The bitmap to modify
    /// @param index The bit index (0-255)
    /// @return The modified bitmap
    function toggleBit(uint256 bitmap, uint256 index) internal pure returns (uint256) {
        if (index >= 256) revert BitIndexOutOfRange(index, 255);
        return bitmap ^ (1 << index);
    }

    /// @notice Check if a bit is set
    /// @param bitmap The bitmap to check
    /// @param index The bit index (0-255)
    /// @return True if bit is set
    function getBit(uint256 bitmap, uint256 index) internal pure returns (bool) {
        if (index >= 256) revert BitIndexOutOfRange(index, 255);
        return (bitmap & (1 << index)) != 0;
    }

    /// @notice Set bit to specific value
    function setBitTo(uint256 bitmap, uint256 index, bool value) internal pure returns (uint256) {
        return value ? setBit(bitmap, index) : clearBit(bitmap, index);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-BIT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set multiple bits from array of indices
    function setBits(uint256 bitmap, uint256[] memory indices) internal pure returns (uint256) {
        unchecked {
            for (uint256 i; i < indices.length; ++i) {
                if (indices[i] >= 256) revert BitIndexOutOfRange(indices[i], 255);
                bitmap |= (1 << indices[i]);
            }
        }
        return bitmap;
    }

    /// @notice Clear multiple bits from array of indices
    function clearBits(uint256 bitmap, uint256[] memory indices) internal pure returns (uint256) {
        unchecked {
            for (uint256 i; i < indices.length; ++i) {
                if (indices[i] >= 256) revert BitIndexOutOfRange(indices[i], 255);
                bitmap &= ~(1 << indices[i]);
            }
        }
        return bitmap;
    }

    /// @notice Check if all specified bits are set
    function hasAllBits(uint256 bitmap, uint256 mask) internal pure returns (bool) {
        return (bitmap & mask) == mask;
    }

    /// @notice Check if any of the specified bits are set
    function hasAnyBit(uint256 bitmap, uint256 mask) internal pure returns (bool) {
        return (bitmap & mask) != 0;
    }

    /// @notice Check if none of the specified bits are set
    function hasNoBits(uint256 bitmap, uint256 mask) internal pure returns (bool) {
        return (bitmap & mask) == 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RANGE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set all bits in range [start, end] inclusive
    function setRange(uint256 bitmap, uint256 start, uint256 end) internal pure returns (uint256) {
        if (start > end || end >= 256) revert InvalidBitRange(start, end);

        uint256 rangeMask = ((1 << (end - start + 1)) - 1) << start;
        return bitmap | rangeMask;
    }

    /// @notice Clear all bits in range [start, end] inclusive
    function clearRange(uint256 bitmap, uint256 start, uint256 end) internal pure returns (uint256) {
        if (start > end || end >= 256) revert InvalidBitRange(start, end);

        uint256 rangeMask = ((1 << (end - start + 1)) - 1) << start;
        return bitmap & ~rangeMask;
    }

    /// @notice Extract bits in range as a new value (shifted to LSB)
    function extractRange(
        uint256 bitmap,
        uint256 start,
        uint256 length
    ) internal pure returns (uint256) {
        if (start + length > 256) revert InvalidBitRange(start, start + length - 1);

        uint256 mask = (1 << length) - 1;
        return (bitmap >> start) & mask;
    }

    /// @notice Insert value at bit range
    function insertRange(
        uint256 bitmap,
        uint256 start,
        uint256 length,
        uint256 value
    ) internal pure returns (uint256) {
        if (start + length > 256) revert InvalidBitRange(start, start + length - 1);

        uint256 mask = (1 << length) - 1;
        // Clear range and insert new value
        return (bitmap & ~(mask << start)) | ((value & mask) << start);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BIT COUNTING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Count number of set bits (population count / hamming weight)
    function popCount(uint256 bitmap) internal pure returns (uint256 count) {
        // Brian Kernighan's algorithm
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            ++count;
        }
    }

    /// @notice Count leading zeros
    function clz(uint256 bitmap) internal pure returns (uint256) {
        if (bitmap == 0) return 256;
        uint256 n = 0;
        if (bitmap <= 0x00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 128; bitmap <<= 128; }
        if (bitmap <= 0x0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 64; bitmap <<= 64; }
        if (bitmap <= 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 32; bitmap <<= 32; }
        if (bitmap <= 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF) { n += 16; bitmap <<= 16; }
        if (bitmap <= 0x00000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFF) { n += 8; bitmap <<= 8; }
        if (bitmap <= 0x0000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFF) { n += 4; bitmap <<= 4; }
        if (bitmap <= 0x00000000000000000000000000000000000000000000000000FFFFFFFFFFFFFF) { n += 2; bitmap <<= 2; }
        if (bitmap <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 1; }
        return n;
    }

    /// @notice Count trailing zeros
    function ctz(uint256 bitmap) internal pure returns (uint256) {
        if (bitmap == 0) return 256;
        uint256 n = 0;
        if ((bitmap & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) { n += 128; bitmap >>= 128; }
        if ((bitmap & 0xFFFFFFFFFFFFFFFF) == 0) { n += 64; bitmap >>= 64; }
        if ((bitmap & 0xFFFFFFFF) == 0) { n += 32; bitmap >>= 32; }
        if ((bitmap & 0xFFFF) == 0) { n += 16; bitmap >>= 16; }
        if ((bitmap & 0xFF) == 0) { n += 8; bitmap >>= 8; }
        if ((bitmap & 0xF) == 0) { n += 4; bitmap >>= 4; }
        if ((bitmap & 0x3) == 0) { n += 2; bitmap >>= 2; }
        if ((bitmap & 0x1) == 0) { n += 1; }
        return n;
    }

    /// @notice Find most significant bit (highest set bit index)
    function msb(uint256 bitmap) internal pure returns (uint256) {
        if (bitmap == 0) return 256; // No bit set
        return 255 - clz(bitmap);
    }

    /// @notice Find least significant bit (lowest set bit index)
    function lsb(uint256 bitmap) internal pure returns (uint256) {
        if (bitmap == 0) return 256; // No bit set
        return ctz(bitmap);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOOLEAN OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Bitwise AND of two bitmaps
    function and_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a & b;
    }

    /// @notice Bitwise OR of two bitmaps
    function or_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a | b;
    }

    /// @notice Bitwise XOR of two bitmaps
    function xor_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a ^ b;
    }

    /// @notice Bitwise NOT of bitmap
    function not_(uint256 bitmap) internal pure returns (uint256) {
        return ~bitmap;
    }

    /// @notice AND NOT (a & ~b) - set difference
    function andNot(uint256 a, uint256 b) internal pure returns (uint256) {
        return a & ~b;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SET OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Union of two bitmaps
    function union(uint256 a, uint256 b) internal pure returns (uint256) {
        return a | b;
    }

    /// @notice Intersection of two bitmaps
    function intersection(uint256 a, uint256 b) internal pure returns (uint256) {
        return a & b;
    }

    /// @notice Difference (elements in a but not in b)
    function difference(uint256 a, uint256 b) internal pure returns (uint256) {
        return a & ~b;
    }

    /// @notice Symmetric difference (elements in either but not both)
    function symmetricDifference(uint256 a, uint256 b) internal pure returns (uint256) {
        return a ^ b;
    }

    /// @notice Check if a is subset of b
    function isSubset(uint256 a, uint256 b) internal pure returns (bool) {
        return (a & b) == a;
    }

    /// @notice Check if a is superset of b
    function isSuperset(uint256 a, uint256 b) internal pure returns (bool) {
        return (a & b) == b;
    }

    /// @notice Check if bitmaps are disjoint (no common bits)
    function isDisjoint(uint256 a, uint256 b) internal pure returns (bool) {
        return (a & b) == 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ITERATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get array of all set bit indices
    function toArray(uint256 bitmap) internal pure returns (uint256[] memory indices) {
        uint256 count = popCount(bitmap);
        indices = new uint256[](count);

        uint256 idx;
        uint256 temp = bitmap;
        while (temp != 0 && idx < count) {
            uint256 bitIndex = ctz(temp);
            indices[idx] = bitIndex;
            temp &= temp - 1; // Clear lowest set bit
            ++idx;
        }
    }

    /// @notice Create bitmap from array of indices
    function fromArray(uint256[] memory indices) internal pure returns (uint256 bitmap) {
        unchecked {
            for (uint256 i; i < indices.length; ++i) {
                if (indices[i] < 256) {
                    bitmap |= (1 << indices[i]);
                }
            }
        }
    }

    /// @notice Get the n-th set bit index (0-indexed)
    function nthSetBit(uint256 bitmap, uint256 n) internal pure returns (uint256) {
        uint256 count;
        uint256 temp = bitmap;

        while (temp != 0) {
            uint256 bitIndex = ctz(temp);
            if (count == n) return bitIndex;
            temp &= temp - 1;
            ++count;
        }

        return 256; // Not found
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PERMISSION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create permission mask from role bits
    function createPermissionMask(uint8[] memory permissions) internal pure returns (uint256 mask) {
        unchecked {
            for (uint256 i; i < permissions.length; ++i) {
                mask |= (1 << permissions[i]);
            }
        }
    }

    /// @notice Check if user has required permissions
    function hasPermissions(uint256 userPerms, uint256 requiredPerms) internal pure returns (bool) {
        return hasAllBits(userPerms, requiredPerms);
    }

    /// @notice Grant permissions
    function grantPermissions(uint256 userPerms, uint256 newPerms) internal pure returns (uint256) {
        return userPerms | newPerms;
    }

    /// @notice Revoke permissions
    function revokePermissions(uint256 userPerms, uint256 revokePerms) internal pure returns (uint256) {
        return userPerms & ~revokePerms;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE BITMAP OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set bit in storage mapping (for large sparse sets)
    /// @dev Uses bucket approach: bitmap[index/256] stores bits [index%256]
    function setStorageBit(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal {
        uint256 bucket = index >> 8; // index / 256
        uint256 bitIndex = index & 0xFF; // index % 256
        bitmaps[bucket] = setBit(bitmaps[bucket], bitIndex);
    }

    /// @notice Clear bit in storage mapping
    function clearStorageBit(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal {
        uint256 bucket = index >> 8;
        uint256 bitIndex = index & 0xFF;
        bitmaps[bucket] = clearBit(bitmaps[bucket], bitIndex);
    }

    /// @notice Get bit from storage mapping
    function getStorageBit(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal view returns (bool) {
        uint256 bucket = index >> 8;
        uint256 bitIndex = index & 0xFF;
        return getBit(bitmaps[bucket], bitIndex);
    }

    /// @notice Toggle bit in storage mapping
    function toggleStorageBit(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal {
        uint256 bucket = index >> 8;
        uint256 bitIndex = index & 0xFF;
        bitmaps[bucket] = toggleBit(bitmaps[bucket], bitIndex);
    }
}
