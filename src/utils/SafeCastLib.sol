// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SafeCastLib
 * @notice Safe integer type conversions with overflow protection
 * @dev Provides safe narrowing conversions for all uint sizes
 */
library SafeCastLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error SafeCastOverflow(uint256 value, string targetType);
    error SafeCastSignedOverflow(int256 value, string targetType);
    error SafeCastNegativeValue(int256 value);

    // ═══════════════════════════════════════════════════════════════════════════
    // UINT256 → SMALLER UINT CONVERSIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Safely cast uint256 to uint248
     */
    function toUint248(uint256 value) internal pure returns (uint248) {
        if (value > type(uint248).max) revert SafeCastOverflow(value, "uint248");
        return uint248(value);
    }

    /**
     * @notice Safely cast uint256 to uint240
     */
    function toUint240(uint256 value) internal pure returns (uint240) {
        if (value > type(uint240).max) revert SafeCastOverflow(value, "uint240");
        return uint240(value);
    }

    /**
     * @notice Safely cast uint256 to uint232
     */
    function toUint232(uint256 value) internal pure returns (uint232) {
        if (value > type(uint232).max) revert SafeCastOverflow(value, "uint232");
        return uint232(value);
    }

    /**
     * @notice Safely cast uint256 to uint224
     */
    function toUint224(uint256 value) internal pure returns (uint224) {
        if (value > type(uint224).max) revert SafeCastOverflow(value, "uint224");
        return uint224(value);
    }

    /**
     * @notice Safely cast uint256 to uint216
     */
    function toUint216(uint256 value) internal pure returns (uint216) {
        if (value > type(uint216).max) revert SafeCastOverflow(value, "uint216");
        return uint216(value);
    }

    /**
     * @notice Safely cast uint256 to uint208
     */
    function toUint208(uint256 value) internal pure returns (uint208) {
        if (value > type(uint208).max) revert SafeCastOverflow(value, "uint208");
        return uint208(value);
    }

    /**
     * @notice Safely cast uint256 to uint200
     */
    function toUint200(uint256 value) internal pure returns (uint200) {
        if (value > type(uint200).max) revert SafeCastOverflow(value, "uint200");
        return uint200(value);
    }

    /**
     * @notice Safely cast uint256 to uint192
     */
    function toUint192(uint256 value) internal pure returns (uint192) {
        if (value > type(uint192).max) revert SafeCastOverflow(value, "uint192");
        return uint192(value);
    }

    /**
     * @notice Safely cast uint256 to uint184
     */
    function toUint184(uint256 value) internal pure returns (uint184) {
        if (value > type(uint184).max) revert SafeCastOverflow(value, "uint184");
        return uint184(value);
    }

    /**
     * @notice Safely cast uint256 to uint176
     */
    function toUint176(uint256 value) internal pure returns (uint176) {
        if (value > type(uint176).max) revert SafeCastOverflow(value, "uint176");
        return uint176(value);
    }

    /**
     * @notice Safely cast uint256 to uint168
     */
    function toUint168(uint256 value) internal pure returns (uint168) {
        if (value > type(uint168).max) revert SafeCastOverflow(value, "uint168");
        return uint168(value);
    }

    /**
     * @notice Safely cast uint256 to uint160
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        if (value > type(uint160).max) revert SafeCastOverflow(value, "uint160");
        return uint160(value);
    }

    /**
     * @notice Safely cast uint256 to uint152
     */
    function toUint152(uint256 value) internal pure returns (uint152) {
        if (value > type(uint152).max) revert SafeCastOverflow(value, "uint152");
        return uint152(value);
    }

    /**
     * @notice Safely cast uint256 to uint144
     */
    function toUint144(uint256 value) internal pure returns (uint144) {
        if (value > type(uint144).max) revert SafeCastOverflow(value, "uint144");
        return uint144(value);
    }

    /**
     * @notice Safely cast uint256 to uint136
     */
    function toUint136(uint256 value) internal pure returns (uint136) {
        if (value > type(uint136).max) revert SafeCastOverflow(value, "uint136");
        return uint136(value);
    }

    /**
     * @notice Safely cast uint256 to uint128
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert SafeCastOverflow(value, "uint128");
        return uint128(value);
    }

    /**
     * @notice Safely cast uint256 to uint120
     */
    function toUint120(uint256 value) internal pure returns (uint120) {
        if (value > type(uint120).max) revert SafeCastOverflow(value, "uint120");
        return uint120(value);
    }

    /**
     * @notice Safely cast uint256 to uint112
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        if (value > type(uint112).max) revert SafeCastOverflow(value, "uint112");
        return uint112(value);
    }

    /**
     * @notice Safely cast uint256 to uint104
     */
    function toUint104(uint256 value) internal pure returns (uint104) {
        if (value > type(uint104).max) revert SafeCastOverflow(value, "uint104");
        return uint104(value);
    }

    /**
     * @notice Safely cast uint256 to uint96
     */
    function toUint96(uint256 value) internal pure returns (uint96) {
        if (value > type(uint96).max) revert SafeCastOverflow(value, "uint96");
        return uint96(value);
    }

    /**
     * @notice Safely cast uint256 to uint88
     */
    function toUint88(uint256 value) internal pure returns (uint88) {
        if (value > type(uint88).max) revert SafeCastOverflow(value, "uint88");
        return uint88(value);
    }

    /**
     * @notice Safely cast uint256 to uint80
     */
    function toUint80(uint256 value) internal pure returns (uint80) {
        if (value > type(uint80).max) revert SafeCastOverflow(value, "uint80");
        return uint80(value);
    }

    /**
     * @notice Safely cast uint256 to uint72
     */
    function toUint72(uint256 value) internal pure returns (uint72) {
        if (value > type(uint72).max) revert SafeCastOverflow(value, "uint72");
        return uint72(value);
    }

    /**
     * @notice Safely cast uint256 to uint64
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) revert SafeCastOverflow(value, "uint64");
        return uint64(value);
    }

    /**
     * @notice Safely cast uint256 to uint56
     */
    function toUint56(uint256 value) internal pure returns (uint56) {
        if (value > type(uint56).max) revert SafeCastOverflow(value, "uint56");
        return uint56(value);
    }

    /**
     * @notice Safely cast uint256 to uint48
     */
    function toUint48(uint256 value) internal pure returns (uint48) {
        if (value > type(uint48).max) revert SafeCastOverflow(value, "uint48");
        return uint48(value);
    }

    /**
     * @notice Safely cast uint256 to uint40
     */
    function toUint40(uint256 value) internal pure returns (uint40) {
        if (value > type(uint40).max) revert SafeCastOverflow(value, "uint40");
        return uint40(value);
    }

    /**
     * @notice Safely cast uint256 to uint32
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) revert SafeCastOverflow(value, "uint32");
        return uint32(value);
    }

    /**
     * @notice Safely cast uint256 to uint24
     */
    function toUint24(uint256 value) internal pure returns (uint24) {
        if (value > type(uint24).max) revert SafeCastOverflow(value, "uint24");
        return uint24(value);
    }

    /**
     * @notice Safely cast uint256 to uint16
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        if (value > type(uint16).max) revert SafeCastOverflow(value, "uint16");
        return uint16(value);
    }

    /**
     * @notice Safely cast uint256 to uint8
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        if (value > type(uint8).max) revert SafeCastOverflow(value, "uint8");
        return uint8(value);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNED ↔ UNSIGNED CONVERSIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Safely cast int256 to uint256
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        if (value < 0) revert SafeCastNegativeValue(value);
        return uint256(value);
    }

    /**
     * @notice Safely cast uint256 to int256
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) revert SafeCastOverflow(value, "int256");
        return int256(value);
    }

    /**
     * @notice Safely cast int256 to int128
     */
    function toInt128(int256 value) internal pure returns (int128) {
        if (value < type(int128).min || value > type(int128).max) {
            revert SafeCastSignedOverflow(value, "int128");
        }
        return int128(value);
    }

    /**
     * @notice Safely cast int256 to int64
     */
    function toInt64(int256 value) internal pure returns (int64) {
        if (value < type(int64).min || value > type(int64).max) {
            revert SafeCastSignedOverflow(value, "int64");
        }
        return int64(value);
    }

    /**
     * @notice Safely cast int256 to int32
     */
    function toInt32(int256 value) internal pure returns (int32) {
        if (value < type(int32).min || value > type(int32).max) {
            revert SafeCastSignedOverflow(value, "int32");
        }
        return int32(value);
    }

    /**
     * @notice Safely cast int256 to int16
     */
    function toInt16(int256 value) internal pure returns (int16) {
        if (value < type(int16).min || value > type(int16).max) {
            revert SafeCastSignedOverflow(value, "int16");
        }
        return int16(value);
    }

    /**
     * @notice Safely cast int256 to int8
     */
    function toInt8(int256 value) internal pure returns (int8) {
        if (value < type(int8).min || value > type(int8).max) {
            revert SafeCastSignedOverflow(value, "int8");
        }
        return int8(value);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS CONVERSIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Cast uint256 to address (truncates upper bits)
     */
    function toAddress(uint256 value) internal pure returns (address) {
        return address(uint160(value));
    }

    /**
     * @notice Cast address to uint256
     */
    function toUint256(address value) internal pure returns (uint256) {
        return uint256(uint160(value));
    }

    /**
     * @notice Cast bytes32 to address (takes last 20 bytes)
     */
    function toAddress(bytes32 value) internal pure returns (address) {
        return address(uint160(uint256(value)));
    }

    /**
     * @notice Cast address to bytes32 (pads with zeros)
     */
    function toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRY-CAST VERSIONS (return success bool instead of reverting)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Try to cast uint256 to uint128
     * @return success True if cast succeeds
     * @return result Cast value (0 if failed)
     */
    function tryToUint128(uint256 value) internal pure returns (bool success, uint128 result) {
        if (value > type(uint128).max) return (false, 0);
        return (true, uint128(value));
    }

    /**
     * @notice Try to cast uint256 to uint96
     */
    function tryToUint96(uint256 value) internal pure returns (bool success, uint96 result) {
        if (value > type(uint96).max) return (false, 0);
        return (true, uint96(value));
    }

    /**
     * @notice Try to cast uint256 to uint64
     */
    function tryToUint64(uint256 value) internal pure returns (bool success, uint64 result) {
        if (value > type(uint64).max) return (false, 0);
        return (true, uint64(value));
    }

    /**
     * @notice Try to cast uint256 to uint48
     */
    function tryToUint48(uint256 value) internal pure returns (bool success, uint48 result) {
        if (value > type(uint48).max) return (false, 0);
        return (true, uint48(value));
    }

    /**
     * @notice Try to cast uint256 to uint32
     */
    function tryToUint32(uint256 value) internal pure returns (bool success, uint32 result) {
        if (value > type(uint32).max) return (false, 0);
        return (true, uint32(value));
    }

    /**
     * @notice Try to cast uint256 to uint16
     */
    function tryToUint16(uint256 value) internal pure returns (bool success, uint16 result) {
        if (value > type(uint16).max) return (false, 0);
        return (true, uint16(value));
    }

    /**
     * @notice Try to cast uint256 to uint8
     */
    function tryToUint8(uint256 value) internal pure returns (bool success, uint8 result) {
        if (value > type(uint8).max) return (false, 0);
        return (true, uint8(value));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SCALING UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Scale value from one decimal precision to another
     * @param value Value to scale
     * @param fromDecimals Current decimals
     * @param toDecimals Target decimals
     * @return Scaled value
     */
    function scaleDecimals(
        uint256 value,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return value;

        if (fromDecimals > toDecimals) {
            uint256 factor = 10 ** (fromDecimals - toDecimals);
            return value / factor;
        } else {
            uint256 factor = 10 ** (toDecimals - fromDecimals);
            return value * factor;
        }
    }

    /**
     * @notice Scale value with rounding up
     */
    function scaleDecimalsUp(
        uint256 value,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return value;

        if (fromDecimals > toDecimals) {
            uint256 factor = 10 ** (fromDecimals - toDecimals);
            return (value + factor - 1) / factor;
        } else {
            uint256 factor = 10 ** (toDecimals - fromDecimals);
            return value * factor;
        }
    }

    /**
     * @notice Scale and cast to uint128
     */
    function scaleToUint128(
        uint256 value,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint128) {
        return toUint128(scaleDecimals(value, fromDecimals, toDecimals));
    }

    /**
     * @notice Scale and cast to uint96
     */
    function scaleToUint96(
        uint256 value,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint96) {
        return toUint96(scaleDecimals(value, fromDecimals, toDecimals));
    }

    /**
     * @notice Scale and cast to uint64
     */
    function scaleToUint64(
        uint256 value,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint64) {
        return toUint64(scaleDecimals(value, fromDecimals, toDecimals));
    }
}
