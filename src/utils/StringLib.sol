// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StringLib
 * @notice Gas-efficient string manipulation library for Solidity
 * @dev Provides common string operations including:
 *      - Concatenation, slicing, and comparison
 *      - Number to string conversion (and vice versa)
 *      - Case conversion and trimming
 *      - Search and replace functionality
 */
library StringLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    bytes16 private constant HEX_DIGITS_UPPER = "0123456789ABCDEF";

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error StringTooLong();
    error InvalidCharacter();
    error IndexOutOfBounds();
    error EmptyString();

    // ═══════════════════════════════════════════════════════════════════════════
    // NUMBER CONVERSION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Converts a uint256 to its decimal string representation
     * @param value The number to convert
     * @return str The decimal string
     */
    function toString(uint256 value) internal pure returns (string memory str) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }

        str = string(buffer);
    }

    /**
     * @notice Converts a signed int256 to its decimal string representation
     * @param value The number to convert
     * @return str The decimal string (with '-' prefix if negative)
     */
    function toString(int256 value) internal pure returns (string memory str) {
        if (value >= 0) {
            return toString(uint256(value));
        }
        return concat("-", toString(uint256(-value)));
    }

    /**
     * @notice Converts a uint256 to its hexadecimal string representation
     * @param value The number to convert
     * @param includePrefix Whether to include "0x" prefix
     * @return str The hexadecimal string
     */
    function toHexString(uint256 value, bool includePrefix) internal pure returns (string memory str) {
        if (value == 0) {
            return includePrefix ? "0x0" : "0";
        }

        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 4;
        }

        uint256 bufferLength = includePrefix ? length + 2 : length;
        bytes memory buffer = new bytes(bufferLength);

        if (includePrefix) {
            buffer[0] = "0";
            buffer[1] = "x";
        }

        uint256 start = includePrefix ? 2 : 0;
        for (uint256 i = start + length; i > start; ) {
            i--;
            buffer[i] = HEX_DIGITS[value & 0xf];
            value >>= 4;
        }

        str = string(buffer);
    }

    /**
     * @notice Converts a uint256 to fixed-length hex string (with padding)
     * @param value The number to convert
     * @param length The desired length (not including 0x prefix)
     * @return str The padded hexadecimal string
     */
    function toHexStringPadded(uint256 value, uint256 length) internal pure returns (string memory str) {
        bytes memory buffer = new bytes(length + 2);
        buffer[0] = "0";
        buffer[1] = "x";

        for (uint256 i = length + 1; i > 1; ) {
            i--;
            buffer[i] = HEX_DIGITS[value & 0xf];
            value >>= 4;
        }

        str = string(buffer);
    }

    /**
     * @notice Converts an address to its hexadecimal string representation
     * @param addr The address to convert
     * @return str The address as "0x" prefixed hex string
     */
    function toHexString(address addr) internal pure returns (string memory str) {
        return toHexStringPadded(uint256(uint160(addr)), 40);
    }

    /**
     * @notice Parses a decimal string to uint256
     * @param str The string to parse
     * @return value The parsed number
     */
    function parseUint(string memory str) internal pure returns (uint256 value) {
        bytes memory b = bytes(str);
        if (b.length == 0) revert EmptyString();

        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c < 48 || c > 57) revert InvalidCharacter();
            value = value * 10 + (c - 48);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRING MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Concatenates two strings
     * @param a First string
     * @param b Second string
     * @return result The concatenated string
     */
    function concat(string memory a, string memory b) internal pure returns (string memory result) {
        result = string(abi.encodePacked(a, b));
    }

    /**
     * @notice Concatenates multiple strings
     * @param strings Array of strings to concatenate
     * @return result The concatenated string
     */
    function join(string[] memory strings) internal pure returns (string memory result) {
        bytes memory temp;
        for (uint256 i = 0; i < strings.length; i++) {
            temp = abi.encodePacked(temp, strings[i]);
        }
        result = string(temp);
    }

    /**
     * @notice Joins strings with a delimiter
     * @param strings Array of strings to join
     * @param delimiter The delimiter to insert between strings
     * @return result The joined string
     */
    function join(
        string[] memory strings,
        string memory delimiter
    ) internal pure returns (string memory result) {
        if (strings.length == 0) return "";
        if (strings.length == 1) return strings[0];

        bytes memory temp = bytes(strings[0]);
        for (uint256 i = 1; i < strings.length; i++) {
            temp = abi.encodePacked(temp, delimiter, strings[i]);
        }
        result = string(temp);
    }

    /**
     * @notice Returns a substring
     * @param str The source string
     * @param start Start index (inclusive)
     * @param end End index (exclusive)
     * @return result The substring
     */
    function substring(
        string memory str,
        uint256 start,
        uint256 end
    ) internal pure returns (string memory result) {
        bytes memory b = bytes(str);
        if (end > b.length) end = b.length;
        if (start >= end) return "";

        bytes memory sub = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            sub[i - start] = b[i];
        }
        result = string(sub);
    }

    /**
     * @notice Returns the length of a string
     * @param str The string to measure
     * @return length The number of bytes
     */
    function length(string memory str) internal pure returns (uint256) {
        return bytes(str).length;
    }

    /**
     * @notice Returns the character at a specific index
     * @param str The source string
     * @param index The index
     * @return char The character as a single-character string
     */
    function charAt(string memory str, uint256 index) internal pure returns (string memory char) {
        bytes memory b = bytes(str);
        if (index >= b.length) revert IndexOutOfBounds();

        bytes memory c = new bytes(1);
        c[0] = b[index];
        char = string(c);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPARISON & SEARCH
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compares two strings for equality
     * @param a First string
     * @param b Second string
     * @return equal True if strings are equal
     */
    function equals(string memory a, string memory b) internal pure returns (bool equal) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @notice Compares two strings (case-insensitive)
     * @param a First string
     * @param b Second string
     * @return equal True if strings are equal ignoring case
     */
    function equalsIgnoreCase(string memory a, string memory b) internal pure returns (bool equal) {
        return keccak256(bytes(toLower(a))) == keccak256(bytes(toLower(b)));
    }

    /**
     * @notice Checks if a string contains a substring
     * @param str The string to search in
     * @param search The substring to find
     * @return found True if substring is found
     */
    function contains(string memory str, string memory search) internal pure returns (bool found) {
        return indexOf(str, search) != type(uint256).max;
    }

    /**
     * @notice Finds the first occurrence of a substring
     * @param str The string to search in
     * @param search The substring to find
     * @return index The index of first occurrence, or type(uint256).max if not found
     */
    function indexOf(string memory str, string memory search) internal pure returns (uint256 index) {
        bytes memory strBytes = bytes(str);
        bytes memory searchBytes = bytes(search);

        if (searchBytes.length == 0 || searchBytes.length > strBytes.length) {
            return type(uint256).max;
        }

        for (uint256 i = 0; i <= strBytes.length - searchBytes.length; i++) {
            bool matchFound = true;
            for (uint256 j = 0; j < searchBytes.length; j++) {
                if (strBytes[i + j] != searchBytes[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) return i;
        }

        return type(uint256).max;
    }

    /**
     * @notice Checks if a string starts with a prefix
     * @param str The string to check
     * @param prefix The prefix to look for
     * @return result True if str starts with prefix
     */
    function startsWith(string memory str, string memory prefix) internal pure returns (bool result) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);

        if (prefixBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    /**
     * @notice Checks if a string ends with a suffix
     * @param str The string to check
     * @param suffix The suffix to look for
     * @return result True if str ends with suffix
     */
    function endsWith(string memory str, string memory suffix) internal pure returns (bool result) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);

        if (suffixBytes.length > strBytes.length) return false;

        uint256 offset = strBytes.length - suffixBytes.length;
        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[offset + i] != suffixBytes[i]) return false;
        }
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CASE CONVERSION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Converts a string to lowercase
     * @param str The string to convert
     * @return result The lowercase string
     */
    function toLower(string memory str) internal pure returns (string memory result) {
        bytes memory b = bytes(str);
        bytes memory lower = new bytes(b.length);

        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            // A-Z is 65-90, convert to a-z (97-122)
            if (c >= 65 && c <= 90) {
                lower[i] = bytes1(c + 32);
            } else {
                lower[i] = b[i];
            }
        }

        result = string(lower);
    }

    /**
     * @notice Converts a string to uppercase
     * @param str The string to convert
     * @return result The uppercase string
     */
    function toUpper(string memory str) internal pure returns (string memory result) {
        bytes memory b = bytes(str);
        bytes memory upper = new bytes(b.length);

        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            // a-z is 97-122, convert to A-Z (65-90)
            if (c >= 97 && c <= 122) {
                upper[i] = bytes1(c - 32);
            } else {
                upper[i] = b[i];
            }
        }

        result = string(upper);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRIMMING & PADDING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Trims whitespace from both ends of a string
     * @param str The string to trim
     * @return result The trimmed string
     */
    function trim(string memory str) internal pure returns (string memory result) {
        bytes memory b = bytes(str);
        if (b.length == 0) return str;

        uint256 start = 0;
        uint256 end = b.length;

        // Find start (skip leading whitespace)
        while (start < end && isWhitespace(b[start])) {
            start++;
        }

        // Find end (skip trailing whitespace)
        while (end > start && isWhitespace(b[end - 1])) {
            end--;
        }

        if (start == 0 && end == b.length) return str;
        return substring(str, start, end);
    }

    /**
     * @notice Pads a string on the left to a specified length
     * @param str The string to pad
     * @param targetLength The desired length
     * @param padChar The character to pad with
     * @return result The padded string
     */
    function padLeft(
        string memory str,
        uint256 targetLength,
        string memory padChar
    ) internal pure returns (string memory result) {
        bytes memory b = bytes(str);
        if (b.length >= targetLength) return str;

        uint256 padLength = targetLength - b.length;
        bytes memory padBytes = bytes(padChar);
        if (padBytes.length == 0) revert EmptyString();

        bytes memory padded = new bytes(targetLength);

        // Fill with padding
        for (uint256 i = 0; i < padLength; i++) {
            padded[i] = padBytes[i % padBytes.length];
        }

        // Copy original string
        for (uint256 i = 0; i < b.length; i++) {
            padded[padLength + i] = b[i];
        }

        result = string(padded);
    }

    /**
     * @notice Pads a string on the right to a specified length
     * @param str The string to pad
     * @param targetLength The desired length
     * @param padChar The character to pad with
     * @return result The padded string
     */
    function padRight(
        string memory str,
        uint256 targetLength,
        string memory padChar
    ) internal pure returns (string memory result) {
        bytes memory b = bytes(str);
        if (b.length >= targetLength) return str;

        uint256 padLength = targetLength - b.length;
        bytes memory padBytes = bytes(padChar);
        if (padBytes.length == 0) revert EmptyString();

        bytes memory padded = new bytes(targetLength);

        // Copy original string
        for (uint256 i = 0; i < b.length; i++) {
            padded[i] = b[i];
        }

        // Fill with padding
        for (uint256 i = 0; i < padLength; i++) {
            padded[b.length + i] = padBytes[i % padBytes.length];
        }

        result = string(padded);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REPLACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Replaces first occurrence of search with replacement
     * @param str The source string
     * @param search The substring to find
     * @param replacement The replacement string
     * @return result The modified string
     */
    function replace(
        string memory str,
        string memory search,
        string memory replacement
    ) internal pure returns (string memory result) {
        uint256 idx = indexOf(str, search);
        if (idx == type(uint256).max) return str;

        string memory before = substring(str, 0, idx);
        string memory after = substring(str, idx + length(search), length(str));

        result = concat(concat(before, replacement), after);
    }

    /**
     * @notice Replaces all occurrences of search with replacement
     * @param str The source string
     * @param search The substring to find
     * @param replacement The replacement string
     * @return result The modified string
     */
    function replaceAll(
        string memory str,
        string memory search,
        string memory replacement
    ) internal pure returns (string memory result) {
        result = str;

        // Safety limit to prevent infinite loops
        for (uint256 i = 0; i < 100; i++) {
            uint256 idx = indexOf(result, search);
            if (idx == type(uint256).max) break;
            result = replace(result, search, replacement);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Checks if a byte is whitespace (space, tab, newline, etc.)
     */
    function isWhitespace(bytes1 b) private pure returns (bool) {
        return b == 0x20 || // space
               b == 0x09 || // tab
               b == 0x0A || // newline
               b == 0x0D || // carriage return
               b == 0x0B || // vertical tab
               b == 0x0C;   // form feed
    }

    /**
     * @notice Splits a string by a delimiter (returns first N parts)
     * @param str The string to split
     * @param delimiter The delimiter
     * @param maxParts Maximum number of parts to return
     * @return parts Array of string parts
     */
    function split(
        string memory str,
        string memory delimiter,
        uint256 maxParts
    ) internal pure returns (string[] memory parts) {
        if (maxParts == 0) return new string[](0);

        // Count occurrences first
        uint256 count = 1;
        string memory temp = str;
        while (count < maxParts) {
            uint256 idx = indexOf(temp, delimiter);
            if (idx == type(uint256).max) break;
            count++;
            temp = substring(temp, idx + length(delimiter), length(temp));
        }

        // Split into parts
        parts = new string[](count);
        temp = str;
        for (uint256 i = 0; i < count - 1; i++) {
            uint256 idx = indexOf(temp, delimiter);
            parts[i] = substring(temp, 0, idx);
            temp = substring(temp, idx + length(delimiter), length(temp));
        }
        parts[count - 1] = temp;
    }
}
