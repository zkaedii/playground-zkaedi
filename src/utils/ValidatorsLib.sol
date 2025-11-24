// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ValidatorsLib
 * @notice Advanced validation utilities for DeFi protocols
 * @dev Provides comprehensive validation for addresses, amounts, signatures,
 *      merkle proofs, timestamps, and complex business logic constraints
 */
library ValidatorsLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev Maximum basis points (100%)
    uint256 internal constant MAX_BPS = 10000;

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev Maximum reasonable timestamp (year 2100)
    uint256 internal constant MAX_TIMESTAMP = 4102444800;

    /// @dev Minimum reasonable timestamp (year 2020)
    uint256 internal constant MIN_TIMESTAMP = 1577836800;

    /// @dev Maximum array length for validation
    uint256 internal constant MAX_ARRAY_LENGTH = 1000;

    /// @dev ETH address constant
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev EIP-1271 magic value
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error ZeroAddress();
    error ZeroAmount();
    error InvalidAddress(address addr);
    error InvalidAmount(uint256 amount);
    error AmountTooSmall(uint256 amount, uint256 minimum);
    error AmountTooLarge(uint256 amount, uint256 maximum);
    error InvalidPercentage(uint256 percentage);
    error InvalidDeadline(uint256 deadline);
    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error InvalidSignature();
    error SignatureExpired();
    error InvalidMerkleProof();
    error InvalidArrayLength(uint256 length);
    error ArrayLengthMismatch(uint256 length1, uint256 length2);
    error DuplicateEntry(bytes32 entry);
    error InvalidRange(uint256 min, uint256 max);
    error ValueOutOfRange(uint256 value, uint256 min, uint256 max);
    error InvalidSelector(bytes4 selector);
    error ContractNotAllowed(address addr);
    error EOANotAllowed(address addr);
    error InvalidChainId(uint256 chainId);
    error InvalidNonce(uint256 provided, uint256 expected);
    error SlippageExceeded(uint256 expected, uint256 actual, uint256 tolerance);
    error PriceDeviationExceeded(uint256 price1, uint256 price2, uint256 maxDeviation);
    error InsufficientBalance(uint256 required, uint256 available);
    error InvalidTokenPair(address token0, address token1);
    error SameAddress(address addr);
    error BlacklistedAddress(address addr);
    error NotWhitelisted(address addr);
    error InvalidProofLength(uint256 length);
    error TimestampInFuture(uint256 timestamp);
    error TimestampTooOld(uint256 timestamp, uint256 maxAge);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validation result with details
    struct ValidationResult {
        bool isValid;
        bytes32 errorCode;
        string message;
    }

    /// @notice Amount constraints
    struct AmountConstraints {
        uint256 minimum;
        uint256 maximum;
        uint256 decimals;
        bool allowZero;
    }

    /// @notice Time constraints
    struct TimeConstraints {
        uint256 minTimestamp;
        uint256 maxTimestamp;
        uint256 maxAge;
        uint256 minDuration;
        uint256 maxDuration;
    }

    /// @notice Address validation config
    struct AddressConfig {
        bool allowZero;
        bool allowContract;
        bool allowEOA;
        bool checkBlacklist;
        bool checkWhitelist;
    }

    /// @notice Whitelist/Blacklist storage
    struct AddressLists {
        mapping(address => bool) whitelist;
        mapping(address => bool) blacklist;
        bool whitelistEnabled;
        bool blacklistEnabled;
    }

    /// @notice Signature validation params
    struct SignatureParams {
        bytes32 hash;
        uint8 v;
        bytes32 r;
        bytes32 s;
        address expectedSigner;
        uint256 deadline;
    }

    /// @notice Price validation params
    struct PriceValidation {
        uint256 spotPrice;
        uint256 oraclePrice;
        uint256 maxDeviationBps;
        uint256 maxStaleness;
        uint256 lastUpdate;
    }

    /// @notice Order validation params
    struct OrderValidation {
        address maker;
        address taker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDRESS VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate address is not zero
    /// @param addr Address to validate
    function requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
    }

    /// @notice Validate multiple addresses are not zero
    /// @param addresses Array of addresses
    function requireNonZeroAddresses(address[] memory addresses) internal pure {
        for (uint256 i; i < addresses.length;) {
            if (addresses[i] == address(0)) {
                revert ZeroAddress();
            }
            unchecked { ++i; }
        }
    }

    /// @notice Validate address with configuration
    /// @param addr Address to validate
    /// @param config Validation configuration
    /// @param lists Whitelist/blacklist storage
    function validateAddress(
        address addr,
        AddressConfig memory config,
        AddressLists storage lists
    ) internal view {
        if (!config.allowZero && addr == address(0)) {
            revert ZeroAddress();
        }

        if (addr != address(0)) {
            bool isContract = _isContract(addr);

            if (!config.allowContract && isContract) {
                revert ContractNotAllowed(addr);
            }

            if (!config.allowEOA && !isContract) {
                revert EOANotAllowed(addr);
            }

            if (config.checkBlacklist && lists.blacklistEnabled && lists.blacklist[addr]) {
                revert BlacklistedAddress(addr);
            }

            if (config.checkWhitelist && lists.whitelistEnabled && !lists.whitelist[addr]) {
                revert NotWhitelisted(addr);
            }
        }
    }

    /// @notice Check if address is a contract
    /// @param addr Address to check
    /// @return isContract True if address has code
    function isContract(address addr) internal view returns (bool) {
        return _isContract(addr);
    }

    /// @dev Internal contract check
    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /// @notice Validate two addresses are different
    /// @param addr1 First address
    /// @param addr2 Second address
    function requireDifferentAddresses(address addr1, address addr2) internal pure {
        if (addr1 == addr2) {
            revert SameAddress(addr1);
        }
    }

    /// @notice Add address to whitelist
    /// @param lists Address lists storage
    /// @param addr Address to whitelist
    function addToWhitelist(AddressLists storage lists, address addr) internal {
        lists.whitelist[addr] = true;
    }

    /// @notice Remove address from whitelist
    /// @param lists Address lists storage
    /// @param addr Address to remove
    function removeFromWhitelist(AddressLists storage lists, address addr) internal {
        lists.whitelist[addr] = false;
    }

    /// @notice Add address to blacklist
    /// @param lists Address lists storage
    /// @param addr Address to blacklist
    function addToBlacklist(AddressLists storage lists, address addr) internal {
        lists.blacklist[addr] = true;
    }

    /// @notice Remove address from blacklist
    /// @param lists Address lists storage
    /// @param addr Address to remove
    function removeFromBlacklist(AddressLists storage lists, address addr) internal {
        lists.blacklist[addr] = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AMOUNT VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate amount is not zero
    /// @param amount Amount to validate
    function requireNonZeroAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert ZeroAmount();
        }
    }

    /// @notice Validate amount with constraints
    /// @param amount Amount to validate
    /// @param constraints Amount constraints
    function validateAmount(uint256 amount, AmountConstraints memory constraints) internal pure {
        if (!constraints.allowZero && amount == 0) {
            revert ZeroAmount();
        }

        if (amount < constraints.minimum) {
            revert AmountTooSmall(amount, constraints.minimum);
        }

        if (constraints.maximum > 0 && amount > constraints.maximum) {
            revert AmountTooLarge(amount, constraints.maximum);
        }
    }

    /// @notice Validate amount is within range
    /// @param amount Amount to validate
    /// @param min Minimum value
    /// @param max Maximum value
    function requireAmountInRange(uint256 amount, uint256 min, uint256 max) internal pure {
        if (min > max) {
            revert InvalidRange(min, max);
        }
        if (amount < min || amount > max) {
            revert ValueOutOfRange(amount, min, max);
        }
    }

    /// @notice Validate percentage in basis points
    /// @param bps Basis points value
    function requireValidBps(uint256 bps) internal pure {
        if (bps > MAX_BPS) {
            revert InvalidPercentage(bps);
        }
    }

    /// @notice Validate percentage in basis points with custom max
    /// @param bps Basis points value
    /// @param maxBps Maximum allowed basis points
    function requireValidBps(uint256 bps, uint256 maxBps) internal pure {
        if (bps > maxBps) {
            revert InvalidPercentage(bps);
        }
    }

    /// @notice Validate balance is sufficient
    /// @param required Required amount
    /// @param available Available amount
    function requireSufficientBalance(uint256 required, uint256 available) internal pure {
        if (required > available) {
            revert InsufficientBalance(required, available);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate deadline has not expired
    /// @param deadline Deadline timestamp
    function requireValidDeadline(uint256 deadline) internal view {
        if (deadline < block.timestamp) {
            revert DeadlineExpired(deadline, block.timestamp);
        }
    }

    /// @notice Validate timestamp with constraints
    /// @param timestamp Timestamp to validate
    /// @param constraints Time constraints
    function validateTimestamp(uint256 timestamp, TimeConstraints memory constraints) internal view {
        if (timestamp < constraints.minTimestamp) {
            revert TimestampTooOld(timestamp, constraints.minTimestamp);
        }

        if (timestamp > constraints.maxTimestamp) {
            revert TimestampInFuture(timestamp);
        }

        if (constraints.maxAge > 0 && block.timestamp > timestamp + constraints.maxAge) {
            revert TimestampTooOld(timestamp, constraints.maxAge);
        }
    }

    /// @notice Validate timestamp is not in the future
    /// @param timestamp Timestamp to validate
    function requireNotFutureTimestamp(uint256 timestamp) internal view {
        if (timestamp > block.timestamp) {
            revert TimestampInFuture(timestamp);
        }
    }

    /// @notice Validate timestamp is recent enough
    /// @param timestamp Timestamp to validate
    /// @param maxAge Maximum age in seconds
    function requireRecentTimestamp(uint256 timestamp, uint256 maxAge) internal view {
        if (block.timestamp > timestamp + maxAge) {
            revert TimestampTooOld(timestamp, maxAge);
        }
    }

    /// @notice Validate duration is within bounds
    /// @param duration Duration to validate
    /// @param minDuration Minimum duration
    /// @param maxDuration Maximum duration
    function requireValidDuration(
        uint256 duration,
        uint256 minDuration,
        uint256 maxDuration
    ) internal pure {
        if (duration < minDuration || duration > maxDuration) {
            revert ValueOutOfRange(duration, minDuration, maxDuration);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNATURE VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate ECDSA signature
    /// @param params Signature parameters
    /// @return isValid True if signature is valid
    function validateSignature(SignatureParams memory params) internal view returns (bool isValid) {
        if (params.deadline > 0 && block.timestamp > params.deadline) {
            revert SignatureExpired();
        }

        address recovered = ecrecover(params.hash, params.v, params.r, params.s);

        if (recovered == address(0)) {
            revert InvalidSignature();
        }

        return recovered == params.expectedSigner;
    }

    /// @notice Validate EIP-712 signature
    /// @param domainSeparator Domain separator
    /// @param structHash Struct hash
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    /// @param expectedSigner Expected signer
    function validateEIP712Signature(
        bytes32 domainSeparator,
        bytes32 structHash,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address expectedSigner
    ) internal pure {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        address recovered = ecrecover(digest, v, r, s);

        if (recovered == address(0) || recovered != expectedSigner) {
            revert InvalidSignature();
        }
    }

    /// @notice Validate EIP-1271 contract signature
    /// @param signer Contract signer
    /// @param hash Message hash
    /// @param signature Signature bytes
    /// @return isValid True if signature is valid
    function validateContractSignature(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool isValid) {
        if (!_isContract(signer)) {
            return false;
        }

        (bool success, bytes memory result) = signer.staticcall(
            abi.encodeWithSelector(EIP1271_MAGIC_VALUE, hash, signature)
        );

        if (!success || result.length < 32) {
            return false;
        }

        bytes4 returnValue = abi.decode(result, (bytes4));
        return returnValue == EIP1271_MAGIC_VALUE;
    }

    /// @notice Recover signer from signature
    /// @param hash Message hash
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    /// @return signer Recovered signer address
    function recoverSigner(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address signer) {
        signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            revert InvalidSignature();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MERKLE PROOF VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify merkle proof
    /// @param proof Merkle proof
    /// @param root Merkle root
    /// @param leaf Leaf to verify
    /// @return isValid True if proof is valid
    function verifyMerkleProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool isValid) {
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

    /// @notice Require valid merkle proof
    /// @param proof Merkle proof
    /// @param root Merkle root
    /// @param leaf Leaf to verify
    function requireValidMerkleProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure {
        if (!verifyMerkleProof(proof, root, leaf)) {
            revert InvalidMerkleProof();
        }
    }

    /// @notice Compute merkle leaf for address and amount
    /// @param account Account address
    /// @param amount Amount value
    /// @return leaf Computed leaf hash
    function computeMerkleLeaf(
        address account,
        uint256 amount
    ) internal pure returns (bytes32 leaf) {
        return keccak256(abi.encodePacked(account, amount));
    }

    /// @notice Compute merkle leaf for multiple values
    /// @param data Encoded data
    /// @return leaf Computed leaf hash
    function computeMerkleLeafFromData(bytes memory data) internal pure returns (bytes32 leaf) {
        return keccak256(data);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ARRAY VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate array length
    /// @param length Array length
    /// @param maxLength Maximum allowed length
    function requireValidArrayLength(uint256 length, uint256 maxLength) internal pure {
        if (length > maxLength) {
            revert InvalidArrayLength(length);
        }
    }

    /// @notice Validate arrays have matching lengths
    /// @param length1 First array length
    /// @param length2 Second array length
    function requireMatchingArrayLengths(uint256 length1, uint256 length2) internal pure {
        if (length1 != length2) {
            revert ArrayLengthMismatch(length1, length2);
        }
    }

    /// @notice Validate array is not empty
    /// @param length Array length
    function requireNonEmptyArray(uint256 length) internal pure {
        if (length == 0) {
            revert InvalidArrayLength(0);
        }
    }

    /// @notice Check for duplicates in bytes32 array
    /// @param array Array to check
    /// @return hasDuplicates True if duplicates exist
    function hasDuplicates(bytes32[] memory array) internal pure returns (bool) {
        for (uint256 i; i < array.length;) {
            for (uint256 j = i + 1; j < array.length;) {
                if (array[i] == array[j]) {
                    return true;
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
        return false;
    }

    /// @notice Check for duplicates in address array
    /// @param array Array to check
    /// @return hasDuplicates True if duplicates exist
    function hasDuplicateAddresses(address[] memory array) internal pure returns (bool) {
        for (uint256 i; i < array.length;) {
            for (uint256 j = i + 1; j < array.length;) {
                if (array[i] == array[j]) {
                    return true;
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
        return false;
    }

    /// @notice Require no duplicates in array
    /// @param array Array to check
    function requireNoDuplicates(bytes32[] memory array) internal pure {
        for (uint256 i; i < array.length;) {
            for (uint256 j = i + 1; j < array.length;) {
                if (array[i] == array[j]) {
                    revert DuplicateEntry(array[i]);
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate price against oracle with deviation check
    /// @param params Price validation parameters
    function validatePrice(PriceValidation memory params) internal view {
        // Check staleness
        if (params.maxStaleness > 0) {
            if (block.timestamp > params.lastUpdate + params.maxStaleness) {
                revert TimestampTooOld(params.lastUpdate, params.maxStaleness);
            }
        }

        // Check deviation
        if (params.oraclePrice > 0 && params.maxDeviationBps > 0) {
            uint256 deviation = _calculateDeviation(params.spotPrice, params.oraclePrice);
            if (deviation > params.maxDeviationBps) {
                revert PriceDeviationExceeded(params.spotPrice, params.oraclePrice, params.maxDeviationBps);
            }
        }
    }

    /// @notice Calculate price deviation in basis points
    /// @param price1 First price
    /// @param price2 Second price
    /// @return deviationBps Deviation in basis points
    function calculatePriceDeviation(
        uint256 price1,
        uint256 price2
    ) internal pure returns (uint256 deviationBps) {
        return _calculateDeviation(price1, price2);
    }

    /// @dev Internal deviation calculation
    function _calculateDeviation(uint256 a, uint256 b) private pure returns (uint256) {
        if (a == 0 || b == 0) return MAX_BPS;

        uint256 diff = a > b ? a - b : b - a;
        uint256 base = a > b ? b : a;

        return (diff * BPS_DENOMINATOR) / base;
    }

    /// @notice Validate slippage is within tolerance
    /// @param expected Expected amount
    /// @param actual Actual amount
    /// @param toleranceBps Tolerance in basis points
    function validateSlippage(
        uint256 expected,
        uint256 actual,
        uint256 toleranceBps
    ) internal pure {
        if (expected == 0) return;

        uint256 minAcceptable = (expected * (BPS_DENOMINATOR - toleranceBps)) / BPS_DENOMINATOR;

        if (actual < minAcceptable) {
            revert SlippageExceeded(expected, actual, toleranceBps);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN PAIR VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate token pair
    /// @param token0 First token
    /// @param token1 Second token
    function validateTokenPair(address token0, address token1) internal pure {
        if (token0 == address(0) || token1 == address(0)) {
            revert ZeroAddress();
        }
        if (token0 == token1) {
            revert InvalidTokenPair(token0, token1);
        }
    }

    /// @notice Sort token pair (for consistent ordering)
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @return token0 Smaller address
    /// @return token1 Larger address
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) {
            revert InvalidTokenPair(tokenA, tokenB);
        }
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert ZeroAddress();
        }
    }

    /// @notice Check if address is ETH placeholder
    /// @param token Token address to check
    /// @return isEth True if address represents ETH
    function isETH(address token) internal pure returns (bool) {
        return token == ETH_ADDRESS || token == address(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ORDER VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate order parameters
    /// @param order Order validation parameters
    function validateOrder(OrderValidation memory order) internal view {
        // Validate addresses
        requireNonZeroAddress(order.maker);
        requireNonZeroAddress(order.tokenIn);
        requireNonZeroAddress(order.tokenOut);

        // Validate different tokens
        if (order.tokenIn == order.tokenOut) {
            revert InvalidTokenPair(order.tokenIn, order.tokenOut);
        }

        // Validate amounts
        requireNonZeroAmount(order.amountIn);
        requireNonZeroAmount(order.amountOut);

        // Validate deadline
        requireValidDeadline(order.deadline);
    }

    /// @notice Validate swap parameters
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param minAmountOut Minimum output amount
    /// @param deadline Swap deadline
    function validateSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal view {
        validateTokenPair(tokenIn, tokenOut);
        requireNonZeroAmount(amountIn);
        requireNonZeroAmount(minAmountOut);
        requireValidDeadline(deadline);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHAIN VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate chain ID matches current chain
    /// @param chainId Chain ID to validate
    function requireCurrentChain(uint256 chainId) internal view {
        if (chainId != block.chainid) {
            revert InvalidChainId(chainId);
        }
    }

    /// @notice Get current chain ID
    /// @return chainId Current chain ID
    function getChainId() internal view returns (uint256 chainId) {
        return block.chainid;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NONCE VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate nonce matches expected value
    /// @param provided Provided nonce
    /// @param expected Expected nonce
    function validateNonce(uint256 provided, uint256 expected) internal pure {
        if (provided != expected) {
            revert InvalidNonce(provided, expected);
        }
    }

    /// @notice Validate and increment nonce
    /// @param currentNonce Current nonce storage
    /// @param providedNonce Provided nonce
    /// @return newNonce Incremented nonce
    function validateAndIncrementNonce(
        uint256 currentNonce,
        uint256 providedNonce
    ) internal pure returns (uint256 newNonce) {
        if (providedNonce != currentNonce) {
            revert InvalidNonce(providedNonce, currentNonce);
        }
        unchecked {
            newNonce = currentNonce + 1;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SELECTOR VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate function selector
    /// @param selector Selector to validate
    /// @param allowedSelectors Array of allowed selectors
    function validateSelector(
        bytes4 selector,
        bytes4[] memory allowedSelectors
    ) internal pure {
        for (uint256 i; i < allowedSelectors.length;) {
            if (selector == allowedSelectors[i]) {
                return;
            }
            unchecked { ++i; }
        }
        revert InvalidSelector(selector);
    }

    /// @notice Extract selector from calldata
    /// @param data Calldata bytes
    /// @return selector Function selector
    function extractSelector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            revert InvalidSelector(bytes4(0));
        }
        assembly {
            selector := mload(add(data, 32))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Batch validate multiple conditions
    /// @param conditions Array of boolean conditions
    /// @return allValid True if all conditions are true
    function validateAll(bool[] memory conditions) internal pure returns (bool allValid) {
        for (uint256 i; i < conditions.length;) {
            if (!conditions[i]) {
                return false;
            }
            unchecked { ++i; }
        }
        return true;
    }

    /// @notice Batch validate - returns on first failure
    /// @param conditions Array of boolean conditions
    /// @return failedIndex Index of first failed condition (type(uint256).max if all pass)
    function validateAllWithIndex(
        bool[] memory conditions
    ) internal pure returns (uint256 failedIndex) {
        for (uint256 i; i < conditions.length;) {
            if (!conditions[i]) {
                return i;
            }
            unchecked { ++i; }
        }
        return type(uint256).max;
    }

    /// @notice Create validation result
    /// @param isValid Whether validation passed
    /// @param errorCode Error code if failed
    /// @param message Error message if failed
    /// @return result Validation result struct
    function createValidationResult(
        bool isValid,
        bytes32 errorCode,
        string memory message
    ) internal pure returns (ValidationResult memory result) {
        result.isValid = isValid;
        result.errorCode = errorCode;
        result.message = message;
    }
}
