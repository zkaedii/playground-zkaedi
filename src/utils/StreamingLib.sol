// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title StreamingLib
/// @notice Token streaming library for continuous payment flows and vesting
/// @dev Implements linear, exponential, and milestone-based streaming patterns
///
/// INTEGRATION NOTES:
/// - This library returns amounts but does NOT perform token transfers. The host contract
///   must handle actual ERC20 transfers and implement appropriate access control.
/// - All rate calculations use integer division which rounds DOWN. This means:
///   - streamedAmount may be slightly less than depositAmount until endTime
///   - ratePerSecond * duration may be < depositAmount due to remainder truncation
/// - Host contracts should use reentrancy guards when performing withdrawals
/// - Consider using the "pull over push" pattern for safety
///
/// @author playground-zkaedi
library StreamingLib {
    // ============ Custom Errors ============
    error StreamNotInitialized();
    error StreamNotStarted();
    error StreamAlreadyStarted();
    error StreamEnded();
    error StreamNotEnded();
    error StreamCancelled();
    error StreamNotCancellable();
    error InvalidStreamDuration();
    error InvalidStreamAmount();
    error InvalidRecipient();
    error InvalidSender();
    error InsufficientStreamedAmount();
    error NothingToWithdraw();
    error WithdrawalExceedsAvailable();
    error UnauthorizedAccess();
    error MilestoneNotReached();
    error InvalidMilestone();
    error CliffNotPassed();

    // ============ Constants ============
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant BPS = 10000;
    uint256 internal constant MAX_MILESTONES = 20;

    // ============ Enums ============
    enum StreamType {
        Linear,           // Constant rate over time
        Exponential,      // Accelerating or decelerating
        Cliff,            // Linear with initial cliff
        Milestone,        // Discrete milestone-based
        Dynamic           // Adjustable rate
    }

    enum StreamStatus {
        Pending,          // Not yet started
        Active,           // Currently streaming
        Paused,           // Temporarily paused
        Completed,        // Fully streamed
        Cancelled         // Terminated early
    }

    // ============ Structs ============

    /// @notice Core stream configuration
    struct StreamConfig {
        address sender;           // Token depositor
        address recipient;        // Token receiver
        address token;            // Token being streamed
        uint256 depositAmount;    // Total tokens deposited
        uint256 startTime;        // Stream start timestamp
        uint256 endTime;          // Stream end timestamp
        uint256 cliffTime;        // Cliff end timestamp (0 if no cliff)
        bool cancelable;          // Can sender cancel?
        bool transferable;        // Can recipient transfer stream?
    }

    /// @notice Linear stream state
    struct LinearStream {
        StreamConfig config;
        uint256 withdrawnAmount;  // Amount already withdrawn
        uint256 ratePerSecond;    // Tokens per second
        StreamStatus status;
        bool initialized;
    }

    /// @notice Exponential stream (for accelerating/decelerating vesting)
    struct ExponentialStream {
        StreamConfig config;
        uint256 withdrawnAmount;
        uint256 exponent;         // 1 = linear, 2 = quadratic, etc.
        bool accelerating;        // true = slow start, false = fast start
        StreamStatus status;
        bool initialized;
    }

    /// @notice Milestone definition
    struct Milestone {
        uint256 unlockTime;       // When milestone unlocks
        uint256 amount;           // Amount unlocked at milestone
        bytes32 conditionHash;    // Optional condition hash (0 = time-based only)
        bool claimed;             // Has this milestone been claimed?
    }

    /// @notice Milestone-based stream
    struct MilestoneStream {
        StreamConfig config;
        Milestone[] milestones;
        uint256 withdrawnAmount;
        uint256 currentMilestone; // Index of next unclaimed milestone
        StreamStatus status;
        bool initialized;
    }

    /// @notice Dynamic rate stream
    struct DynamicStream {
        StreamConfig config;
        uint256 withdrawnAmount;
        uint256 baseRate;         // Base rate per second
        uint256 currentRate;      // Current rate (can be adjusted)
        uint256 lastRateUpdate;   // Last rate change timestamp
        uint256 accumulatedBeforeChange; // Amount accumulated before last rate change
        StreamStatus status;
        bool initialized;
    }

    /// @notice Batch stream for multiple recipients
    struct BatchStream {
        address sender;
        address token;
        uint256 totalDeposited;
        uint256 startTime;
        uint256 endTime;
        mapping(address => uint256) allocations;  // Per-recipient allocation
        mapping(address => uint256) withdrawn;    // Per-recipient withdrawn
        address[] recipients;
        bool initialized;
    }

    // ============ Linear Stream Functions ============

    /// @notice Create a linear stream
    /// @dev Rate calculation uses integer division: ratePerSecond = amount / duration.
    ///      Due to rounding, ratePerSecond * duration may be slightly less than amount.
    ///      The full depositAmount is available at endTime regardless of rate.
    /// @param stream The stream storage reference
    /// @param sender Token depositor address
    /// @param recipient Token receiver address
    /// @param token Token being streamed
    /// @param amount Total tokens to stream (must be > 0)
    /// @param startTime Stream start timestamp (0 = block.timestamp)
    /// @param duration Stream duration in seconds (must be > 0)
    /// @param cliffDuration Cliff duration in seconds (0 = no cliff)
    /// @param cancelable Whether sender can cancel the stream
    /// @param transferable Whether recipient can transfer the stream
    /// @return streamId Unique identifier for the stream
    function createLinearStream(
        LinearStream storage stream,
        address sender,
        address recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        uint256 cliffDuration,
        bool cancelable,
        bool transferable
    ) internal returns (uint256 streamId) {
        if (recipient == address(0)) revert InvalidRecipient();
        if (sender == address(0)) revert InvalidSender();
        if (amount == 0) revert InvalidStreamAmount();
        if (duration == 0) revert InvalidStreamDuration();
        if (startTime == 0) startTime = block.timestamp;

        uint256 endTime = startTime + duration;
        uint256 cliffTime = cliffDuration > 0 ? startTime + cliffDuration : 0;

        stream.config = StreamConfig({
            sender: sender,
            recipient: recipient,
            token: token,
            depositAmount: amount,
            startTime: startTime,
            endTime: endTime,
            cliffTime: cliffTime,
            cancelable: cancelable,
            transferable: transferable
        });

        // Note: Integer division may result in ratePerSecond * duration < amount
        // This is handled by returning full depositAmount at endTime
        stream.ratePerSecond = amount / duration;
        stream.withdrawnAmount = 0;
        stream.status = StreamStatus.Pending;
        stream.initialized = true;

        return uint256(keccak256(abi.encodePacked(sender, recipient, block.timestamp)));
    }

    /// @notice Calculate streamed amount for linear stream
    function streamedAmount(LinearStream storage stream) internal view returns (uint256) {
        if (!stream.initialized) return 0;
        if (block.timestamp < stream.config.startTime) return 0;

        // Check cliff
        if (stream.config.cliffTime > 0 && block.timestamp < stream.config.cliffTime) {
            return 0;
        }

        if (block.timestamp >= stream.config.endTime) {
            return stream.config.depositAmount;
        }

        uint256 elapsed = block.timestamp - stream.config.startTime;
        return stream.ratePerSecond * elapsed;
    }

    /// @notice Get withdrawable amount from linear stream
    function withdrawableAmount(LinearStream storage stream) internal view returns (uint256) {
        uint256 streamed = streamedAmount(stream);
        if (streamed <= stream.withdrawnAmount) return 0;
        return streamed - stream.withdrawnAmount;
    }

    /// @notice Withdraw from linear stream
    function withdrawLinear(
        LinearStream storage stream,
        uint256 amount
    ) internal returns (uint256 withdrawn) {
        _checkStreamActive(stream.status, stream.initialized);

        uint256 available = withdrawableAmount(stream);
        if (available == 0) revert NothingToWithdraw();

        withdrawn = amount > available ? available : amount;
        stream.withdrawnAmount += withdrawn;

        // Update status if fully withdrawn
        if (stream.withdrawnAmount >= stream.config.depositAmount) {
            stream.status = StreamStatus.Completed;
        } else if (stream.status == StreamStatus.Pending) {
            stream.status = StreamStatus.Active;
        }

        return withdrawn;
    }

    /// @notice Cancel linear stream
    function cancelLinear(
        LinearStream storage stream,
        address caller
    ) internal returns (uint256 senderRefund, uint256 recipientAmount) {
        if (!stream.initialized) revert StreamNotInitialized();
        if (!stream.config.cancelable) revert StreamNotCancellable();
        if (caller != stream.config.sender) revert UnauthorizedAccess();
        if (stream.status == StreamStatus.Cancelled) revert StreamCancelled();
        if (stream.status == StreamStatus.Completed) revert StreamEnded();

        uint256 streamed = streamedAmount(stream);
        recipientAmount = streamed > stream.withdrawnAmount ? streamed - stream.withdrawnAmount : 0;
        senderRefund = stream.config.depositAmount - streamed;

        stream.status = StreamStatus.Cancelled;

        return (senderRefund, recipientAmount);
    }

    // ============ Exponential Stream Functions ============

    /// @notice Create exponential stream
    function createExponentialStream(
        ExponentialStream storage stream,
        address sender,
        address recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        uint256 exponent,
        bool accelerating,
        bool cancelable
    ) internal {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidStreamAmount();
        if (duration == 0) revert InvalidStreamDuration();
        if (exponent == 0 || exponent > 5) revert InvalidStreamDuration();
        if (startTime == 0) startTime = block.timestamp;

        stream.config = StreamConfig({
            sender: sender,
            recipient: recipient,
            token: token,
            depositAmount: amount,
            startTime: startTime,
            endTime: startTime + duration,
            cliffTime: 0,
            cancelable: cancelable,
            transferable: false
        });

        stream.exponent = exponent;
        stream.accelerating = accelerating;
        stream.withdrawnAmount = 0;
        stream.status = StreamStatus.Pending;
        stream.initialized = true;
    }

    /// @notice Calculate streamed amount for exponential stream
    function streamedAmountExponential(
        ExponentialStream storage stream
    ) internal view returns (uint256) {
        if (!stream.initialized) return 0;
        if (block.timestamp < stream.config.startTime) return 0;
        if (block.timestamp >= stream.config.endTime) {
            return stream.config.depositAmount;
        }

        uint256 elapsed = block.timestamp - stream.config.startTime;
        uint256 duration = stream.config.endTime - stream.config.startTime;

        // Calculate progress ratio (0 to PRECISION)
        uint256 progress = (elapsed * PRECISION) / duration;

        // Apply exponential curve
        uint256 curvedProgress;
        if (stream.accelerating) {
            // Slow start, fast end: y = x^n
            curvedProgress = _pow(progress, stream.exponent);
        } else {
            // Fast start, slow end: y = 1 - (1-x)^n
            uint256 inverse = PRECISION - progress;
            uint256 inversePow = _pow(inverse, stream.exponent);
            curvedProgress = PRECISION - inversePow;
        }

        return (stream.config.depositAmount * curvedProgress) / PRECISION;
    }

    /// @notice Withdraw from exponential stream
    function withdrawExponential(
        ExponentialStream storage stream,
        uint256 amount
    ) internal returns (uint256 withdrawn) {
        _checkStreamActive(stream.status, stream.initialized);

        uint256 streamed = streamedAmountExponential(stream);
        uint256 available = streamed > stream.withdrawnAmount ? streamed - stream.withdrawnAmount : 0;

        if (available == 0) revert NothingToWithdraw();

        withdrawn = amount > available ? available : amount;
        stream.withdrawnAmount += withdrawn;

        if (stream.withdrawnAmount >= stream.config.depositAmount) {
            stream.status = StreamStatus.Completed;
        } else if (stream.status == StreamStatus.Pending) {
            stream.status = StreamStatus.Active;
        }

        return withdrawn;
    }

    // ============ Milestone Stream Functions ============

    /// @notice Create milestone-based stream
    function createMilestoneStream(
        MilestoneStream storage stream,
        address sender,
        address recipient,
        address token,
        uint256 totalAmount,
        uint256[] memory unlockTimes,
        uint256[] memory amounts,
        bool cancelable
    ) internal {
        if (recipient == address(0)) revert InvalidRecipient();
        if (totalAmount == 0) revert InvalidStreamAmount();
        if (unlockTimes.length == 0 || unlockTimes.length > MAX_MILESTONES) revert InvalidMilestone();
        if (unlockTimes.length != amounts.length) revert InvalidMilestone();

        uint256 sumAmounts = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            sumAmounts += amounts[i];
            if (i > 0 && unlockTimes[i] <= unlockTimes[i - 1]) revert InvalidMilestone();
        }
        if (sumAmounts != totalAmount) revert InvalidStreamAmount();

        stream.config = StreamConfig({
            sender: sender,
            recipient: recipient,
            token: token,
            depositAmount: totalAmount,
            startTime: block.timestamp,
            endTime: unlockTimes[unlockTimes.length - 1],
            cliffTime: 0,
            cancelable: cancelable,
            transferable: false
        });

        // Add milestones
        for (uint256 i = 0; i < unlockTimes.length; i++) {
            stream.milestones.push(Milestone({
                unlockTime: unlockTimes[i],
                amount: amounts[i],
                conditionHash: bytes32(0),
                claimed: false
            }));
        }

        stream.withdrawnAmount = 0;
        stream.currentMilestone = 0;
        stream.status = StreamStatus.Pending;
        stream.initialized = true;
    }

    /// @notice Get claimable milestones
    function claimableMilestoneAmount(
        MilestoneStream storage stream
    ) internal view returns (uint256 amount, uint256 count) {
        if (!stream.initialized) return (0, 0);

        for (uint256 i = stream.currentMilestone; i < stream.milestones.length; i++) {
            Milestone storage m = stream.milestones[i];
            if (block.timestamp >= m.unlockTime && !m.claimed) {
                amount += m.amount;
                count++;
            } else {
                break; // Milestones are ordered, so we can stop
            }
        }

        return (amount, count);
    }

    /// @notice Claim milestones
    function claimMilestones(
        MilestoneStream storage stream
    ) internal returns (uint256 claimed) {
        _checkStreamActive(stream.status, stream.initialized);

        (uint256 claimable, uint256 count) = claimableMilestoneAmount(stream);
        if (claimable == 0) revert NothingToWithdraw();

        // Mark milestones as claimed
        for (uint256 i = 0; i < count; i++) {
            stream.milestones[stream.currentMilestone + i].claimed = true;
        }

        stream.currentMilestone += count;
        stream.withdrawnAmount += claimable;

        if (stream.currentMilestone >= stream.milestones.length) {
            stream.status = StreamStatus.Completed;
        } else if (stream.status == StreamStatus.Pending) {
            stream.status = StreamStatus.Active;
        }

        return claimable;
    }

    /// @notice Get milestone info
    function getMilestoneInfo(
        MilestoneStream storage stream,
        uint256 index
    ) internal view returns (
        uint256 unlockTime,
        uint256 amount,
        bool claimed,
        bool claimable
    ) {
        if (index >= stream.milestones.length) revert InvalidMilestone();

        Milestone storage m = stream.milestones[index];
        return (
            m.unlockTime,
            m.amount,
            m.claimed,
            !m.claimed && block.timestamp >= m.unlockTime
        );
    }

    // ============ Dynamic Stream Functions ============

    /// @notice Create dynamic rate stream
    /// @dev End time is calculated as startTime + (amount / initialRate).
    ///      Due to integer division, the calculated duration may result in
    ///      duration * initialRate < amount. Rate changes recalculate endTime.
    /// @param stream The stream storage reference
    /// @param sender Token depositor address
    /// @param recipient Token receiver address
    /// @param token Token being streamed
    /// @param amount Total tokens to stream (must be > 0)
    /// @param startTime Stream start timestamp (0 = block.timestamp)
    /// @param initialRate Initial rate per second (must be > 0)
    /// @param cancelable Whether sender can cancel the stream
    function createDynamicStream(
        DynamicStream storage stream,
        address sender,
        address recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 initialRate,
        bool cancelable
    ) internal {
        if (recipient == address(0)) revert InvalidRecipient();
        if (sender == address(0)) revert InvalidSender();
        if (amount == 0) revert InvalidStreamAmount();
        if (initialRate == 0) revert InvalidStreamAmount();
        if (startTime == 0) startTime = block.timestamp;

        // Calculate end time based on initial rate
        // Note: Integer division means duration * initialRate may be < amount
        uint256 duration = amount / initialRate;

        stream.config = StreamConfig({
            sender: sender,
            recipient: recipient,
            token: token,
            depositAmount: amount,
            startTime: startTime,
            endTime: startTime + duration,
            cliffTime: 0,
            cancelable: cancelable,
            transferable: false
        });

        stream.baseRate = initialRate;
        stream.currentRate = initialRate;
        stream.lastRateUpdate = startTime;
        stream.accumulatedBeforeChange = 0;
        stream.withdrawnAmount = 0;
        stream.status = StreamStatus.Pending;
        stream.initialized = true;
    }

    /// @notice Update stream rate
    function updateRate(
        DynamicStream storage stream,
        uint256 newRate,
        address caller
    ) internal {
        if (!stream.initialized) revert StreamNotInitialized();
        if (caller != stream.config.sender) revert UnauthorizedAccess();
        if (stream.status == StreamStatus.Completed || stream.status == StreamStatus.Cancelled) {
            revert StreamEnded();
        }

        // Calculate accumulated amount at current rate
        uint256 elapsed = block.timestamp - stream.lastRateUpdate;
        stream.accumulatedBeforeChange += stream.currentRate * elapsed;

        // Update rate
        stream.currentRate = newRate;
        stream.lastRateUpdate = block.timestamp;

        // Recalculate end time based on remaining amount
        uint256 remaining = stream.config.depositAmount - stream.accumulatedBeforeChange;
        if (newRate > 0) {
            stream.config.endTime = block.timestamp + (remaining / newRate);
        }
    }

    /// @notice Calculate streamed amount for dynamic stream
    function streamedAmountDynamic(
        DynamicStream storage stream
    ) internal view returns (uint256) {
        if (!stream.initialized) return 0;
        if (block.timestamp < stream.config.startTime) return 0;

        uint256 elapsed = block.timestamp - stream.lastRateUpdate;
        uint256 currentPortion = stream.currentRate * elapsed;
        uint256 total = stream.accumulatedBeforeChange + currentPortion;

        return total > stream.config.depositAmount ? stream.config.depositAmount : total;
    }

    /// @notice Withdraw from dynamic stream
    function withdrawDynamic(
        DynamicStream storage stream,
        uint256 amount
    ) internal returns (uint256 withdrawn) {
        _checkStreamActive(stream.status, stream.initialized);

        uint256 streamed = streamedAmountDynamic(stream);
        uint256 available = streamed > stream.withdrawnAmount ? streamed - stream.withdrawnAmount : 0;

        if (available == 0) revert NothingToWithdraw();

        withdrawn = amount > available ? available : amount;
        stream.withdrawnAmount += withdrawn;

        if (stream.withdrawnAmount >= stream.config.depositAmount) {
            stream.status = StreamStatus.Completed;
        } else if (stream.status == StreamStatus.Pending) {
            stream.status = StreamStatus.Active;
        }

        return withdrawn;
    }

    // ============ Batch Stream Functions ============

    /// @notice Create batch stream for multiple recipients
    function createBatchStream(
        BatchStream storage batch,
        address sender,
        address token,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration,
        address[] memory recipients,
        uint256[] memory allocations
    ) internal {
        if (recipients.length == 0 || recipients.length != allocations.length) {
            revert InvalidRecipient();
        }
        if (totalAmount == 0) revert InvalidStreamAmount();
        if (duration == 0) revert InvalidStreamDuration();
        if (startTime == 0) startTime = block.timestamp;

        uint256 sumAllocations = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            sumAllocations += allocations[i];
        }
        if (sumAllocations != totalAmount) revert InvalidStreamAmount();

        batch.sender = sender;
        batch.token = token;
        batch.totalDeposited = totalAmount;
        batch.startTime = startTime;
        batch.endTime = startTime + duration;

        for (uint256 i = 0; i < recipients.length; i++) {
            batch.allocations[recipients[i]] = allocations[i];
            batch.recipients.push(recipients[i]);
        }

        batch.initialized = true;
    }

    /// @notice Get batch stream recipient info
    /// @dev Streamed amount uses pro-rata calculation: (allocation * elapsed) / duration.
    ///      Integer division rounds down, so full allocation is only available at endTime.
    /// @param batch The batch stream storage reference
    /// @param recipient Address to query
    /// @return allocation Total allocation for recipient
    /// @return streamed Amount streamed so far (may be less than allocation due to rounding)
    /// @return withdrawn Amount already withdrawn
    /// @return available Amount available to withdraw now
    function getBatchRecipientInfo(
        BatchStream storage batch,
        address recipient
    ) internal view returns (
        uint256 allocation,
        uint256 streamed,
        uint256 withdrawn,
        uint256 available
    ) {
        allocation = batch.allocations[recipient];
        if (allocation == 0) return (0, 0, 0, 0);

        if (block.timestamp < batch.startTime) {
            streamed = 0;
        } else if (block.timestamp >= batch.endTime) {
            streamed = allocation;
        } else {
            uint256 elapsed = block.timestamp - batch.startTime;
            uint256 duration = batch.endTime - batch.startTime;
            // duration > 0 guaranteed by createBatchStream validation
            streamed = (allocation * elapsed) / duration;
        }

        withdrawn = batch.withdrawn[recipient];
        available = streamed > withdrawn ? streamed - withdrawn : 0;

        return (allocation, streamed, withdrawn, available);
    }

    /// @notice Withdraw from batch stream
    function withdrawBatch(
        BatchStream storage batch,
        address recipient,
        uint256 amount
    ) internal returns (uint256 withdrawn) {
        if (!batch.initialized) revert StreamNotInitialized();

        (, , , uint256 available) = getBatchRecipientInfo(batch, recipient);
        if (available == 0) revert NothingToWithdraw();

        withdrawn = amount > available ? available : amount;
        batch.withdrawn[recipient] += withdrawn;

        return withdrawn;
    }

    // ============ Query Functions ============

    /// @notice Get stream progress as percentage (in BPS)
    function getProgress(
        StreamConfig storage config,
        uint256 withdrawnAmount
    ) internal view returns (uint256) {
        if (config.depositAmount == 0) return 0;
        return (withdrawnAmount * BPS) / config.depositAmount;
    }

    /// @notice Get time remaining in stream
    function getTimeRemaining(StreamConfig storage config) internal view returns (uint256) {
        if (block.timestamp >= config.endTime) return 0;
        return config.endTime - block.timestamp;
    }

    /// @notice Check if stream has cliff and if it's passed
    function isCliffPassed(StreamConfig storage config) internal view returns (bool) {
        if (config.cliffTime == 0) return true;
        return block.timestamp >= config.cliffTime;
    }

    /// @notice Get stream status string
    function getStatusString(StreamStatus status) internal pure returns (string memory) {
        if (status == StreamStatus.Pending) return "Pending";
        if (status == StreamStatus.Active) return "Active";
        if (status == StreamStatus.Paused) return "Paused";
        if (status == StreamStatus.Completed) return "Completed";
        if (status == StreamStatus.Cancelled) return "Cancelled";
        return "Unknown";
    }

    // ============ Internal Helpers ============

    function _checkStreamActive(StreamStatus status, bool initialized) private pure {
        if (!initialized) revert StreamNotInitialized();
        if (status == StreamStatus.Cancelled) revert StreamCancelled();
        if (status == StreamStatus.Completed) revert StreamEnded();
    }

    /// @notice Power function for exponential calculations
    function _pow(uint256 base, uint256 exp) private pure returns (uint256) {
        if (exp == 0) return PRECISION;
        if (exp == 1) return base;

        uint256 result = PRECISION;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) / PRECISION;
            }
            base = (base * base) / PRECISION;
            exp /= 2;
        }
        return result;
    }

    // ============ Transfer Functions ============

    /// @notice Transfer stream to new recipient
    function transferStream(
        StreamConfig storage config,
        address newRecipient,
        address caller
    ) internal {
        if (caller != config.recipient) revert UnauthorizedAccess();
        if (!config.transferable) revert UnauthorizedAccess();
        if (newRecipient == address(0)) revert InvalidRecipient();

        config.recipient = newRecipient;
    }
}
