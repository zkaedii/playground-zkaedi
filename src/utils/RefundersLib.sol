// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RefundersLib
 * @notice Comprehensive refund mechanism utilities for DeFi protocols
 * @dev Provides gas refunds, token refunds, fee rebates, overpayment handling,
 *      and batch refund processing with security measures
 */
library RefundersLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum gas price for refunds (to prevent abuse)
    uint256 internal constant MAX_GAS_PRICE = 1000 gwei;

    /// @dev Maximum gas units refundable per transaction
    uint256 internal constant MAX_GAS_REFUND = 500_000;

    /// @dev Minimum refund amount (to avoid dust)
    uint256 internal constant MIN_REFUND_AMOUNT = 1000;

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev Maximum refund percentage (100%)
    uint256 internal constant MAX_REFUND_BPS = 10000;

    /// @dev Default refund window (30 days)
    uint256 internal constant DEFAULT_REFUND_WINDOW = 30 days;

    /// @dev Maximum batch size for refunds
    uint256 internal constant MAX_BATCH_SIZE = 100;

    /// @dev Gas overhead for refund processing
    uint256 internal constant REFUND_GAS_OVERHEAD = 21000;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error RefundNotAvailable(bytes32 refundId);
    error RefundAlreadyClaimed(bytes32 refundId);
    error RefundExpired(bytes32 refundId, uint256 deadline);
    error RefundNotExpired(bytes32 refundId);
    error InsufficientRefundBalance(uint256 requested, uint256 available);
    error RefundAmountTooSmall(uint256 amount, uint256 minimum);
    error RefundAmountTooLarge(uint256 amount, uint256 maximum);
    error InvalidRefundRecipient(address recipient);
    error UnauthorizedRefund(address caller);
    error RefundTransferFailed(address recipient, uint256 amount);
    error GasPriceTooHigh(uint256 gasPrice, uint256 maximum);
    error BatchSizeExceeded(uint256 size, uint256 maximum);
    error InvalidRefundPercentage(uint256 percentage);
    error RefundWindowClosed(uint256 closedAt);
    error RefundPoolDepleted();
    error DuplicateRefund(bytes32 refundId);
    error InvalidMerkleProof();
    error ClaimPeriodNotStarted(uint256 startTime);
    error TokenTransferFailed(address token, address recipient, uint256 amount);
    error ZeroAddress();
    error InvalidRefundType();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Refund status enum
    enum RefundStatus {
        Pending,
        Approved,
        Claimed,
        Rejected,
        Expired,
        Cancelled
    }

    /// @notice Refund type classification
    enum RefundType {
        GasRefund,
        TokenRefund,
        FeeRebate,
        Overpayment,
        FailedTransaction,
        ProtocolCompensation,
        AirdropClaim
    }

    /// @notice Individual refund record
    struct RefundRecord {
        bytes32 refundId;
        address recipient;
        address token; // address(0) for ETH
        uint256 amount;
        uint256 createdAt;
        uint256 expiresAt;
        RefundStatus status;
        RefundType refundType;
        bytes32 reason;
        bytes32 txHash;
    }

    /// @notice Refund pool for a specific token
    struct RefundPool {
        address token;
        uint256 totalDeposited;
        uint256 totalClaimed;
        uint256 pendingAmount;
        uint256 reservedAmount;
        bool isActive;
    }

    /// @notice Refund registry storage
    struct RefundRegistry {
        mapping(bytes32 => RefundRecord) refunds;
        mapping(address => bytes32[]) userRefunds;
        mapping(address => RefundPool) pools;
        mapping(address => uint256) userTotalClaimed;
        uint256 totalRefunds;
        uint256 claimedRefunds;
        bytes32 merkleRoot;
        uint256 claimStartTime;
        uint256 claimEndTime;
    }

    /// @notice Gas refund configuration
    struct GasRefundConfig {
        uint256 maxGasPrice;
        uint256 maxGasUnits;
        uint256 refundPercentageBps;
        uint256 minimumRefund;
        bool isEnabled;
    }

    /// @notice Gas refund tracker
    struct GasTracker {
        uint256 startGas;
        uint256 gasPrice;
        address refundRecipient;
        bool shouldRefund;
    }

    /// @notice Fee rebate configuration
    struct RebateConfig {
        uint256 rebatePercentageBps;
        uint256 minimumVolume;
        uint256 maximumRebate;
        uint256 periodDuration;
        bool isActive;
    }

    /// @notice User rebate tracking
    struct UserRebateState {
        uint256 periodStart;
        uint256 volumeInPeriod;
        uint256 rebatesEarned;
        uint256 rebatesClaimed;
    }

    /// @notice Batch refund request
    struct BatchRefundRequest {
        address[] recipients;
        address[] tokens;
        uint256[] amounts;
        RefundType refundType;
        bytes32 batchId;
    }

    /// @notice Batch refund result
    struct BatchRefundResult {
        bytes32 batchId;
        uint256 successCount;
        uint256 failureCount;
        uint256 totalAmount;
        bytes32[] refundIds;
    }

    /// @notice Overpayment record
    struct Overpayment {
        address payer;
        address token;
        uint256 amount;
        uint256 recordedAt;
        bool refunded;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFUND REGISTRY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a new refund record
    /// @param registry Refund registry storage
    /// @param recipient Refund recipient
    /// @param token Token address (address(0) for ETH)
    /// @param amount Refund amount
    /// @param refundType Type of refund
    /// @param reason Reason hash
    /// @param expiryDuration Duration until expiry
    /// @return refundId Generated refund ID
    function createRefund(
        RefundRegistry storage registry,
        address recipient,
        address token,
        uint256 amount,
        RefundType refundType,
        bytes32 reason,
        uint256 expiryDuration
    ) internal returns (bytes32 refundId) {
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (amount < MIN_REFUND_AMOUNT) {
            revert RefundAmountTooSmall(amount, MIN_REFUND_AMOUNT);
        }

        refundId = keccak256(
            abi.encode(recipient, token, amount, block.timestamp, registry.totalRefunds)
        );

        if (registry.refunds[refundId].refundId != bytes32(0)) {
            revert DuplicateRefund(refundId);
        }

        uint256 expiry = expiryDuration > 0
            ? block.timestamp + expiryDuration
            : block.timestamp + DEFAULT_REFUND_WINDOW;

        registry.refunds[refundId] = RefundRecord({
            refundId: refundId,
            recipient: recipient,
            token: token,
            amount: amount,
            createdAt: block.timestamp,
            expiresAt: expiry,
            status: RefundStatus.Pending,
            refundType: refundType,
            reason: reason,
            txHash: bytes32(0)
        });

        registry.userRefunds[recipient].push(refundId);

        RefundPool storage pool = registry.pools[token];
        pool.pendingAmount += amount;

        unchecked {
            ++registry.totalRefunds;
        }
    }

    /// @notice Approve a pending refund
    /// @param registry Refund registry storage
    /// @param refundId Refund to approve
    function approveRefund(RefundRegistry storage registry, bytes32 refundId) internal {
        RefundRecord storage refund = registry.refunds[refundId];

        if (refund.refundId == bytes32(0)) {
            revert RefundNotAvailable(refundId);
        }
        if (refund.status != RefundStatus.Pending) {
            revert RefundAlreadyClaimed(refundId);
        }

        refund.status = RefundStatus.Approved;
    }

    /// @notice Claim an approved refund
    /// @param registry Refund registry storage
    /// @param refundId Refund to claim
    /// @return recipient Refund recipient
    /// @return token Token address
    /// @return amount Refund amount
    function claimRefund(
        RefundRegistry storage registry,
        bytes32 refundId
    ) internal returns (address recipient, address token, uint256 amount) {
        RefundRecord storage refund = registry.refunds[refundId];

        if (refund.refundId == bytes32(0)) {
            revert RefundNotAvailable(refundId);
        }
        if (refund.status == RefundStatus.Claimed) {
            revert RefundAlreadyClaimed(refundId);
        }
        if (refund.status == RefundStatus.Rejected || refund.status == RefundStatus.Cancelled) {
            revert RefundNotAvailable(refundId);
        }
        if (block.timestamp > refund.expiresAt) {
            refund.status = RefundStatus.Expired;
            revert RefundExpired(refundId, refund.expiresAt);
        }

        recipient = refund.recipient;
        token = refund.token;
        amount = refund.amount;

        refund.status = RefundStatus.Claimed;
        refund.txHash = bytes32(uint256(uint160(msg.sender)));

        RefundPool storage pool = registry.pools[token];
        pool.pendingAmount -= amount;
        pool.totalClaimed += amount;

        registry.userTotalClaimed[recipient] += amount;

        unchecked {
            ++registry.claimedRefunds;
        }
    }

    /// @notice Reject a refund
    /// @param registry Refund registry storage
    /// @param refundId Refund to reject
    function rejectRefund(RefundRegistry storage registry, bytes32 refundId) internal {
        RefundRecord storage refund = registry.refunds[refundId];

        if (refund.refundId == bytes32(0)) {
            revert RefundNotAvailable(refundId);
        }
        if (refund.status != RefundStatus.Pending && refund.status != RefundStatus.Approved) {
            revert RefundAlreadyClaimed(refundId);
        }

        RefundPool storage pool = registry.pools[refund.token];
        pool.pendingAmount -= refund.amount;

        refund.status = RefundStatus.Rejected;
    }

    /// @notice Get refund record
    /// @param registry Refund registry storage
    /// @param refundId Refund ID
    /// @return refund Refund record
    function getRefund(
        RefundRegistry storage registry,
        bytes32 refundId
    ) internal view returns (RefundRecord storage refund) {
        refund = registry.refunds[refundId];
        if (refund.refundId == bytes32(0)) {
            revert RefundNotAvailable(refundId);
        }
    }

    /// @notice Check if refund is claimable
    /// @param registry Refund registry storage
    /// @param refundId Refund ID
    /// @return claimable True if refund can be claimed
    function isRefundClaimable(
        RefundRegistry storage registry,
        bytes32 refundId
    ) internal view returns (bool claimable) {
        RefundRecord storage refund = registry.refunds[refundId];

        if (refund.refundId == bytes32(0)) return false;
        if (refund.status != RefundStatus.Approved && refund.status != RefundStatus.Pending) return false;
        if (block.timestamp > refund.expiresAt) return false;

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFUND POOL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize a refund pool
    /// @param registry Refund registry storage
    /// @param token Token for the pool
    function initializePool(RefundRegistry storage registry, address token) internal {
        RefundPool storage pool = registry.pools[token];
        pool.token = token;
        pool.isActive = true;
    }

    /// @notice Deposit to refund pool
    /// @param registry Refund registry storage
    /// @param token Token address
    /// @param amount Amount to deposit
    function depositToPool(
        RefundRegistry storage registry,
        address token,
        uint256 amount
    ) internal {
        RefundPool storage pool = registry.pools[token];
        pool.totalDeposited += amount;
    }

    /// @notice Reserve funds in pool for pending refund
    /// @param registry Refund registry storage
    /// @param token Token address
    /// @param amount Amount to reserve
    function reserveInPool(
        RefundRegistry storage registry,
        address token,
        uint256 amount
    ) internal {
        RefundPool storage pool = registry.pools[token];
        uint256 available = pool.totalDeposited - pool.totalClaimed - pool.reservedAmount;

        if (amount > available) {
            revert InsufficientRefundBalance(amount, available);
        }

        pool.reservedAmount += amount;
    }

    /// @notice Release reserved funds
    /// @param registry Refund registry storage
    /// @param token Token address
    /// @param amount Amount to release
    function releaseReserved(
        RefundRegistry storage registry,
        address token,
        uint256 amount
    ) internal {
        RefundPool storage pool = registry.pools[token];
        pool.reservedAmount -= amount;
    }

    /// @notice Get pool available balance
    /// @param registry Refund registry storage
    /// @param token Token address
    /// @return available Available balance for refunds
    function getPoolAvailable(
        RefundRegistry storage registry,
        address token
    ) internal view returns (uint256 available) {
        RefundPool storage pool = registry.pools[token];
        return pool.totalDeposited - pool.totalClaimed - pool.reservedAmount - pool.pendingAmount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS REFUND FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Start gas tracking for potential refund
    /// @param recipient Address to receive refund
    /// @return tracker Gas tracker struct
    function startGasTracking(address recipient) internal view returns (GasTracker memory tracker) {
        tracker.startGas = gasleft();
        tracker.gasPrice = tx.gasprice;
        tracker.refundRecipient = recipient;
        tracker.shouldRefund = true;
    }

    /// @notice Calculate gas refund amount
    /// @param tracker Gas tracker
    /// @param config Gas refund configuration
    /// @return refundAmount Amount to refund
    function calculateGasRefund(
        GasTracker memory tracker,
        GasRefundConfig memory config
    ) internal view returns (uint256 refundAmount) {
        if (!config.isEnabled || !tracker.shouldRefund) {
            return 0;
        }

        uint256 gasUsed = tracker.startGas - gasleft() + REFUND_GAS_OVERHEAD;
        uint256 effectiveGasPrice = tracker.gasPrice;

        // Cap gas price
        if (effectiveGasPrice > config.maxGasPrice) {
            effectiveGasPrice = config.maxGasPrice;
        }

        // Cap gas units
        if (gasUsed > config.maxGasUnits) {
            gasUsed = config.maxGasUnits;
        }

        // Calculate base refund
        uint256 baseRefund = gasUsed * effectiveGasPrice;

        // Apply refund percentage
        refundAmount = (baseRefund * config.refundPercentageBps) / BPS_DENOMINATOR;

        // Enforce minimum
        if (refundAmount < config.minimumRefund) {
            refundAmount = 0;
        }
    }

    /// @notice Finalize gas refund
    /// @param tracker Gas tracker
    /// @param config Gas refund configuration
    /// @return recipient Refund recipient
    /// @return amount Refund amount
    function finalizeGasRefund(
        GasTracker memory tracker,
        GasRefundConfig memory config
    ) internal view returns (address recipient, uint256 amount) {
        amount = calculateGasRefund(tracker, config);
        recipient = tracker.refundRecipient;
    }

    /// @notice Validate gas refund configuration
    /// @param config Configuration to validate
    function validateGasRefundConfig(GasRefundConfig memory config) internal pure {
        if (config.maxGasPrice > MAX_GAS_PRICE) {
            revert GasPriceTooHigh(config.maxGasPrice, MAX_GAS_PRICE);
        }
        if (config.refundPercentageBps > MAX_REFUND_BPS) {
            revert InvalidRefundPercentage(config.refundPercentageBps);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE REBATE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize user rebate state for new period
    /// @param state User rebate state storage
    /// @param periodStart Start of rebate period
    function initRebatePeriod(UserRebateState storage state, uint256 periodStart) internal {
        state.periodStart = periodStart;
        state.volumeInPeriod = 0;
        state.rebatesEarned = 0;
    }

    /// @notice Record volume for rebate calculation
    /// @param state User rebate state storage
    /// @param config Rebate configuration
    /// @param volume Volume to record
    /// @return rebateEarned Rebate amount earned from this volume
    function recordVolumeForRebate(
        UserRebateState storage state,
        RebateConfig memory config,
        uint256 volume
    ) internal returns (uint256 rebateEarned) {
        if (!config.isActive) return 0;

        // Check if new period
        if (block.timestamp >= state.periodStart + config.periodDuration) {
            state.periodStart = block.timestamp;
            state.volumeInPeriod = 0;
            state.rebatesEarned = 0;
        }

        state.volumeInPeriod += volume;

        // Calculate rebate if above minimum volume
        if (state.volumeInPeriod >= config.minimumVolume) {
            rebateEarned = (volume * config.rebatePercentageBps) / BPS_DENOMINATOR;

            // Cap at maximum
            uint256 remainingCap = config.maximumRebate > state.rebatesEarned
                ? config.maximumRebate - state.rebatesEarned
                : 0;

            if (rebateEarned > remainingCap) {
                rebateEarned = remainingCap;
            }

            state.rebatesEarned += rebateEarned;
        }
    }

    /// @notice Calculate total claimable rebate
    /// @param state User rebate state
    /// @return claimable Claimable rebate amount
    function getClaimableRebate(UserRebateState storage state) internal view returns (uint256 claimable) {
        return state.rebatesEarned - state.rebatesClaimed;
    }

    /// @notice Claim rebate
    /// @param state User rebate state storage
    /// @param amount Amount to claim
    function claimRebate(UserRebateState storage state, uint256 amount) internal {
        uint256 claimable = state.rebatesEarned - state.rebatesClaimed;
        if (amount > claimable) {
            revert InsufficientRefundBalance(amount, claimable);
        }
        state.rebatesClaimed += amount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OVERPAYMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Record an overpayment
    /// @param payer Address that overpaid
    /// @param token Token that was overpaid
    /// @param expectedAmount Expected payment amount
    /// @param actualAmount Actual payment amount
    /// @return overpayment Overpayment record
    function recordOverpayment(
        address payer,
        address token,
        uint256 expectedAmount,
        uint256 actualAmount
    ) internal view returns (Overpayment memory overpayment) {
        if (actualAmount <= expectedAmount) {
            return overpayment; // No overpayment
        }

        overpayment = Overpayment({
            payer: payer,
            token: token,
            amount: actualAmount - expectedAmount,
            recordedAt: block.timestamp,
            refunded: false
        });
    }

    /// @notice Calculate overpayment from expected vs actual
    /// @param expected Expected amount
    /// @param actual Actual amount received
    /// @return overpayAmount Overpayment amount
    function calculateOverpayment(
        uint256 expected,
        uint256 actual
    ) internal pure returns (uint256 overpayAmount) {
        return actual > expected ? actual - expected : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH REFUND FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create batch refund request
    /// @param recipients Array of recipients
    /// @param tokens Array of tokens
    /// @param amounts Array of amounts
    /// @param refundType Type of refund
    /// @return request Batch refund request
    function createBatchRequest(
        address[] memory recipients,
        address[] memory tokens,
        uint256[] memory amounts,
        RefundType refundType
    ) internal view returns (BatchRefundRequest memory request) {
        if (recipients.length != amounts.length || recipients.length != tokens.length) {
            revert InvalidRefundRecipient(address(0));
        }
        if (recipients.length > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded(recipients.length, MAX_BATCH_SIZE);
        }

        request = BatchRefundRequest({
            recipients: recipients,
            tokens: tokens,
            amounts: amounts,
            refundType: refundType,
            batchId: keccak256(abi.encode(recipients, tokens, amounts, block.timestamp))
        });
    }

    /// @notice Process batch refunds in registry
    /// @param registry Refund registry storage
    /// @param request Batch request to process
    /// @return result Batch processing result
    function processBatchRefunds(
        RefundRegistry storage registry,
        BatchRefundRequest memory request
    ) internal returns (BatchRefundResult memory result) {
        result.batchId = request.batchId;
        result.refundIds = new bytes32[](request.recipients.length);

        for (uint256 i; i < request.recipients.length;) {
            if (request.recipients[i] != address(0) && request.amounts[i] >= MIN_REFUND_AMOUNT) {
                bytes32 refundId = createRefund(
                    registry,
                    request.recipients[i],
                    request.tokens[i],
                    request.amounts[i],
                    request.refundType,
                    request.batchId,
                    DEFAULT_REFUND_WINDOW
                );

                result.refundIds[i] = refundId;
                result.totalAmount += request.amounts[i];
                unchecked { ++result.successCount; }
            } else {
                unchecked { ++result.failureCount; }
            }

            unchecked { ++i; }
        }
    }

    /// @notice Calculate batch total
    /// @param amounts Array of amounts
    /// @return total Sum of all amounts
    function calculateBatchTotal(uint256[] memory amounts) internal pure returns (uint256 total) {
        for (uint256 i; i < amounts.length;) {
            total += amounts[i];
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MERKLE PROOF REFUND FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set merkle root for airdrop/refund claims
    /// @param registry Refund registry storage
    /// @param merkleRoot New merkle root
    /// @param claimStart Start time for claims
    /// @param claimEnd End time for claims
    function setMerkleRoot(
        RefundRegistry storage registry,
        bytes32 merkleRoot,
        uint256 claimStart,
        uint256 claimEnd
    ) internal {
        registry.merkleRoot = merkleRoot;
        registry.claimStartTime = claimStart;
        registry.claimEndTime = claimEnd;
    }

    /// @notice Verify merkle proof for refund claim
    /// @param registry Refund registry storage
    /// @param account Account claiming
    /// @param amount Amount being claimed
    /// @param proof Merkle proof
    /// @return valid True if proof is valid
    function verifyMerkleProof(
        RefundRegistry storage registry,
        address account,
        uint256 amount,
        bytes32[] memory proof
    ) internal view returns (bool valid) {
        bytes32 leaf = keccak256(abi.encodePacked(account, amount));
        return _verifyProof(proof, registry.merkleRoot, leaf);
    }

    /// @dev Internal merkle proof verification
    function _verifyProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) private pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length;) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            unchecked { ++i; }
        }

        return computedHash == root;
    }

    /// @notice Check if merkle claim period is active
    /// @param registry Refund registry storage
    /// @return active True if claim period is active
    function isMerkleClaimActive(RefundRegistry storage registry) internal view returns (bool active) {
        return block.timestamp >= registry.claimStartTime && block.timestamp <= registry.claimEndTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate refund ID
    /// @param recipient Refund recipient
    /// @param token Token address
    /// @param amount Refund amount
    /// @param nonce Unique nonce
    /// @return refundId Generated refund ID
    function generateRefundId(
        address recipient,
        address token,
        uint256 amount,
        uint256 nonce
    ) internal view returns (bytes32 refundId) {
        return keccak256(abi.encode(recipient, token, amount, nonce, block.chainid));
    }

    /// @notice Calculate refund with percentage
    /// @param originalAmount Original amount
    /// @param percentageBps Refund percentage in basis points
    /// @return refundAmount Calculated refund amount
    function calculatePercentageRefund(
        uint256 originalAmount,
        uint256 percentageBps
    ) internal pure returns (uint256 refundAmount) {
        if (percentageBps > MAX_REFUND_BPS) {
            revert InvalidRefundPercentage(percentageBps);
        }
        return (originalAmount * percentageBps) / BPS_DENOMINATOR;
    }

    /// @notice Check if amount meets minimum threshold
    /// @param amount Amount to check
    /// @param minimum Minimum threshold
    /// @return meetsMinimum True if amount meets minimum
    function meetsMinimumThreshold(
        uint256 amount,
        uint256 minimum
    ) internal pure returns (bool meetsMinimum) {
        return amount >= minimum;
    }

    /// @notice Calculate pro-rata refund for partial fills
    /// @param totalAmount Total order amount
    /// @param filledAmount Amount that was filled
    /// @param originalFee Original fee charged
    /// @return refundableFee Fee that should be refunded
    function calculateProRataRefund(
        uint256 totalAmount,
        uint256 filledAmount,
        uint256 originalFee
    ) internal pure returns (uint256 refundableFee) {
        if (totalAmount == 0 || filledAmount >= totalAmount) return 0;

        uint256 unfilledAmount = totalAmount - filledAmount;
        return (originalFee * unfilledAmount) / totalAmount;
    }

    /// @notice Get user's pending refund count
    /// @param registry Refund registry storage
    /// @param user User address
    /// @return count Number of pending refunds
    function getUserPendingRefundCount(
        RefundRegistry storage registry,
        address user
    ) internal view returns (uint256 count) {
        bytes32[] storage refundIds = registry.userRefunds[user];

        for (uint256 i; i < refundIds.length;) {
            RefundRecord storage refund = registry.refunds[refundIds[i]];
            if (refund.status == RefundStatus.Pending || refund.status == RefundStatus.Approved) {
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }
    }

    /// @notice Get user's total refund amount
    /// @param registry Refund registry storage
    /// @param user User address
    /// @param token Token to sum (address(0) for ETH)
    /// @return total Total pending refund amount
    function getUserTotalPendingRefund(
        RefundRegistry storage registry,
        address user,
        address token
    ) internal view returns (uint256 total) {
        bytes32[] storage refundIds = registry.userRefunds[user];

        for (uint256 i; i < refundIds.length;) {
            RefundRecord storage refund = registry.refunds[refundIds[i]];
            if (
                refund.token == token &&
                (refund.status == RefundStatus.Pending || refund.status == RefundStatus.Approved)
            ) {
                total += refund.amount;
            }
            unchecked { ++i; }
        }
    }

    /// @notice Mark expired refunds
    /// @param registry Refund registry storage
    /// @param refundIds Array of refund IDs to check
    /// @return expiredCount Number of refunds marked as expired
    function markExpiredRefunds(
        RefundRegistry storage registry,
        bytes32[] memory refundIds
    ) internal returns (uint256 expiredCount) {
        for (uint256 i; i < refundIds.length;) {
            RefundRecord storage refund = registry.refunds[refundIds[i]];

            if (
                refund.status == RefundStatus.Pending &&
                block.timestamp > refund.expiresAt
            ) {
                refund.status = RefundStatus.Expired;

                RefundPool storage pool = registry.pools[refund.token];
                pool.pendingAmount -= refund.amount;

                unchecked { ++expiredCount; }
            }

            unchecked { ++i; }
        }
    }
}
