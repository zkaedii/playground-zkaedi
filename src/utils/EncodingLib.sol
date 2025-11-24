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

    // Protocol identifiers
    uint8 internal constant PROTOCOL_CCIP = 0;
    uint8 internal constant PROTOCOL_LAYERZERO = 1;
    uint8 internal constant PROTOCOL_WORMHOLE = 2;
    uint8 internal constant PROTOCOL_AXELAR = 3;
    uint8 internal constant PROTOCOL_HYPERLANE = 4;

    // Version for payload format
    uint8 internal constant PAYLOAD_VERSION = 1;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidPayloadLength(uint256 expected, uint256 actual);
    error InvalidMessageType(uint8 msgType);
    error InvalidVersion(uint8 version);
    error DecodingFailed();
    error EmptyPayload();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Cross-chain swap message
    struct SwapMessage {
        uint8 version;
        uint8 msgType;
        bytes32 txId;
        address sender;
        address recipient;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        bytes extraData;
    }

    /// @notice Bridge transfer message
    struct BridgeMessage {
        uint8 version;
        uint8 msgType;
        bytes32 txId;
        address sender;
        address recipient;
        address token;
        uint256 amount;
        uint64 srcChainId;
        uint64 dstChainId;
    }

    /// @notice Callback message
    struct CallbackMessage {
        uint8 version;
        uint8 msgType;
        bytes32 originalTxId;
        bool success;
        uint256 resultAmount;
        bytes resultData;
    }

    /// @notice Swap route hop
    struct RouteHop {
        address tokenIn;
        address tokenOut;
        address dex;
        uint24 fee;           // For Uniswap V3 style pools
        bytes extraData;      // DEX-specific data
    }

    /// @notice Multi-hop route
    struct SwapRoute {
        RouteHop[] hops;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        uint256 deadline;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SWAP MESSAGE ENCODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encode swap message
     */
    function encodeSwapMessage(SwapMessage memory msg_) internal pure returns (bytes memory) {
        return abi.encode(
            PAYLOAD_VERSION,
            MSG_TYPE_SWAP,
            msg_.txId,
            msg_.sender,
            msg_.recipient,
            msg_.tokenIn,
            msg_.tokenOut,
            msg_.amountIn,
            msg_.minAmountOut,
            msg_.deadline,
            msg_.extraData
        );
    }

    /**
     * @notice Decode swap message
     */
    function decodeSwapMessage(bytes memory payload) internal pure returns (SwapMessage memory msg_) {
        if (payload.length == 0) revert EmptyPayload();

        (
            msg_.version,
            msg_.msgType,
            msg_.txId,
            msg_.sender,
            msg_.recipient,
            msg_.tokenIn,
            msg_.tokenOut,
            msg_.amountIn,
            msg_.minAmountOut,
            msg_.deadline,
            msg_.extraData
        ) = abi.decode(
            payload,
            (uint8, uint8, bytes32, address, address, address, address, uint256, uint256, uint256, bytes)
        );

        if (msg_.version != PAYLOAD_VERSION) revert InvalidVersion(msg_.version);
        if (msg_.msgType != MSG_TYPE_SWAP) revert InvalidMessageType(msg_.msgType);
    }

    /**
     * @notice Encode swap message compact (minimal size)
     */
    function encodeSwapCompact(
        bytes32 txId,
        address recipient,
        address tokenOut,
        uint256 minAmountOut
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MSG_TYPE_SWAP,
            txId,
            recipient,
            tokenOut,
            minAmountOut
        );
    }

    /**
     * @notice Decode compact swap message
     */
    function decodeSwapCompact(bytes memory payload) internal pure returns (
        bytes32 txId,
        address recipient,
        address tokenOut,
        uint256 minAmountOut
    ) {
        if (payload.length < 93) revert InvalidPayloadLength(93, payload.length);

        uint8 msgType;
        assembly {
            msgType := mload(add(payload, 1))
            txId := mload(add(payload, 33))
            recipient := mload(add(payload, 53))
            tokenOut := mload(add(payload, 73))
            minAmountOut := mload(add(payload, 105))
        }

        if (msgType != MSG_TYPE_SWAP) revert InvalidMessageType(msgType);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BRIDGE MESSAGE ENCODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encode bridge message
     */
    function encodeBridgeMessage(BridgeMessage memory msg_) internal pure returns (bytes memory) {
        return abi.encode(
            PAYLOAD_VERSION,
            MSG_TYPE_BRIDGE,
            msg_.txId,
            msg_.sender,
            msg_.recipient,
            msg_.token,
            msg_.amount,
            msg_.srcChainId,
            msg_.dstChainId
        );
    }

    /**
     * @notice Decode bridge message
     */
    function decodeBridgeMessage(bytes memory payload) internal pure returns (BridgeMessage memory msg_) {
        if (payload.length == 0) revert EmptyPayload();

        (
            msg_.version,
            msg_.msgType,
            msg_.txId,
            msg_.sender,
            msg_.recipient,
            msg_.token,
            msg_.amount,
            msg_.srcChainId,
            msg_.dstChainId
        ) = abi.decode(
            payload,
            (uint8, uint8, bytes32, address, address, address, uint256, uint64, uint64)
        );

        if (msg_.msgType != MSG_TYPE_BRIDGE) revert InvalidMessageType(msg_.msgType);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLBACK MESSAGE ENCODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encode callback message
     */
    function encodeCallbackMessage(CallbackMessage memory msg_) internal pure returns (bytes memory) {
        return abi.encode(
            PAYLOAD_VERSION,
            MSG_TYPE_CALLBACK,
            msg_.originalTxId,
            msg_.success,
            msg_.resultAmount,
            msg_.resultData
        );
    }

    /**
     * @notice Decode callback message
     */
    function decodeCallbackMessage(bytes memory payload) internal pure returns (CallbackMessage memory msg_) {
        if (payload.length == 0) revert EmptyPayload();

        (
            msg_.version,
            msg_.msgType,
            msg_.originalTxId,
            msg_.success,
            msg_.resultAmount,
            msg_.resultData
        ) = abi.decode(
            payload,
            (uint8, uint8, bytes32, bool, uint256, bytes)
        );

        if (msg_.msgType != MSG_TYPE_CALLBACK) revert InvalidMessageType(msg_.msgType);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROUTE ENCODING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encode single route hop
     */
    function encodeHop(RouteHop memory hop) internal pure returns (bytes memory) {
        return abi.encode(
            hop.tokenIn,
            hop.tokenOut,
            hop.dex,
            hop.fee,
            hop.extraData
        );
    }

    /**
     * @notice Decode single route hop
     */
    function decodeHop(bytes memory data) internal pure returns (RouteHop memory hop) {
        (
            hop.tokenIn,
            hop.tokenOut,
            hop.dex,
            hop.fee,
            hop.extraData
        ) = abi.decode(data, (address, address, address, uint24, bytes));
    }

    /**
     * @notice Encode full swap route
     */
    function encodeRoute(SwapRoute memory route) internal pure returns (bytes memory) {
        bytes[] memory encodedHops = new bytes[](route.hops.length);
        for (uint256 i; i < route.hops.length;) {
            encodedHops[i] = encodeHop(route.hops[i]);
            unchecked { ++i; }
        }

        return abi.encode(
            encodedHops,
            route.amountIn,
            route.minAmountOut,
            route.recipient,
            route.deadline
        );
    }

    /**
     * @notice Encode path for Uniswap V3 style (packed addresses and fees)
     * @param tokens Token addresses in order
     * @param fees Pool fees between each pair
     * @return Packed path bytes
     */
    function encodeV3Path(
        address[] memory tokens,
        uint24[] memory fees
    ) internal pure returns (bytes memory) {
        if (tokens.length < 2 || fees.length != tokens.length - 1) {
            revert DecodingFailed();
        }

        bytes memory path = abi.encodePacked(tokens[0]);
        for (uint256 i; i < fees.length;) {
            path = abi.encodePacked(path, fees[i], tokens[i + 1]);
            unchecked { ++i; }
        }
        return path;
    }

    /**
     * @notice Encode path for Uniswap V2 style (just addresses)
     */
    function encodeV2Path(address[] memory tokens) internal pure returns (bytes memory) {
        return abi.encode(tokens);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MESSAGE TYPE DETECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extract message type from payload
     */
    function getMessageType(bytes memory payload) internal pure returns (uint8) {
        if (payload.length == 0) revert EmptyPayload();

        // Check if first byte is version (standard encoding)
        uint8 firstByte = uint8(payload[0]);
        if (firstByte == PAYLOAD_VERSION && payload.length > 1) {
            return uint8(payload[1]);
        }
        // Otherwise first byte is message type (compact encoding)
        return firstByte;
    }

    /**
     * @notice Check if payload is swap message
     */
    function isSwapMessage(bytes memory payload) internal pure returns (bool) {
        return getMessageType(payload) == MSG_TYPE_SWAP;
    }

    /**
     * @notice Check if payload is bridge message
     */
    function isBridgeMessage(bytes memory payload) internal pure returns (bool) {
        return getMessageType(payload) == MSG_TYPE_BRIDGE;
    }

    /**
     * @notice Check if payload is callback message
     */
    function isCallbackMessage(bytes memory payload) internal pure returns (bool) {
        return getMessageType(payload) == MSG_TYPE_CALLBACK;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generate unique transaction ID
     */
    function generateTxId(
        address sender,
        uint256 nonce,
        uint256 chainId
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            sender,
            nonce,
            chainId,
            block.timestamp,
            blockhash(block.number - 1)
        ));
    }

    /**
     * @notice Convert address to bytes32 (for cross-chain compatibility)
     */
    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @notice Convert bytes32 to address
     */
    function bytes32ToAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    /**
     * @notice Pack two addresses into bytes32 (truncates to 10 bytes each)
     */
    function packAddressPair(address a, address b) internal pure returns (bytes32) {
        return bytes32(
            (uint256(uint160(a)) << 96) | uint256(uint80(uint160(b)))
        );
    }

    /**
     * @notice Create message hash for signing
     */
    function hashMessage(
        bytes32 txId,
        address sender,
        address recipient,
        uint256 amount,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(txId, sender, recipient, amount, deadline));
    }

    /**
     * @notice Validate payload has minimum length
     */
    function validateMinLength(bytes memory payload, uint256 minLength) internal pure {
        if (payload.length < minLength) {
            revert InvalidPayloadLength(minLength, payload.length);
        }
    }
}
