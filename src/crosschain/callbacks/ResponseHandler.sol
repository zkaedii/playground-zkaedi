// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*//////////////////////////////////////////////////////////////
                    RESPONSE HANDLER
//////////////////////////////////////////////////////////////*/

/**
 * @title ResponseHandler
 * @notice Handles callbacks and responses from cross-chain operations
 * @dev Features:
 *      - Async callback management
 *      - Response routing
 *      - State synchronization
 *      - Event emission for off-chain tracking
 *      - Timeout handling
 */
contract ResponseHandler is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    enum ResponseType {
        SUCCESS,
        FAILURE,
        PARTIAL,
        TIMEOUT,
        RETRY_REQUESTED
    }

    struct PendingCallback {
        bytes32 requestId;
        address requester;
        address callbackContract;
        bytes4 callbackSelector;
        uint256 timestamp;
        uint256 timeout;
        bool executed;
        bytes expectedData;
    }

    struct Response {
        bytes32 requestId;
        ResponseType responseType;
        bytes data;
        uint256 sourceChainId;
        uint256 receivedAt;
        uint256 processedAt;
    }

    struct CallbackResult {
        bool success;
        bytes returnData;
        uint256 gasUsed;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error CallbackNotFound();
    error CallbackAlreadyExecuted();
    error CallbackExpired();
    error UnauthorizedResponder();
    error CallbackFailed();
    error InvalidResponse();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event CallbackRegistered(
        bytes32 indexed requestId,
        address indexed requester,
        address callbackContract,
        uint256 timeout
    );
    event ResponseReceived(
        bytes32 indexed requestId,
        ResponseType responseType,
        uint256 sourceChainId
    );
    event CallbackExecuted(
        bytes32 indexed requestId,
        bool success,
        bytes returnData
    );
    event CallbackTimeout(bytes32 indexed requestId);
    event CallbackRetryRequested(bytes32 indexed requestId);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Request ID => Pending callback
    mapping(bytes32 => PendingCallback) public pendingCallbacks;

    /// @dev Request ID => Response
    mapping(bytes32 => Response) public responses;

    /// @dev Request ID => Callback results
    mapping(bytes32 => CallbackResult) public callbackResults;

    /// @dev Authorized responders
    mapping(address => bool) public authorizedResponders;

    /// @dev Request ID => retry count
    mapping(bytes32 => uint256) public retryCount;

    /// @dev Max retries
    uint256 public maxRetries;

    /// @dev Default timeout
    uint256 public defaultTimeout;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        maxRetries = 3;
        defaultTimeout = 1 hours;
    }

    /*//////////////////////////////////////////////////////////////
                    CALLBACK REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a callback for a pending request
    function registerCallback(
        bytes32 requestId,
        address callbackContract,
        bytes4 callbackSelector,
        uint256 timeout,
        bytes calldata expectedData
    ) external returns (bool) {
        require(pendingCallbacks[requestId].timestamp == 0, "Already registered");

        pendingCallbacks[requestId] = PendingCallback({
            requestId: requestId,
            requester: msg.sender,
            callbackContract: callbackContract,
            callbackSelector: callbackSelector,
            timestamp: block.timestamp,
            timeout: timeout == 0 ? defaultTimeout : timeout,
            executed: false,
            expectedData: expectedData
        });

        emit CallbackRegistered(requestId, msg.sender, callbackContract, timeout);

        return true;
    }

    /// @notice Register multiple callbacks
    function registerCallbackBatch(
        bytes32[] calldata requestIds,
        address[] calldata callbackContracts,
        bytes4[] calldata selectors,
        uint256[] calldata timeouts
    ) external {
        require(
            requestIds.length == callbackContracts.length &&
            callbackContracts.length == selectors.length &&
            selectors.length == timeouts.length,
            "Length mismatch"
        );

        for (uint256 i; i < requestIds.length; ++i) {
            this.registerCallback(
                requestIds[i],
                callbackContracts[i],
                selectors[i],
                timeouts[i],
                ""
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    RESPONSE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle incoming response
    function handleResponse(
        bytes32 requestId,
        ResponseType responseType,
        bytes calldata data,
        uint256 sourceChainId
    ) external nonReentrant returns (CallbackResult memory result) {
        require(authorizedResponders[msg.sender], "Unauthorized");

        PendingCallback storage callback = pendingCallbacks[requestId];
        if (callback.timestamp == 0) revert CallbackNotFound();
        if (callback.executed) revert CallbackAlreadyExecuted();

        // Check timeout
        if (block.timestamp > callback.timestamp + callback.timeout) {
            callback.executed = true;
            emit CallbackTimeout(requestId);
            revert CallbackExpired();
        }

        // Store response
        responses[requestId] = Response({
            requestId: requestId,
            responseType: responseType,
            data: data,
            sourceChainId: sourceChainId,
            receivedAt: block.timestamp,
            processedAt: 0
        });

        emit ResponseReceived(requestId, responseType, sourceChainId);

        // Execute callback based on response type
        if (responseType == ResponseType.SUCCESS || responseType == ResponseType.PARTIAL) {
            result = _executeCallback(requestId, data);
        } else if (responseType == ResponseType.FAILURE) {
            result = _handleFailure(requestId, data);
        } else if (responseType == ResponseType.RETRY_REQUESTED) {
            _handleRetryRequest(requestId);
        }

        responses[requestId].processedAt = block.timestamp;
        callbackResults[requestId] = result;

        return result;
    }

    /// @notice Handle success response
    function handleSuccessResponse(
        bytes32 requestId,
        bytes calldata data,
        uint256 sourceChainId
    ) external returns (CallbackResult memory) {
        return this.handleResponse(requestId, ResponseType.SUCCESS, data, sourceChainId);
    }

    /// @notice Handle failure response
    function handleFailureResponse(
        bytes32 requestId,
        bytes calldata errorData,
        uint256 sourceChainId
    ) external returns (CallbackResult memory) {
        return this.handleResponse(requestId, ResponseType.FAILURE, errorData, sourceChainId);
    }

    /*//////////////////////////////////////////////////////////////
                    CALLBACK EXECUTION
    //////////////////////////////////////////////////////////////*/

    function _executeCallback(
        bytes32 requestId,
        bytes calldata data
    ) internal returns (CallbackResult memory result) {
        PendingCallback storage callback = pendingCallbacks[requestId];

        uint256 gasStart = gasleft();

        // Execute callback on target contract
        (bool success, bytes memory returnData) = callback.callbackContract.call(
            abi.encodeWithSelector(
                callback.callbackSelector,
                requestId,
                data
            )
        );

        callback.executed = true;

        result = CallbackResult({
            success: success,
            returnData: returnData,
            gasUsed: gasStart - gasleft()
        });

        emit CallbackExecuted(requestId, success, returnData);

        return result;
    }

    function _handleFailure(
        bytes32 requestId,
        bytes calldata errorData
    ) internal returns (CallbackResult memory result) {
        PendingCallback storage callback = pendingCallbacks[requestId];

        // Check if retry is possible
        if (retryCount[requestId] < maxRetries) {
            retryCount[requestId]++;
            emit CallbackRetryRequested(requestId);

            return CallbackResult({
                success: false,
                returnData: errorData,
                gasUsed: 0
            });
        }

        // Final failure - execute failure callback if available
        bytes4 failureSelector = bytes4(keccak256("onFailure(bytes32,bytes)"));

        (bool success, bytes memory returnData) = callback.callbackContract.call(
            abi.encodeWithSelector(failureSelector, requestId, errorData)
        );

        callback.executed = true;

        return CallbackResult({
            success: success,
            returnData: returnData,
            gasUsed: 0
        });
    }

    function _handleRetryRequest(bytes32 requestId) internal {
        if (retryCount[requestId] >= maxRetries) {
            revert CallbackFailed();
        }

        retryCount[requestId]++;
        emit CallbackRetryRequested(requestId);
    }

    /*//////////////////////////////////////////////////////////////
                    TIMEOUT HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Process expired callbacks
    function processTimeouts(bytes32[] calldata requestIds) external {
        for (uint256 i; i < requestIds.length; ++i) {
            PendingCallback storage callback = pendingCallbacks[requestIds[i]];

            if (callback.timestamp == 0) continue;
            if (callback.executed) continue;
            if (block.timestamp <= callback.timestamp + callback.timeout) continue;

            // Mark as executed (timed out)
            callback.executed = true;

            // Try to call timeout handler
            bytes4 timeoutSelector = bytes4(keccak256("onTimeout(bytes32)"));
            callback.callbackContract.call(
                abi.encodeWithSelector(timeoutSelector, requestIds[i])
            );

            emit CallbackTimeout(requestIds[i]);
        }
    }

    /// @notice Check if callback is expired
    function isExpired(bytes32 requestId) external view returns (bool) {
        PendingCallback storage callback = pendingCallbacks[requestId];
        return block.timestamp > callback.timestamp + callback.timeout;
    }

    /*//////////////////////////////////////////////////////////////
                    SYNCHRONOUS RESPONSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Wait for response (for view functions)
    function getResponse(bytes32 requestId)
        external view returns (Response memory)
    {
        return responses[requestId];
    }

    /// @notice Check if response received
    function hasResponse(bytes32 requestId) external view returns (bool) {
        return responses[requestId].receivedAt != 0;
    }

    /// @notice Get callback status
    function getCallbackStatus(bytes32 requestId)
        external view returns (
            bool registered,
            bool executed,
            bool expired,
            uint256 retriesRemaining
        )
    {
        PendingCallback storage callback = pendingCallbacks[requestId];

        registered = callback.timestamp != 0;
        executed = callback.executed;
        expired = block.timestamp > callback.timestamp + callback.timeout;
        retriesRemaining = maxRetries - retryCount[requestId];
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setAuthorizedResponder(address responder, bool authorized) external onlyOwner {
        authorizedResponders[responder] = authorized;
    }

    function setMaxRetries(uint256 _maxRetries) external onlyOwner {
        maxRetries = _maxRetries;
    }

    function setDefaultTimeout(uint256 _timeout) external onlyOwner {
        defaultTimeout = _timeout;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    uint256[40] private __gap;
}
