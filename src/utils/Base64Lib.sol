// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Base64Lib
 * @notice Gas-efficient Base64 encoding and decoding library
 * @dev Provides RFC 4648 compliant Base64 encoding/decoding
 *      Optimized for on-chain SVG and JSON generation (NFT metadata)
 *      Supports both standard and URL-safe variants
 */
library Base64Lib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Standard Base64 encoding table
    bytes internal constant ENCODING_TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @dev URL-safe Base64 encoding table (RFC 4648 Section 5)
    bytes internal constant ENCODING_TABLE_URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    /// @dev Decoding table - maps ASCII to 6-bit values (invalid chars = 0xFF)
    /// Stored as bytes32 chunks for gas efficiency

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidBase64Character();
    error InvalidBase64Length();
    error InvalidPadding();

    // ═══════════════════════════════════════════════════════════════════════════
    // ENCODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encodes bytes to Base64 string
     * @param data The bytes to encode
     * @return result The Base64 encoded string
     */
    function encode(bytes memory data) internal pure returns (string memory result) {
        if (data.length == 0) return "";

        // Calculate output length (4 chars per 3 bytes, with padding)
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // Allocate memory for result
        bytes memory output = new bytes(encodedLen);

        // Load encoding table into memory for faster access
        bytes memory table = ENCODING_TABLE;

        assembly {
            // Set up pointers
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(output, 32)

            // Process 3 bytes at a time
            for {} lt(dataPtr, endPtr) {} {
                // Load 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)

                // Extract 4 x 6-bit values
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }

            // Handle padding
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3D) // '='
                mstore8(sub(resultPtr, 2), 0x3D) // '='
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3D) // '='
            }
        }

        return string(output);
    }

    /**
     * @notice Encodes bytes to URL-safe Base64 (no padding)
     * @param data The bytes to encode
     * @return result The URL-safe Base64 encoded string
     */
    function encodeURL(bytes memory data) internal pure returns (string memory result) {
        if (data.length == 0) return "";

        // Calculate output length (no padding for URL-safe)
        uint256 remainder = data.length % 3;
        uint256 encodedLen = 4 * (data.length / 3);
        if (remainder > 0) {
            encodedLen += remainder + 1;
        }

        bytes memory output = new bytes(encodedLen);
        bytes memory table = ENCODING_TABLE_URL;

        assembly {
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(output, 32)

            // Process complete 3-byte groups
            for {} iszero(lt(sub(endPtr, dataPtr), 3)) {} {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)

                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }

            // Handle remaining bytes (no padding)
            let remaining := sub(endPtr, dataPtr)
            if eq(remaining, 1) {
                dataPtr := add(dataPtr, 1)
                let input := and(mload(dataPtr), 0xFF0000000000000000000000000000000000000000000000000000000000)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(250, input), 0x3F))))
                mstore8(add(resultPtr, 1), mload(add(tablePtr, and(shr(244, input), 0x3F))))
            }
            if eq(remaining, 2) {
                dataPtr := add(dataPtr, 2)
                let input := and(mload(dataPtr), 0xFFFF00000000000000000000000000000000000000000000000000000000)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(250, input), 0x3F))))
                mstore8(add(resultPtr, 1), mload(add(tablePtr, and(shr(244, input), 0x3F))))
                mstore8(add(resultPtr, 2), mload(add(tablePtr, and(shr(238, input), 0x3F))))
            }
        }

        return string(output);
    }

    /**
     * @notice Encodes a string to Base64
     * @param str The string to encode
     * @return The Base64 encoded string
     */
    function encode(string memory str) internal pure returns (string memory) {
        return encode(bytes(str));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DECODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Decodes a Base64 string to bytes
     * @param encoded The Base64 encoded string
     * @return result The decoded bytes
     */
    function decode(string memory encoded) internal pure returns (bytes memory result) {
        bytes memory data = bytes(encoded);
        if (data.length == 0) return "";
        if (data.length % 4 != 0) revert InvalidBase64Length();

        // Count padding characters
        uint256 padding = 0;
        if (data.length > 0 && data[data.length - 1] == "=") padding++;
        if (data.length > 1 && data[data.length - 2] == "=") padding++;

        // Calculate output length
        uint256 decodedLen = (data.length / 4) * 3 - padding;
        result = new bytes(decodedLen);

        assembly {
            let dataPtr := add(data, 32)
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)

            // Decoding table inline
            // A-Z: 0-25, a-z: 26-51, 0-9: 52-61, +: 62, /: 63
            function decodeChar(c) -> v {
                switch true
                case 1 {
                    // A-Z (65-90) -> 0-25
                    if and(gt(c, 64), lt(c, 91)) {
                        v := sub(c, 65)
                        leave
                    }
                    // a-z (97-122) -> 26-51
                    if and(gt(c, 96), lt(c, 123)) {
                        v := sub(c, 71)
                        leave
                    }
                    // 0-9 (48-57) -> 52-61
                    if and(gt(c, 47), lt(c, 58)) {
                        v := add(c, 4)
                        leave
                    }
                    // + (43) -> 62
                    if eq(c, 43) {
                        v := 62
                        leave
                    }
                    // / (47) -> 63
                    if eq(c, 47) {
                        v := 63
                        leave
                    }
                    // = (61) -> 0 (padding)
                    if eq(c, 61) {
                        v := 0
                        leave
                    }
                    // Invalid character
                    v := 0xFF
                }
            }

            // Process 4 characters at a time
            for {} lt(dataPtr, endPtr) {} {
                // Read 4 characters
                let c0 := byte(0, mload(dataPtr))
                let c1 := byte(0, mload(add(dataPtr, 1)))
                let c2 := byte(0, mload(add(dataPtr, 2)))
                let c3 := byte(0, mload(add(dataPtr, 3)))

                // Decode characters
                let v0 := decodeChar(c0)
                let v1 := decodeChar(c1)
                let v2 := decodeChar(c2)
                let v3 := decodeChar(c3)

                // Check for invalid characters
                if or(eq(v0, 0xFF), or(eq(v1, 0xFF), or(eq(v2, 0xFF), eq(v3, 0xFF)))) {
                    revert(0, 0)
                }

                // Combine into 3 bytes
                let combined := or(or(shl(18, v0), shl(12, v1)), or(shl(6, v2), v3))

                // Write output bytes
                mstore8(resultPtr, and(shr(16, combined), 0xFF))
                mstore8(add(resultPtr, 1), and(shr(8, combined), 0xFF))
                mstore8(add(resultPtr, 2), and(combined, 0xFF))

                dataPtr := add(dataPtr, 4)
                resultPtr := add(resultPtr, 3)
            }
        }
    }

    /**
     * @notice Decodes a URL-safe Base64 string to bytes
     * @param encoded The URL-safe Base64 encoded string
     * @return result The decoded bytes
     */
    function decodeURL(string memory encoded) internal pure returns (bytes memory result) {
        bytes memory data = bytes(encoded);
        if (data.length == 0) return "";

        // Add padding if needed
        uint256 remainder = data.length % 4;
        uint256 paddingNeeded = remainder > 0 ? 4 - remainder : 0;

        // Create padded version
        bytes memory padded = new bytes(data.length + paddingNeeded);
        for (uint256 i = 0; i < data.length; i++) {
            // Convert URL-safe chars to standard
            if (data[i] == "-") {
                padded[i] = "+";
            } else if (data[i] == "_") {
                padded[i] = "/";
            } else {
                padded[i] = data[i];
            }
        }

        // Add padding
        for (uint256 i = 0; i < paddingNeeded; i++) {
            padded[data.length + i] = "=";
        }

        return decode(string(padded));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DATA URI HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Creates a data URI with Base64 encoded content
     * @param mimeType The MIME type (e.g., "application/json", "image/svg+xml")
     * @param data The data to encode
     * @return uri The complete data URI
     */
    function toDataURI(
        string memory mimeType,
        bytes memory data
    ) internal pure returns (string memory uri) {
        return string(
            abi.encodePacked(
                "data:",
                mimeType,
                ";base64,",
                encode(data)
            )
        );
    }

    /**
     * @notice Creates a JSON data URI (common for NFT metadata)
     * @param json The JSON string
     * @return uri The JSON data URI
     */
    function jsonDataURI(string memory json) internal pure returns (string memory uri) {
        return toDataURI("application/json", bytes(json));
    }

    /**
     * @notice Creates an SVG data URI (common for on-chain NFT images)
     * @param svg The SVG content
     * @return uri The SVG data URI
     */
    function svgDataURI(string memory svg) internal pure returns (string memory uri) {
        return toDataURI("image/svg+xml", bytes(svg));
    }

    /**
     * @notice Creates a plain text data URI
     * @param text The text content
     * @return uri The text data URI
     */
    function textDataURI(string memory text) internal pure returns (string memory uri) {
        return toDataURI("text/plain", bytes(text));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if a string is valid Base64
     * @param encoded The string to validate
     * @return valid True if the string is valid Base64
     */
    function isValidBase64(string memory encoded) internal pure returns (bool valid) {
        bytes memory data = bytes(encoded);
        if (data.length == 0) return true;
        if (data.length % 4 != 0) return false;

        for (uint256 i = 0; i < data.length; i++) {
            bytes1 c = data[i];

            // Check if character is valid
            bool isUppercase = c >= "A" && c <= "Z";
            bool isLowercase = c >= "a" && c <= "z";
            bool isDigit = c >= "0" && c <= "9";
            bool isPlus = c == "+";
            bool isSlash = c == "/";
            bool isPadding = c == "=" && i >= data.length - 2;

            if (!(isUppercase || isLowercase || isDigit || isPlus || isSlash || isPadding)) {
                return false;
            }

            // Padding must only be at the end
            if (c == "=" && i < data.length - 2) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Checks if a string is valid URL-safe Base64
     * @param encoded The string to validate
     * @return valid True if the string is valid URL-safe Base64
     */
    function isValidBase64URL(string memory encoded) internal pure returns (bool valid) {
        bytes memory data = bytes(encoded);
        if (data.length == 0) return true;

        for (uint256 i = 0; i < data.length; i++) {
            bytes1 c = data[i];

            bool isUppercase = c >= "A" && c <= "Z";
            bool isLowercase = c >= "a" && c <= "z";
            bool isDigit = c >= "0" && c <= "9";
            bool isMinus = c == "-";
            bool isUnderscore = c == "_";

            if (!(isUppercase || isLowercase || isDigit || isMinus || isUnderscore)) {
                return false;
            }
        }

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates the encoded length for given input length
     * @param inputLength The length of input bytes
     * @return encodedLength The length of Base64 output
     */
    function encodedLength(uint256 inputLength) internal pure returns (uint256) {
        return 4 * ((inputLength + 2) / 3);
    }

    /**
     * @notice Calculates the decoded length for given Base64 input
     * @param encoded The Base64 string
     * @return decodedLength The length of decoded output
     */
    function decodedLength(string memory encoded) internal pure returns (uint256) {
        bytes memory data = bytes(encoded);
        if (data.length == 0) return 0;

        uint256 padding = 0;
        if (data[data.length - 1] == "=") padding++;
        if (data.length > 1 && data[data.length - 2] == "=") padding++;

        return (data.length / 4) * 3 - padding;
    }
}
