// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SVGLib} from "../../utils/SVGLib.sol";
import {FractalLib} from "../../utils/FractalLib.sol";
import {ColorLib} from "../../utils/ColorLib.sol";
import {AccessControlLib} from "../../utils/AccessControlLib.sol";
import {PausableLib} from "../../utils/PausableLib.sol";
import {ReentrancyGuardLib} from "../../utils/ReentrancyGuardLib.sol";

/**
 * @title ERC721FractalTemplate
 * @notice ERC721 NFT with fully on-chain generative fractal SVG artwork
 * @dev Each token generates unique fractal art based on token ID and seed
 *
 * Features:
 * - Fully on-chain SVG generation (no external dependencies)
 * - Multiple fractal types: Sierpinski, Koch, Tree, Carpet, Vicsek, Hexagonal
 * - Deterministic generation from token ID (same token = same art)
 * - Customizable color palettes
 * - Base64-encoded metadata and image
 * - ERC721 compliant with Enumerable and Metadata extensions
 * - ERC2981 royalty support
 *
 * TODO: Customize the following before deployment:
 * - Collection name and symbol
 * - Max supply and mint price
 * - Royalty percentage
 * - Fractal parameters (depth, colors, etc.)
 */
contract ERC721FractalTemplate {
    // ============ LIBRARIES ============

    using SVGLib for *;
    using FractalLib for *;
    using ColorLib for *;

    // ============ ERRORS ============

    error NotOwnerOrApproved();
    error TokenDoesNotExist();
    error MaxSupplyReached();
    error InsufficientPayment();
    error InvalidRecipient();
    error TokenAlreadyMinted();
    error TransferToNonReceiver();
    error MintLimitExceeded();
    error InvalidFractalType();
    error WithdrawFailed();

    // ============ EVENTS ============

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event FractalGenerated(uint256 indexed tokenId, FractalType fractalType, uint256 seed);

    // ============ TYPES ============

    /// @notice Supported fractal types
    enum FractalType {
        SIERPINSKI_TRIANGLE,
        SIERPINSKI_CARPET,
        KOCH_SNOWFLAKE,
        FRACTAL_TREE,
        VICSEK,
        HEXAGONAL,
        GOLDEN_SPIRAL,
        CANTOR_SET
    }

    /// @notice Token metadata stored on-chain
    struct TokenData {
        FractalType fractalType;
        uint256 seed;
        uint256 depth;
        uint256 colorPalette;
        uint256 mintTimestamp;
    }

    // ============ CONSTANTS ============

    /// @notice ERC165 interface IDs
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;
    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;
    bytes4 private constant INTERFACE_ID_ERC165 = 0x01ffc9a7;

    /// @notice Access control roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice SVG canvas dimensions
    uint256 private constant CANVAS_SIZE = 400;

    /// @notice Base64 encoding table
    string private constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    // ============ STATE VARIABLES ============

    /// @notice Collection name
    string public name;

    /// @notice Collection symbol
    string public symbol;

    /// @notice Collection description
    string public description;

    /// @notice Maximum supply (0 = unlimited)
    uint256 public maxSupply;

    /// @notice Mint price in wei
    uint256 public mintPrice;

    /// @notice Current total supply
    uint256 public totalSupply;

    /// @notice Per-wallet mint limit (0 = unlimited)
    uint256 public mintLimit;

    /// @notice Royalty percentage (basis points, 100 = 1%)
    uint256 public royaltyBps;

    /// @notice Royalty recipient address
    address public royaltyRecipient;

    /// @notice Token ownership mapping
    mapping(uint256 => address) private _owners;

    /// @notice Token approval mapping
    mapping(uint256 => address) private _tokenApprovals;

    /// @notice Operator approval mapping
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @notice Balance per address
    mapping(address => uint256) private _balances;

    /// @notice Mints per address
    mapping(address => uint256) public mintsPerAddress;

    /// @notice Token data mapping
    mapping(uint256 => TokenData) public tokenData;

    /// @notice Enumerable: owner to token index mapping
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    /// @notice Enumerable: token to owner index mapping
    mapping(uint256 => uint256) private _ownedTokensIndex;

    /// @notice Enumerable: all tokens array
    uint256[] private _allTokens;

    /// @notice Enumerable: token to all tokens index mapping
    mapping(uint256 => uint256) private _allTokensIndex;

    /// @notice Library storage
    AccessControlLib.AccessControlStorage internal _accessControl;
    PausableLib.PauseState internal _pauseState;
    ReentrancyGuardLib.ReentrancyGuard internal _reentrancyGuard;

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize the fractal NFT collection
     * @param _name Collection name
     * @param _symbol Collection symbol
     * @param _description Collection description
     * @param _maxSupply Maximum supply (0 for unlimited)
     * @param _mintPrice Mint price in wei
     * @param _mintLimit Per-wallet mint limit
     * @param _royaltyBps Royalty in basis points
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _description,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _mintLimit,
        uint256 _royaltyBps
    ) {
        name = _name;
        symbol = _symbol;
        description = _description;
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        mintLimit = _mintLimit;
        royaltyBps = _royaltyBps;
        royaltyRecipient = msg.sender;

        // Initialize access control
        AccessControlLib.initializeWithAdmin(_accessControl, msg.sender);
        AccessControlLib.grantRole(_accessControl, MINTER_ROLE, msg.sender);
        AccessControlLib.grantRole(_accessControl, PAUSER_ROLE, msg.sender);
        AccessControlLib.grantRole(_accessControl, ADMIN_ROLE, msg.sender);
    }

    // ============ MINTING ============

    /**
     * @notice Mint a fractal NFT with random type
     * @return tokenId The minted token ID
     */
    function mint() external payable returns (uint256) {
        return mintWithType(FractalType(uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, totalSupply))) % 8));
    }

    /**
     * @notice Mint a fractal NFT with specific type
     * @param fractalType The type of fractal to generate
     * @return tokenId The minted token ID
     */
    function mintWithType(FractalType fractalType) public payable returns (uint256) {
        ReentrancyGuardLib.enter(_reentrancyGuard);
        _requireNotPaused();

        if (msg.value < mintPrice) revert InsufficientPayment();
        if (maxSupply > 0 && totalSupply >= maxSupply) revert MaxSupplyReached();
        if (mintLimit > 0 && mintsPerAddress[msg.sender] >= mintLimit) revert MintLimitExceeded();

        uint256 tokenId = totalSupply + 1;

        // Generate deterministic seed from token ID
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId, block.prevrandao, msg.sender)));

        // Determine depth based on fractal type (gas optimization)
        uint256 depth = _getDefaultDepth(fractalType);

        // Select color palette
        uint256 palette = seed % 8;

        // Store token data
        tokenData[tokenId] = TokenData({
            fractalType: fractalType,
            seed: seed,
            depth: depth,
            colorPalette: palette,
            mintTimestamp: block.timestamp
        });

        _mint(msg.sender, tokenId);
        mintsPerAddress[msg.sender]++;

        emit FractalGenerated(tokenId, fractalType, seed);

        ReentrancyGuardLib.exit(_reentrancyGuard);
        return tokenId;
    }

    /**
     * @notice Admin mint with custom parameters
     * @param to Recipient address
     * @param fractalType Fractal type
     * @param seed Custom seed
     * @param depth Recursion depth
     * @param palette Color palette index
     * @return tokenId The minted token ID
     */
    function adminMint(
        address to,
        FractalType fractalType,
        uint256 seed,
        uint256 depth,
        uint256 palette
    ) external returns (uint256) {
        AccessControlLib.requireRole(_accessControl, MINTER_ROLE, msg.sender);
        if (maxSupply > 0 && totalSupply >= maxSupply) revert MaxSupplyReached();

        uint256 tokenId = totalSupply + 1;

        tokenData[tokenId] = TokenData({
            fractalType: fractalType,
            seed: seed,
            depth: depth,
            colorPalette: palette,
            mintTimestamp: block.timestamp
        });

        _mint(to, tokenId);

        emit FractalGenerated(tokenId, fractalType, seed);
        return tokenId;
    }

    // ============ SVG GENERATION ============

    /**
     * @notice Generate SVG artwork for a token
     * @param tokenId Token ID
     * @return SVG string
     */
    function generateSVG(uint256 tokenId) public view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();

        TokenData memory data = tokenData[tokenId];
        string[] memory colors = _getPalette(data.colorPalette);
        string memory bgColor = _getBackgroundColor(data.colorPalette);

        string memory fractalContent = _generateFractalContent(data, colors);

        return SVGLib.createSVGWithBackground(CANVAS_SIZE, CANVAS_SIZE, bgColor, fractalContent);
    }

    /**
     * @notice Internal fractal content generation
     */
    function _generateFractalContent(TokenData memory data, string[] memory colors) internal pure returns (string memory) {
        int256 center = int256(CANVAS_SIZE / 2);
        uint256 size = (CANVAS_SIZE * 80) / 100; // 80% of canvas

        if (data.fractalType == FractalType.SIERPINSKI_TRIANGLE) {
            return FractalLib.sierpinskiTriangle(
                FractalLib.SierpinskiConfig({
                    size: size,
                    depth: data.depth,
                    fillColor: colors[0],
                    strokeColor: colors[1],
                    strokeWidth: 1,
                    centerX: center,
                    centerY: center
                })
            );
        }

        if (data.fractalType == FractalType.SIERPINSKI_CARPET) {
            return FractalLib.sierpinskiCarpet(size, data.depth, colors[0], center, center);
        }

        if (data.fractalType == FractalType.KOCH_SNOWFLAKE) {
            return FractalLib.kochSnowflake(
                FractalLib.KochConfig({
                    size: size,
                    depth: data.depth,
                    strokeColor: colors[0],
                    strokeWidth: 2,
                    centerX: center,
                    centerY: center,
                    filled: true,
                    fillColor: colors[1]
                })
            );
        }

        if (data.fractalType == FractalType.FRACTAL_TREE) {
            return FractalLib.fractalTree(
                FractalLib.TreeConfig({
                    trunkLength: size / 3,
                    depth: data.depth,
                    branchAngle: 250, // 25 degrees
                    lengthRatio: 700, // 70%
                    widthRatio: 800,
                    colors: colors,
                    startX: center,
                    startY: int256(CANVAS_SIZE - 40)
                })
            );
        }

        if (data.fractalType == FractalType.VICSEK) {
            return FractalLib.vicsekFractal(size, data.depth, colors[0], center, center);
        }

        if (data.fractalType == FractalType.HEXAGONAL) {
            return FractalLib.hexagonalFractal(size / 2, data.depth, colors[0], colors[1], 2, center, center);
        }

        if (data.fractalType == FractalType.GOLDEN_SPIRAL) {
            return FractalLib.goldenSpiral(
                FractalLib.SpiralConfig({
                    turns: 5,
                    startRadius: 5,
                    growth: 1100, // 1.1x per step
                    points: 36,
                    strokeColor: colors[0],
                    strokeWidth: 2,
                    centerX: center,
                    centerY: center
                })
            );
        }

        if (data.fractalType == FractalType.CANTOR_SET) {
            return FractalLib.cantorSet(
                FractalLib.CantorConfig({
                    width: size,
                    depth: data.depth,
                    lineHeight: 10,
                    gapHeight: 20,
                    color: colors[0],
                    startX: int256((CANVAS_SIZE - size) / 2),
                    startY: 40
                })
            );
        }

        // Default fallback
        return FractalLib.sierpinskiTriangle(
            FractalLib.SierpinskiConfig({
                size: size,
                depth: 4,
                fillColor: colors[0],
                strokeColor: colors[1],
                strokeWidth: 1,
                centerX: center,
                centerY: center
            })
        );
    }

    /**
     * @notice Get color palette by index
     */
    function _getPalette(uint256 index) internal pure returns (string[] memory) {
        string[] memory colors = new string[](5);

        if (index == 0) {
            // Sunset
            string[5] memory sunset = ColorLib.sunsetPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = sunset[i];
        } else if (index == 1) {
            // Ocean
            string[5] memory ocean = ColorLib.oceanPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = ocean[i];
        } else if (index == 2) {
            // Forest
            string[5] memory forest = ColorLib.forestPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = forest[i];
        } else if (index == 3) {
            // Fire
            string[5] memory fire = ColorLib.firePalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = fire[i];
        } else if (index == 4) {
            // Neon
            string[5] memory neon = ColorLib.neonPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = neon[i];
        } else if (index == 5) {
            // Earth
            string[5] memory earth = ColorLib.earthPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = earth[i];
        } else if (index == 6) {
            // Cosmic
            string[5] memory cosmic = ColorLib.cosmicPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = cosmic[i];
        } else {
            // Pastel
            string[5] memory pastel = ColorLib.pastelPalette();
            for (uint256 i = 0; i < 5; i++) colors[i] = pastel[i];
        }

        return colors;
    }

    /**
     * @notice Get background color for palette
     */
    function _getBackgroundColor(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "1a1a2e"; // Dark blue
        if (index == 1) return "001219"; // Dark teal
        if (index == 2) return "1b4332"; // Dark green
        if (index == 3) return "2d2d2d"; // Dark gray
        if (index == 4) return "0a0a0a"; // Near black
        if (index == 5) return "3d2914"; // Dark brown
        if (index == 6) return "0D0221"; // Deep purple
        return "f8f9fa"; // Light gray
    }

    /**
     * @notice Get default depth for fractal type
     */
    function _getDefaultDepth(FractalType fractalType) internal pure returns (uint256) {
        if (fractalType == FractalType.SIERPINSKI_TRIANGLE) return 5;
        if (fractalType == FractalType.SIERPINSKI_CARPET) return 4;
        if (fractalType == FractalType.KOCH_SNOWFLAKE) return 4;
        if (fractalType == FractalType.FRACTAL_TREE) return 8;
        if (fractalType == FractalType.VICSEK) return 4;
        if (fractalType == FractalType.HEXAGONAL) return 3;
        if (fractalType == FractalType.GOLDEN_SPIRAL) return 5;
        if (fractalType == FractalType.CANTOR_SET) return 6;
        return 4;
    }

    // ============ METADATA ============

    /**
     * @notice Get token URI with on-chain metadata and SVG
     * @param tokenId Token ID
     * @return Base64-encoded JSON metadata
     */
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();

        TokenData memory data = tokenData[tokenId];
        string memory svg = generateSVG(tokenId);
        string memory svgBase64 = _base64Encode(bytes(svg));

        string memory attributes = string(
            abi.encodePacked(
                '[{"trait_type":"Fractal Type","value":"', _fractalTypeName(data.fractalType), '"},',
                '{"trait_type":"Depth","value":', SVGLib.uintToString(data.depth), '},',
                '{"trait_type":"Palette","value":"', _paletteName(data.colorPalette), '"},',
                '{"trait_type":"Seed","value":"', SVGLib.uintToString(data.seed), '"}]'
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name":"', name, ' #', SVGLib.uintToString(tokenId), '",',
                '"description":"', description, '",',
                '"image":"data:image/svg+xml;base64,', svgBase64, '",',
                '"attributes":', attributes, '}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", _base64Encode(bytes(json))));
    }

    /**
     * @notice Get fractal type name
     */
    function _fractalTypeName(FractalType fractalType) internal pure returns (string memory) {
        if (fractalType == FractalType.SIERPINSKI_TRIANGLE) return "Sierpinski Triangle";
        if (fractalType == FractalType.SIERPINSKI_CARPET) return "Sierpinski Carpet";
        if (fractalType == FractalType.KOCH_SNOWFLAKE) return "Koch Snowflake";
        if (fractalType == FractalType.FRACTAL_TREE) return "Fractal Tree";
        if (fractalType == FractalType.VICSEK) return "Vicsek Fractal";
        if (fractalType == FractalType.HEXAGONAL) return "Hexagonal Fractal";
        if (fractalType == FractalType.GOLDEN_SPIRAL) return "Golden Spiral";
        if (fractalType == FractalType.CANTOR_SET) return "Cantor Set";
        return "Unknown";
    }

    /**
     * @notice Get palette name
     */
    function _paletteName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Sunset";
        if (index == 1) return "Ocean";
        if (index == 2) return "Forest";
        if (index == 3) return "Fire";
        if (index == 4) return "Neon";
        if (index == 5) return "Earth";
        if (index == 6) return "Cosmic";
        return "Pastel";
    }

    // ============ ERC721 CORE ============

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert InvalidRecipient();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    function approve(address to, uint256 tokenId) external {
        address owner = _owners[tokenId];
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) revert NotOwnerOrApproved();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        _requireNotPaused();
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) revert TransferToNonReceiver();
            } catch {
                revert TransferToNonReceiver();
            }
        }
    }

    // ============ ERC721 ENUMERABLE ============

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        require(index < _balances[owner], "Index out of bounds");
        return _ownedTokens[owner][index];
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        require(index < _allTokens.length, "Index out of bounds");
        return _allTokens[index];
    }

    // ============ ERC2981 ROYALTY ============

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBps) / 10000;
        return (royaltyRecipient, royaltyAmount);
    }

    // ============ ERC165 ============

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == INTERFACE_ID_ERC721
            || interfaceId == INTERFACE_ID_ERC721_METADATA
            || interfaceId == INTERFACE_ID_ERC721_ENUMERABLE
            || interfaceId == INTERFACE_ID_ERC2981
            || interfaceId == INTERFACE_ID_ERC165;
    }

    // ============ ADMIN FUNCTIONS ============

    function setMintPrice(uint256 _mintPrice) external {
        AccessControlLib.requireRole(_accessControl, ADMIN_ROLE, msg.sender);
        mintPrice = _mintPrice;
    }

    function setMintLimit(uint256 _mintLimit) external {
        AccessControlLib.requireRole(_accessControl, ADMIN_ROLE, msg.sender);
        mintLimit = _mintLimit;
    }

    function setRoyalty(address _recipient, uint256 _bps) external {
        AccessControlLib.requireRole(_accessControl, ADMIN_ROLE, msg.sender);
        royaltyRecipient = _recipient;
        royaltyBps = _bps;
    }

    function pause() external {
        AccessControlLib.requireRole(_accessControl, PAUSER_ROLE, msg.sender);
        PausableLib.pause(_pauseState);
    }

    function unpause() external {
        AccessControlLib.requireRole(_accessControl, PAUSER_ROLE, msg.sender);
        PausableLib.unpause(_pauseState);
    }

    function withdraw() external {
        AccessControlLib.requireRole(_accessControl, ADMIN_ROLE, msg.sender);
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert WithdrawFailed();
    }

    // ============ INTERNAL FUNCTIONS ============

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert InvalidRecipient();
        if (_owners[tokenId] != address(0)) revert TokenAlreadyMinted();

        _balances[to]++;
        _owners[tokenId] = to;
        totalSupply++;

        // Enumerable
        _addTokenToOwnerEnumeration(to, tokenId);
        _addTokenToAllTokensEnumeration(tokenId);

        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert InvalidRecipient();
        if (_owners[tokenId] != from) revert NotOwnerOrApproved();

        // Clear approvals
        delete _tokenApprovals[tokenId];

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        // Enumerable
        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender];
    }

    function _requireNotPaused() internal view {
        PausableLib.requireNotPaused(_pauseState);
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = _balances[to] - 1;
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastTokenIndex = _balances[from];
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    // ============ BASE64 ENCODING ============

    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen);

        bytes memory table = bytes(TABLE);

        uint256 i;
        uint256 j;

        for (i = 0; i + 3 <= data.length; i += 3) {
            uint256 a = uint8(data[i]);
            uint256 b = uint8(data[i + 1]);
            uint256 c = uint8(data[i + 2]);

            result[j++] = table[a >> 2];
            result[j++] = table[((a & 0x03) << 4) | (b >> 4)];
            result[j++] = table[((b & 0x0f) << 2) | (c >> 6)];
            result[j++] = table[c & 0x3f];
        }

        if (data.length % 3 == 1) {
            uint256 a = uint8(data[i]);
            result[j++] = table[a >> 2];
            result[j++] = table[(a & 0x03) << 4];
            result[j++] = "=";
            result[j++] = "=";
        } else if (data.length % 3 == 2) {
            uint256 a = uint8(data[i]);
            uint256 b = uint8(data[i + 1]);
            result[j++] = table[a >> 2];
            result[j++] = table[((a & 0x03) << 4) | (b >> 4)];
            result[j++] = table[(b & 0x0f) << 2];
            result[j++] = "=";
        }

        return string(result);
    }
}

// ============ INTERFACES ============

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}
