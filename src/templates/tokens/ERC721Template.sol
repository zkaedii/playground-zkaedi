// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC721Template
 * @notice Production-ready ERC721 NFT template with common extensions
 * @dev Implements ERC721 with enumerable, metadata, royalties, and batch minting
 *
 * TEMPLATE INSTRUCTIONS:
 * 1. Search and replace "ERC721Template" with your collection name
 * 2. Update NFT_NAME, NFT_SYMBOL, and BASE_URI
 * 3. Configure MAX_SUPPLY and royalty settings
 * 4. Customize mint pricing and limits
 * 5. Remove features you don't need
 */

import {AccessControlLib} from "../utils/AccessControlLib.sol";
import {PausableLib} from "../utils/PausableLib.sol";
import {ReentrancyGuardLib} from "../utils/ReentrancyGuardLib.sol";
import {StringUtils} from "../utils/StringUtils.sol";

contract ERC721Template {
    // ============ CONSTANTS ============
    // TODO: Update these values
    string public constant name = "Template NFT";
    string public constant symbol = "TNFT";
    uint256 public constant MAX_SUPPLY = 10000;
    uint96 public constant DEFAULT_ROYALTY_BPS = 500; // 5%

    // ERC165 Interface IDs
    bytes4 internal constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 internal constant INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 internal constant INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;
    bytes4 internal constant INTERFACE_ID_ERC2981 = 0x2a55205a;
    bytes4 internal constant INTERFACE_ID_ERC165 = 0x01ffc9a7;

    // ============ ERRORS ============
    error ZeroAddress();
    error TokenDoesNotExist(uint256 tokenId);
    error NotOwnerOrApproved(address caller, uint256 tokenId);
    error TransferToNonReceiver(address to);
    error MintingPaused();
    error MaxSupplyReached();
    error InvalidMintAmount(uint256 amount);
    error InsufficientPayment(uint256 required, uint256 provided);
    error TransferFailed();
    error MaxPerWalletExceeded(uint256 limit);
    error NotTokenOwner(address caller, uint256 tokenId);

    // ============ STATE ============
    string public baseURI;
    uint256 public totalSupply;
    uint256 public mintPrice;
    uint256 public maxPerWallet;
    bool public mintingActive;

    // Token ownership
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    // Enumerable extension
    mapping(address => mapping(uint256 => uint256)) internal _ownedTokens;
    mapping(uint256 => uint256) internal _ownedTokensIndex;
    uint256[] internal _allTokens;
    mapping(uint256 => uint256) internal _allTokensIndex;

    // Metadata extension
    mapping(uint256 => string) internal _tokenURIs;

    // Royalty info (EIP-2981)
    address public royaltyReceiver;
    uint96 public royaltyBps;

    // Mint tracking
    mapping(address => uint256) public mintedPerWallet;

    // Access control and pausable
    AccessControlLib.AccessControlStorage internal _accessControl;
    PausableLib.PauseState internal _pauseState;
    ReentrancyGuardLib.ReentrancyGuard internal _reentrancyGuard;

    // ============ EVENTS ============
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event BaseURIUpdated(string newBaseURI);
    event MintPriceUpdated(uint256 newPrice);
    event MintingStatusChanged(bool active);
    event RoyaltyUpdated(address receiver, uint96 bps);
    event Withdrawn(address to, uint256 amount);

    // ============ CONSTRUCTOR ============
    constructor(
        address admin,
        string memory _baseURI,
        uint256 _mintPrice,
        uint256 _maxPerWallet
    ) {
        if (admin == address(0)) revert ZeroAddress();

        baseURI = _baseURI;
        mintPrice = _mintPrice;
        maxPerWallet = _maxPerWallet;
        royaltyReceiver = admin;
        royaltyBps = DEFAULT_ROYALTY_BPS;

        // Initialize access control
        AccessControlLib.initializeStandardRoles(_accessControl, admin);

        // Initialize reentrancy guard
        ReentrancyGuardLib.initialize(_reentrancyGuard);
    }

    // ============ ERC721 CORE ============
    function balanceOf(address owner) public view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist(tokenId);
        return owner;
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        _requireNotPaused();
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotOwnerOrApproved(msg.sender, tokenId);
        }
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        _requireNotPaused();
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotOwnerOrApproved(msg.sender, tokenId);
        }
        _safeTransfer(from, to, tokenId, data);
    }

    // ============ ENUMERABLE EXTENSION ============
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        require(index < balanceOf(owner), "Index out of bounds");
        return _ownedTokens[owner][index];
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        require(index < totalSupply, "Index out of bounds");
        return _allTokens[index];
    }

    // ============ METADATA EXTENSION ============
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist(tokenId);

        string memory _tokenURI = _tokenURIs[tokenId];
        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }

        return StringUtils.concat(baseURI, StringUtils.toString(tokenId));
    }

    // ============ ROYALTY (EIP-2981) ============
    function royaltyInfo(
        uint256, /* tokenId */
        uint256 salePrice
    ) external view returns (address receiver, uint256 royaltyAmount) {
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * royaltyBps) / 10000;
    }

    // ============ ERC165 ============
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == INTERFACE_ID_ERC165 ||
            interfaceId == INTERFACE_ID_ERC721 ||
            interfaceId == INTERFACE_ID_ERC721_METADATA ||
            interfaceId == INTERFACE_ID_ERC721_ENUMERABLE ||
            interfaceId == INTERFACE_ID_ERC2981;
    }

    // ============ MINTING ============
    function mint(uint256 amount) external payable {
        ReentrancyGuardLib.enter(_reentrancyGuard);
        _requireNotPaused();

        if (!mintingActive) revert MintingPaused();
        if (amount == 0 || amount > 10) revert InvalidMintAmount(amount);
        if (totalSupply + amount > MAX_SUPPLY) revert MaxSupplyReached();
        if (maxPerWallet > 0 && mintedPerWallet[msg.sender] + amount > maxPerWallet) {
            revert MaxPerWalletExceeded(maxPerWallet);
        }

        uint256 requiredPayment = mintPrice * amount;
        if (msg.value < requiredPayment) {
            revert InsufficientPayment(requiredPayment, msg.value);
        }

        mintedPerWallet[msg.sender] += amount;

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = totalSupply + 1;
            _safeMint(msg.sender, tokenId);
        }

        // Refund excess payment
        if (msg.value > requiredPayment) {
            (bool success, ) = msg.sender.call{value: msg.value - requiredPayment}("");
            if (!success) revert TransferFailed();
        }

        ReentrancyGuardLib.exit(_reentrancyGuard);
    }

    function adminMint(address to, uint256 amount) external {
        _requireRole(AccessControlLib.MINTER_ROLE);
        if (amount == 0) revert InvalidMintAmount(amount);
        if (totalSupply + amount > MAX_SUPPLY) revert MaxSupplyReached();

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = totalSupply + 1;
            _safeMint(to, tokenId);
        }
    }

    function adminMintBatch(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        _requireRole(AccessControlLib.MINTER_ROLE);
        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            for (uint256 j = 0; j < amounts[i]; j++) {
                if (totalSupply >= MAX_SUPPLY) revert MaxSupplyReached();
                uint256 tokenId = totalSupply + 1;
                _safeMint(recipients[i], tokenId);
            }
        }
    }

    // ============ BURNING ============
    function burn(uint256 tokenId) external {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotOwnerOrApproved(msg.sender, tokenId);
        }
        _burn(tokenId);
    }

    // ============ ADMIN FUNCTIONS ============
    function setBaseURI(string calldata _baseURI) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        baseURI = _baseURI;
        emit BaseURIUpdated(_baseURI);
    }

    function setTokenURI(uint256 tokenId, string calldata _tokenURI) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist(tokenId);
        _tokenURIs[tokenId] = _tokenURI;
    }

    function setMintPrice(uint256 _mintPrice) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        mintPrice = _mintPrice;
        emit MintPriceUpdated(_mintPrice);
    }

    function setMaxPerWallet(uint256 _maxPerWallet) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        maxPerWallet = _maxPerWallet;
    }

    function setMintingActive(bool active) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        mintingActive = active;
        emit MintingStatusChanged(active);
    }

    function setRoyaltyInfo(address receiver, uint96 bps) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        require(bps <= 1000, "Max 10% royalty");
        royaltyReceiver = receiver;
        royaltyBps = bps;
        emit RoyaltyUpdated(receiver, bps);
    }

    function pause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.pause(_pauseState, "Admin pause");
    }

    function unpause() external {
        _requireRole(AccessControlLib.PAUSER_ROLE);
        PausableLib.unpause(_pauseState);
    }

    function withdraw(address to) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(to, balance);
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

    // ============ VIEW FUNCTIONS ============
    function isPaused() external view returns (bool) {
        return PausableLib.isPausedView(_pauseState);
    }

    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokens = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = _ownedTokens[owner][i];
        }

        return tokens;
    }

    // ============ INTERNAL FUNCTIONS ============
    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert NotTokenOwner(from, tokenId);
        if (to == address(0)) revert ZeroAddress();

        // Clear approvals
        delete _tokenApprovals[tokenId];

        // Update enumerable tracking
        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert TransferToNonReceiver(to);
        }
    }

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert ZeroAddress();

        _balances[to] += 1;
        _owners[tokenId] = to;
        totalSupply += 1;

        _addTokenToAllTokensEnumeration(tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(address(0), to, tokenId);
    }

    function _safeMint(address to, uint256 tokenId) internal {
        _mint(to, tokenId);
        if (!_checkOnERC721Received(address(0), to, tokenId, "")) {
            revert TransferToNonReceiver(to);
        }
    }

    function _burn(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);

        delete _tokenApprovals[tokenId];
        delete _tokenURIs[tokenId];

        _removeTokenFromOwnerEnumeration(owner, tokenId);
        _removeTokenFromAllTokensEnumeration(tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];
        totalSupply -= 1;

        emit Transfer(owner, address(0), tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) internal {
        uint256 length = _balances[to];
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) internal {
        uint256 lastTokenIndex = _balances[from] - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) internal {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) internal {
        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId;
        _allTokensIndex[lastTokenId] = tokenIndex;

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal returns (bool) {
        if (to.code.length == 0) return true;

        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    function _requireRole(bytes32 role) internal view {
        AccessControlLib.checkRole(_accessControl, role, msg.sender);
    }

    function _requireNotPaused() internal view {
        if (PausableLib.isPausedView(_pauseState)) {
            revert MintingPaused();
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
