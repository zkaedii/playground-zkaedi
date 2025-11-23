// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
                CROSS-CHAIN MESSAGING INTERFACES
//////////////////////////////////////////////////////////////*/

/// @title ICCIPRouter
/// @notice Interface for Chainlink CCIP Router
interface ICCIPRouter {
    struct EVM2AnyMessage {
        bytes receiver;                  // Receiver address on destination chain
        bytes data;                      // Arbitrary data payload
        EVMTokenAmount[] tokenAmounts;   // Tokens to transfer
        address feeToken;                // Token for paying fees (address(0) for native)
        bytes extraArgs;                 // Extra arguments (gas limit, etc.)
    }

    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;
        bytes data;
        EVMTokenAmount[] destTokenAmounts;
    }

    /// @notice Send a cross-chain message
    /// @param destinationChainSelector The destination chain selector
    /// @param message The message to send
    /// @return messageId The unique message ID
    function ccipSend(
        uint64 destinationChainSelector,
        EVM2AnyMessage calldata message
    ) external payable returns (bytes32 messageId);

    /// @notice Get the fee for sending a message
    function getFee(
        uint64 destinationChainSelector,
        EVM2AnyMessage calldata message
    ) external view returns (uint256 fee);

    /// @notice Check if a chain is supported
    function isChainSupported(uint64 chainSelector) external view returns (bool);

    /// @notice Get supported tokens for a destination chain
    function getSupportedTokens(uint64 chainSelector) external view returns (address[] memory);
}

/// @title ICCIPReceiver
/// @notice Interface that must be implemented by CCIP message receivers
interface ICCIPReceiver {
    /// @notice Called by CCIP router when a message is received
    function ccipReceive(ICCIPRouter.Any2EVMMessage calldata message) external;
}

/// @title ILayerZeroEndpoint
/// @notice Interface for LayerZero V2 Endpoint
interface ILayerZeroEndpoint {
    struct MessagingParams {
        uint32 dstEid;              // Destination endpoint ID
        bytes32 receiver;           // Receiver address (bytes32 format)
        bytes message;              // Message payload
        bytes options;              // Execution options
        bool payInLzToken;          // Pay fees in LZ token
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    /// @notice Send a cross-chain message via LayerZero
    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);

    /// @notice Quote the fee for sending a message
    function quote(
        MessagingParams calldata _params,
        address _sender
    ) external view returns (MessagingFee memory);

    /// @notice Set the delegate for message verification
    function setDelegate(address _delegate) external;

    /// @notice Get the next nonce for a destination
    function nextNonce(address _sender, uint32 _dstEid, bytes32 _receiver) external view returns (uint64);
}

/// @title ILayerZeroReceiver
/// @notice Interface for LayerZero message receivers (OApp pattern)
interface ILayerZeroReceiver {
    /// @notice Called when a LayerZero message is received
    function lzReceive(
        ILayerZeroEndpoint.Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;

    /// @notice Check if a pathway is allowed
    function allowInitializePath(ILayerZeroEndpoint.Origin calldata _origin) external view returns (bool);

    /// @notice Get the next expected nonce
    function nextNonce(uint32 _srcEid, bytes32 _sender) external view returns (uint64);
}

/// @title IWormhole
/// @notice Interface for Wormhole core bridge (used by Pyth for cross-chain)
interface IWormhole {
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
        uint8 guardianIndex;
    }

    struct VM {
        uint8 version;
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
        bytes payload;
        uint32 guardianSetIndex;
        Signature[] signatures;
        bytes32 hash;
    }

    /// @notice Publish a message
    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

    /// @notice Parse and verify a VAA (Verified Action Approval)
    function parseAndVerifyVM(bytes calldata encodedVM)
        external view returns (VM memory vm, bool valid, string memory reason);

    /// @notice Get the message fee
    function messageFee() external view returns (uint256);

    /// @notice Get the current guardian set index
    function getCurrentGuardianSetIndex() external view returns (uint32);

    /// @notice Get chain ID
    function chainId() external view returns (uint16);
}

/// @title ICrossChainBridge
/// @notice Unified interface for cross-chain token bridges
interface ICrossChainBridge {
    enum BridgeProtocol {
        CCIP,
        LAYERZERO,
        WORMHOLE,
        AXELAR,
        HYPERLANE
    }

    struct BridgeRequest {
        address token;              // Token to bridge
        uint256 amount;             // Amount to bridge
        uint256 destChainId;        // Destination chain ID
        address recipient;          // Recipient on destination
        bytes extraData;            // Protocol-specific data
    }

    struct BridgeQuote {
        uint256 fee;                // Bridge fee in native token
        uint256 estimatedTime;      // Estimated delivery time
        BridgeProtocol protocol;    // Protocol being used
    }

    /// @notice Bridge tokens to another chain
    function bridge(BridgeRequest calldata request) external payable returns (bytes32 txId);

    /// @notice Get a quote for bridging
    function quote(BridgeRequest calldata request) external view returns (BridgeQuote memory);

    /// @notice Check bridge transaction status
    function getStatus(bytes32 txId) external view returns (uint8 status);
}
