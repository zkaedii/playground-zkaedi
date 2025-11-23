// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*//////////////////////////////////////////////////////////////
                RETRY MANAGER & DEAD LETTER QUEUE
//////////////////////////////////////////////////////////////*/

/**
 * @title RetryManager
 * @notice Manages failed message retries and dead letter queue
 * @dev Features:
 *      - Configurable retry policies
 *      - Exponential backoff
 *      - Dead letter queue for permanent failures
 *      - Manual intervention support
 *      - Metrics and monitoring
 */
contract RetryManager is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    enum MessageState {
        PENDING,
        PROCESSING,
        SUCCEEDED,
        RETRYING,
        DEAD_LETTERED,
        MANUALLY_RESOLVED
    }

    struct RetryPolicy {
        uint8 maxRetries;
        uint256 initialDelay;       // Initial delay in seconds
        uint256 maxDelay;           // Max delay (for exponential backoff)
        uint256 backoffMultiplier;  // Multiplier * 100 (e.g., 200 = 2x)
        bool useExponentialBackoff;
    }

    struct FailedMessage {
        bytes32 messageId;
        bytes32 originalTxId;
        address sender;
        uint256 sourceChainId;
        uint256 destChainId;
        bytes payload;
        bytes errorData;
        uint256 firstFailedAt;
        uint256 lastRetryAt;
        uint256 nextRetryAt;
        uint8 retryCount;
        MessageState state;
        uint256 value;
        address[] tokens;
        uint256[] amounts;
    }

    struct DeadLetter {
        bytes32 messageId;
        FailedMessage message;
        uint256 deadLetteredAt;
        string resolution;
        bool resolved;
    }

    struct RetryMetrics {
        uint256 totalMessages;
        uint256 successfulRetries;
        uint256 failedRetries;
        uint256 deadLettered;
        uint256 manuallyResolved;
        uint256 pendingRetries;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error MessageNotFound();
    error MaxRetriesExceeded();
    error RetryNotReady();
    error AlreadyResolved();
    error InvalidRetryPolicy();
    error NotRetryable();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MessageQueued(
        bytes32 indexed messageId,
        bytes32 indexed originalTxId,
        uint256 sourceChainId,
        uint256 destChainId
    );
    event RetryScheduled(
        bytes32 indexed messageId,
        uint8 retryCount,
        uint256 nextRetryAt
    );
    event RetryExecuted(
        bytes32 indexed messageId,
        bool success,
        uint8 retryCount
    );
    event MessageDeadLettered(
        bytes32 indexed messageId,
        string reason
    );
    event DeadLetterResolved(
        bytes32 indexed messageId,
        string resolution
    );
    event MessageSucceeded(bytes32 indexed messageId, uint8 totalRetries);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Message ID => Failed message
    mapping(bytes32 => FailedMessage) public failedMessages;

    /// @dev Dead letter queue
    mapping(bytes32 => DeadLetter) public deadLetterQueue;

    /// @dev Default retry policy
    RetryPolicy public defaultPolicy;

    /// @dev Chain-specific policies
    mapping(uint256 => RetryPolicy) public chainPolicies;

    /// @dev Messages pending retry (sorted by nextRetryAt)
    bytes32[] public retryQueue;

    /// @dev Message index in queue
    mapping(bytes32 => uint256) public queueIndex;

    /// @dev Authorized executors
    mapping(address => bool) public executors;

    /// @dev Metrics
    RetryMetrics public metrics;

    /// @dev Handler contract for retries
    address public retryHandler;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _retryHandler) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        retryHandler = _retryHandler;

        // Default policy: 5 retries, exponential backoff starting at 1 min
        defaultPolicy = RetryPolicy({
            maxRetries: 5,
            initialDelay: 60,        // 1 minute
            maxDelay: 3600,          // 1 hour max
            backoffMultiplier: 200,  // 2x
            useExponentialBackoff: true
        });
    }

    /*//////////////////////////////////////////////////////////////
                    MESSAGE QUEUEING
    //////////////////////////////////////////////////////////////*/

    /// @notice Queue a failed message for retry
    function queueForRetry(
        bytes32 messageId,
        bytes32 originalTxId,
        address sender,
        uint256 sourceChainId,
        uint256 destChainId,
        bytes calldata payload,
        bytes calldata errorData,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable returns (bool) {
        require(executors[msg.sender] || msg.sender == owner(), "Not authorized");

        RetryPolicy memory policy = _getPolicy(destChainId);

        uint256 nextRetry = block.timestamp + policy.initialDelay;

        failedMessages[messageId] = FailedMessage({
            messageId: messageId,
            originalTxId: originalTxId,
            sender: sender,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            payload: payload,
            errorData: errorData,
            firstFailedAt: block.timestamp,
            lastRetryAt: 0,
            nextRetryAt: nextRetry,
            retryCount: 0,
            state: MessageState.RETRYING,
            value: msg.value,
            tokens: tokens,
            amounts: amounts
        });

        _addToQueue(messageId);

        metrics.totalMessages++;
        metrics.pendingRetries++;

        emit MessageQueued(messageId, originalTxId, sourceChainId, destChainId);
        emit RetryScheduled(messageId, 0, nextRetry);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                    RETRY EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute pending retries
    function executeRetries(uint256 maxRetries_) external nonReentrant {
        require(executors[msg.sender] || msg.sender == owner(), "Not authorized");

        uint256 executed;

        for (uint256 i; i < retryQueue.length && executed < maxRetries_; ) {
            bytes32 messageId = retryQueue[i];
            FailedMessage storage msg_ = failedMessages[messageId];

            if (msg_.state != MessageState.RETRYING) {
                _removeFromQueue(i);
                continue;
            }

            if (block.timestamp < msg_.nextRetryAt) {
                ++i;
                continue;
            }

            // Execute retry
            bool success = _executeRetry(messageId);
            executed++;

            if (success) {
                _handleSuccess(messageId);
                _removeFromQueue(i);
            } else {
                _handleFailure(messageId, i);
            }
        }
    }

    /// @notice Execute single retry
    function executeRetry(bytes32 messageId) external nonReentrant returns (bool) {
        require(executors[msg.sender] || msg.sender == owner(), "Not authorized");

        FailedMessage storage msg_ = failedMessages[messageId];

        if (msg_.messageId == bytes32(0)) revert MessageNotFound();
        if (msg_.state != MessageState.RETRYING) revert NotRetryable();
        if (block.timestamp < msg_.nextRetryAt) revert RetryNotReady();

        bool success = _executeRetry(messageId);

        if (success) {
            _handleSuccess(messageId);
        } else {
            _handleFailure(messageId, queueIndex[messageId]);
        }

        return success;
    }

    function _executeRetry(bytes32 messageId) internal returns (bool) {
        FailedMessage storage msg_ = failedMessages[messageId];

        msg_.state = MessageState.PROCESSING;
        msg_.lastRetryAt = block.timestamp;
        msg_.retryCount++;

        // Call retry handler
        (bool success, ) = retryHandler.call{value: msg_.value}(
            abi.encodeWithSignature(
                "retryMessage(bytes32,bytes,address[],uint256[])",
                messageId,
                msg_.payload,
                msg_.tokens,
                msg_.amounts
            )
        );

        emit RetryExecuted(messageId, success, msg_.retryCount);

        return success;
    }

    function _handleSuccess(bytes32 messageId) internal {
        FailedMessage storage msg_ = failedMessages[messageId];

        msg_.state = MessageState.SUCCEEDED;

        metrics.successfulRetries++;
        metrics.pendingRetries--;

        emit MessageSucceeded(messageId, msg_.retryCount);
    }

    function _handleFailure(bytes32 messageId, uint256 queueIdx) internal {
        FailedMessage storage msg_ = failedMessages[messageId];
        RetryPolicy memory policy = _getPolicy(msg_.destChainId);

        if (msg_.retryCount >= policy.maxRetries) {
            _deadLetter(messageId, "Max retries exceeded");
            _removeFromQueue(queueIdx);
        } else {
            // Schedule next retry
            uint256 delay = _calculateDelay(msg_.retryCount, policy);
            msg_.nextRetryAt = block.timestamp + delay;
            msg_.state = MessageState.RETRYING;

            emit RetryScheduled(messageId, msg_.retryCount, msg_.nextRetryAt);
        }

        metrics.failedRetries++;
    }

    function _calculateDelay(
        uint8 retryCount,
        RetryPolicy memory policy
    ) internal pure returns (uint256) {
        if (!policy.useExponentialBackoff) {
            return policy.initialDelay;
        }

        uint256 delay = policy.initialDelay;

        for (uint8 i; i < retryCount; ++i) {
            delay = (delay * policy.backoffMultiplier) / 100;
            if (delay > policy.maxDelay) {
                return policy.maxDelay;
            }
        }

        return delay;
    }

    /*//////////////////////////////////////////////////////////////
                    DEAD LETTER QUEUE
    //////////////////////////////////////////////////////////////*/

    function _deadLetter(bytes32 messageId, string memory reason) internal {
        FailedMessage storage msg_ = failedMessages[messageId];

        msg_.state = MessageState.DEAD_LETTERED;

        deadLetterQueue[messageId] = DeadLetter({
            messageId: messageId,
            message: msg_,
            deadLetteredAt: block.timestamp,
            resolution: "",
            resolved: false
        });

        metrics.deadLettered++;
        metrics.pendingRetries--;

        emit MessageDeadLettered(messageId, reason);
    }

    /// @notice Manually dead-letter a message
    function deadLetterMessage(bytes32 messageId, string calldata reason) external {
        require(executors[msg.sender] || msg.sender == owner(), "Not authorized");

        FailedMessage storage msg_ = failedMessages[messageId];
        if (msg_.messageId == bytes32(0)) revert MessageNotFound();

        _deadLetter(messageId, reason);
    }

    /// @notice Resolve a dead-lettered message
    function resolveDeadLetter(
        bytes32 messageId,
        string calldata resolution,
        bool refund
    ) external onlyOwner {
        DeadLetter storage dl = deadLetterQueue[messageId];
        if (dl.messageId == bytes32(0)) revert MessageNotFound();
        if (dl.resolved) revert AlreadyResolved();

        dl.resolved = true;
        dl.resolution = resolution;

        failedMessages[messageId].state = MessageState.MANUALLY_RESOLVED;

        // Refund tokens if requested
        if (refund) {
            FailedMessage storage msg_ = failedMessages[messageId];

            if (msg_.value > 0) {
                (bool success, ) = msg_.sender.call{value: msg_.value}("");
                require(success, "ETH refund failed");
            }

            for (uint256 i; i < msg_.tokens.length; ++i) {
                if (msg_.amounts[i] > 0) {
                    IERC20(msg_.tokens[i]).safeTransfer(msg_.sender, msg_.amounts[i]);
                }
            }
        }

        metrics.manuallyResolved++;

        emit DeadLetterResolved(messageId, resolution);
    }

    /// @notice Retry a dead-lettered message
    function retryDeadLetter(bytes32 messageId) external {
        require(executors[msg.sender] || msg.sender == owner(), "Not authorized");

        DeadLetter storage dl = deadLetterQueue[messageId];
        if (dl.messageId == bytes32(0)) revert MessageNotFound();
        if (dl.resolved) revert AlreadyResolved();

        FailedMessage storage msg_ = failedMessages[messageId];

        // Reset retry count and re-queue
        msg_.retryCount = 0;
        msg_.state = MessageState.RETRYING;
        msg_.nextRetryAt = block.timestamp;

        _addToQueue(messageId);

        metrics.pendingRetries++;
    }

    /*//////////////////////////////////////////////////////////////
                    QUEUE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function _addToQueue(bytes32 messageId) internal {
        retryQueue.push(messageId);
        queueIndex[messageId] = retryQueue.length - 1;
    }

    function _removeFromQueue(uint256 index) internal {
        if (index >= retryQueue.length) return;

        bytes32 messageId = retryQueue[index];

        // Move last element to deleted position
        if (index != retryQueue.length - 1) {
            bytes32 lastMessage = retryQueue[retryQueue.length - 1];
            retryQueue[index] = lastMessage;
            queueIndex[lastMessage] = index;
        }

        retryQueue.pop();
        delete queueIndex[messageId];
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getQueueLength() external view returns (uint256) {
        return retryQueue.length;
    }

    function getPendingRetries(uint256 limit)
        external view returns (bytes32[] memory pending, uint256 count)
    {
        uint256 actualLimit = limit > retryQueue.length ? retryQueue.length : limit;
        pending = new bytes32[](actualLimit);
        count = 0;

        for (uint256 i; i < retryQueue.length && count < actualLimit; ++i) {
            bytes32 messageId = retryQueue[i];
            FailedMessage storage msg_ = failedMessages[messageId];

            if (msg_.state == MessageState.RETRYING &&
                block.timestamp >= msg_.nextRetryAt) {
                pending[count] = messageId;
                count++;
            }
        }
    }

    function getDeadLetters(uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        // Would iterate through dead letter queue
        // Simplified for this implementation
        bytes32[] memory result = new bytes32[](limit);
        return result;
    }

    function getMetrics() external view returns (RetryMetrics memory) {
        return metrics;
    }

    function _getPolicy(uint256 chainId) internal view returns (RetryPolicy memory) {
        RetryPolicy memory policy = chainPolicies[chainId];
        if (policy.maxRetries == 0) {
            return defaultPolicy;
        }
        return policy;
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setDefaultPolicy(RetryPolicy calldata policy) external onlyOwner {
        if (policy.maxRetries == 0) revert InvalidRetryPolicy();
        defaultPolicy = policy;
    }

    function setChainPolicy(uint256 chainId, RetryPolicy calldata policy) external onlyOwner {
        chainPolicies[chainId] = policy;
    }

    function setExecutor(address executor, bool authorized) external onlyOwner {
        executors[executor] = authorized;
    }

    function setRetryHandler(address handler) external onlyOwner {
        retryHandler = handler;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}

    uint256[40] private __gap;
}
