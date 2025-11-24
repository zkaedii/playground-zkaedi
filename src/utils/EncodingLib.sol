// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EncodingLib
 * @notice Cross-chain message encoding/decoding utilities
 * @dev Provides standardized encoding for swap routes, messages, and payloads
 */
library EncodingLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    // Message type identifiers
    uint8 internal constant MSG_TYPE_SWAP = 0x01;
    uint8 internal constant MSG_TYPE_BRIDGE = 0x02;
    uint8 internal constant MSG_TYPE_CALLBACK = 0x03;
    uint8 internal constant MSG_TYPE_GOVERNANCE = 0x04;
    uint8 internal constant MSG_TYPE_EMERGENCY = 0x05;

    // Route encoding version
    uint8 internal constant ROUTE_VERSION_V2 = 0x02;
    uint8 internal constant ROUTE_VERSION_V3 = 0x03;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidMessageType();
    error InvalidRouteVersion();
    error DecodingError();
    error InvalidDataLength();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Cross-chain message header
    struct MessageHeader {
        uint8 messageType;
        uint8 version;
        uint32 srcChainId;
        uint32 dstChainId;
        uint64 nonce;
        uint64 timestamp;
        address sender;
    }

    /// @notice Swap route hop
    struct RouteHop {
        address pool;
        address tokenIn;
        address tokenOut;
        uint24 fee;          // For V3-style pools
        bool isV3;           // True for concentrated liquidity
    }

    /// @notice Full swap route
    struct SwapRoute {
        RouteHop[] hops;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        uint256 deadline;
    }

    /// @notice Bridge payload
    struct BridgePayload {
        address token;
        uint256 amount;
        address recipient;
        uint32 destinationChain;
        bytes extraData;
    }

    /// @notice Callback data
    struct CallbackData {
        bytes32 requestId;
        address callbackTarget;
        bytes4 callbackSelector;
        bytes callbackArgs;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MESSAGE HEADER ENCODING/DECODING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Encode message header (38 bytes)
    function encodeHeader(MessageHeader memory header) internal pure returns (bytes memory) {
        return abi.encodePacked(
            header.messageType,
            header.version,
            header.srcChainId,
            header.dstChainId,
            header.nonce,
            header.timestamp,
            header.sender
        );
    }

    /// @notice Decode message header from bytes
    function decodeHeader(bytes memory data) internal pure returns (MessageHeader memory header) {
        if (data.length < 38) revert InvalidDataLength();

        assembly {
            let ptr := add(data, 32)
            // messageType (1 byte) + version (1 byte)
            let firstWord := mload(ptr)
            mstore(header, shr(248, firstWord))  // messageType
            mstore(add(header, 0x20), shr(248, shl(8, firstWord)))  // version
            mstore(add(header, 0x40), shr(224, shl(16, firstWord))) // srcChainId
            mstore(add(header, 0x60), shr(224, shl(48, firstWord))) // dstChainId
            mstore(add(header, 0x80), shr(192, shl(80, firstWord))) // nonce
            mstore(add(header, 0xa0), shr(192, shl(144, firstWord))) // timestamp
            // sender (20 bytes starting at offset 18)
            mstore(add(header, 0xc0), shr(96, mload(add(ptr, 18))))
        }
    }

    /// @notice Get message type from encoded data
    function getMessageType(bytes memory data) internal pure returns (uint8) {
        if (data.length < 1) revert InvalidDataLength();
        return uint8(data[0]);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SWAP ROUTE ENCODING/DECODING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Encode a single route hop
    function encodeHop(RouteHop memory hop) internal pure returns (bytes memory) {
        return abi.encodePacked(
            hop.pool,
            hop.tokenIn,
            hop.tokenOut,
            hop.fee,
            hop.isV3 ? uint8(1) : uint8(0)
        );
    }

    /// @notice Encode full swap route
    function encodeRoute(SwapRoute memory route) internal pure returns (bytes memory) {
        bytes memory hopsEncoded;

        for (uint256 i; i < route.hops.length; ++i) {
            hopsEncoded = abi.encodePacked(hopsEncoded, encodeHop(route.hops[i]));
        }

        return abi.encodePacked(
            uint8(route.hops.length),
            hopsEncoded,
            route.amountIn,
            route.minAmountOut,
            route.recipient,
            route.deadline
        );
    }

    /// @notice Encode V2-style path (address array)
    function encodeV2Path(address[] memory path) internal pure returns (bytes memory) {
        bytes memory encoded;
        unchecked {
            for (uint256 i; i < path.length; ++i) {
                encoded = abi.encodePacked(encoded, path[i]);
            }
        }
        return encoded;
    }

    /// @notice Decode V2-style path
    function decodeV2Path(bytes memory data) internal pure returns (address[] memory path) {
        if (data.length % 20 != 0) revert InvalidDataLength();

        uint256 count = data.length / 20;
        path = new address[](count);

        assembly {
            let ptr := add(data, 32)
            for { let i := 0 } lt(i, count) { i := add(i, 1) } {
                mstore(
                    add(add(path, 32), mul(i, 32)),
                    shr(96, mload(add(ptr, mul(i, 20))))
                )
            }
        }
    }

    /// @notice Encode V3-style path (address + fee + address + fee + ...)
    function encodeV3Path(
        address[] memory tokens,
        uint24[] memory fees
    ) internal pure returns (bytes memory path) {
        if (tokens.length != fees.length + 1) revert InvalidDataLength();

        path = abi.encodePacked(tokens[0]);

        unchecked {
            for (uint256 i; i < fees.length; ++i) {
                path = abi.encodePacked(path, fees[i], tokens[i + 1]);
            }
        }
    }

    /// @notice Decode V3-style path
    function decodeV3Path(bytes memory path) internal pure returns (
        address[] memory tokens,
        uint24[] memory fees
    ) {
        // Each token is 20 bytes, each fee is 3 bytes
        // Path format: token0 + fee0 + token1 + fee1 + token2 + ...
        // Minimum: 20 bytes (single token, no swaps)
        // With swap: 20 + 3 + 20 = 43 bytes

        if (path.length < 20) revert InvalidDataLength();

        uint256 numPools = (path.length - 20) / 23;
        tokens = new address[](numPools + 1);
        fees = new uint24[](numPools);

        assembly {
            let ptr := add(path, 32)
            // First token
            mstore(add(tokens, 32), shr(96, mload(ptr)))

            for { let i := 0 } lt(i, numPools) { i := add(i, 1) } {
                // Fee (3 bytes)
                let feePtr := add(ptr, add(20, mul(i, 23)))
                mstore(
                    add(add(fees, 32), mul(i, 32)),
                    shr(232, mload(feePtr))
                )
                // Next token (20 bytes)
                let tokenPtr := add(feePtr, 3)
                mstore(
                    add(add(tokens, 64), mul(i, 32)),
                    shr(96, mload(tokenPtr))
                )
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BRIDGE PAYLOAD ENCODING/DECODING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Encode bridge payload
    function encodeBridgePayload(BridgePayload memory payload) internal pure returns (bytes memory) {
        return abi.encode(
            payload.token,
            payload.amount,
            payload.recipient,
            payload.destinationChain,
            payload.extraData
        );
    }

    /// @notice Decode bridge payload
    function decodeBridgePayload(bytes memory data) internal pure returns (BridgePayload memory) {
        (
            address token,
            uint256 amount,
            address recipient,
            uint32 destinationChain,
            bytes memory extraData
        ) = abi.decode(data, (address, uint256, address, uint32, bytes));

        return BridgePayload({
            token: token,
            amount: amount,
            recipient: recipient,
            destinationChain: destinationChain,
            extraData: extraData
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLBACK ENCODING/DECODING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Encode callback data
    function encodeCallback(CallbackData memory callback) internal pure returns (bytes memory) {
        return abi.encode(
            callback.requestId,
            callback.callbackTarget,
            callback.callbackSelector,
            callback.callbackArgs
        );
    }

    /// @notice Decode callback data
    function decodeCallback(bytes memory data) internal pure returns (CallbackData memory) {
        (
            bytes32 requestId,
            address callbackTarget,
            bytes4 callbackSelector,
            bytes memory callbackArgs
        ) = abi.decode(data, (bytes32, address, bytes4, bytes));

        return CallbackData({
            requestId: requestId,
            callbackTarget: callbackTarget,
            callbackSelector: callbackSelector,
            callbackArgs: callbackArgs
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PACKED ENCODING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Pack two uint128 values into uint256
    function packUint128(uint128 a, uint128 b) internal pure returns (uint256) {
        return (uint256(a) << 128) | uint256(b);
    }

    /// @notice Unpack uint256 into two uint128 values
    function unpackUint128(uint256 packed) internal pure returns (uint128 a, uint128 b) {
        a = uint128(packed >> 128);
        b = uint128(packed);
    }

    /// @notice Pack four uint64 values into uint256
    function packUint64(
        uint64 a,
        uint64 b,
        uint64 c,
        uint64 d
    ) internal pure returns (uint256) {
        return (uint256(a) << 192) | (uint256(b) << 128) | (uint256(c) << 64) | uint256(d);
    }

    /// @notice Unpack uint256 into four uint64 values
    function unpackUint64(uint256 packed) internal pure returns (
        uint64 a,
        uint64 b,
        uint64 c,
        uint64 d
    ) {
        a = uint64(packed >> 192);
        b = uint64(packed >> 128);
        c = uint64(packed >> 64);
        d = uint64(packed);
    }

    /// @notice Pack address and uint96 into single slot
    function packAddressUint96(address addr, uint96 value) internal pure returns (uint256) {
        return (uint256(uint160(addr)) << 96) | uint256(value);
    }

    /// @notice Unpack address and uint96
    function unpackAddressUint96(uint256 packed) internal pure returns (address addr, uint96 value) {
        addr = address(uint160(packed >> 96));
        value = uint96(packed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MESSAGE ID GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate unique message ID
    function generateMessageId(
        uint32 srcChainId,
        uint32 dstChainId,
        address sender,
        uint64 nonce
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            srcChainId,
            dstChainId,
            sender,
            nonce,
            block.timestamp
        ));
    }

    /// @notice Generate deterministic message ID (same inputs = same output)
    function deterministicMessageId(
        uint32 srcChainId,
        uint32 dstChainId,
        address sender,
        uint64 nonce,
        bytes32 payloadHash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            srcChainId,
            dstChainId,
            sender,
            nonce,
            payloadHash
        ));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SELECTOR HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Extract function selector from calldata
    function extractSelector(bytes calldata data) internal pure returns (bytes4) {
        if (data.length < 4) revert InvalidDataLength();
        return bytes4(data[:4]);
    }

    /// @notice Create calldata with selector and encoded args
    function createCalldata(
        bytes4 selector,
        bytes memory args
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(selector, args);
    }

    /// @notice Create calldata for function call with single address arg
    function createCalldataAddress(
        bytes4 selector,
        address arg
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(selector, arg);
    }

    /// @notice Create calldata for function call with address and uint256
    function createCalldataAddressUint(
        bytes4 selector,
        address addr,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(selector, addr, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HASH HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Hash swap route for verification
    function hashRoute(SwapRoute memory route) internal pure returns (bytes32) {
        return keccak256(encodeRoute(route));
    }

    /// @notice Hash message header
    function hashHeader(MessageHeader memory header) internal pure returns (bytes32) {
        return keccak256(encodeHeader(header));
    }

    /// @notice Verify message hasn't been tampered with
    function verifyIntegrity(
        bytes memory message,
        bytes32 expectedHash
    ) internal pure returns (bool) {
        return keccak256(message) == expectedHash;
    }
}
