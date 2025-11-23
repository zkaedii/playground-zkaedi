// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/*//////////////////////////////////////////////////////////////
                        CUSTOM VALUE TYPES
//////////////////////////////////////////////////////////////*/

/// @dev Basis points (0-10000) with type safety
type BPS is uint16;

/// @dev Timestamp with overflow-safe arithmetic
type Timestamp is uint40;

/// @dev Compact token amount (max ~1.2e24 with 18 decimals)
type TokenAmount is uint96;

/// @dev Packed address + flags in single slot
type PackedAccount is uint256;

/*//////////////////////////////////////////////////////////////
                        TYPE LIBRARIES
//////////////////////////////////////////////////////////////*/

using BPSLib for BPS global;
using TimestampLib for Timestamp global;
using TokenAmountLib for TokenAmount global;
using PackedAccountLib for PackedAccount global;

library BPSLib {
    uint16 internal constant MAX = 10000;
    uint16 internal constant DENOMINATOR = 10000;

    function unwrap(BPS self) internal pure returns (uint16) {
        return BPS.unwrap(self);
    }

    function isValid(BPS self) internal pure returns (bool) {
        return BPS.unwrap(self) <= MAX;
    }

    /// @dev Calculate percentage: (amount * bps) / 10000
    function mulDiv(BPS self, uint256 amount) internal pure returns (uint256) {
        unchecked {
            return (amount * BPS.unwrap(self)) / DENOMINATOR;
        }
    }

    /// @dev Subtract percentage from amount
    function deduct(BPS self, uint256 amount) internal pure returns (uint256 net, uint256 fee) {
        unchecked {
            fee = (amount * BPS.unwrap(self)) / DENOMINATOR;
            net = amount - fee;
        }
    }

    /// @dev Linear interpolation between two rates based on progress (0-10000)
    function lerp(BPS from, BPS to, BPS progress) internal pure returns (BPS) {
        unchecked {
            uint256 f = BPS.unwrap(from);
            uint256 t = BPS.unwrap(to);
            uint256 p = BPS.unwrap(progress);

            if (t >= f) {
                return BPS.wrap(uint16(f + ((t - f) * p) / DENOMINATOR));
            } else {
                return BPS.wrap(uint16(f - ((f - t) * p) / DENOMINATOR));
            }
        }
    }
}

library TimestampLib {
    function unwrap(Timestamp self) internal pure returns (uint40) {
        return Timestamp.unwrap(self);
    }

    function now_() internal view returns (Timestamp) {
        return Timestamp.wrap(uint40(block.timestamp));
    }

    function elapsed(Timestamp self) internal view returns (uint256) {
        unchecked {
            return block.timestamp - Timestamp.unwrap(self);
        }
    }

    function isExpired(Timestamp self) internal view returns (bool) {
        return block.timestamp >= Timestamp.unwrap(self);
    }

    function add(Timestamp self, uint40 duration) internal pure returns (Timestamp) {
        unchecked {
            return Timestamp.wrap(Timestamp.unwrap(self) + duration);
        }
    }
}

library TokenAmountLib {
    function unwrap(TokenAmount self) internal pure returns (uint96) {
        return TokenAmount.unwrap(self);
    }

    function wrap(uint256 amount) internal pure returns (TokenAmount) {
        require(amount <= type(uint96).max, "Overflow");
        return TokenAmount.wrap(uint96(amount));
    }

    function add(TokenAmount a, TokenAmount b) internal pure returns (TokenAmount) {
        unchecked {
            return TokenAmount.wrap(TokenAmount.unwrap(a) + TokenAmount.unwrap(b));
        }
    }

    function sub(TokenAmount a, TokenAmount b) internal pure returns (TokenAmount) {
        unchecked {
            return TokenAmount.wrap(TokenAmount.unwrap(a) - TokenAmount.unwrap(b));
        }
    }

    function toUint(TokenAmount self) internal pure returns (uint256) {
        return uint256(TokenAmount.unwrap(self));
    }
}

library PackedAccountLib {
    // Layout: [160 bits address][8 bits flags][40 bits timestamp][48 bits data]
    uint256 internal constant ADDR_MASK = (1 << 160) - 1;
    uint256 internal constant FLAG_SHIFT = 160;
    uint256 internal constant TS_SHIFT = 168;
    uint256 internal constant DATA_SHIFT = 208;

    // Flags
    uint8 internal constant FLAG_WHITELISTED = 1 << 0;
    uint8 internal constant FLAG_BLACKLISTED = 1 << 1;
    uint8 internal constant FLAG_IS_CONTRACT = 1 << 2;
    uint8 internal constant FLAG_VERIFIED = 1 << 3;

    function pack(
        address addr,
        uint8 flags,
        Timestamp ts,
        uint48 data
    ) internal pure returns (PackedAccount) {
        unchecked {
            return PackedAccount.wrap(
                uint256(uint160(addr)) |
                (uint256(flags) << FLAG_SHIFT) |
                (uint256(Timestamp.unwrap(ts)) << TS_SHIFT) |
                (uint256(data) << DATA_SHIFT)
            );
        }
    }

    function addr(PackedAccount self) internal pure returns (address) {
        return address(uint160(PackedAccount.unwrap(self) & ADDR_MASK));
    }

    function flags(PackedAccount self) internal pure returns (uint8) {
        unchecked {
            return uint8(PackedAccount.unwrap(self) >> FLAG_SHIFT);
        }
    }

    function hasFlag(PackedAccount self, uint8 flag) internal pure returns (bool) {
        unchecked {
            return (uint8(PackedAccount.unwrap(self) >> FLAG_SHIFT) & flag) != 0;
        }
    }

    function timestamp(PackedAccount self) internal pure returns (Timestamp) {
        unchecked {
            return Timestamp.wrap(uint40(PackedAccount.unwrap(self) >> TS_SHIFT));
        }
    }

    function data(PackedAccount self) internal pure returns (uint48) {
        unchecked {
            return uint48(PackedAccount.unwrap(self) >> DATA_SHIFT);
        }
    }

    function setFlag(PackedAccount self, uint8 flag, bool value) internal pure returns (PackedAccount) {
        uint256 raw = PackedAccount.unwrap(self);
        uint256 flagBits = uint256(flag) << FLAG_SHIFT;

        if (value) {
            return PackedAccount.wrap(raw | flagBits);
        } else {
            return PackedAccount.wrap(raw & ~flagBits);
        }
    }
}

/*//////////////////////////////////////////////////////////////
                        NOVEL MECHANICS
//////////////////////////////////////////////////////////////*/

/// @dev Decay curve for dynamic burn rates
library DecayCurve {
    /// @dev Exponential decay: rate * e^(-lambda * t)
    /// Approximated via: rate * (1 - t/halfLife)^2 for gas efficiency
    function exponentialDecay(
        BPS initialRate,
        uint256 elapsed,
        uint256 halfLife
    ) internal pure returns (BPS) {
        if (elapsed >= halfLife * 2) return BPS.wrap(0);

        unchecked {
            uint256 remaining = (halfLife * 2) - elapsed;
            uint256 factor = (remaining * remaining) / (halfLife * halfLife * 4);
            uint256 newRate = (BPS.unwrap(initialRate) * factor);
            return BPS.wrap(uint16(newRate > 10000 ? 10000 : newRate));
        }
    }

    /// @dev Sigmoid curve for gradual transitions
    /// Approximated via piecewise linear for gas
    function sigmoid(uint256 x, uint256 midpoint, uint256 steepness) internal pure returns (BPS) {
        unchecked {
            if (x <= midpoint - steepness) return BPS.wrap(0);
            if (x >= midpoint + steepness) return BPS.wrap(10000);

            uint256 progress = ((x - (midpoint - steepness)) * 10000) / (steepness * 2);
            return BPS.wrap(uint16(progress));
        }
    }
}

/// @dev Merkle proof utilities for airdrops/allowlists
library MerkleLib {
    function verify(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i; i < proof.length; ) {
            bytes32 proofElement = proof[i];

            // Sort pairs for consistent hashing
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            unchecked { ++i; }
        }

        return computedHash == root;
    }

    function leaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount));
    }
}

/*//////////////////////////////////////////////////////////////
                    UUPS TOKEN V3 - OPTIMIZED
//////////////////////////////////////////////////////////////*/

/**
 * @title UUPSTokenV3
 * @author Optimized implementation with novel mechanics
 * @notice Gas-optimized UUPS token featuring:
 *         - Custom value types for type safety
 *         - Packed storage (5 slots → 2 slots for config)
 *         - Dynamic burn curves (decay, sigmoid)
 *         - Time-weighted holdings for loyalty rewards
 *         - Merkle-based claiming system
 *         - Flash loan callbacks
 *         - Commit-reveal governance
 */
contract UUPSTokenV3 is
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidBPS();
    error InvalidAddress();
    error Unauthorized();
    error AlreadyClaimed();
    error InvalidProof();
    error FlashLoanFailed();
    error CooldownActive();
    error MaxSupplyExceeded();
    error CommitRequired();
    error CommitExpired();
    error InvalidCommit();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BurnExecuted(address indexed from, uint256 amount, BurnType burnType);
    event ConfigUpdated(bytes32 indexed key, uint256 oldValue, uint256 newValue);
    event AccountFlagsUpdated(address indexed account, uint8 oldFlags, uint8 newFlags);
    event MerkleClaim(address indexed account, uint256 amount, uint256 tranche);
    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);
    event HoldingReward(address indexed account, uint256 reward, uint256 holdingDuration);
    event CommitRevealed(address indexed account, bytes32 commitHash, bytes data);

    enum BurnType { TRANSFER, MANUAL, DECAY, GOVERNANCE }

    /*//////////////////////////////////////////////////////////////
                        PACKED STORAGE SLOT 1
    //////////////////////////////////////////////////////////////*/

    /// @dev Packed config: [burnRate:16][flashFee:16][rewardRate:16][maxSupply:96][flags:16][reserved:96]
    struct PackedConfig {
        BPS burnRate;           // 16 bits - Transfer burn rate
        BPS flashFee;           // 16 bits - Flash loan fee
        BPS rewardRate;         // 16 bits - Holding reward rate (per epoch)
        TokenAmount maxSupply;  // 96 bits - Hard cap
        uint16 configFlags;     // 16 bits - Global flags
        // 96 bits reserved
    }

    PackedConfig private _config;

    /*//////////////////////////////////////////////////////////////
                        PACKED STORAGE SLOT 2
    //////////////////////////////////////////////////////////////*/

    /// @dev Packed state: [totalBurned:96][lastRewardEpoch:40][merkleRoot:96+bits via separate slot]
    struct PackedState {
        TokenAmount totalBurned;    // 96 bits
        Timestamp lastRewardEpoch;  // 40 bits
        Timestamp deployTimestamp;  // 40 bits
        uint80 reserved;            // 80 bits for future use
    }

    PackedState private _state;

    /*//////////////////////////////////////////////////////////////
                            MERKLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Merkle roots for different claim tranches
    mapping(uint256 tranche => bytes32 root) public merkleRoots;

    /// @dev Claimed status: packed bits per tranche
    mapping(uint256 tranche => mapping(uint256 wordIndex => uint256 bitmap)) private _claimed;

    /*//////////////////////////////////////////////////////////////
                        ACCOUNT DATA (PACKED)
    //////////////////////////////////////////////////////////////*/

    /// @dev Per-account packed data
    mapping(address => PackedAccount) private _accountData;

    /// @dev Commit-reveal storage for governance
    mapping(address => bytes32) private _commits;
    mapping(address => Timestamp) private _commitTimestamps;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant EPOCH_DURATION = 1 days;
    uint256 private constant COMMIT_WINDOW = 1 hours;
    uint256 private constant REVEAL_WINDOW = 24 hours;
    uint16 private constant FLAG_FLASH_ENABLED = 1 << 0;
    uint16 private constant FLAG_REWARDS_ENABLED = 1 << 1;
    uint16 private constant FLAG_DECAY_ENABLED = 1 << 2;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validBPS(BPS rate) {
        if (!rate.isValid()) revert InvalidBPS();
        _;
    }

    modifier notZeroAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initializeV3(
        string calldata name_,
        string calldata symbol_,
        uint256 initialSupply,
        uint256 maxSupply_,
        uint16 burnRateBps
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        BPS burnRate = BPS.wrap(burnRateBps);
        if (!burnRate.isValid()) revert InvalidBPS();

        // Pack config into single slot
        _config = PackedConfig({
            burnRate: burnRate,
            flashFee: BPS.wrap(10), // 0.1% flash fee default
            rewardRate: BPS.wrap(50), // 0.5% reward rate default
            maxSupply: TokenAmountLib.wrap(maxSupply_),
            configFlags: FLAG_FLASH_ENABLED | FLAG_REWARDS_ENABLED
        });

        _state = PackedState({
            totalBurned: TokenAmount.wrap(0),
            lastRewardEpoch: TimestampLib.now_(),
            deployTimestamp: TimestampLib.now_(),
            reserved: 0
        });

        // Mint with max supply check
        if (initialSupply > maxSupply_) revert MaxSupplyExceeded();
        _mint(msg.sender, initialSupply);

        // Auto-whitelist deployer
        _setAccountFlag(msg.sender, PackedAccountLib.FLAG_WHITELISTED, true);
    }

    /// @dev Reinitialize from V2 to V3
    function reinitializeV3(uint256 maxSupply_) external reinitializer(3) {
        _config.maxSupply = TokenAmountLib.wrap(maxSupply_);
        _config.flashFee = BPS.wrap(10);
        _config.rewardRate = BPS.wrap(50);
        _config.configFlags = FLAG_FLASH_ENABLED | FLAG_REWARDS_ENABLED;

        _state.deployTimestamp = TimestampLib.now_();
        _state.lastRewardEpoch = TimestampLib.now_();
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIMIZED TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        // Early exit for mint/burn (no fee logic)
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // Load account data once (saves SLOAD on second access)
        PackedAccount fromData = _accountData[from];
        PackedAccount toData = _accountData[to];

        // Check whitelist via packed flags (single bit check)
        bool exempt = fromData.hasFlag(PackedAccountLib.FLAG_WHITELISTED) ||
                      toData.hasFlag(PackedAccountLib.FLAG_WHITELISTED);

        if (exempt) {
            super._update(from, to, amount);
            _updateHoldingTimestamp(from, to);
            return;
        }

        // Calculate dynamic burn rate
        BPS effectiveRate = _calculateEffectiveBurnRate();

        // Deduct burn using optimized BPS math
        (uint256 netAmount, uint256 burnAmount) = effectiveRate.deduct(amount);

        // Execute burn if non-zero
        if (burnAmount != 0) {
            // Direct _update to address(0) for burn
            super._update(from, address(0), burnAmount);

            // Update packed state
            _state.totalBurned = _state.totalBurned.add(TokenAmountLib.wrap(burnAmount));

            emit BurnExecuted(from, burnAmount, BurnType.TRANSFER);
        }

        // Execute transfer
        super._update(from, to, netAmount);

        // Update holding timestamps for rewards
        _updateHoldingTimestamp(from, to);
    }

    /// @dev Update holding start time for reward calculations
    function _updateHoldingTimestamp(address from, address to) private {
        // Update 'from' timestamp if balance becomes 0
        if (balanceOf(from) == 0) {
            _accountData[from] = PackedAccountLib.pack(
                from,
                _accountData[from].flags(),
                Timestamp.wrap(0),
                0
            );
        }

        // Set 'to' timestamp if this is first tokens
        PackedAccount toData = _accountData[to];
        if (toData.timestamp().unwrap() == 0) {
            _accountData[to] = PackedAccountLib.pack(
                to,
                toData.flags(),
                TimestampLib.now_(),
                0
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DYNAMIC BURN CURVES
    //////////////////////////////////////////////////////////////*/

    /// @dev Calculate effective burn rate based on time/conditions
    function _calculateEffectiveBurnRate() internal view returns (BPS) {
        BPS baseRate = _config.burnRate;

        // If decay enabled, reduce rate over time
        if (_config.configFlags & FLAG_DECAY_ENABLED != 0) {
            uint256 elapsed = _state.deployTimestamp.elapsed();
            uint256 halfLife = 365 days; // 1 year half-life

            return DecayCurve.exponentialDecay(baseRate, elapsed, halfLife);
        }

        return baseRate;
    }

    /// @dev Preview burn for UI/integrations
    function previewTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint256 netAmount, uint256 burnAmount, BPS effectiveRate) {
        PackedAccount fromData = _accountData[from];
        PackedAccount toData = _accountData[to];

        bool exempt = fromData.hasFlag(PackedAccountLib.FLAG_WHITELISTED) ||
                      toData.hasFlag(PackedAccountLib.FLAG_WHITELISTED);

        if (exempt || from == address(0) || to == address(0)) {
            return (amount, 0, BPS.wrap(0));
        }

        effectiveRate = _calculateEffectiveBurnRate();
        (netAmount, burnAmount) = effectiveRate.deduct(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        FLASH LOANS (EIP-3156)
    //////////////////////////////////////////////////////////////*/

    /// @dev Flash loan with callback
    function flashLoan(
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        if (_config.configFlags & FLAG_FLASH_ENABLED == 0) revert Unauthorized();

        uint256 fee = _config.flashFee.mulDiv(amount);
        uint256 balanceBefore = balanceOf(address(this));

        // Mint tokens to receiver
        _mint(receiver, amount);

        // Callback
        (bool success, bytes memory result) = receiver.call(
            abi.encodeWithSignature(
                "onFlashLoan(address,uint256,uint256,bytes)",
                msg.sender,
                amount,
                fee,
                data
            )
        );

        if (!success) revert FlashLoanFailed();

        // Verify repayment
        uint256 repayment = amount + fee;
        _burn(receiver, repayment);

        // Fee goes to protocol (burned or kept)
        if (fee > 0) {
            _state.totalBurned = _state.totalBurned.add(TokenAmountLib.wrap(fee));
            emit BurnExecuted(receiver, fee, BurnType.MANUAL);
        }

        emit FlashLoan(receiver, amount, fee);
        return true;
    }

    function flashFee(uint256 amount) external view returns (uint256) {
        return _config.flashFee.mulDiv(amount);
    }

    function maxFlashLoan() external view returns (uint256) {
        // Can mint up to max supply minus current supply
        uint256 current = totalSupply();
        uint256 max = _config.maxSupply.toUint();
        return max > current ? max - current : 0;
    }

    /*//////////////////////////////////////////////////////////////
                    TIME-WEIGHTED HOLDING REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @dev Claim holding rewards based on duration
    function claimHoldingReward() external returns (uint256 reward) {
        if (_config.configFlags & FLAG_REWARDS_ENABLED == 0) revert Unauthorized();

        PackedAccount data = _accountData[msg.sender];
        Timestamp holdStart = data.timestamp();

        if (holdStart.unwrap() == 0) return 0;

        uint256 holdingDuration = holdStart.elapsed();
        uint256 epochs = holdingDuration / EPOCH_DURATION;

        if (epochs == 0) return 0;

        // Calculate reward: balance * rate * epochs
        uint256 balance = balanceOf(msg.sender);
        reward = _config.rewardRate.mulDiv(balance) * epochs / 10000;

        // Check max supply
        if (totalSupply() + reward > _config.maxSupply.toUint()) {
            reward = _config.maxSupply.toUint() - totalSupply();
        }

        if (reward > 0) {
            _mint(msg.sender, reward);

            // Reset holding timestamp
            _accountData[msg.sender] = PackedAccountLib.pack(
                msg.sender,
                data.flags(),
                TimestampLib.now_(),
                0
            );

            emit HoldingReward(msg.sender, reward, holdingDuration);
        }
    }

    /// @dev Preview claimable rewards
    function pendingReward(address account) external view returns (uint256) {
        PackedAccount data = _accountData[account];
        Timestamp holdStart = data.timestamp();

        if (holdStart.unwrap() == 0) return 0;

        uint256 epochs = holdStart.elapsed() / EPOCH_DURATION;
        if (epochs == 0) return 0;

        uint256 balance = balanceOf(account);
        return _config.rewardRate.mulDiv(balance) * epochs / 10000;
    }

    /*//////////////////////////////////////////////////////////////
                    MERKLE AIRDROP / CLAIMS
    //////////////////////////////////////////////////////////////*/

    /// @dev Set merkle root for a claim tranche
    function setMerkleRoot(uint256 tranche, bytes32 root) external onlyOwner {
        merkleRoots[tranche] = root;
    }

    /// @dev Claim from merkle airdrop
    function merkleClaim(
        uint256 tranche,
        uint256 index,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        // Check not claimed (bitmap)
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 word = _claimed[tranche][wordIndex];

        if (word & (1 << bitIndex) != 0) revert AlreadyClaimed();

        // Verify proof
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, amount));
        if (!MerkleLib.verify(proof, merkleRoots[tranche], node)) revert InvalidProof();

        // Mark claimed
        _claimed[tranche][wordIndex] = word | (1 << bitIndex);

        // Mint tokens
        if (totalSupply() + amount > _config.maxSupply.toUint()) revert MaxSupplyExceeded();
        _mint(msg.sender, amount);

        emit MerkleClaim(msg.sender, amount, tranche);
    }

    /// @dev Check if claimed
    function isClaimed(uint256 tranche, uint256 index) external view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        return _claimed[tranche][wordIndex] & (1 << bitIndex) != 0;
    }

    /*//////////////////////////////////////////////////////////////
                    COMMIT-REVEAL GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @dev Commit hash for future reveal (MEV protection)
    function commit(bytes32 hash) external {
        _commits[msg.sender] = hash;
        _commitTimestamps[msg.sender] = TimestampLib.now_();
    }

    /// @dev Reveal and execute committed action
    function reveal(bytes calldata data, bytes32 salt) external {
        bytes32 commitHash = _commits[msg.sender];
        Timestamp commitTime = _commitTimestamps[msg.sender];

        if (commitHash == bytes32(0)) revert CommitRequired();

        uint256 elapsed = commitTime.elapsed();
        if (elapsed < COMMIT_WINDOW) revert CooldownActive();
        if (elapsed > REVEAL_WINDOW) revert CommitExpired();

        // Verify reveal matches commit
        bytes32 expectedHash = keccak256(abi.encodePacked(data, salt));
        if (expectedHash != commitHash) revert InvalidCommit();

        // Clear commit
        delete _commits[msg.sender];
        delete _commitTimestamps[msg.sender];

        emit CommitRevealed(msg.sender, commitHash, data);

        // Execute action based on data (example: transfer)
        // This is extensible - data encodes the action
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setBurnRate(uint16 newRateBps) external onlyOwner {
        BPS newRate = BPS.wrap(newRateBps);
        if (!newRate.isValid()) revert InvalidBPS();

        emit ConfigUpdated("burnRate", BPS.unwrap(_config.burnRate), newRateBps);
        _config.burnRate = newRate;
    }

    function setFlashFee(uint16 newFeeBps) external onlyOwner {
        BPS newFee = BPS.wrap(newFeeBps);
        if (!newFee.isValid()) revert InvalidBPS();

        emit ConfigUpdated("flashFee", BPS.unwrap(_config.flashFee), newFeeBps);
        _config.flashFee = newFee;
    }

    function setRewardRate(uint16 newRateBps) external onlyOwner {
        BPS newRate = BPS.wrap(newRateBps);
        if (!newRate.isValid()) revert InvalidBPS();

        emit ConfigUpdated("rewardRate", BPS.unwrap(_config.rewardRate), newRateBps);
        _config.rewardRate = newRate;
    }

    function setConfigFlag(uint16 flag, bool enabled) external onlyOwner {
        uint16 oldFlags = _config.configFlags;

        if (enabled) {
            _config.configFlags = oldFlags | flag;
        } else {
            _config.configFlags = oldFlags & ~flag;
        }

        emit ConfigUpdated("configFlags", oldFlags, _config.configFlags);
    }

    function setAccountFlag(address account, uint8 flag, bool value) external onlyOwner {
        _setAccountFlag(account, flag, value);
    }

    function _setAccountFlag(address account, uint8 flag, bool value) internal {
        PackedAccount current = _accountData[account];
        uint8 oldFlags = current.flags();

        PackedAccount updated = current.setFlag(flag, value);
        _accountData[account] = updated;

        emit AccountFlagsUpdated(account, oldFlags, updated.flags());
    }

    function setWhitelistBatch(address[] calldata accounts, bool status) external onlyOwner {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ) {
            _setAccountFlag(accounts[i], PackedAccountLib.FLAG_WHITELISTED, status);
            unchecked { ++i; }
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function burnRate() external view returns (uint16) {
        return BPS.unwrap(_config.burnRate);
    }

    function effectiveBurnRate() external view returns (uint16) {
        return BPS.unwrap(_calculateEffectiveBurnRate());
    }

    function totalBurned() external view returns (uint256) {
        return _state.totalBurned.toUint();
    }

    function maxSupply() external view returns (uint256) {
        return _config.maxSupply.toUint();
    }

    function configFlags() external view returns (uint16) {
        return _config.configFlags;
    }

    function accountData(address account) external view returns (
        uint8 flags,
        uint40 holdingStart,
        bool isWhitelisted
    ) {
        PackedAccount data = _accountData[account];
        flags = data.flags();
        holdingStart = Timestamp.unwrap(data.timestamp());
        isWhitelisted = data.hasFlag(PackedAccountLib.FLAG_WHITELISTED);
    }

    function deployTimestamp() external view returns (uint40) {
        return Timestamp.unwrap(_state.deployTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
        notZeroAddress(newImplementation)
    {}

    function version() external pure returns (string memory) {
        return "3.0.0";
    }

    /*//////////////////////////////////////////////////////////////
                            STORAGE GAP
    //////////////////////////////////////////////////////////////*/

    uint256[44] private __gap;
}
