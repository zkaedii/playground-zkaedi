// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StringUtils
 * @notice Gas-efficient string manipulation library for Solidity
 * @dev Implements common string operations, formatting, and conversions
 */
library StringUtils {
    // ============ ERRORS ============
    error EmptyString();
    error StringTooLong(uint256 length, uint256 maxLength);
    error InvalidCharacter(bytes1 char);
    error InvalidHexString();
    error InvalidNumberString();
    error IndexOutOfBounds(uint256 index, uint256 length);

    // ============ CONSTANTS ============
    bytes16 internal constant HEX_DIGITS = "0123456789abcdef";
    bytes16 internal constant HEX_DIGITS_UPPER = "0123456789ABCDEF";
    uint256 internal constant MAX_STRING_LENGTH = 1024;

    // ============ BASIC OPERATIONS ============

    /**
     * @notice Get string length
     * @param str The string
     * @return The length in bytes
     */
    function length(string memory str) internal pure returns (uint256) {
        return bytes(str).length;
    }

    /**
     * @notice Check if string is empty
     * @param str The string to check
     * @return True if empty
     */
    function isEmpty(string memory str) internal pure returns (bool) {
        return bytes(str).length == 0;
    }

    /**
     * @notice Compare two strings for equality
     * @param a First string
     * @param b Second string
     * @return True if equal
     */
    function equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @notice Compare string with bytes32
     * @param str The string
     * @param b32 The bytes32
     * @return True if equal
     */
    function equalsBytes32(string memory str, bytes32 b32) internal pure returns (bool) {
        return keccak256(bytes(str)) == keccak256(abi.encodePacked(b32));
    }

    /**
     * @notice Concatenate two strings
     * @param a First string
     * @param b Second string
     * @return The concatenated string
     */
    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    /**
     * @notice Concatenate multiple strings
     * @param strings Array of strings to concatenate
     * @return result The concatenated string
     */
    function concatMany(string[] memory strings) internal pure returns (string memory result) {
        bytes memory temp;
        for (uint256 i = 0; i < strings.length; i++) {
            temp = abi.encodePacked(temp, strings[i]);
        }
        return string(temp);
    }

    // ============ NUMBER CONVERSIONS ============

    /**
     * @notice Convert uint256 to string
     * @param value The number to convert
     * @return The string representation
     */
    function toString(uint256 value) internal pure returns (string memory) {
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
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @notice Convert int256 to string
     * @param value The signed number to convert
     * @return The string representation
     */
    function toStringSigned(int256 value) internal pure returns (string memory) {
        if (value >= 0) {
            return toString(uint256(value));
        }
        return concat("-", toString(uint256(-value)));
    }

    /**
     * @notice Convert uint256 to string with decimals
     * @param value The number (in smallest unit)
     * @param decimals Number of decimal places
     * @return The formatted string
     */
    function toStringWithDecimals(
        uint256 value,
        uint8 decimals
    ) internal pure returns (string memory) {
        if (decimals == 0) return toString(value);

        uint256 divisor = 10 ** decimals;
        uint256 wholePart = value / divisor;
        uint256 fractionalPart = value % divisor;

        if (fractionalPart == 0) {
            return concat(toString(wholePart), ".0");
        }

        // Pad fractional part with leading zeros
        string memory fracStr = toString(fractionalPart);
        bytes memory fracBytes = bytes(fracStr);

        // Add leading zeros if needed
        uint256 leadingZeros = decimals - fracBytes.length;
        bytes memory paddedFrac = new bytes(decimals);

        for (uint256 i = 0; i < leadingZeros; i++) {
            paddedFrac[i] = "0";
        }
        for (uint256 i = 0; i < fracBytes.length; i++) {
            paddedFrac[leadingZeros + i] = fracBytes[i];
        }

        // Trim trailing zeros
        uint256 trimmedLength = decimals;
        while (trimmedLength > 1 && paddedFrac[trimmedLength - 1] == "0") {
            trimmedLength--;
        }

        bytes memory trimmedFrac = new bytes(trimmedLength);
        for (uint256 i = 0; i < trimmedLength; i++) {
            trimmedFrac[i] = paddedFrac[i];
        }

        return string(abi.encodePacked(toString(wholePart), ".", trimmedFrac));
    }

    /**
     * @notice Parse string to uint256
     * @param str The string to parse
     * @return value The parsed number
     */
    function parseUint(string memory str) internal pure returns (uint256 value) {
        bytes memory b = bytes(str);
        if (b.length == 0) revert EmptyString();

        for (uint256 i = 0; i < b.length; i++) {
            uint8 char = uint8(b[i]);
            if (char < 48 || char > 57) revert InvalidNumberString();
            value = value * 10 + (char - 48);
        }
    }

    // ============ HEX CONVERSIONS ============

    /**
     * @notice Convert uint256 to hex string
     * @param value The number to convert
     * @return The hex string (without 0x prefix)
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 4;
        }

        bytes memory buffer = new bytes(length);
        while (value != 0) {
            length--;
            buffer[length] = HEX_DIGITS[value & 0xf];
            value >>= 4;
        }

        return string(buffer);
    }

    /**
     * @notice Convert uint256 to hex string with fixed length
     * @param value The number to convert
     * @param byteLength Number of bytes (will be 2x hex chars)
     * @return The hex string (without 0x prefix)
     */
    function toHexStringFixed(
        uint256 value,
        uint256 byteLength
    ) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * byteLength);
        for (uint256 i = 2 * byteLength; i > 0; i--) {
            buffer[i - 1] = HEX_DIGITS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }

    /**
     * @notice Convert address to hex string
     * @param addr The address to convert
     * @return The hex string with 0x prefix
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return concat("0x", toHexStringFixed(uint256(uint160(addr)), 20));
    }

    /**
     * @notice Convert bytes32 to hex string
     * @param value The bytes32 to convert
     * @return The hex string with 0x prefix
     */
    function toHexString(bytes32 value) internal pure returns (string memory) {
        return concat("0x", toHexStringFixed(uint256(value), 32));
    }

    /**
     * @notice Convert bytes to hex string
     * @param data The bytes to convert
     * @return The hex string with 0x prefix
     */
    function bytesToHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory hexChars = new bytes(2 * data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hexChars[2 * i] = HEX_DIGITS[uint8(data[i]) >> 4];
            hexChars[2 * i + 1] = HEX_DIGITS[uint8(data[i]) & 0x0f];
        }
        return concat("0x", string(hexChars));
    }

    // ============ STRING MANIPULATION ============

    /**
     * @notice Get substring
     * @param str The source string
     * @param startIndex Start index (inclusive)
     * @param endIndex End index (exclusive)
     * @return The substring
     */
    function substring(
        string memory str,
        uint256 startIndex,
        uint256 endIndex
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (startIndex >= strBytes.length) revert IndexOutOfBounds(startIndex, strBytes.length);
        if (endIndex > strBytes.length) endIndex = strBytes.length;
        if (startIndex >= endIndex) return "";

        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }

        return string(result);
    }

    /**
     * @notice Convert string to lowercase
     * @param str The string to convert
     * @return The lowercase string
     */
    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }

        return string(bLower);
    }

    /**
     * @notice Convert string to uppercase
     * @param str The string to convert
     * @return The uppercase string
     */
    function toUpper(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bUpper = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x61 && bStr[i] <= 0x7A) {
                bUpper[i] = bytes1(uint8(bStr[i]) - 32);
            } else {
                bUpper[i] = bStr[i];
            }
        }

        return string(bUpper);
    }

    /**
     * @notice Check if string contains substring
     * @param str The string to search in
     * @param substr The substring to find
     * @return True if found
     */
    function contains(
        string memory str,
        string memory substr
    ) internal pure returns (bool) {
        return indexOf(str, substr) != type(uint256).max;
    }

    /**
     * @notice Find index of substring
     * @param str The string to search in
     * @param substr The substring to find
     * @return The index, or type(uint256).max if not found
     */
    function indexOf(
        string memory str,
        string memory substr
    ) internal pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length == 0) return 0;
        if (substrBytes.length > strBytes.length) return type(uint256).max;

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }

        return type(uint256).max;
    }

    /**
     * @notice Check if string starts with prefix
     * @param str The string to check
     * @param prefix The prefix to look for
     * @return True if starts with prefix
     */
    function startsWith(
        string memory str,
        string memory prefix
    ) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);

        if (prefixBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }

        return true;
    }

    /**
     * @notice Check if string ends with suffix
     * @param str The string to check
     * @param suffix The suffix to look for
     * @return True if ends with suffix
     */
    function endsWith(
        string memory str,
        string memory suffix
    ) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);

        if (suffixBytes.length > strBytes.length) return false;

        uint256 offset = strBytes.length - suffixBytes.length;
        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[offset + i] != suffixBytes[i]) return false;
        }

        return true;
    }

    // ============ BYTES32 CONVERSIONS ============

    /**
     * @notice Convert string to bytes32 (truncates if too long)
     * @param str The string to convert
     * @return result The bytes32 representation
     */
    function toBytes32(string memory str) internal pure returns (bytes32 result) {
        bytes memory strBytes = bytes(str);
        assembly {
            result := mload(add(strBytes, 32))
        }
    }

    /**
     * @notice Convert bytes32 to string (removes trailing zeros)
     * @param value The bytes32 to convert
     * @return The string representation
     */
    function fromBytes32(bytes32 value) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(32);
        uint256 length = 0;

        for (uint256 i = 0; i < 32; i++) {
            bytes1 char = value[i];
            if (char != 0) {
                bytesArray[i] = char;
                length = i + 1;
            }
        }

        bytes memory trimmed = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            trimmed[i] = bytesArray[i];
        }

        return string(trimmed);
    }

    // ============ FORMATTING ============

    /**
     * @notice Pad string on left
     * @param str The string to pad
     * @param totalLength Target length
     * @param padChar Character to pad with
     * @return The padded string
     */
    function padLeft(
        string memory str,
        uint256 totalLength,
        bytes1 padChar
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= totalLength) return str;

        uint256 padLength = totalLength - strBytes.length;
        bytes memory result = new bytes(totalLength);

        for (uint256 i = 0; i < padLength; i++) {
            result[i] = padChar;
        }
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padLength + i] = strBytes[i];
        }

        return string(result);
    }

    /**
     * @notice Pad string on right
     * @param str The string to pad
     * @param totalLength Target length
     * @param padChar Character to pad with
     * @return The padded string
     */
    function padRight(
        string memory str,
        uint256 totalLength,
        bytes1 padChar
    ) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= totalLength) return str;

        bytes memory result = new bytes(totalLength);

        for (uint256 i = 0; i < strBytes.length; i++) {
            result[i] = strBytes[i];
        }
        for (uint256 i = strBytes.length; i < totalLength; i++) {
            result[i] = padChar;
        }

        return string(result);
    }

    /**
     * @notice Format address as checksummed string (EIP-55)
     * @param addr The address to format
     * @return The checksummed address string
     */
    function toChecksumAddress(address addr) internal pure returns (string memory) {
        bytes memory lowercaseHex = bytes(toHexStringFixed(uint256(uint160(addr)), 20));
        bytes32 hash = keccak256(abi.encodePacked(toLower(string(lowercaseHex))));

        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";

        for (uint256 i = 0; i < 40; i++) {
            uint8 hashByte = uint8(hash[i / 2]);
            uint8 hashNibble = (i % 2 == 0) ? (hashByte >> 4) : (hashByte & 0x0f);

            if (hashNibble >= 8 && lowercaseHex[i] >= 0x61 && lowercaseHex[i] <= 0x66) {
                result[i + 2] = bytes1(uint8(lowercaseHex[i]) - 32);
            } else {
                result[i + 2] = lowercaseHex[i];
            }
        }

        return string(result);
    }
}
