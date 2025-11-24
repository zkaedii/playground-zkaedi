// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/HardenedSecurityLib.sol";
import "../utils/ValidatorsLib.sol";
import "../utils/StakingLib.sol";
import "../utils/RewardLib.sol";
import "../utils/RefundersLib.sol";

/**
 * @title DeFiVault
 * @notice Production-ready DeFi vault demonstrating integration of multiple utility libraries
 * @dev Combines security, staking, rewards, and refund functionality into a cohesive vault
 */
contract DeFiVault {
    using HardenedSecurityLib for *;
    using ValidatorsLib for *;
    using StakingLib for StakingLib.StakingPool;
    using RewardLib for *;
    using RefundersLib for RefundersLib.RefundRegistry;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Staking pool storage
    StakingLib.StakingPool private stakingPool;

    /// @notice Reward pool storage
    RewardLib.RewardPool private rewardPool;

    /// @notice Refund registry
    RefundersLib.RefundRegistry private refundRegistry;

    /// @notice Rate limiter for deposits
    HardenedSecurityLib.RateLimiter private depositLimiter;

    /// @notice Cooldown tracker for withdrawals
    HardenedSecurityLib.CooldownTracker private withdrawalCooldown;

    /// @notice Nonce manager for signatures
    HardenedSecurityLib.NonceManager private nonceManager;

    /// @notice Emergency state
    HardenedSecurityLib.EmergencyState private emergencyState;

    /// @notice Flash loan protection
    HardenedSecurityLib.FlashLoanGuard private flashLoanGuard;

    /// @notice Address validation lists
    ValidatorsLib.AddressLists private addressLists;

    /// @notice Vault token
    address public immutable vaultToken;

    /// @notice Reward token
    address public immutable rewardToken;

    /// @notice Owner address
    address public owner;

    /// @notice EIP-712 domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyActivated(address indexed activator, bytes32 reason);
    event EmergencyDeactivated(address indexed deactivator);
    event RefundCreated(bytes32 indexed refundId, address indexed recipient, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error Unauthorized();
    error InvalidAmount();
    error TransferFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier notInEmergency() {
        emergencyState.requireNotEmergency();
        _;
    }

    modifier flashLoanProtected() {
        flashLoanGuard.enforceFlashLoanProtection(msg.sender);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _vaultToken,
        address _rewardToken,
        uint256 _rewardRate
    ) {
        ValidatorsLib.requireNonZeroAddress(_vaultToken);
        ValidatorsLib.requireNonZeroAddress(_rewardToken);

        vaultToken = _vaultToken;
        rewardToken = _rewardToken;
        owner = msg.sender;

        // Initialize staking pool
        stakingPool.initializePool(
            _vaultToken,
            _rewardToken,
            _rewardRate,
            type(uint256).max // No cap
        );

        // Initialize reward pool
        rewardPool.initializePool(block.timestamp, block.timestamp + 365 days);
        rewardPool.addRewardToken(_rewardToken, _rewardRate);

        // Initialize security mechanisms
        depositLimiter.initRateLimiter(100, 1 hours); // 100 deposits per hour
        withdrawalCooldown.initCooldown(1 days); // 1 day cooldown
        flashLoanGuard.initFlashLoanGuard(1); // 1 block delay

        // Initialize refund registry
        refundRegistry.initializePool(address(0)); // ETH refunds
        refundRegistry.initializePool(_vaultToken);

        // Build domain separator
        DOMAIN_SEPARATOR = HardenedSecurityLib.buildDomainSeparator(
            "DeFiVault",
            "1"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit tokens into the vault
     * @param amount Amount to deposit
     * @return shares Shares received
     */
    function deposit(uint256 amount)
        external
        notInEmergency
        flashLoanProtected
        returns (uint256 shares)
    {
        // Validate input
        ValidatorsLib.requireNonZeroAmount(amount);

        // Check rate limit
        depositLimiter.consumeRateLimit(msg.sender);

        // Validate sender
        ValidatorsLib.AddressConfig memory config = ValidatorsLib.AddressConfig({
            allowZero: false,
            allowContract: true,
            allowEOA: true,
            checkBlacklist: true,
            checkWhitelist: false
        });
        ValidatorsLib.validateAddress(msg.sender, config, addressLists);

        // Perform stake
        shares = stakingPool.stake(msg.sender, amount);

        // Transfer tokens (assumes approval)
        // In production: use SafeERC20
        (bool success,) = vaultToken.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                amount
            )
        );
        if (!success) revert TransferFailed();

        emit Deposited(msg.sender, amount, shares);
    }

    /**
     * @notice Deposit with permit (gasless approval)
     * @param amount Amount to deposit
     * @param deadline Permit deadline
     * @param v Signature v
     * @param r Signature r
     * @param s Signature s
     */
    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notInEmergency flashLoanProtected returns (uint256 shares) {
        ValidatorsLib.requireNonZeroAmount(amount);
        ValidatorsLib.requireValidDeadline(deadline);

        // Validate permit signature
        uint256 nonce = nonceManager.getCurrentNonce(msg.sender);
        HardenedSecurityLib.validatePermit(
            DOMAIN_SEPARATOR,
            msg.sender,
            address(this),
            amount,
            nonce,
            deadline,
            v, r, s
        );
        nonceManager.consumeNonceSequential(msg.sender, nonce);

        // Perform deposit
        depositLimiter.consumeRateLimit(msg.sender);
        shares = stakingPool.stake(msg.sender, amount);

        emit Deposited(msg.sender, amount, shares);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WITHDRAWAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initiate withdrawal cooldown
     * @param amount Amount to withdraw
     */
    function initiateWithdrawal(uint256 amount) external notInEmergency {
        ValidatorsLib.requireNonZeroAmount(amount);
        stakingPool.initiateCooldown(msg.sender, amount);
    }

    /**
     * @notice Complete withdrawal after cooldown
     * @return amount Amount withdrawn
     * @return rewards Rewards claimed
     */
    function completeWithdrawal()
        external
        notInEmergency
        flashLoanProtected
        returns (uint256 amount, uint256 rewards)
    {
        // Enforce withdrawal cooldown
        withdrawalCooldown.enforceCooldown(msg.sender);

        // Complete unstake
        (amount, rewards) = stakingPool.unstake(msg.sender);

        // Transfer tokens back
        if (amount > 0) {
            (bool success,) = vaultToken.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    amount
                )
            );
            if (!success) revert TransferFailed();
        }

        // Transfer rewards
        if (rewards > 0) {
            (bool success,) = rewardToken.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    rewards
                )
            );
            if (!success) revert TransferFailed();
        }

        emit Withdrawn(msg.sender, amount, rewards);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARDS FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim pending rewards
     * @return rewards Amount of rewards claimed
     */
    function claimRewards() external notInEmergency returns (uint256 rewards) {
        rewards = stakingPool.claimRewards(msg.sender);

        if (rewards > 0) {
            (bool success,) = rewardToken.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    rewards
                )
            );
            if (!success) revert TransferFailed();
        }

        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @notice Get pending rewards for user
     * @param user User address
     * @return pending Pending reward amount
     */
    function getPendingRewards(address user) external view returns (uint256 pending) {
        return stakingPool.pendingRewards(user);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFUND FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a refund for failed transaction
     * @param recipient Refund recipient
     * @param token Token to refund
     * @param amount Refund amount
     * @param reason Reason for refund
     */
    function createRefund(
        address recipient,
        address token,
        uint256 amount,
        bytes32 reason
    ) external onlyOwner returns (bytes32 refundId) {
        refundId = refundRegistry.createRefund(
            recipient,
            token,
            amount,
            RefundersLib.RefundType.FailedTransaction,
            reason,
            30 days
        );
        refundRegistry.approveRefund(refundId);

        emit RefundCreated(refundId, recipient, amount);
    }

    /**
     * @notice Claim a refund
     * @param refundId Refund ID to claim
     */
    function claimRefund(bytes32 refundId) external {
        (address recipient, address token, uint256 amount) = refundRegistry.claimRefund(refundId);

        if (recipient != msg.sender) revert Unauthorized();

        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            (bool success,) = token.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    amount
                )
            );
            if (!success) revert TransferFailed();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Activate emergency mode
     * @param reason Reason for emergency
     */
    function activateEmergency(bytes32 reason) external onlyOwner {
        emergencyState.activateEmergencyMode(reason);
        emit EmergencyActivated(msg.sender, reason);
    }

    /**
     * @notice Deactivate emergency mode
     */
    function deactivateEmergency() external onlyOwner {
        emergencyState.deactivateEmergencyMode();
        emit EmergencyDeactivated(msg.sender);
    }

    /**
     * @notice Emergency withdraw (bypasses cooldown)
     */
    function emergencyWithdraw() external returns (uint256 amount) {
        emergencyState.requireEmergency();

        StakingLib.StakePosition storage position = stakingPool.getStakePosition(msg.sender);
        amount = position.amount;

        if (amount > 0) {
            // Direct withdrawal without rewards
            (bool success,) = vaultToken.call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    msg.sender,
                    amount
                )
            );
            if (!success) revert TransferFailed();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add address to blacklist
     * @param addr Address to blacklist
     */
    function addToBlacklist(address addr) external onlyOwner {
        ValidatorsLib.addToBlacklist(addressLists, addr);
    }

    /**
     * @notice Remove address from blacklist
     * @param addr Address to remove
     */
    function removeFromBlacklist(address addr) external onlyOwner {
        ValidatorsLib.removeFromBlacklist(addressLists, addr);
    }

    /**
     * @notice Update reward rate
     * @param newRate New reward rate per second
     */
    function setRewardRate(uint256 newRate) external onlyOwner {
        stakingPool.setRewardRate(newRate);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user staking stats
     * @param user User address
     * @return stats Staking statistics
     */
    function getUserStats(address user) external view returns (StakingLib.StakerStats memory stats) {
        return stakingPool.getStakerStats(user);
    }

    /**
     * @notice Check if emergency mode is active
     * @return active True if emergency mode is active
     */
    function isEmergencyActive() external view returns (bool active) {
        return emergencyState.isEmergencyActive();
    }

    /**
     * @notice Get remaining rate limit
     * @return remaining Remaining deposits in current window
     */
    function getRemainingDeposits() external view returns (uint256 remaining) {
        return depositLimiter.getRemainingOperations();
    }

    /**
     * @notice Get user's current nonce
     * @param user User address
     * @return nonce Current nonce
     */
    function getNonce(address user) external view returns (uint256 nonce) {
        return nonceManager.getCurrentNonce(user);
    }

    /**
     * @notice Check if user is blacklisted
     * @param user User address
     * @return blacklisted True if blacklisted
     */
    function isBlacklisted(address user) external view returns (bool blacklisted) {
        return addressLists.blacklist[user];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RECEIVE
    // ═══════════════════════════════════════════════════════════════════════════

    receive() external payable {
        refundRegistry.depositToPool(address(0), msg.value);
    }
}
