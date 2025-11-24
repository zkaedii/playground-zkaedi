// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title InputValidation
 * @notice Centralized input validation library for consistent parameter checking
 * @dev Provides reusable validation functions with custom error types
 */
library InputValidation {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error ZeroAddress();
    error ZeroAmount();
    error ZeroValue();
    error InvalidBPS(uint256 bps);
    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error DeadlineTooSoon(uint256 deadline, uint256 minDeadline);
    error DeadlineTooFar(uint256 deadline, uint256 maxDeadline);
    error InvalidRecipient(address recipient);
    error SameAddress(address addr);
    error ArrayLengthMismatch(uint256 length1, uint256 length2);
    error EmptyArray();
    error ArrayTooLarge(uint256 length, uint256 maxLength);
    error InsufficientBalance(uint256 required, uint256 available);
    error ValueTooLow(uint256 value, uint256 minimum);
    error ValueTooHigh(uint256 value, uint256 maximum);
    error InvalidRange(uint256 min, uint256 max);
    error InvalidChainId(uint256 chainId);
    error InvalidSelector(bytes4 selector);
    error EmptyBytes();
    error StringTooLong(uint256 length, uint256 maxLength);
    error InvalidNonce(uint256 provided, uint256 expected);
    error InvalidTimestamp(uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant MAX_REASONABLE_DEADLINE = 365 days;
    uint256 internal constant MIN_DEADLINE_BUFFER = 1 minutes;

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate address is not zero
     * @param addr Address to validate
     */
    function notZeroAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Validate multiple addresses are not zero
     * @param addrs Addresses to validate
     */
    function notZeroAddresses(address[] memory addrs) internal pure {
        uint256 length = addrs.length;
        for (uint256 i; i < length;) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            unchecked { ++i; }
        }
    }

    /**
     * @notice Validate recipient is valid (not zero, not self)
     * @param recipient Recipient address
     * @param self Contract address to check against
     */
    function validRecipient(address recipient, address self) internal pure {
        if (recipient == address(0)) revert ZeroAddress();
        if (recipient == self) revert InvalidRecipient(recipient);
    }

    /**
     * @notice Validate two addresses are different
     * @param addr1 First address
     * @param addr2 Second address
     */
    function notSameAddress(address addr1, address addr2) internal pure {
        if (addr1 == addr2) revert SameAddress(addr1);
    }

    /**
     * @notice Check if address is a contract
     * @param addr Address to check
     * @return True if address has code
     */
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AMOUNT VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate amount is not zero
     * @param amount Amount to validate
     */
    function notZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /**
     * @notice Validate amount is within range
     * @param amount Amount to validate
     * @param min Minimum value (inclusive)
     * @param max Maximum value (inclusive)
     */
    function amountInRange(uint256 amount, uint256 min, uint256 max) internal pure {
        if (min > max) revert InvalidRange(min, max);
        if (amount < min) revert ValueTooLow(amount, min);
        if (amount > max) revert ValueTooHigh(amount, max);
    }

    /**
     * @notice Validate amount is at least minimum
     * @param amount Amount to validate
     * @param min Minimum value
     */
    function atLeast(uint256 amount, uint256 min) internal pure {
        if (amount < min) revert ValueTooLow(amount, min);
    }

    /**
     * @notice Validate amount is at most maximum
     * @param amount Amount to validate
     * @param max Maximum value
     */
    function atMost(uint256 amount, uint256 max) internal pure {
        if (amount > max) revert ValueTooHigh(amount, max);
    }

    /**
     * @notice Validate balance is sufficient
     * @param required Required amount
     * @param available Available balance
     */
    function sufficientBalance(uint256 required, uint256 available) internal pure {
        if (required > available) revert InsufficientBalance(required, available);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIS POINTS VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate basis points is within valid range (0-10000)
     * @param bps Basis points to validate
     */
    function validBPS(uint256 bps) internal pure {
        if (bps > MAX_BPS) revert InvalidBPS(bps);
    }

    /**
     * @notice Validate basis points is within custom range
     * @param bps Basis points to validate
     * @param maxBps Maximum allowed basis points
     */
    function validBPSWithMax(uint256 bps, uint256 maxBps) internal pure {
        if (bps > maxBps) revert InvalidBPS(bps);
    }

    /**
     * @notice Validate basis points is within min-max range
     * @param bps Basis points to validate
     * @param minBps Minimum basis points
     * @param maxBps Maximum basis points
     */
    function validBPSRange(uint256 bps, uint256 minBps, uint256 maxBps) internal pure {
        if (bps < minBps || bps > maxBps) revert InvalidBPS(bps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEADLINE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate deadline has not expired
     * @param deadline Deadline timestamp
     */
    function deadlineNotExpired(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
    }

    /**
     * @notice Validate deadline is in the future with minimum buffer
     * @param deadline Deadline timestamp
     * @param minBuffer Minimum time in future
     */
    function deadlineWithBuffer(uint256 deadline, uint256 minBuffer) internal view {
        uint256 minDeadline = block.timestamp + minBuffer;
        if (deadline < minDeadline) revert DeadlineTooSoon(deadline, minDeadline);
    }

    /**
     * @notice Validate deadline is within acceptable range
     * @param deadline Deadline timestamp
     * @param minBuffer Minimum time in future
     * @param maxDuration Maximum time in future
     */
    function deadlineInRange(uint256 deadline, uint256 minBuffer, uint256 maxDuration) internal view {
        uint256 minDeadline = block.timestamp + minBuffer;
        uint256 maxDeadline = block.timestamp + maxDuration;
        if (deadline < minDeadline) revert DeadlineTooSoon(deadline, minDeadline);
        if (deadline > maxDeadline) revert DeadlineTooFar(deadline, maxDeadline);
    }

    /**
     * @notice Validate timestamp is valid (not zero, not too far in past/future)
     * @param timestamp Timestamp to validate
     * @param maxPastDelta Maximum seconds in the past
     * @param maxFutureDelta Maximum seconds in the future
     */
    function validTimestamp(uint256 timestamp, uint256 maxPastDelta, uint256 maxFutureDelta) internal view {
        if (timestamp == 0) revert InvalidTimestamp(timestamp);
        if (timestamp < block.timestamp - maxPastDelta) revert InvalidTimestamp(timestamp);
        if (timestamp > block.timestamp + maxFutureDelta) revert InvalidTimestamp(timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ARRAY VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate array is not empty
     * @param length Array length
     */
    function notEmptyArray(uint256 length) internal pure {
        if (length == 0) revert EmptyArray();
    }

    /**
     * @notice Validate two arrays have matching lengths
     * @param length1 First array length
     * @param length2 Second array length
     */
    function matchingLengths(uint256 length1, uint256 length2) internal pure {
        if (length1 != length2) revert ArrayLengthMismatch(length1, length2);
    }

    /**
     * @notice Validate multiple arrays have matching lengths
     * @param lengths Array of lengths to check
     */
    function allMatchingLengths(uint256[] memory lengths) internal pure {
        if (lengths.length < 2) return;
        uint256 expected = lengths[0];
        for (uint256 i = 1; i < lengths.length;) {
            if (lengths[i] != expected) revert ArrayLengthMismatch(expected, lengths[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Validate array length is within bounds
     * @param length Array length
     * @param maxLength Maximum allowed length
     */
    function arrayWithinBounds(uint256 length, uint256 maxLength) internal pure {
        if (length > maxLength) revert ArrayTooLarge(length, maxLength);
    }

    /**
     * @notice Validate array is not empty and within bounds
     * @param length Array length
     * @param maxLength Maximum allowed length
     */
    function validArrayLength(uint256 length, uint256 maxLength) internal pure {
        if (length == 0) revert EmptyArray();
        if (length > maxLength) revert ArrayTooLarge(length, maxLength);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BYTES VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate bytes is not empty
     * @param data Bytes to validate
     */
    function notEmptyBytes(bytes memory data) internal pure {
        if (data.length == 0) revert EmptyBytes();
    }

    /**
     * @notice Validate bytes is not empty (calldata)
     * @param data Bytes to validate
     */
    function notEmptyBytesCalldata(bytes calldata data) internal pure {
        if (data.length == 0) revert EmptyBytes();
    }

    /**
     * @notice Validate string length is within bounds
     * @param str String to validate
     * @param maxLength Maximum length
     */
    function stringWithinBounds(string memory str, uint256 maxLength) internal pure {
        if (bytes(str).length > maxLength) revert StringTooLong(bytes(str).length, maxLength);
    }

    /**
     * @notice Validate function selector is not zero
     * @param selector Selector to validate
     */
    function validSelector(bytes4 selector) internal pure {
        if (selector == bytes4(0)) revert InvalidSelector(selector);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHAIN & NONCE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate chain ID matches current chain
     * @param chainId Chain ID to validate
     */
    function currentChain(uint256 chainId) internal view {
        if (chainId != block.chainid) revert InvalidChainId(chainId);
    }

    /**
     * @notice Validate chain ID is not zero
     * @param chainId Chain ID to validate
     */
    function validChainId(uint256 chainId) internal pure {
        if (chainId == 0) revert InvalidChainId(chainId);
    }

    /**
     * @notice Validate nonce matches expected value
     * @param provided Provided nonce
     * @param expected Expected nonce
     */
    function validNonce(uint256 provided, uint256 expected) internal pure {
        if (provided != expected) revert InvalidNonce(provided, expected);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMBINED VALIDATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate common swap parameters
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @param recipient Recipient address
     * @param deadline Transaction deadline
     */
    function validateSwapParams(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        uint256 deadline
    ) internal view {
        notZeroAddress(tokenIn);
        notZeroAddress(tokenOut);
        notSameAddress(tokenIn, tokenOut);
        notZeroAmount(amountIn);
        notZeroAddress(recipient);
        deadlineNotExpired(deadline);
    }

    /**
     * @notice Validate common transfer parameters
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function validateTransferParams(
        address from,
        address to,
        uint256 amount
    ) internal pure {
        notZeroAddress(from);
        notZeroAddress(to);
        notSameAddress(from, to);
        notZeroAmount(amount);
    }

    /**
     * @notice Validate fee configuration
     * @param feeBps Fee in basis points
     * @param recipient Fee recipient
     * @param maxFeeBps Maximum allowed fee
     */
    function validateFeeConfig(
        uint256 feeBps,
        address recipient,
        uint256 maxFeeBps
    ) internal pure {
        validBPSWithMax(feeBps, maxFeeBps);
        if (feeBps > 0) {
            notZeroAddress(recipient);
        }
    }
}
