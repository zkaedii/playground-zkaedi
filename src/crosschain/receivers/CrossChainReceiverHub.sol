// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICrossChain.sol";

/*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN RECEIVER HUB
//////////////////////////////////////////////////////////////*/

/**
 * @title CrossChainReceiverHub
 * @notice Unified receiver for all cross-chain messaging protocols
 * @dev Handles incoming messages from CCIP, LayerZero, Wormhole, Axelar, Hyperlane
 */
contract CrossChainReceiverHub is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            ENUMS & STRUCTS
    //////////////////////////////////////////////////////////////*/

    enum Protocol {
        CCIP,
        LAYERZERO,
        WORMHOLE,
        AXELAR,
        HYPERLANE
    }

    enum MessageStatus {
        PENDING,
        PROCESSING,
        COMPLETED,
        FAILED,
        REFUNDED,
        EXPIRED
    }

    struct InboundMessage {
        bytes32 messageId;
        Protocol protocol;
        uint256 sourceChainId;
        bytes32 sourceSender;
        bytes payload;
        uint256 timestamp;
        uint256 gasUsed;
        MessageStatus status;
        bytes result;
    }

    struct ProtocolConfig {
        address endpoint;
        bool isActive;
        uint256 minGasLimit;
        uint256 maxPayloadSize;
        mapping(uint256 => bytes32) trustedRemotes; // chainId => address
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error UnauthorizedProtocol();
    error UnauthorizedSender();
    error InvalidPayload();
    error MessageAlreadyProcessed();
    error MessageExpired();
    error ExecutionFailed();
    error ProtocolNotActive();
    error PayloadTooLarge();
    error InsufficientGas();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MessageReceived(
        bytes32 indexed messageId,
        Protocol indexed protocol,
        uint256 sourceChainId,
        bytes32 sourceSender,
        uint256 payloadSize
    );
    event MessageProcessed(
        bytes32 indexed messageId,
        MessageStatus status,
        bytes result
    );
    event MessageFailed(
        bytes32 indexed messageId,
        string reason
    );
    event ProtocolConfigured(
        Protocol indexed protocol,
        address endpoint,
        bool isActive
    );
    event TrustedRemoteSet(
        Protocol indexed protocol,
        uint256 chainId,
        bytes32 remote
    );

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Protocol configurations
    mapping(Protocol => ProtocolConfig) internal _protocolConfigs;

    /// @dev Message storage
    mapping(bytes32 => InboundMessage) public messages;

    /// @dev Message ID => processed flag
    mapping(bytes32 => bool) public processedMessages;

    /// @dev Nonce tracking per source chain
    mapping(Protocol => mapping(uint256 => uint64)) public inboundNonces;

    /// @dev Message handler contracts
    mapping(bytes4 => address) public messageHandlers;

    /// @dev Default message handler
    address public defaultHandler;

    /// @dev Message expiry time
    uint256 public messageExpiry;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _defaultHandler) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        defaultHandler = _defaultHandler;
        messageExpiry = 7 days;
    }

    /*//////////////////////////////////////////////////////////////
                        CCIP RECEIVER
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive message from Chainlink CCIP
    function ccipReceive(
        ICCIPRouter.Any2EVMMessage calldata message
    ) external nonReentrant whenNotPaused {
        _validateProtocol(Protocol.CCIP, msg.sender);

        bytes32 messageId = message.messageId;
        if (processedMessages[messageId]) revert MessageAlreadyProcessed();

        // Decode source chain and sender
        uint256 sourceChainId = _ccipSelectorToChainId(message.sourceChainSelector);
        bytes32 sourceSender = bytes32(message.sender);

        _validateTrustedRemote(Protocol.CCIP, sourceChainId, sourceSender);

        // Store message
        messages[messageId] = InboundMessage({
            messageId: messageId,
            protocol: Protocol.CCIP,
            sourceChainId: sourceChainId,
            sourceSender: sourceSender,
            payload: message.data,
            timestamp: block.timestamp,
            gasUsed: 0,
            status: MessageStatus.PENDING,
            result: ""
        });

        emit MessageReceived(
            messageId,
            Protocol.CCIP,
            sourceChainId,
            sourceSender,
            message.data.length
        );

        // Process message
        _processMessage(messageId, message.data, message.destTokenAmounts);
    }

    /*//////////////////////////////////////////////////////////////
                    LAYERZERO V2 RECEIVER
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive message from LayerZero V2
    function lzReceive(
        ILayerZeroEndpoint.Origin calldata origin,
        bytes32 guid,
        bytes calldata payload,
        address executor,
        bytes calldata extraData
    ) external payable nonReentrant whenNotPaused {
        _validateProtocol(Protocol.LAYERZERO, msg.sender);

        if (processedMessages[guid]) revert MessageAlreadyProcessed();

        uint256 sourceChainId = _lzEidToChainId(origin.srcEid);
        _validateTrustedRemote(Protocol.LAYERZERO, sourceChainId, origin.sender);

        // Update nonce
        inboundNonces[Protocol.LAYERZERO][sourceChainId] = origin.nonce;

        // Store message
        messages[guid] = InboundMessage({
            messageId: guid,
            protocol: Protocol.LAYERZERO,
            sourceChainId: sourceChainId,
            sourceSender: origin.sender,
            payload: payload,
            timestamp: block.timestamp,
            gasUsed: 0,
            status: MessageStatus.PENDING,
            result: ""
        });

        emit MessageReceived(
            guid,
            Protocol.LAYERZERO,
            sourceChainId,
            origin.sender,
            payload.length
        );

        // Process message
        ICCIPRouter.EVMTokenAmount[] memory emptyTokens;
        _processMessage(guid, payload, emptyTokens);
    }

    /// @notice Check if LayerZero path is allowed
    function allowInitializePath(
        ILayerZeroEndpoint.Origin calldata origin
    ) external view returns (bool) {
        uint256 chainId = _lzEidToChainId(origin.srcEid);
        return _protocolConfigs[Protocol.LAYERZERO].trustedRemotes[chainId] == origin.sender;
    }

    /// @notice Get next expected nonce for LayerZero
    function nextNonce(uint32 srcEid, bytes32) external view returns (uint64) {
        uint256 chainId = _lzEidToChainId(srcEid);
        return inboundNonces[Protocol.LAYERZERO][chainId] + 1;
    }

    /*//////////////////////////////////////////////////////////////
                    WORMHOLE RECEIVER
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive and verify Wormhole VAA
    function receiveWormholeMessage(
        bytes calldata encodedVAA
    ) external nonReentrant whenNotPaused {
        _validateProtocol(Protocol.WORMHOLE, msg.sender);

        IWormhole wormhole = IWormhole(_protocolConfigs[Protocol.WORMHOLE].endpoint);

        // Parse and verify VAA
        (IWormhole.VM memory vm, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedVAA);

        if (!valid) revert ExecutionFailed();

        bytes32 messageId = vm.hash;
        if (processedMessages[messageId]) revert MessageAlreadyProcessed();

        uint256 sourceChainId = _wormholeChainIdToEvmChainId(vm.emitterChainId);
        _validateTrustedRemote(Protocol.WORMHOLE, sourceChainId, vm.emitterAddress);

        // Store message
        messages[messageId] = InboundMessage({
            messageId: messageId,
            protocol: Protocol.WORMHOLE,
            sourceChainId: sourceChainId,
            sourceSender: vm.emitterAddress,
            payload: vm.payload,
            timestamp: block.timestamp,
            gasUsed: 0,
            status: MessageStatus.PENDING,
            result: ""
        });

        emit MessageReceived(
            messageId,
            Protocol.WORMHOLE,
            sourceChainId,
            vm.emitterAddress,
            vm.payload.length
        );

        // Process message
        ICCIPRouter.EVMTokenAmount[] memory emptyTokens;
        _processMessage(messageId, vm.payload, emptyTokens);
    }

    /*//////////////////////////////////////////////////////////////
                    AXELAR RECEIVER
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive message from Axelar Gateway
    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        _validateProtocol(Protocol.AXELAR, msg.sender);

        if (processedMessages[commandId]) revert MessageAlreadyProcessed();

        uint256 sourceChainId = _axelarChainToId(sourceChain);
        bytes32 sourceSender = keccak256(bytes(sourceAddress));

        // Store message
        messages[commandId] = InboundMessage({
            messageId: commandId,
            protocol: Protocol.AXELAR,
            sourceChainId: sourceChainId,
            sourceSender: sourceSender,
            payload: payload,
            timestamp: block.timestamp,
            gasUsed: 0,
            status: MessageStatus.PENDING,
            result: ""
        });

        emit MessageReceived(
            commandId,
            Protocol.AXELAR,
            sourceChainId,
            sourceSender,
            payload.length
        );

        // Create token amounts for processing
        ICCIPRouter.EVMTokenAmount[] memory tokenAmounts = new ICCIPRouter.EVMTokenAmount[](1);
        address token = _getAxelarToken(tokenSymbol);
        tokenAmounts[0] = ICCIPRouter.EVMTokenAmount({
            token: token,
            amount: amount
        });

        _processMessage(commandId, payload, tokenAmounts);
    }

    /// @notice Receive message without token from Axelar
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external nonReentrant whenNotPaused {
        _validateProtocol(Protocol.AXELAR, msg.sender);

        if (processedMessages[commandId]) revert MessageAlreadyProcessed();

        uint256 sourceChainId = _axelarChainToId(sourceChain);
        bytes32 sourceSender = keccak256(bytes(sourceAddress));

        messages[commandId] = InboundMessage({
            messageId: commandId,
            protocol: Protocol.AXELAR,
            sourceChainId: sourceChainId,
            sourceSender: sourceSender,
            payload: payload,
            timestamp: block.timestamp,
            gasUsed: 0,
            status: MessageStatus.PENDING,
            result: ""
        });

        emit MessageReceived(
            commandId,
            Protocol.AXELAR,
            sourceChainId,
            sourceSender,
            payload.length
        );

        ICCIPRouter.EVMTokenAmount[] memory emptyTokens;
        _processMessage(commandId, payload, emptyTokens);
    }

    /*//////////////////////////////////////////////////////////////
                    HYPERLANE RECEIVER
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive message from Hyperlane Mailbox
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata payload
    ) external nonReentrant whenNotPaused {
        _validateProtocol(Protocol.HYPERLANE, msg.sender);

        bytes32 messageId = keccak256(abi.encodePacked(
            origin,
            sender,
            payload,
            block.timestamp
        ));

        if (processedMessages[messageId]) revert MessageAlreadyProcessed();

        uint256 sourceChainId = uint256(origin);
        _validateTrustedRemote(Protocol.HYPERLANE, sourceChainId, sender);

        messages[messageId] = InboundMessage({
            messageId: messageId,
            protocol: Protocol.HYPERLANE,
            sourceChainId: sourceChainId,
            sourceSender: sender,
            payload: payload,
            timestamp: block.timestamp,
            gasUsed: 0,
            status: MessageStatus.PENDING,
            result: ""
        });

        emit MessageReceived(
            messageId,
            Protocol.HYPERLANE,
            sourceChainId,
            sender,
            payload.length
        );

        ICCIPRouter.EVMTokenAmount[] memory emptyTokens;
        _processMessage(messageId, payload, emptyTokens);
    }

    /*//////////////////////////////////////////////////////////////
                    MESSAGE PROCESSING
    //////////////////////////////////////////////////////////////*/

    /// @dev Process incoming message
    function _processMessage(
        bytes32 messageId,
        bytes memory payload,
        ICCIPRouter.EVMTokenAmount[] memory tokenAmounts
    ) internal {
        InboundMessage storage msg_ = messages[messageId];
        msg_.status = MessageStatus.PROCESSING;

        uint256 gasStart = gasleft();

        try this.executeMessage(messageId, payload, tokenAmounts) returns (bytes memory result) {
            msg_.status = MessageStatus.COMPLETED;
            msg_.result = result;
            msg_.gasUsed = gasStart - gasleft();
            processedMessages[messageId] = true;

            emit MessageProcessed(messageId, MessageStatus.COMPLETED, result);
        } catch Error(string memory reason) {
            msg_.status = MessageStatus.FAILED;
            msg_.result = bytes(reason);
            msg_.gasUsed = gasStart - gasleft();

            emit MessageFailed(messageId, reason);
        } catch {
            msg_.status = MessageStatus.FAILED;
            msg_.result = "Unknown error";
            msg_.gasUsed = gasStart - gasleft();

            emit MessageFailed(messageId, "Unknown error");
        }
    }

    /// @notice Execute message (external for try/catch)
    function executeMessage(
        bytes32 messageId,
        bytes calldata payload,
        ICCIPRouter.EVMTokenAmount[] calldata tokenAmounts
    ) external returns (bytes memory) {
        require(msg.sender == address(this), "Only self");

        // Decode action selector
        bytes4 selector = bytes4(payload[:4]);
        bytes memory data = payload[4:];

        // Find handler
        address handler = messageHandlers[selector];
        if (handler == address(0)) {
            handler = defaultHandler;
        }

        if (handler == address(0)) revert InvalidPayload();

        // Call handler
        (bool success, bytes memory result) = handler.call(
            abi.encodeWithSignature(
                "handleMessage(bytes32,bytes,tuple[])",
                messageId,
                data,
                tokenAmounts
            )
        );

        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert ExecutionFailed();
        }

        return result;
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _validateProtocol(Protocol protocol, address sender) internal view {
        ProtocolConfig storage config = _protocolConfigs[protocol];
        if (!config.isActive) revert ProtocolNotActive();
        if (config.endpoint != sender) revert UnauthorizedProtocol();
    }

    function _validateTrustedRemote(
        Protocol protocol,
        uint256 chainId,
        bytes32 sender
    ) internal view {
        bytes32 trusted = _protocolConfigs[protocol].trustedRemotes[chainId];
        if (trusted != sender && trusted != bytes32(0)) {
            revert UnauthorizedSender();
        }
    }

    /*//////////////////////////////////////////////////////////////
                    CHAIN ID CONVERSIONS
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 => uint256) public ccipSelectorToChainId;
    mapping(uint32 => uint256) public lzEidToChainId;
    mapping(uint16 => uint256) public wormholeChainToEvmChainId;
    mapping(bytes32 => uint256) public axelarChainToId;
    mapping(string => address) public axelarTokens;

    function _ccipSelectorToChainId(uint64 selector) internal view returns (uint256) {
        return ccipSelectorToChainId[selector];
    }

    function _lzEidToChainId(uint32 eid) internal view returns (uint256) {
        return lzEidToChainId[eid];
    }

    function _wormholeChainIdToEvmChainId(uint16 whChainId) internal view returns (uint256) {
        return wormholeChainToEvmChainId[whChainId];
    }

    function _axelarChainToId(string calldata chain) internal view returns (uint256) {
        return axelarChainToId[keccak256(bytes(chain))];
    }

    function _getAxelarToken(string calldata symbol) internal view returns (address) {
        return axelarTokens[symbol];
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function configureProtocol(
        Protocol protocol,
        address endpoint,
        bool isActive,
        uint256 minGasLimit,
        uint256 maxPayloadSize
    ) external onlyOwner {
        ProtocolConfig storage config = _protocolConfigs[protocol];
        config.endpoint = endpoint;
        config.isActive = isActive;
        config.minGasLimit = minGasLimit;
        config.maxPayloadSize = maxPayloadSize;

        emit ProtocolConfigured(protocol, endpoint, isActive);
    }

    function setTrustedRemote(
        Protocol protocol,
        uint256 chainId,
        bytes32 remote
    ) external onlyOwner {
        _protocolConfigs[protocol].trustedRemotes[chainId] = remote;
        emit TrustedRemoteSet(protocol, chainId, remote);
    }

    function setMessageHandler(bytes4 selector, address handler) external onlyOwner {
        messageHandlers[selector] = handler;
    }

    function setDefaultHandler(address handler) external onlyOwner {
        defaultHandler = handler;
    }

    function setChainIdMappings(
        uint64[] calldata ccipSelectors,
        uint32[] calldata lzEids,
        uint16[] calldata whChainIds,
        string[] calldata axelarChains,
        uint256[] calldata evmChainIds
    ) external onlyOwner {
        for (uint i; i < ccipSelectors.length; ++i) {
            ccipSelectorToChainId[ccipSelectors[i]] = evmChainIds[i];
        }
        for (uint i; i < lzEids.length; ++i) {
            lzEidToChainId[lzEids[i]] = evmChainIds[i];
        }
        for (uint i; i < whChainIds.length; ++i) {
            wormholeChainToEvmChainId[whChainIds[i]] = evmChainIds[i];
        }
        for (uint i; i < axelarChains.length; ++i) {
            axelarChainToId[keccak256(bytes(axelarChains[i]))] = evmChainIds[i];
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}

    uint256[40] private __gap;
}
