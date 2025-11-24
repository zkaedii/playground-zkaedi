// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VaultTemplate
 * @notice ERC-4626 compliant tokenized vault template
 * @dev Implements deposit/withdraw with shares, fees, and strategy pattern
 *
 * TEMPLATE INSTRUCTIONS:
 * 1. Search and replace "VaultTemplate" with your vault name
 * 2. Configure ASSET token address
 * 3. Set fee parameters and strategy address
 * 4. Customize yield generation logic
 * 5. Add additional strategies as needed
 */

import {AccessControlLib} from "../utils/AccessControlLib.sol";
import {PausableLib} from "../utils/PausableLib.sol";
import {ReentrancyGuardLib} from "../utils/ReentrancyGuardLib.sol";
import {MathUtils} from "../utils/MathUtils.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256);
    function harvest() external returns (uint256);
    function totalAssets() external view returns (uint256);
    function emergencyWithdraw() external;
}

contract VaultTemplate {
    using MathUtils for uint256;

    // ============ CONSTANTS ============
    uint256 public constant MAX_BPS = 10000;
    uint256 public constant MAX_WITHDRAWAL_FEE = 500;    // 5% max
    uint256 public constant MAX_PERFORMANCE_FEE = 2000;  // 20% max
    uint256 public constant MAX_MANAGEMENT_FEE = 300;    // 3% max annual

    // ============ ERRORS ============
    error ZeroAddress();
    error ZeroAmount();
    error ZeroShares();
    error InsufficientBalance(uint256 available, uint256 required);
    error InsufficientAllowance(uint256 available, uint256 required);
    error SlippageExceeded(uint256 expected, uint256 actual);
    error TransferFailed();
    error VaultPaused();
    error WithdrawalLocked(uint256 unlockTime);
    error DepositLimitExceeded(uint256 limit);
    error InvalidFee(uint256 fee);
    error StrategyNotSet();
    error EmergencyShutdown();

    // ============ STATE ============
    // ERC20 data for vault shares
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Vault data
    IERC20 public immutable asset;
    IStrategy public strategy;

    uint256 public depositLimit;
    uint256 public withdrawalLockPeriod;
    mapping(address => uint256) public lastDepositTime;

    // Fee configuration
    uint256 public withdrawalFee;      // In basis points
    uint256 public performanceFee;     // In basis points
    uint256 public managementFee;      // In basis points (annual)
    address public feeRecipient;
    uint256 public lastFeeCollection;

    // Emergency state
    bool public emergencyShutdown;
    uint256 public totalDebt;          // Total assets deployed to strategy

    AccessControlLib.AccessControlStorage internal _accessControl;
    PausableLib.PauseState internal _pauseState;
    ReentrancyGuardLib.ReentrancyGuard internal _reentrancyGuard;

    // ============ EVENTS ============
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event FeesCollected(uint256 managementFee, uint256 performanceFee);
    event EmergencyShutdownActivated(address indexed activatedBy);
    event DepositLimitUpdated(uint256 newLimit);
    event Harvested(uint256 profit, uint256 fee);

    // ============ CONSTRUCTOR ============
    constructor(
        address admin,
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _depositLimit
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();

        asset = IERC20(_asset);
        name = _name;
        symbol = _symbol;
        decimals = IERC20(_asset).decimals();

        depositLimit = _depositLimit;
        feeRecipient = admin;
        lastFeeCollection = block.timestamp;

        // Default fees
        withdrawalFee = 10;      // 0.1%
        performanceFee = 1000;   // 10%
        managementFee = 200;     // 2% annual

        // Initialize access control
        AccessControlLib.initializeStandardRoles(_accessControl, admin);

        // Initialize reentrancy guard
        ReentrancyGuardLib.initialize(_reentrancyGuard);
    }

    // ============ ERC20 FUNCTIONS ============

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert InsufficientAllowance(currentAllowance, amount);
            }
            unchecked {
                allowance[from][msg.sender] = currentAllowance - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    // ============ ERC4626 CORE FUNCTIONS ============

    /**
     * @notice Deposit assets and receive shares
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        ReentrancyGuardLib.enter(_reentrancyGuard);
        _requireNotPaused();
        _requireNotShutdown();

        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Check deposit limit
        if (depositLimit > 0 && totalAssets() + assets > depositLimit) {
            revert DepositLimitExceeded(depositLimit);
        }

        shares = previewDeposit(assets);
        if (shares == 0) revert ZeroShares();

        // Transfer assets from sender
        if (!asset.transferFrom(msg.sender, address(this), assets)) {
            revert TransferFailed();
        }

        // Mint shares
        _mint(receiver, shares);

        // Track deposit time for withdrawal lock
        lastDepositTime[receiver] = block.timestamp;

        emit Deposit(msg.sender, receiver, assets, shares);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Mint exact shares by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets deposited
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        ReentrancyGuardLib.enter(_reentrancyGuard);
        _requireNotPaused();
        _requireNotShutdown();

        if (shares == 0) revert ZeroShares();
        if (receiver == address(0)) revert ZeroAddress();

        assets = previewMint(shares);
        if (assets == 0) revert ZeroAmount();

        // Check deposit limit
        if (depositLimit > 0 && totalAssets() + assets > depositLimit) {
            revert DepositLimitExceeded(depositLimit);
        }

        // Transfer assets from sender
        if (!asset.transferFrom(msg.sender, address(this), assets)) {
            revert TransferFailed();
        }

        // Mint shares
        _mint(receiver, shares);

        lastDepositTime[receiver] = block.timestamp;

        emit Deposit(msg.sender, receiver, assets, shares);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address whose shares to burn
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        ReentrancyGuardLib.enter(_reentrancyGuard);

        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Check withdrawal lock
        if (withdrawalLockPeriod > 0) {
            uint256 unlockTime = lastDepositTime[owner] + withdrawalLockPeriod;
            if (block.timestamp < unlockTime) {
                revert WithdrawalLocked(unlockTime);
            }
        }

        shares = previewWithdraw(assets);
        if (shares == 0) revert ZeroShares();

        // Check allowance if caller is not owner
        if (msg.sender != owner) {
            uint256 currentAllowance = allowance[owner][msg.sender];
            if (currentAllowance < shares) {
                revert InsufficientAllowance(currentAllowance, shares);
            }
            if (currentAllowance != type(uint256).max) {
                allowance[owner][msg.sender] = currentAllowance - shares;
            }
        }

        // Burn shares
        _burn(owner, shares);

        // Calculate and apply withdrawal fee
        uint256 fee = (assets * withdrawalFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - fee;

        // Ensure we have enough liquid assets
        _ensureLiquidity(assets);

        // Transfer assets
        if (!asset.transfer(receiver, assetsAfterFee)) {
            revert TransferFailed();
        }
        if (fee > 0 && !asset.transfer(feeRecipient, fee)) {
            revert TransferFailed();
        }

        emit Withdraw(msg.sender, receiver, owner, assetsAfterFee, shares);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Address whose shares to burn
     * @return assets Amount of assets received
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        ReentrancyGuardLib.enter(_reentrancyGuard);

        if (shares == 0) revert ZeroShares();
        if (receiver == address(0)) revert ZeroAddress();

        // Check withdrawal lock
        if (withdrawalLockPeriod > 0) {
            uint256 unlockTime = lastDepositTime[owner] + withdrawalLockPeriod;
            if (block.timestamp < unlockTime) {
                revert WithdrawalLocked(unlockTime);
            }
        }

        // Check allowance if caller is not owner
        if (msg.sender != owner) {
            uint256 currentAllowance = allowance[owner][msg.sender];
            if (currentAllowance < shares) {
                revert InsufficientAllowance(currentAllowance, shares);
            }
            if (currentAllowance != type(uint256).max) {
                allowance[owner][msg.sender] = currentAllowance - shares;
            }
        }

        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAmount();

        // Burn shares
        _burn(owner, shares);

        // Calculate and apply withdrawal fee
        uint256 fee = (assets * withdrawalFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - fee;

        // Ensure we have enough liquid assets
        _ensureLiquidity(assets);

        // Transfer assets
        if (!asset.transfer(receiver, assetsAfterFee)) {
            revert TransferFailed();
        }
        if (fee > 0 && !asset.transfer(feeRecipient, fee)) {
            revert TransferFailed();
        }

        emit Withdraw(msg.sender, receiver, owner, assetsAfterFee, shares);

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    // ============ ERC4626 VIEW FUNCTIONS ============

    function totalAssets() public view returns (uint256) {
        uint256 vaultBalance = asset.balanceOf(address(this));
        uint256 strategyAssets = address(strategy) != address(0) ? strategy.totalAssets() : 0;
        return vaultBalance + strategyAssets;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : (assets * supply) / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : (shares * totalAssets()) / supply;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : MathUtils.ceilDiv(shares * totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : MathUtils.ceilDiv(assets * supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function maxDeposit(address) external view returns (uint256) {
        if (emergencyShutdown || PausableLib.isPausedView(_pauseState)) return 0;
        if (depositLimit == 0) return type(uint256).max;
        uint256 currentAssets = totalAssets();
        return currentAssets >= depositLimit ? 0 : depositLimit - currentAssets;
    }

    function maxMint(address receiver) external view returns (uint256) {
        if (emergencyShutdown || PausableLib.isPausedView(_pauseState)) return 0;
        uint256 maxAssets = this.maxDeposit(receiver);
        return convertToShares(maxAssets);
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    // ============ STRATEGY FUNCTIONS ============

    /**
     * @notice Harvest profits from strategy
     */
    function harvest() external {
        _requireRole(AccessControlLib.OPERATOR_ROLE);

        if (address(strategy) == address(0)) revert StrategyNotSet();

        uint256 profit = strategy.harvest();

        if (profit > 0) {
            uint256 fee = (profit * performanceFee) / MAX_BPS;
            if (fee > 0) {
                // Mint shares to fee recipient
                uint256 feeShares = convertToShares(fee);
                _mint(feeRecipient, feeShares);
            }
            emit Harvested(profit, fee);
        }

        _collectManagementFee();
    }

    /**
     * @notice Deploy assets to strategy
     * @param amount Amount to deploy
     */
    function deployToStrategy(uint256 amount) external {
        _requireRole(AccessControlLib.OPERATOR_ROLE);
        _requireNotShutdown();

        if (address(strategy) == address(0)) revert StrategyNotSet();

        if (!asset.approve(address(strategy), amount)) revert TransferFailed();
        strategy.deposit(amount);
        totalDebt += amount;
    }

    /**
     * @notice Withdraw assets from strategy
     * @param amount Amount to withdraw
     */
    function withdrawFromStrategy(uint256 amount) external {
        _requireRole(AccessControlLib.OPERATOR_ROLE);

        if (address(strategy) == address(0)) revert StrategyNotSet();

        uint256 withdrawn = strategy.withdraw(amount);
        totalDebt -= withdrawn;
    }

    // ============ ADMIN FUNCTIONS ============

    function setStrategy(address _strategy) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);

        address oldStrategy = address(strategy);

        // Withdraw from old strategy if exists
        if (oldStrategy != address(0)) {
            strategy.emergencyWithdraw();
            totalDebt = 0;
        }

        strategy = IStrategy(_strategy);

        emit StrategyUpdated(oldStrategy, _strategy);
    }

    function setFees(
        uint256 _withdrawalFee,
        uint256 _performanceFee,
        uint256 _managementFee
    ) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);

        if (_withdrawalFee > MAX_WITHDRAWAL_FEE) revert InvalidFee(_withdrawalFee);
        if (_performanceFee > MAX_PERFORMANCE_FEE) revert InvalidFee(_performanceFee);
        if (_managementFee > MAX_MANAGEMENT_FEE) revert InvalidFee(_managementFee);

        withdrawalFee = _withdrawalFee;
        performanceFee = _performanceFee;
        managementFee = _managementFee;
    }

    function setFeeRecipient(address _feeRecipient) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    function setDepositLimit(uint256 _limit) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        depositLimit = _limit;
        emit DepositLimitUpdated(_limit);
    }

    function setWithdrawalLockPeriod(uint256 _period) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        require(_period <= 30 days, "Max 30 days lock");
        withdrawalLockPeriod = _period;
    }

    function activateEmergencyShutdown() external {
        _requireRole(AccessControlLib.GUARDIAN_ROLE);

        emergencyShutdown = true;

        // Withdraw everything from strategy
        if (address(strategy) != address(0)) {
            strategy.emergencyWithdraw();
            totalDebt = 0;
        }

        emit EmergencyShutdownActivated(msg.sender);
    }

    function pause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.pause(_pauseState, "Admin pause");
    }

    function unpause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.unpause(_pauseState);
    }

    // ============ ROLE MANAGEMENT ============
    function grantRole(bytes32 role, address account) external {
        AccessControlLib.checkRoleAdmin(_accessControl, role);
        AccessControlLib.grantRole(_accessControl, role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        AccessControlLib.checkRoleAdmin(_accessControl, role);
        AccessControlLib.revokeRole(_accessControl, role, account);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return AccessControlLib.hasRole(_accessControl, role, account);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) {
            revert InsufficientBalance(fromBalance, amount);
        }

        unchecked {
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) {
            revert InsufficientBalance(fromBalance, amount);
        }

        unchecked {
            balanceOf[from] = fromBalance - amount;
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    function _ensureLiquidity(uint256 amount) internal {
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance < amount && address(strategy) != address(0)) {
            uint256 needed = amount - vaultBalance;
            uint256 withdrawn = strategy.withdraw(needed);
            totalDebt -= withdrawn;
        }
    }

    function _collectManagementFee() internal {
        uint256 timeSinceLastCollection = block.timestamp - lastFeeCollection;
        if (timeSinceLastCollection == 0) return;

        uint256 annualFee = (totalAssets() * managementFee) / MAX_BPS;
        uint256 fee = (annualFee * timeSinceLastCollection) / 365 days;

        if (fee > 0) {
            uint256 feeShares = convertToShares(fee);
            _mint(feeRecipient, feeShares);
        }

        lastFeeCollection = block.timestamp;
    }

    function _requireRole(bytes32 role) internal view {
        AccessControlLib.checkRole(_accessControl, role, msg.sender);
    }

    function _requireNotPaused() internal view {
        if (PausableLib.isPausedView(_pauseState)) {
            revert VaultPaused();
        }
    }

    function _requireNotShutdown() internal view {
        if (emergencyShutdown) revert EmergencyShutdown();
    }
}
