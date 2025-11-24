// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BitmapLib
 * @notice Efficient bitmap operations for flags, permissions, and set membership
 * @dev Supports uint8, uint16, uint32, uint64, and uint256 bitmaps
 */
library BitmapLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error BitIndexOutOfRange(uint256 index, uint256 maxIndex);
    error InvalidBitRange(uint256 start, uint256 end);

    // ═══════════════════════════════════════════════════════════════════════════
    // SINGLE BIT OPERATIONS (uint256)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if bit is set at index
     * @param bitmap The bitmap
     * @param index Bit index (0-255)
     * @return True if bit is set
     */
    function isSet(uint256 bitmap, uint8 index) internal pure returns (bool) {
        return (bitmap & (1 << index)) != 0;
    }

    /**
     * @notice Set bit at index
     * @param bitmap The bitmap
     * @param index Bit index (0-255)
     * @return Updated bitmap
     */
    function set(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap | (1 << index);
    }

    /**
     * @notice Clear bit at index
     * @param bitmap The bitmap
     * @param index Bit index (0-255)
     * @return Updated bitmap
     */
    function clear(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap & ~(1 << index);
    }

    /**
     * @notice Toggle bit at index
     * @param bitmap The bitmap
     * @param index Bit index (0-255)
     * @return Updated bitmap
     */
    function toggle(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap ^ (1 << index);
    }

    /**
     * @notice Set bit to specific value
     * @param bitmap The bitmap
     * @param index Bit index (0-255)
     * @param value Value to set (true = 1, false = 0)
     * @return Updated bitmap
     */
    function setTo(uint256 bitmap, uint8 index, bool value) internal pure returns (uint256) {
        if (value) {
            return set(bitmap, index);
        } else {
            return clear(bitmap, index);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-BIT OPERATIONS (uint256)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set multiple bits at once
     * @param bitmap The bitmap
     * @param mask Bits to set (1s indicate bits to set)
     * @return Updated bitmap
     */
    function setMask(uint256 bitmap, uint256 mask) internal pure returns (uint256) {
        return bitmap | mask;
    }

    /**
     * @notice Clear multiple bits at once
     * @param bitmap The bitmap
     * @param mask Bits to clear (1s indicate bits to clear)
     * @return Updated bitmap
     */
    function clearMask(uint256 bitmap, uint256 mask) internal pure returns (uint256) {
        return bitmap & ~mask;
    }

    /**
     * @notice Toggle multiple bits at once
     * @param bitmap The bitmap
     * @param mask Bits to toggle
     * @return Updated bitmap
     */
    function toggleMask(uint256 bitmap, uint256 mask) internal pure returns (uint256) {
        return bitmap ^ mask;
    }

    /**
     * @notice Check if all bits in mask are set
     * @param bitmap The bitmap
     * @param mask Required bits
     * @return True if all bits in mask are set
     */
    function hasAll(uint256 bitmap, uint256 mask) internal pure returns (bool) {
        return (bitmap & mask) == mask;
    }

    /**
     * @notice Check if any bit in mask is set
     * @param bitmap The bitmap
     * @param mask Bits to check
     * @return True if any bit in mask is set
     */
    function hasAny(uint256 bitmap, uint256 mask) internal pure returns (bool) {
        return (bitmap & mask) != 0;
    }

    /**
     * @notice Check if no bits in mask are set
     * @param bitmap The bitmap
     * @param mask Bits to check
     * @return True if no bits in mask are set
     */
    function hasNone(uint256 bitmap, uint256 mask) internal pure returns (bool) {
        return (bitmap & mask) == 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RANGE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create mask for bit range
     * @param start Start bit (inclusive)
     * @param end End bit (exclusive)
     * @return Mask with bits set in range
     */
    function rangeMask(uint8 start, uint8 end) internal pure returns (uint256) {
        if (start >= end) revert InvalidBitRange(start, end);
        uint256 size = end - start;
        return ((1 << size) - 1) << start;
    }

    /**
     * @notice Set bits in range
     */
    function setRange(uint256 bitmap, uint8 start, uint8 end) internal pure returns (uint256) {
        return bitmap | rangeMask(start, end);
    }

    /**
     * @notice Clear bits in range
     */
    function clearRange(uint256 bitmap, uint8 start, uint8 end) internal pure returns (uint256) {
        return bitmap & ~rangeMask(start, end);
    }

    /**
     * @notice Extract value from bit range
     * @param bitmap The bitmap
     * @param start Start bit
     * @param width Number of bits
     * @return Extracted value
     */
    function extract(uint256 bitmap, uint8 start, uint8 width) internal pure returns (uint256) {
        uint256 mask = (1 << width) - 1;
        return (bitmap >> start) & mask;
    }

    /**
     * @notice Insert value into bit range
     * @param bitmap The bitmap
     * @param value Value to insert
     * @param start Start bit
     * @param width Number of bits
     * @return Updated bitmap
     */
    function insert(uint256 bitmap, uint256 value, uint8 start, uint8 width) internal pure returns (uint256) {
        uint256 mask = (1 << width) - 1;
        uint256 cleared = bitmap & ~(mask << start);
        return cleared | ((value & mask) << start);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COUNTING & SEARCHING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Count number of set bits (population count)
     * @param bitmap The bitmap
     * @return Number of set bits
     */
    function popCount(uint256 bitmap) internal pure returns (uint256 count) {
        // Brian Kernighan's algorithm
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            unchecked { ++count; }
        }
    }

    /**
     * @notice Count leading zeros
     */
    function clz(uint256 bitmap) internal pure returns (uint256) {
        if (bitmap == 0) return 256;
        uint256 n = 0;
        if (bitmap <= 0x00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 128; bitmap <<= 128; }
        if (bitmap <= 0x0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 64; bitmap <<= 64; }
        if (bitmap <= 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { n += 32; bitmap <<= 32; }
        if (bitmap <= 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF) { n += 16; bitmap <<= 16; }
        if (bitmap <= 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF) { n += 8; bitmap <<= 8; }
        if (bitmap <= 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF) { n += 4; bitmap <<= 4; }
        if (bitmap <= 0x000000000000000000000000000000000000000000000000000000000000FFFF) { n += 2; bitmap <<= 2; }
        if (bitmap <= 0x00000000000000000000000000000000000000000000000000000000000000FF) { n += 1; }
        return n;
    }

    /**
     * @notice Find most significant bit (highest set bit)
     * @return index Index of MSB (255 if bitmap is 0)
     */
    function msb(uint256 bitmap) internal pure returns (uint8) {
        if (bitmap == 0) return 255;
        return uint8(255 - clz(bitmap));
    }

    /**
     * @notice Find least significant bit (lowest set bit)
     * @return index Index of LSB (255 if bitmap is 0)
     */
    function lsb(uint256 bitmap) internal pure returns (uint8) {
        if (bitmap == 0) return 255;
        return uint8(popCount((bitmap & (~bitmap + 1)) - 1));
    }

    /**
     * @notice Find next set bit after index
     * @param bitmap The bitmap
     * @param startIndex Start searching from this index
     * @return found True if found
     * @return index Index of next set bit
     */
    function nextSetBit(
        uint256 bitmap,
        uint8 startIndex
    ) internal pure returns (bool found, uint8 index) {
        uint256 mask = ~((1 << startIndex) - 1); // Mask off bits before start
        uint256 masked = bitmap & mask;
        if (masked == 0) return (false, 0);
        return (true, lsb(masked));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT8 OPERATIONS (8-bit flags)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if bit is set (uint8)
     */
    function isSet8(uint8 bitmap, uint8 index) internal pure returns (bool) {
        if (index >= 8) revert BitIndexOutOfRange(index, 7);
        return (bitmap & (1 << index)) != 0;
    }

    /**
     * @notice Set bit (uint8)
     */
    function set8(uint8 bitmap, uint8 index) internal pure returns (uint8) {
        if (index >= 8) revert BitIndexOutOfRange(index, 7);
        return bitmap | uint8(1 << index);
    }

    /**
     * @notice Clear bit (uint8)
     */
    function clear8(uint8 bitmap, uint8 index) internal pure returns (uint8) {
        if (index >= 8) revert BitIndexOutOfRange(index, 7);
        return bitmap & ~uint8(1 << index);
    }

    /**
     * @notice Toggle bit (uint8)
     */
    function toggle8(uint8 bitmap, uint8 index) internal pure returns (uint8) {
        if (index >= 8) revert BitIndexOutOfRange(index, 7);
        return bitmap ^ uint8(1 << index);
    }

    /**
     * @notice Count set bits (uint8)
     */
    function popCount8(uint8 bitmap) internal pure returns (uint8 count) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            unchecked { ++count; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT64 OPERATIONS (64-bit flags)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if bit is set (uint64)
     */
    function isSet64(uint64 bitmap, uint8 index) internal pure returns (bool) {
        if (index >= 64) revert BitIndexOutOfRange(index, 63);
        return (bitmap & (uint64(1) << index)) != 0;
    }

    /**
     * @notice Set bit (uint64)
     */
    function set64(uint64 bitmap, uint8 index) internal pure returns (uint64) {
        if (index >= 64) revert BitIndexOutOfRange(index, 63);
        return bitmap | (uint64(1) << index);
    }

    /**
     * @notice Clear bit (uint64)
     */
    function clear64(uint64 bitmap, uint8 index) internal pure returns (uint64) {
        if (index >= 64) revert BitIndexOutOfRange(index, 63);
        return bitmap & ~(uint64(1) << index);
    }

    /**
     * @notice Count set bits (uint64)
     */
    function popCount64(uint64 bitmap) internal pure returns (uint8 count) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            unchecked { ++count; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE BITMAP (for large sets)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if index is set in storage bitmap array
     * @param bitmaps Storage array of bitmaps
     * @param index Global bit index
     * @return True if set
     */
    function isSetStorage(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal view returns (bool) {
        uint256 bucket = index / 256;
        uint8 bit = uint8(index % 256);
        return isSet(bitmaps[bucket], bit);
    }

    /**
     * @notice Set bit in storage bitmap
     */
    function setStorage(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal {
        uint256 bucket = index / 256;
        uint8 bit = uint8(index % 256);
        bitmaps[bucket] = set(bitmaps[bucket], bit);
    }

    /**
     * @notice Clear bit in storage bitmap
     */
    function clearStorage(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal {
        uint256 bucket = index / 256;
        uint8 bit = uint8(index % 256);
        bitmaps[bucket] = clear(bitmaps[bucket], bit);
    }

    /**
     * @notice Toggle bit in storage bitmap
     */
    function toggleStorage(
        mapping(uint256 => uint256) storage bitmaps,
        uint256 index
    ) internal {
        uint256 bucket = index / 256;
        uint8 bit = uint8(index % 256);
        bitmaps[bucket] = toggle(bitmaps[bucket], bit);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PERMISSION FLAGS (Common Use Case)
    // ═══════════════════════════════════════════════════════════════════════════

    // Common permission flag indices
    uint8 internal constant FLAG_ADMIN = 0;
    uint8 internal constant FLAG_OPERATOR = 1;
    uint8 internal constant FLAG_EXECUTOR = 2;
    uint8 internal constant FLAG_GUARDIAN = 3;
    uint8 internal constant FLAG_PAUSER = 4;
    uint8 internal constant FLAG_MINTER = 5;
    uint8 internal constant FLAG_BURNER = 6;
    uint8 internal constant FLAG_TRANSFERER = 7;

    /**
     * @notice Check if has admin permission
     */
    function isAdmin(uint256 permissions) internal pure returns (bool) {
        return isSet(permissions, FLAG_ADMIN);
    }

    /**
     * @notice Check if has operator permission
     */
    function isOperator(uint256 permissions) internal pure returns (bool) {
        return isSet(permissions, FLAG_OPERATOR);
    }

    /**
     * @notice Check if has executor permission
     */
    function isExecutor(uint256 permissions) internal pure returns (bool) {
        return isSet(permissions, FLAG_EXECUTOR);
    }

    /**
     * @notice Create permission mask from array of flag indices
     */
    function createPermissionMask(uint8[] memory flags) internal pure returns (uint256 mask) {
        for (uint256 i; i < flags.length;) {
            mask |= (1 << flags[i]);
            unchecked { ++i; }
        }
    }
}
