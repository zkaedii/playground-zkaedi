// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title HardenedSecurityLib
 * @notice Advanced hardened security utilities for smart contracts
 * @dev Provides multi-layered security mechanisms including rate limiting,
 *      signature validation, anti-manipulation checks, and emergency controls
 */
library HardenedSecurityLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum rate limit window (30 days)
    uint256 internal constant MAX_RATE_WINDOW = 30 days;

    /// @dev Minimum cooldown period (1 minute)
    uint256 internal constant MIN_COOLDOWN = 1 minutes;

    /// @dev Maximum manipulation threshold (50%)
    uint256 internal constant MAX_MANIPULATION_THRESHOLD = 5000;

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev EIP-712 domain separator typehash
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Permit typehash for gasless approvals
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev Action authorization typehash
    bytes32 internal constant ACTION_TYPEHASH =
        keccak256("Action(address actor,bytes32 actionHash,uint256 nonce,uint256 deadline)");

    /// @dev Multi-sig approval typehash
    bytes32 internal constant MULTISIG_TYPEHASH =
        keccak256("MultiSig(bytes32 proposalId,address[] signers,uint256 threshold,uint256 deadline)");

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error RateLimitExceeded(address account, uint256 current, uint256 limit);
    error CooldownNotExpired(address account, uint256 remainingTime);
    error InvalidSignature();
    error SignatureExpired(uint256 deadline, uint256 currentTime);
    error NonceAlreadyUsed(address account, uint256 nonce);
    error InvalidNonce(address account, uint256 expected, uint256 provided);
    error ManipulationDetected(uint256 previousValue, uint256 currentValue, uint256 threshold);
    error UnauthorizedCaller(address caller, address expected);
    error EmergencyModeActive();
    error EmergencyModeNotActive();
    error InvalidThreshold(uint256 provided, uint256 max);
    error InsufficientSignatures(uint256 provided, uint256 required);
    error DuplicateSigner(address signer);
    error InvalidSigner(address signer);
    error ActionAlreadyExecuted(bytes32 actionId);
    error ActionNotFound(bytes32 actionId);
    error TimelockNotExpired(uint256 unlockTime, uint256 currentTime);
    error InvalidWindow(uint256 window);
    error ZeroAddress();
    error InvalidProof();
    error ReplayAttackDetected(bytes32 txHash);
    error FlashLoanDetected(uint256 blockNumber);
    error SandwichAttackDetected(uint256 slippage);
    error PriceManipulationDetected(uint256 spotPrice, uint256 twapPrice);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Rate limiter configuration and state
    struct RateLimiter {
        uint256 maxOperations;
        uint256 windowDuration;
        uint256 windowStart;
        uint256 operationCount;
    }

    /// @notice Cooldown tracker for accounts
    struct CooldownTracker {
        uint256 cooldownDuration;
        mapping(address => uint256) lastAction;
    }

    /// @notice Nonce manager for replay protection
    struct NonceManager {
        mapping(address => uint256) nonces;
        mapping(address => mapping(uint256 => bool)) usedNonces;
    }

    /// @notice Anti-manipulation state tracker
    struct ManipulationGuard {
        uint256 lastValue;
        uint256 lastUpdateBlock;
        uint256 thresholdBps;
        uint256 minBlockDelay;
    }

    /// @notice Emergency mode state
    struct EmergencyState {
        bool isActive;
        uint256 activatedAt;
        address activatedBy;
        bytes32 reason;
    }

    /// @notice Multi-signature proposal
    struct MultiSigProposal {
        bytes32 actionHash;
        uint256 threshold;
        uint256 deadline;
        uint256 approvalCount;
        bool executed;
        mapping(address => bool) hasApproved;
    }

    /// @notice Timelock configuration
    struct TimelockConfig {
        uint256 delay;
        uint256 gracePeriod;
        mapping(bytes32 => uint256) queuedAt;
        mapping(bytes32 => bool) executed;
    }

    /// @notice Flash loan protection state
    struct FlashLoanGuard {
        mapping(address => uint256) lastTxBlock;
        uint256 blockDelay;
    }

    /// @notice Sandwich attack protection
    struct SandwichGuard {
        uint256 maxSlippageBps;
        mapping(bytes32 => uint256) pendingTxPrices;
    }

    /// @notice TWAP oracle state for manipulation detection
    struct TWAPState {
        uint256 cumulativePrice;
        uint256 lastUpdateTime;
        uint256 lastPrice;
        uint256 twapWindow;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RATE LIMITING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize a rate limiter
    /// @param limiter The rate limiter storage
    /// @param maxOps Maximum operations per window
    /// @param windowDuration Duration of the rate limit window
    function initRateLimiter(
        RateLimiter storage limiter,
        uint256 maxOps,
        uint256 windowDuration
    ) internal {
        if (windowDuration == 0 || windowDuration > MAX_RATE_WINDOW) {
            revert InvalidWindow(windowDuration);
        }
        limiter.maxOperations = maxOps;
        limiter.windowDuration = windowDuration;
        limiter.windowStart = block.timestamp;
        limiter.operationCount = 0;
    }

    /// @notice Check and consume rate limit
    /// @param limiter The rate limiter storage
    /// @param account The account performing the operation
    function consumeRateLimit(RateLimiter storage limiter, address account) internal {
        _resetWindowIfExpired(limiter);

        if (limiter.operationCount >= limiter.maxOperations) {
            revert RateLimitExceeded(account, limiter.operationCount, limiter.maxOperations);
        }

        unchecked {
            ++limiter.operationCount;
        }
    }

    /// @notice Check if rate limit is available without consuming
    /// @param limiter The rate limiter storage
    /// @return available True if operation is allowed
    function isRateLimitAvailable(RateLimiter storage limiter) internal view returns (bool available) {
        uint256 effectiveCount = limiter.operationCount;

        if (block.timestamp >= limiter.windowStart + limiter.windowDuration) {
            effectiveCount = 0;
        }

        return effectiveCount < limiter.maxOperations;
    }

    /// @notice Get remaining operations in current window
    /// @param limiter The rate limiter storage
    /// @return remaining Number of operations remaining
    function getRemainingOperations(RateLimiter storage limiter) internal view returns (uint256 remaining) {
        uint256 effectiveCount = limiter.operationCount;

        if (block.timestamp >= limiter.windowStart + limiter.windowDuration) {
            effectiveCount = 0;
        }

        return limiter.maxOperations > effectiveCount ? limiter.maxOperations - effectiveCount : 0;
    }

    /// @dev Reset window if expired
    function _resetWindowIfExpired(RateLimiter storage limiter) private {
        if (block.timestamp >= limiter.windowStart + limiter.windowDuration) {
            limiter.windowStart = block.timestamp;
            limiter.operationCount = 0;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COOLDOWN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize cooldown tracker
    /// @param tracker The cooldown tracker storage
    /// @param duration Cooldown duration in seconds
    function initCooldown(CooldownTracker storage tracker, uint256 duration) internal {
        if (duration < MIN_COOLDOWN) {
            duration = MIN_COOLDOWN;
        }
        tracker.cooldownDuration = duration;
    }

    /// @notice Check and start cooldown for an account
    /// @param tracker The cooldown tracker storage
    /// @param account The account to check
    function enforceCooldown(CooldownTracker storage tracker, address account) internal {
        uint256 lastAction = tracker.lastAction[account];

        if (lastAction != 0) {
            uint256 cooldownEnd = lastAction + tracker.cooldownDuration;
            if (block.timestamp < cooldownEnd) {
                revert CooldownNotExpired(account, cooldownEnd - block.timestamp);
            }
        }

        tracker.lastAction[account] = block.timestamp;
    }

    /// @notice Check if cooldown has expired for an account
    /// @param tracker The cooldown tracker storage
    /// @param account The account to check
    /// @return expired True if cooldown has expired
    function isCooldownExpired(
        CooldownTracker storage tracker,
        address account
    ) internal view returns (bool expired) {
        uint256 lastAction = tracker.lastAction[account];
        if (lastAction == 0) return true;
        return block.timestamp >= lastAction + tracker.cooldownDuration;
    }

    /// @notice Get remaining cooldown time
    /// @param tracker The cooldown tracker storage
    /// @param account The account to check
    /// @return remaining Seconds until cooldown expires
    function getRemainingCooldown(
        CooldownTracker storage tracker,
        address account
    ) internal view returns (uint256 remaining) {
        uint256 lastAction = tracker.lastAction[account];
        if (lastAction == 0) return 0;

        uint256 cooldownEnd = lastAction + tracker.cooldownDuration;
        return block.timestamp >= cooldownEnd ? 0 : cooldownEnd - block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NONCE MANAGEMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current nonce for an account
    /// @param manager The nonce manager storage
    /// @param account The account to query
    /// @return nonce Current nonce value
    function getCurrentNonce(
        NonceManager storage manager,
        address account
    ) internal view returns (uint256 nonce) {
        return manager.nonces[account];
    }

    /// @notice Consume and increment nonce (sequential)
    /// @param manager The nonce manager storage
    /// @param account The account
    /// @param providedNonce The nonce provided by caller
    function consumeNonceSequential(
        NonceManager storage manager,
        address account,
        uint256 providedNonce
    ) internal {
        uint256 currentNonce = manager.nonces[account];
        if (providedNonce != currentNonce) {
            revert InvalidNonce(account, currentNonce, providedNonce);
        }
        unchecked {
            manager.nonces[account] = currentNonce + 1;
        }
    }

    /// @notice Consume nonce (non-sequential, bitmap-based)
    /// @param manager The nonce manager storage
    /// @param account The account
    /// @param nonce The nonce to consume
    function consumeNonceNonSequential(
        NonceManager storage manager,
        address account,
        uint256 nonce
    ) internal {
        if (manager.usedNonces[account][nonce]) {
            revert NonceAlreadyUsed(account, nonce);
        }
        manager.usedNonces[account][nonce] = true;
    }

    /// @notice Check if a non-sequential nonce has been used
    /// @param manager The nonce manager storage
    /// @param account The account
    /// @param nonce The nonce to check
    /// @return used True if nonce has been used
    function isNonceUsed(
        NonceManager storage manager,
        address account,
        uint256 nonce
    ) internal view returns (bool used) {
        return manager.usedNonces[account][nonce];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIGNATURE VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Build EIP-712 domain separator
    /// @param name Contract name
    /// @param version Contract version
    /// @return separator The domain separator hash
    function buildDomainSeparator(
        string memory name,
        string memory version
    ) internal view returns (bytes32 separator) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Recover signer from EIP-712 signature
    /// @param domainSeparator The domain separator
    /// @param structHash The struct hash
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    /// @return signer The recovered signer address
    function recoverSigner(
        bytes32 domainSeparator,
        bytes32 structHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address signer) {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) {
            revert InvalidSignature();
        }
    }

    /// @notice Verify action signature with deadline
    /// @param domainSeparator The domain separator
    /// @param actor Expected actor address
    /// @param actionHash Hash of the action
    /// @param nonce Action nonce
    /// @param deadline Signature deadline
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function verifyActionSignature(
        bytes32 domainSeparator,
        address actor,
        bytes32 actionHash,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        bytes32 structHash = keccak256(
            abi.encode(ACTION_TYPEHASH, actor, actionHash, nonce, deadline)
        );

        address signer = recoverSigner(domainSeparator, structHash, v, r, s);
        if (signer != actor) {
            revert InvalidSignature();
        }
    }

    /// @notice Validate permit signature (EIP-2612 style)
    /// @param domainSeparator The domain separator
    /// @param owner Token owner
    /// @param spender Spender address
    /// @param value Approved value
    /// @param nonce Owner's nonce
    /// @param deadline Permit deadline
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function validatePermit(
        bytes32 domainSeparator,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
        );

        address signer = recoverSigner(domainSeparator, structHash, v, r, s);
        if (signer != owner) {
            revert InvalidSignature();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ANTI-MANIPULATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize manipulation guard
    /// @param guard The manipulation guard storage
    /// @param initialValue Initial tracked value
    /// @param thresholdBps Maximum allowed change in basis points
    /// @param minBlockDelay Minimum blocks between updates
    function initManipulationGuard(
        ManipulationGuard storage guard,
        uint256 initialValue,
        uint256 thresholdBps,
        uint256 minBlockDelay
    ) internal {
        if (thresholdBps > MAX_MANIPULATION_THRESHOLD) {
            revert InvalidThreshold(thresholdBps, MAX_MANIPULATION_THRESHOLD);
        }
        guard.lastValue = initialValue;
        guard.lastUpdateBlock = block.number;
        guard.thresholdBps = thresholdBps;
        guard.minBlockDelay = minBlockDelay;
    }

    /// @notice Check value against manipulation threshold
    /// @param guard The manipulation guard storage
    /// @param newValue The new value to check
    function checkManipulation(ManipulationGuard storage guard, uint256 newValue) internal view {
        if (guard.lastValue == 0) return;

        uint256 change;
        if (newValue > guard.lastValue) {
            change = newValue - guard.lastValue;
        } else {
            change = guard.lastValue - newValue;
        }

        uint256 changePercentage = (change * BPS_DENOMINATOR) / guard.lastValue;

        if (changePercentage > guard.thresholdBps) {
            revert ManipulationDetected(guard.lastValue, newValue, guard.thresholdBps);
        }
    }

    /// @notice Update manipulation guard with new value
    /// @param guard The manipulation guard storage
    /// @param newValue The new value
    function updateManipulationGuard(ManipulationGuard storage guard, uint256 newValue) internal {
        checkManipulation(guard, newValue);

        if (block.number < guard.lastUpdateBlock + guard.minBlockDelay) {
            revert FlashLoanDetected(block.number);
        }

        guard.lastValue = newValue;
        guard.lastUpdateBlock = block.number;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize flash loan guard
    /// @param guard The flash loan guard storage
    /// @param blockDelay Required blocks between transactions
    function initFlashLoanGuard(FlashLoanGuard storage guard, uint256 blockDelay) internal {
        guard.blockDelay = blockDelay;
    }

    /// @notice Check and update flash loan protection
    /// @param guard The flash loan guard storage
    /// @param account The account to check
    function enforceFlashLoanProtection(FlashLoanGuard storage guard, address account) internal {
        uint256 lastBlock = guard.lastTxBlock[account];

        if (lastBlock != 0 && block.number < lastBlock + guard.blockDelay) {
            revert FlashLoanDetected(block.number);
        }

        guard.lastTxBlock[account] = block.number;
    }

    /// @notice Check if account is protected (without updating)
    /// @param guard The flash loan guard storage
    /// @param account The account to check
    /// @return isProtected True if sufficient blocks have passed
    function isFlashLoanProtected(
        FlashLoanGuard storage guard,
        address account
    ) internal view returns (bool isProtected) {
        uint256 lastBlock = guard.lastTxBlock[account];
        return lastBlock == 0 || block.number >= lastBlock + guard.blockDelay;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SANDWICH ATTACK PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize sandwich guard
    /// @param guard The sandwich guard storage
    /// @param maxSlippageBps Maximum allowed slippage in basis points
    function initSandwichGuard(SandwichGuard storage guard, uint256 maxSlippageBps) internal {
        guard.maxSlippageBps = maxSlippageBps;
    }

    /// @notice Check for sandwich attack based on price slippage
    /// @param guard The sandwich guard storage
    /// @param expectedPrice Expected execution price
    /// @param actualPrice Actual execution price
    function checkSandwichAttack(
        SandwichGuard storage guard,
        uint256 expectedPrice,
        uint256 actualPrice
    ) internal view {
        if (expectedPrice == 0) return;

        uint256 slippage;
        if (actualPrice > expectedPrice) {
            slippage = ((actualPrice - expectedPrice) * BPS_DENOMINATOR) / expectedPrice;
        } else {
            slippage = ((expectedPrice - actualPrice) * BPS_DENOMINATOR) / expectedPrice;
        }

        if (slippage > guard.maxSlippageBps) {
            revert SandwichAttackDetected(slippage);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TWAP ORACLE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize TWAP state
    /// @param state The TWAP state storage
    /// @param initialPrice Initial price
    /// @param window TWAP window duration
    function initTWAP(TWAPState storage state, uint256 initialPrice, uint256 window) internal {
        state.cumulativePrice = 0;
        state.lastUpdateTime = block.timestamp;
        state.lastPrice = initialPrice;
        state.twapWindow = window;
    }

    /// @notice Update TWAP with new price
    /// @param state The TWAP state storage
    /// @param newPrice New spot price
    function updateTWAP(TWAPState storage state, uint256 newPrice) internal {
        uint256 timeElapsed = block.timestamp - state.lastUpdateTime;

        if (timeElapsed > 0) {
            state.cumulativePrice += state.lastPrice * timeElapsed;
            state.lastUpdateTime = block.timestamp;
            state.lastPrice = newPrice;
        }
    }

    /// @notice Get current TWAP
    /// @param state The TWAP state storage
    /// @return twap The time-weighted average price
    function getTWAP(TWAPState storage state) internal view returns (uint256 twap) {
        uint256 timeElapsed = block.timestamp - state.lastUpdateTime;
        uint256 currentCumulative = state.cumulativePrice + (state.lastPrice * timeElapsed);

        uint256 totalTime = state.twapWindow;
        if (totalTime == 0) return state.lastPrice;

        return currentCumulative / totalTime;
    }

    /// @notice Check for price manipulation using TWAP
    /// @param state The TWAP state storage
    /// @param spotPrice Current spot price
    /// @param maxDeviationBps Maximum allowed deviation from TWAP
    function checkPriceManipulation(
        TWAPState storage state,
        uint256 spotPrice,
        uint256 maxDeviationBps
    ) internal view {
        uint256 twapPrice = getTWAP(state);
        if (twapPrice == 0) return;

        uint256 deviation;
        if (spotPrice > twapPrice) {
            deviation = ((spotPrice - twapPrice) * BPS_DENOMINATOR) / twapPrice;
        } else {
            deviation = ((twapPrice - spotPrice) * BPS_DENOMINATOR) / twapPrice;
        }

        if (deviation > maxDeviationBps) {
            revert PriceManipulationDetected(spotPrice, twapPrice);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY MODE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Activate emergency mode
    /// @param state The emergency state storage
    /// @param reason Reason for activation
    function activateEmergencyMode(EmergencyState storage state, bytes32 reason) internal {
        if (state.isActive) {
            revert EmergencyModeActive();
        }

        state.isActive = true;
        state.activatedAt = block.timestamp;
        state.activatedBy = msg.sender;
        state.reason = reason;
    }

    /// @notice Deactivate emergency mode
    /// @param state The emergency state storage
    function deactivateEmergencyMode(EmergencyState storage state) internal {
        if (!state.isActive) {
            revert EmergencyModeNotActive();
        }

        state.isActive = false;
        state.activatedAt = 0;
        state.activatedBy = address(0);
        state.reason = bytes32(0);
    }

    /// @notice Check if emergency mode is active
    /// @param state The emergency state storage
    /// @return active True if emergency mode is active
    function isEmergencyActive(EmergencyState storage state) internal view returns (bool active) {
        return state.isActive;
    }

    /// @notice Require emergency mode to be inactive
    /// @param state The emergency state storage
    function requireNotEmergency(EmergencyState storage state) internal view {
        if (state.isActive) {
            revert EmergencyModeActive();
        }
    }

    /// @notice Require emergency mode to be active
    /// @param state The emergency state storage
    function requireEmergency(EmergencyState storage state) internal view {
        if (!state.isActive) {
            revert EmergencyModeNotActive();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMELOCK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize timelock configuration
    /// @param config The timelock config storage
    /// @param delay Timelock delay
    /// @param gracePeriod Grace period after unlock
    function initTimelock(
        TimelockConfig storage config,
        uint256 delay,
        uint256 gracePeriod
    ) internal {
        config.delay = delay;
        config.gracePeriod = gracePeriod;
    }

    /// @notice Queue an action for timelock
    /// @param config The timelock config storage
    /// @param actionId Unique action identifier
    function queueAction(TimelockConfig storage config, bytes32 actionId) internal {
        if (config.queuedAt[actionId] != 0) {
            revert ActionAlreadyExecuted(actionId);
        }
        config.queuedAt[actionId] = block.timestamp;
    }

    /// @notice Execute a timelocked action
    /// @param config The timelock config storage
    /// @param actionId Action identifier
    function executeTimelocked(TimelockConfig storage config, bytes32 actionId) internal {
        uint256 queuedTime = config.queuedAt[actionId];

        if (queuedTime == 0) {
            revert ActionNotFound(actionId);
        }

        if (config.executed[actionId]) {
            revert ActionAlreadyExecuted(actionId);
        }

        uint256 unlockTime = queuedTime + config.delay;
        if (block.timestamp < unlockTime) {
            revert TimelockNotExpired(unlockTime, block.timestamp);
        }

        uint256 expiryTime = unlockTime + config.gracePeriod;
        if (block.timestamp > expiryTime) {
            revert SignatureExpired(expiryTime, block.timestamp);
        }

        config.executed[actionId] = true;
    }

    /// @notice Check if action can be executed
    /// @param config The timelock config storage
    /// @param actionId Action identifier
    /// @return canExecute True if action can be executed now
    function canExecuteTimelocked(
        TimelockConfig storage config,
        bytes32 actionId
    ) internal view returns (bool canExecute) {
        uint256 queuedTime = config.queuedAt[actionId];
        if (queuedTime == 0 || config.executed[actionId]) return false;

        uint256 unlockTime = queuedTime + config.delay;
        uint256 expiryTime = unlockTime + config.gracePeriod;

        return block.timestamp >= unlockTime && block.timestamp <= expiryTime;
    }

    /// @notice Cancel a queued action
    /// @param config The timelock config storage
    /// @param actionId Action identifier
    function cancelTimelocked(TimelockConfig storage config, bytes32 actionId) internal {
        if (config.queuedAt[actionId] == 0) {
            revert ActionNotFound(actionId);
        }
        if (config.executed[actionId]) {
            revert ActionAlreadyExecuted(actionId);
        }

        delete config.queuedAt[actionId];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HASH & UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Compute action hash from parameters
    /// @param target Target contract
    /// @param value ETH value
    /// @param data Call data
    /// @param salt Unique salt
    /// @return actionHash The computed hash
    function computeActionHash(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 salt
    ) internal pure returns (bytes32 actionHash) {
        return keccak256(abi.encode(target, value, keccak256(data), salt));
    }

    /// @notice Compute transaction hash for replay protection
    /// @param sender Transaction sender
    /// @param target Target address
    /// @param value ETH value
    /// @param data Call data
    /// @param nonce Transaction nonce
    /// @return txHash The transaction hash
    function computeTxHash(
        address sender,
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce
    ) internal view returns (bytes32 txHash) {
        return keccak256(abi.encode(sender, target, value, keccak256(data), nonce, block.chainid));
    }

    /// @notice Validate caller is expected address
    /// @param expected Expected caller address
    function requireCaller(address expected) internal view {
        if (msg.sender != expected) {
            revert UnauthorizedCaller(msg.sender, expected);
        }
    }

    /// @notice Validate address is not zero
    /// @param addr Address to validate
    function requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
    }

    /// @notice Validate multiple addresses are not zero
    /// @param addresses Array of addresses to validate
    function requireNonZeroAddresses(address[] memory addresses) internal pure {
        uint256 length = addresses.length;
        for (uint256 i; i < length;) {
            if (addresses[i] == address(0)) {
                revert ZeroAddress();
            }
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-SIG VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify multiple signatures for multi-sig validation
    /// @param domainSeparator Domain separator for EIP-712
    /// @param structHash Struct hash to sign
    /// @param signers Expected signers array
    /// @param signatures Packed signatures (65 bytes each)
    /// @param threshold Minimum required signatures
    function verifyMultiSignatures(
        bytes32 domainSeparator,
        bytes32 structHash,
        address[] memory signers,
        bytes memory signatures,
        uint256 threshold
    ) internal pure {
        if (signatures.length < threshold * 65) {
            revert InsufficientSignatures(signatures.length / 65, threshold);
        }

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        address lastSigner = address(0);
        uint256 validCount;

        for (uint256 i; i < threshold;) {
            uint256 offset = i * 65;

            uint8 v;
            bytes32 r;
            bytes32 s;

            assembly {
                r := mload(add(signatures, add(32, offset)))
                s := mload(add(signatures, add(64, offset)))
                v := byte(0, mload(add(signatures, add(96, offset))))
            }

            address signer = ecrecover(digest, v, r, s);

            if (signer == address(0)) {
                revert InvalidSignature();
            }

            // Ensure signers are in ascending order (no duplicates)
            if (signer <= lastSigner) {
                revert DuplicateSigner(signer);
            }

            // Verify signer is in allowed list
            bool isValidSigner = false;
            for (uint256 j; j < signers.length;) {
                if (signers[j] == signer) {
                    isValidSigner = true;
                    break;
                }
                unchecked { ++j; }
            }

            if (!isValidSigner) {
                revert InvalidSigner(signer);
            }

            lastSigner = signer;
            unchecked { ++validCount; ++i; }
        }

        if (validCount < threshold) {
            revert InsufficientSignatures(validCount, threshold);
        }
    }
}
