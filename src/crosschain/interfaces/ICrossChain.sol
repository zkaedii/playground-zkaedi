// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
            COMPREHENSIVE CROSS-CHAIN INTERFACES
//////////////////////////////////////////////////////////////*/

// ============ CCIP Interfaces ============

interface ICCIPRouter {
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
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

    function ccipSend(uint64 destinationChainSelector, EVM2AnyMessage calldata message)
        external payable returns (bytes32 messageId);
    function getFee(uint64 destinationChainSelector, EVM2AnyMessage calldata message)
        external view returns (uint256 fee);
    function isChainSupported(uint64 chainSelector) external view returns (bool);
    function getSupportedTokens(uint64 chainSelector) external view returns (address[] memory);
}

// ============ LayerZero V2 Interfaces ============

interface ILayerZeroEndpoint {
    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
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

    function send(MessagingParams calldata _params, address _refundAddress)
        external payable returns (MessagingReceipt memory);
    function quote(MessagingParams calldata _params, address _sender)
        external view returns (MessagingFee memory);
    function setDelegate(address _delegate) external;
    function nextNonce(address _sender, uint32 _dstEid, bytes32 _receiver)
        external view returns (uint64);
}

// ============ Wormhole Interfaces ============

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

    function publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel)
        external payable returns (uint64 sequence);
    function parseAndVerifyVM(bytes calldata encodedVM)
        external view returns (VM memory vm, bool valid, string memory reason);
    function messageFee() external view returns (uint256);
    function getCurrentGuardianSetIndex() external view returns (uint32);
    function chainId() external view returns (uint16);
}

// ============ Axelar Interfaces ============

interface IAxelarGateway {
    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external;

    function callContractWithToken(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    ) external;

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);

    function tokenAddresses(string memory symbol) external view returns (address);
}

interface IAxelarGasService {
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;

    function payNativeGasForContractCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address refundAddress
    ) external payable;
}

// ============ Hyperlane Interfaces ============

interface IMailbox {
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external payable returns (bytes32 messageId);

    function process(bytes calldata metadata, bytes calldata message) external;

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external view returns (uint256 fee);

    function localDomain() external view returns (uint32);
    function delivered(bytes32 messageId) external view returns (bool);
}

interface IInterchainSecurityModule {
    function verify(bytes calldata metadata, bytes calldata message)
        external returns (bool);
    function moduleType() external view returns (uint8);
}

// ============ Unified Message Handler ============

interface IMessageHandler {
    function handleMessage(
        bytes32 messageId,
        bytes calldata data,
        ICCIPRouter.EVMTokenAmount[] calldata tokenAmounts
    ) external returns (bytes memory);

    function onFailure(bytes32 messageId, bytes calldata errorData) external;
    function onTimeout(bytes32 messageId) external;
}

// ============ Callback Interfaces ============

interface ICallbackReceiver {
    function onCrossChainResponse(
        bytes32 requestId,
        bool success,
        bytes calldata data
    ) external;
}

interface IRefundReceiver {
    function onRefund(
        bytes32 txId,
        address token,
        uint256 amount,
        bytes calldata reason
    ) external;
}

// ============ Retry Handler ============

interface IRetryHandler {
    function retryMessage(
        bytes32 messageId,
        bytes calldata payload,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable returns (bool);
}

// ============ Fee Collector ============

interface IFeeCollector {
    function collectFee(
        bytes32 txId,
        address payer,
        uint256 amount,
        address token
    ) external payable returns (uint256 fee);

    function refundExcess(bytes32 txId, address recipient) external;
}

// ============ Emergency Actions ============

interface IEmergencyHandler {
    function pause() external;
    function unpause() external;
    function emergencyWithdraw(address token, uint256 amount) external;
    function rescueTokens(address token, address recipient, uint256 amount) external;
}

// ============ Chain Registry ============

interface IChainRegistry {
    struct ChainInfo {
        uint256 evmChainId;
        uint64 ccipSelector;
        uint32 lzEndpointId;
        uint16 wormholeChainId;
        string axelarChainId;
        uint32 hyperlaneDomain;
        bool isActive;
    }

    function getChainInfo(uint256 chainId) external view returns (ChainInfo memory);
    function getCCIPSelector(uint256 chainId) external view returns (uint64);
    function getLZEndpointId(uint256 chainId) external view returns (uint32);
    function getWormholeChainId(uint256 chainId) external view returns (uint16);
    function isChainSupported(uint256 chainId) external view returns (bool);
}
