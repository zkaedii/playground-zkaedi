// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC20Template
 * @notice Production-ready ERC20 token template with common extensions
 * @dev Implements ERC20 with mint, burn, pause, and permit functionality
 *
 * TEMPLATE INSTRUCTIONS:
 * 1. Search and replace "ERC20Template" with your token name
 * 2. Update TOKEN_NAME and TOKEN_SYMBOL constants
 * 3. Configure INITIAL_SUPPLY and DECIMALS
 * 4. Customize roles and permissions as needed
 * 5. Remove features you don't need
 */

import {AccessControlLib} from "../utils/AccessControlLib.sol";
import {PausableLib} from "../utils/PausableLib.sol";
import {ReentrancyGuardLib} from "../utils/ReentrancyGuardLib.sol";

contract ERC20Template {
    // ============ CONSTANTS ============
    // TODO: Update these values
    string public constant name = "Template Token";
    string public constant symbol = "TMPL";
    uint8 public constant decimals = 18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18;

    // EIP-2612 Permit
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    // ============ ERRORS ============
    error InsufficientBalance(uint256 available, uint256 required);
    error InsufficientAllowance(uint256 available, uint256 required);
    error ZeroAddress();
    error ExpiredDeadline(uint256 deadline);
    error InvalidSignature();
    error TransferWhilePaused();
    error MintingDisabled();
    error BurningDisabled();
    error ExceedsMaxSupply(uint256 attempted, uint256 maximum);

    // ============ STATE ============
    uint256 public totalSupply;
    uint256 public maxSupply; // 0 = unlimited
    bool public mintingEnabled = true;
    bool public burningEnabled = true;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    AccessControlLib.AccessControlStorage internal _accessControl;
    PausableLib.PauseState internal _pauseState;
    ReentrancyGuardLib.ReentrancyGuard internal _reentrancyGuard;

    bytes32 internal immutable _cachedDomainSeparator;
    uint256 internal immutable _cachedChainId;

    // ============ EVENTS ============
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MintingToggled(bool enabled);
    event BurningToggled(bool enabled);
    event MaxSupplySet(uint256 maxSupply);

    // ============ CONSTRUCTOR ============
    constructor(address admin, uint256 _maxSupply) {
        if (admin == address(0)) revert ZeroAddress();

        maxSupply = _maxSupply;
        _cachedChainId = block.chainid;
        _cachedDomainSeparator = _computeDomainSeparator();

        // Initialize access control
        AccessControlLib.initializeStandardRoles(_accessControl, admin);

        // Initialize reentrancy guard
        ReentrancyGuardLib.initialize(_reentrancyGuard);

        // Mint initial supply to admin
        if (INITIAL_SUPPLY > 0) {
            _mint(admin, INITIAL_SUPPLY);
        }
    }

    // ============ ERC20 CORE ============
    function transfer(address to, uint256 amount) external returns (bool) {
        _requireNotPaused();
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        _requireNotPaused();
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ============ EIP-2612 PERMIT ============
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert ExpiredDeadline(deadline);

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash)
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        if (recoveredAddress == address(0) || recoveredAddress != owner) {
            revert InvalidSignature();
        }

        _approve(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        if (block.chainid == _cachedChainId) {
            return _cachedDomainSeparator;
        }
        return _computeDomainSeparator();
    }

    // ============ MINTING ============
    function mint(address to, uint256 amount) external {
        _requireRole(AccessControlLib.MINTER_ROLE);
        if (!mintingEnabled) revert MintingDisabled();
        _mint(to, amount);
    }

    function mintBatch(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        _requireRole(AccessControlLib.MINTER_ROLE);
        if (!mintingEnabled) revert MintingDisabled();

        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    // ============ BURNING ============
    function burn(uint256 amount) external {
        if (!burningEnabled) revert BurningDisabled();
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        if (!burningEnabled) revert BurningDisabled();
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // ============ ADMIN FUNCTIONS ============
    function pause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.pause(_pauseState, "Admin pause");
    }

    function unpause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.unpause(_pauseState);
    }

    function setMintingEnabled(bool enabled) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        mintingEnabled = enabled;
        emit MintingToggled(enabled);
    }

    function setBurningEnabled(bool enabled) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        burningEnabled = enabled;
        emit BurningToggled(enabled);
    }

    function setMaxSupply(uint256 _maxSupply) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        require(_maxSupply == 0 || _maxSupply >= totalSupply, "Below current supply");
        maxSupply = _maxSupply;
        emit MaxSupplySet(_maxSupply);
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

    function renounceRole(bytes32 role) external {
        AccessControlLib.renounceRole(_accessControl, role, msg.sender);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return AccessControlLib.hasRole(_accessControl, role, account);
    }

    // ============ VIEW FUNCTIONS ============
    function isPaused() external view returns (bool) {
        return PausableLib.isPausedView(_pauseState);
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
        if (to == address(0)) revert ZeroAddress();

        if (maxSupply > 0 && totalSupply + amount > maxSupply) {
            revert ExceedsMaxSupply(totalSupply + amount, maxSupply);
        }

        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();

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

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) revert ZeroAddress();
        if (spender == address(0)) revert ZeroAddress();

        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert InsufficientAllowance(currentAllowance, amount);
            }
            unchecked {
                allowance[owner][spender] = currentAllowance - amount;
            }
        }
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function _requireRole(bytes32 role) internal view {
        AccessControlLib.checkRole(_accessControl, role, msg.sender);
    }

    function _requireNotPaused() internal view {
        if (PausableLib.isPausedView(_pauseState)) {
            revert TransferWhilePaused();
        }
    }
}
