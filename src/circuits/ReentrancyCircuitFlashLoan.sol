// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyCircuitFlashLoan
 * @notice Smart custom reentrancy circuit specifically for flash loan operations
 * @dev Implements EIP-3156 compliant protection with multi-asset and batch flash loan support
 *
 * Key Features:
 * - Single and batch flash loan protection
 * - Callback verification
 * - Fee manipulation prevention
 * - Same-block arbitrage detection
 * - Multi-protocol flash loan tracking
 */
library ReentrancyCircuitFlashLoan {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error FlashLoanReentrantCall();
    error FlashLoanAlreadyActive();
    error FlashLoanCallbackFailed();
    error FlashLoanInvalidCallback();
    error FlashLoanRepaymentMismatch(uint256 expected, uint256 received);
    error FlashLoanFeeManipulation();
    error FlashLoanMaxBatchExceeded(uint256 max, uint256 requested);
    error FlashLoanSameBlockArbitrage();
    error FlashLoanInvalidInitiator();
    error FlashLoanExpired();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    uint256 internal constant CALLBACK_ENTERED = 3;

    // Flash loan operation flags
    uint256 internal constant OP_FLASH_LOAN_SINGLE = 1 << 0;
    uint256 internal constant OP_FLASH_LOAN_BATCH = 1 << 1;
    uint256 internal constant OP_CALLBACK = 1 << 2;
    uint256 internal constant OP_REPAYMENT = 1 << 3;

    // Maximum assets in batch flash loan
    uint8 internal constant MAX_BATCH_SIZE = 10;

    // EIP-3156 callback selector
    bytes32 internal constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Global flash loan guard
    struct FlashLoanGuard {
        uint256 status;
        uint256 activeOperations;
        uint64 lastFlashLoanBlock;
        uint8 activeFlashLoans;
        uint8 maxConcurrent;
        bool batchActive;
    }

    /// @notice Single flash loan context
    struct FlashLoanContext {
        bool active;
        address token;
        address initiator;
        address receiver;
        uint256 amount;
        uint256 fee;
        uint256 expectedRepayment;
        uint64 startBlock;
        bytes32 dataHash;
    }

    /// @notice Batch flash loan context
    struct BatchFlashLoanContext {
        bool active;
        address initiator;
        address receiver;
        uint8 tokenCount;
        uint64 startBlock;
        uint256 totalExpectedRepayment;
        bytes32 batchHash;
    }

    /// @notice Per-token flash loan tracking
    struct TokenFlashState {
        uint64 lastFlashBlock;
        uint256 lastFlashAmount;
        uint256 totalFlashedToday;
        uint64 dayStartTimestamp;
        uint256 flashCount;
    }

    /// @notice Callback verification
    struct CallbackVerification {
        bytes32 expectedHash;
        address expectedInitiator;
        address expectedSender;
        bool verified;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event FlashLoanStarted(
        address indexed token,
        address indexed initiator,
        address receiver,
        uint256 amount,
        uint256 fee
    );
    event FlashLoanCompleted(
        address indexed token,
        address indexed initiator,
        uint256 amount,
        uint256 fee
    );
    event BatchFlashLoanStarted(
        address indexed initiator,
        uint8 tokenCount,
        uint256 totalAmount
    );
    event BatchFlashLoanCompleted(
        address indexed initiator,
        uint8 tokenCount
    );
    event FlashLoanCallbackVerified(address indexed initiator, bytes32 dataHash);
    event FlashLoanAnomalyDetected(address indexed token, string reason);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the flash loan guard
     * @param guard The guard storage to initialize
     * @param maxConcurrent Maximum concurrent flash loans allowed
     */
    function initialize(FlashLoanGuard storage guard, uint8 maxConcurrent) internal {
        guard.status = NOT_ENTERED;
        guard.maxConcurrent = maxConcurrent > 0 ? maxConcurrent : 1;
    }

    /**
     * @notice Initialize token flash state
     * @param state The token state storage
     */
    function initializeTokenState(TokenFlashState storage state) internal {
        state.dayStartTimestamp = uint64(block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SINGLE FLASH LOAN PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start a single flash loan
     * @param guard The flash loan guard
     * @param context The flash loan context
     * @param token Token being borrowed
     * @param initiator Flash loan initiator
     * @param receiver Flash loan receiver
     * @param amount Amount being borrowed
     * @param fee Fee for the flash loan
     * @param data Callback data
     */
    function startFlashLoan(
        FlashLoanGuard storage guard,
        FlashLoanContext storage context,
        address token,
        address initiator,
        address receiver,
        uint256 amount,
        uint256 fee,
        bytes memory data
    ) internal {
        _checkAndEnterGuard(guard, OP_FLASH_LOAN_SINGLE);

        if (context.active) {
            revert FlashLoanAlreadyActive();
        }

        context.active = true;
        context.token = token;
        context.initiator = initiator;
        context.receiver = receiver;
        context.amount = amount;
        context.fee = fee;
        context.expectedRepayment = amount + fee;
        context.startBlock = uint64(block.number);
        context.dataHash = keccak256(data);

        guard.activeFlashLoans++;

        emit FlashLoanStarted(token, initiator, receiver, amount, fee);
    }

    /**
     * @notice Verify callback and prepare for repayment
     * @param context The flash loan context
     * @param verification Callback verification data
     * @param initiator Callback initiator
     * @param data Callback data
     * @return True if callback is valid
     */
    function verifyCallback(
        FlashLoanContext storage context,
        CallbackVerification storage verification,
        address initiator,
        bytes memory data
    ) internal returns (bool) {
        if (!context.active) {
            revert FlashLoanInvalidCallback();
        }

        // Verify initiator
        if (context.initiator != initiator) {
            revert FlashLoanInvalidInitiator();
        }

        // Verify same block
        if (context.startBlock != block.number) {
            revert FlashLoanExpired();
        }

        // Verify data integrity
        if (context.dataHash != keccak256(data)) {
            revert FlashLoanInvalidCallback();
        }

        verification.verified = true;
        verification.expectedInitiator = initiator;

        emit FlashLoanCallbackVerified(initiator, context.dataHash);

        return true;
    }

    /**
     * @notice Complete flash loan after repayment
     * @param guard The flash loan guard
     * @param context The flash loan context
     * @param actualRepayment Actual amount repaid
     */
    function completeFlashLoan(
        FlashLoanGuard storage guard,
        FlashLoanContext storage context,
        uint256 actualRepayment
    ) internal {
        if (!context.active) {
            revert FlashLoanReentrantCall();
        }

        // Verify repayment
        if (actualRepayment < context.expectedRepayment) {
            revert FlashLoanRepaymentMismatch(context.expectedRepayment, actualRepayment);
        }

        emit FlashLoanCompleted(
            context.token,
            context.initiator,
            context.amount,
            context.fee
        );

        // Clear context
        _clearFlashLoanContext(context);

        guard.activeFlashLoans--;
        _exitGuard(guard, OP_FLASH_LOAN_SINGLE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH FLASH LOAN PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start a batch flash loan
     * @param guard The flash loan guard
     * @param batchContext The batch context
     * @param initiator Flash loan initiator
     * @param receiver Flash loan receiver
     * @param tokens Array of tokens
     * @param amounts Array of amounts
     * @param fees Array of fees
     */
    function startBatchFlashLoan(
        FlashLoanGuard storage guard,
        BatchFlashLoanContext storage batchContext,
        address initiator,
        address receiver,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory fees
    ) internal {
        if (tokens.length > MAX_BATCH_SIZE) {
            revert FlashLoanMaxBatchExceeded(MAX_BATCH_SIZE, tokens.length);
        }

        _checkAndEnterGuard(guard, OP_FLASH_LOAN_BATCH);

        if (batchContext.active) {
            revert FlashLoanAlreadyActive();
        }

        uint256 totalRepayment = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalRepayment += amounts[i] + fees[i];
        }

        batchContext.active = true;
        batchContext.initiator = initiator;
        batchContext.receiver = receiver;
        batchContext.tokenCount = uint8(tokens.length);
        batchContext.startBlock = uint64(block.number);
        batchContext.totalExpectedRepayment = totalRepayment;
        batchContext.batchHash = keccak256(abi.encodePacked(tokens, amounts, fees));

        guard.batchActive = true;

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        emit BatchFlashLoanStarted(initiator, uint8(tokens.length), totalAmount);
    }

    /**
     * @notice Complete batch flash loan
     * @param guard The flash loan guard
     * @param batchContext The batch context
     * @param actualRepayments Array of actual repayments per token
     */
    function completeBatchFlashLoan(
        FlashLoanGuard storage guard,
        BatchFlashLoanContext storage batchContext,
        uint256[] memory actualRepayments
    ) internal {
        if (!batchContext.active) {
            revert FlashLoanReentrantCall();
        }

        // Verify total repayment
        uint256 totalActual = 0;
        for (uint256 i = 0; i < actualRepayments.length; i++) {
            totalActual += actualRepayments[i];
        }

        if (totalActual < batchContext.totalExpectedRepayment) {
            revert FlashLoanRepaymentMismatch(batchContext.totalExpectedRepayment, totalActual);
        }

        emit BatchFlashLoanCompleted(batchContext.initiator, batchContext.tokenCount);

        // Clear context
        batchContext.active = false;
        batchContext.initiator = address(0);
        batchContext.receiver = address(0);
        batchContext.tokenCount = 0;
        batchContext.totalExpectedRepayment = 0;
        batchContext.batchHash = bytes32(0);

        guard.batchActive = false;
        _exitGuard(guard, OP_FLASH_LOAN_BATCH);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN STATE TRACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update token flash state
     * @param state The token state
     * @param amount Amount being flash borrowed
     */
    function updateTokenState(TokenFlashState storage state, uint256 amount) internal {
        // Reset daily counter if new day
        if (block.timestamp >= state.dayStartTimestamp + 1 days) {
            state.totalFlashedToday = 0;
            state.dayStartTimestamp = uint64(block.timestamp);
        }

        state.lastFlashBlock = uint64(block.number);
        state.lastFlashAmount = amount;
        state.totalFlashedToday += amount;
        state.flashCount++;
    }

    /**
     * @notice Check for same-block arbitrage
     * @param state The token state
     * @return True if same-block flash detected
     */
    function isSameBlockFlash(TokenFlashState storage state) internal view returns (bool) {
        return state.lastFlashBlock == block.number;
    }

    /**
     * @notice Get token flash statistics
     * @param state The token state
     */
    function getTokenStats(TokenFlashState storage state) internal view returns (
        uint64 lastBlock,
        uint256 lastAmount,
        uint256 totalToday,
        uint256 count
    ) {
        return (
            state.lastFlashBlock,
            state.lastFlashAmount,
            state.totalFlashedToday,
            state.flashCount
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE MANIPULATION PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify fee hasn't been manipulated during flash loan
     * @param originalFee Fee at start
     * @param currentFee Current fee
     * @param maxDeviationBps Maximum allowed deviation in basis points
     */
    function verifyFeeIntegrity(
        uint256 originalFee,
        uint256 currentFee,
        uint256 maxDeviationBps
    ) internal pure {
        if (originalFee == 0) return;

        uint256 deviation;
        if (currentFee > originalFee) {
            deviation = ((currentFee - originalFee) * 10000) / originalFee;
        } else {
            deviation = ((originalFee - currentFee) * 10000) / originalFee;
        }

        if (deviation > maxDeviationBps) {
            revert FlashLoanFeeManipulation();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get flash loan guard status
     * @param guard The flash loan guard
     */
    function getGuardStatus(FlashLoanGuard storage guard) internal view returns (
        uint256 status,
        uint8 activeLoans,
        bool batchActive,
        uint64 lastBlock
    ) {
        return (
            guard.status,
            guard.activeFlashLoans,
            guard.batchActive,
            guard.lastFlashLoanBlock
        );
    }

    /**
     * @notice Get flash loan context status
     * @param context The flash loan context
     */
    function getContextStatus(FlashLoanContext storage context) internal view returns (
        bool active,
        address token,
        uint256 amount,
        uint256 expectedRepayment
    ) {
        return (
            context.active,
            context.token,
            context.amount,
            context.expectedRepayment
        );
    }

    /**
     * @notice Check if any flash loan is active
     * @param guard The flash loan guard
     * @return True if flash loan in progress
     */
    function isFlashLoanActive(FlashLoanGuard storage guard) internal view returns (bool) {
        return guard.status != NOT_ENTERED || guard.activeFlashLoans > 0;
    }

    /**
     * @notice Check if can start another flash loan
     * @param guard The flash loan guard
     * @return True if new flash loan allowed
     */
    function canStartFlashLoan(FlashLoanGuard storage guard) internal view returns (bool) {
        return guard.activeFlashLoans < guard.maxConcurrent && !guard.batchActive;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _checkAndEnterGuard(FlashLoanGuard storage guard, uint256 operation) private {
        if (guard.status == 0) {
            guard.status = NOT_ENTERED;
        }

        if (guard.status != NOT_ENTERED && operation == OP_FLASH_LOAN_BATCH) {
            revert FlashLoanReentrantCall();
        }

        if (guard.activeFlashLoans >= guard.maxConcurrent) {
            revert FlashLoanReentrantCall();
        }

        guard.status = ENTERED;
        guard.activeOperations |= operation;
        guard.lastFlashLoanBlock = uint64(block.number);
    }

    function _exitGuard(FlashLoanGuard storage guard, uint256 operation) private {
        guard.activeOperations &= ~operation;

        if (guard.activeFlashLoans == 0 && !guard.batchActive) {
            guard.status = NOT_ENTERED;
        }
    }

    function _clearFlashLoanContext(FlashLoanContext storage context) private {
        context.active = false;
        context.token = address(0);
        context.initiator = address(0);
        context.receiver = address(0);
        context.amount = 0;
        context.fee = 0;
        context.expectedRepayment = 0;
        context.dataHash = bytes32(0);
    }
}
