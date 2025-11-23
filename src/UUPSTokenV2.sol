// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UUPSTokenV2
 * @notice Enhanced UUPS token with tokenomics features:
 *         - Transaction-based burn (0.5% default)
 *         - Whitelist for fee exemptions
 *         - Governance integration hooks
 *         - Emergency pause functionality
 * @dev Upgradeable implementation for existing UUPS token
 */
contract UUPSTokenV2 is
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokensBurned(address indexed from, uint256 amount);
    event BurnRateUpdated(uint256 oldRate, uint256 newRate);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    event StakingContractSet(address indexed stakingContract);
    event GovernanceContractSet(address indexed governanceContract);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Burn rate in basis points (50 = 0.5%)
    uint256 public burnRate;

    /// @notice Maximum burn rate (10% = 1000 bps)
    uint256 public constant MAX_BURN_RATE = 1000;

    /// @notice Addresses exempt from transfer fees
    mapping(address => bool) public isWhitelisted;

    /// @notice Staking contract address (for emissions)
    address public stakingContract;

    /// @notice Governance contract address (for voting power)
    address public governanceContract;

    /// @notice Total tokens burned
    uint256 public totalBurned;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        require(msg.sender == governanceContract, "Only governance");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize V2 with tokenomics parameters
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _initialSupply Initial supply (with 18 decimals)
     * @param _burnRate Initial burn rate (basis points)
     */
    function initializeV2(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _burnRate
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        require(_burnRate <= MAX_BURN_RATE, "Burn rate too high");
        burnRate = _burnRate;

        // Mint initial supply to deployer
        _mint(msg.sender, _initialSupply);

        // Whitelist deployer initially
        isWhitelisted[msg.sender] = true;
    }

    /**
     * @notice Reinitializer for upgrading from V1 to V2
     * @dev Use this when upgrading existing token
     * @param _burnRate Initial burn rate
     */
    function reinitializeV2(uint256 _burnRate) public reinitializer(2) {
        require(_burnRate <= MAX_BURN_RATE, "Burn rate too high");
        burnRate = _burnRate;

        // Whitelist owner
        isWhitelisted[owner()] = true;
    }

    /*//////////////////////////////////////////////////////////////
                          TOKENOMICS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enhanced transfer with burn mechanism
     * @dev Burns a percentage of each transfer (unless whitelisted)
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        // Skip burn logic for:
        // - Minting (from == address(0))
        // - Burning (to == address(0))
        // - Whitelisted addresses
        // - Staking contract (to prevent double burn)
        if (
            from == address(0) ||
            to == address(0) ||
            isWhitelisted[from] ||
            isWhitelisted[to] ||
            from == stakingContract ||
            to == stakingContract
        ) {
            super._update(from, to, amount);
            return;
        }

        // Calculate burn amount
        uint256 burnAmount = (amount * burnRate) / 10000;
        uint256 netAmount = amount - burnAmount;

        // Execute burn
        if (burnAmount > 0) {
            super._update(from, address(0), burnAmount);
            totalBurned += burnAmount;
            emit TokensBurned(from, burnAmount);
        }

        // Execute transfer
        super._update(from, to, netAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update burn rate
     * @param _newRate New burn rate in basis points
     */
    function setBurnRate(uint256 _newRate) external onlyOwner {
        require(_newRate <= MAX_BURN_RATE, "Burn rate too high");
        uint256 oldRate = burnRate;
        burnRate = _newRate;
        emit BurnRateUpdated(oldRate, _newRate);
    }

    /**
     * @notice Update whitelist status
     * @param account Address to update
     * @param status Whitelist status
     */
    function setWhitelist(address account, bool status) external onlyOwner {
        isWhitelisted[account] = status;
        emit WhitelistUpdated(account, status);
    }

    /**
     * @notice Batch update whitelist
     * @param accounts Array of addresses
     * @param status Whitelist status for all
     */
    function setWhitelistBatch(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = status;
            emit WhitelistUpdated(accounts[i], status);
        }
    }

    /**
     * @notice Set staking contract address
     * @param _stakingContract Staking contract address
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        require(_stakingContract != address(0), "Invalid address");
        stakingContract = _stakingContract;
        isWhitelisted[_stakingContract] = true; // Auto-whitelist
        emit StakingContractSet(_stakingContract);
    }

    /**
     * @notice Set governance contract address
     * @param _governanceContract Governance contract address
     */
    function setGovernanceContract(address _governanceContract) external onlyOwner {
        require(_governanceContract != address(0), "Invalid address");
        governanceContract = _governanceContract;
        isWhitelisted[_governanceContract] = true; // Auto-whitelist
        emit GovernanceContractSet(_governanceContract);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint new tokens (governance-only)
     * @dev Used for emissions, rewards, etc.
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function governanceMint(address to, uint256 amount) external onlyGovernance {
        _mint(to, amount);
    }

    /**
     * @notice Emergency burn (governance-only)
     * @dev Requires 75% governance approval
     * @param amount Amount to burn
     */
    function emergencyBurn(uint256 amount) external onlyGovernance {
        _burn(address(this), amount);
        totalBurned += amount;
        emit TokensBurned(address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate effective transfer amount after burn
     * @param amount Gross transfer amount
     * @param from Sender address
     * @param to Recipient address
     * @return netAmount Net amount received
     * @return burnAmount Amount burned
     */
    function calculateTransferAmounts(
        uint256 amount,
        address from,
        address to
    ) external view returns (uint256 netAmount, uint256 burnAmount) {
        // Check if burn applies
        if (
            from == address(0) ||
            to == address(0) ||
            isWhitelisted[from] ||
            isWhitelisted[to] ||
            from == stakingContract ||
            to == stakingContract
        ) {
            return (amount, 0);
        }

        burnAmount = (amount * burnRate) / 10000;
        netAmount = amount - burnAmount;
    }

    /**
     * @notice Get total supply minus burned tokens
     * @dev For accurate circulating supply calculation
     */
    function circulatingSupply() external view returns (uint256) {
        return totalSupply();
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Authorize upgrade to new implementation
     * @dev Only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Get implementation version
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
