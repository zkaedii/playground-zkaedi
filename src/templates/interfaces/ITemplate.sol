// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Interface Templates
 * @notice Collection of common interface patterns for DeFi protocols
 * @dev Use these as starting points for your protocol interfaces
 */

// ============ BASIC INTERFACES ============

/**
 * @title IERC20Extended
 * @notice Extended ERC20 interface with common extensions
 */
interface IERC20Extended {
    // Core ERC20
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    // Metadata
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    // Permit (EIP-2612)
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // Mint/Burn (optional)
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title IERC721Extended
 * @notice Extended ERC721 interface with common extensions
 */
interface IERC721Extended {
    // Core ERC721
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    // Metadata
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);

    // Enumerable
    function totalSupply() external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function tokenByIndex(uint256 index) external view returns (uint256);

    // Royalty (EIP-2981)
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);

    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}

// ============ DEFI INTERFACES ============

/**
 * @title IStaking
 * @notice Standard staking interface
 */
interface IStaking {
    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 stakedAt;
        uint256 lockEndTime;
    }

    // Core functions
    function stake(uint256 amount, uint256 lockPeriod) external;
    function unstake(uint256 amount) external;
    function claimRewards() external;
    function compound() external;
    function emergencyWithdraw() external;

    // View functions
    function pendingRewards(address user) external view returns (uint256);
    function getStakeInfo(address user) external view returns (StakeInfo memory);
    function totalStaked() external view returns (uint256);
    function rewardPerSecond() external view returns (uint256);
    function getAPY(uint256 lockPeriod) external view returns (uint256);

    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsCompounded(address indexed user, uint256 amount);
}

/**
 * @title IVault
 * @notice ERC4626 compliant vault interface
 */
interface IVault {
    // ERC4626 Core
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    // Events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
}

/**
 * @title IStrategy
 * @notice Yield strategy interface for vaults
 */
interface IStrategy {
    function vault() external view returns (address);
    function want() external view returns (address);
    function totalAssets() external view returns (uint256);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256);
    function harvest() external returns (uint256);
    function emergencyWithdraw() external;

    function estimatedAPY() external view returns (uint256);
    function isActive() external view returns (bool);

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 profit);
}

/**
 * @title ILendingPool
 * @notice Basic lending pool interface
 */
interface ILendingPool {
    struct UserAccount {
        uint256 deposited;
        uint256 borrowed;
        uint256 collateral;
        uint256 lastUpdate;
    }

    function deposit(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function borrow(address asset, uint256 amount) external;
    function repay(address asset, uint256 amount) external;
    function liquidate(address borrower, address collateralAsset, address debtAsset) external;

    function getUserAccount(address user) external view returns (UserAccount memory);
    function getHealthFactor(address user) external view returns (uint256);
    function getAvailableBorrow(address user) external view returns (uint256);

    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event Liquidated(address indexed liquidator, address indexed borrower, uint256 amount);
}

/**
 * @title IAMM
 * @notice Automated Market Maker interface
 */
interface IAMM {
    struct Pool {
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalLiquidity;
        uint256 fee;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory);
    function getPool(address tokenA, address tokenB) external view returns (Pool memory);

    event LiquidityAdded(address indexed provider, address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed provider, address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);
    event Swap(address indexed sender, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
}

// ============ GOVERNANCE INTERFACES ============

/**
 * @title IGovernor
 * @notice Governance contract interface
 */
interface IGovernor {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
    }

    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256);

    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);

    function cancel(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external returns (uint256);

    function state(uint256 proposalId) external view returns (ProposalState);
    function proposalThreshold() external view returns (uint256);
    function quorum(uint256 blockNumber) external view returns (uint256);
    function getVotes(address account, uint256 blockNumber) external view returns (uint256);
    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 support, uint256 weight, string reason);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
}

/**
 * @title ITimelock
 * @notice Timelock controller interface
 */
interface ITimelock {
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;

    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;

    function cancel(bytes32 id) external;

    function getMinDelay() external view returns (uint256);
    function isOperation(bytes32 id) external view returns (bool);
    function isOperationPending(bytes32 id) external view returns (bool);
    function isOperationReady(bytes32 id) external view returns (bool);
    function isOperationDone(bytes32 id) external view returns (bool);
    function getTimestamp(bytes32 id) external view returns (uint256);

    event CallScheduled(bytes32 indexed id, address indexed target, uint256 value, bytes data, uint256 delay);
    event CallExecuted(bytes32 indexed id, address indexed target, uint256 value, bytes data);
    event Cancelled(bytes32 indexed id);
}

// ============ ORACLE INTERFACES ============

/**
 * @title IPriceOracle
 * @notice Price oracle interface
 */
interface IPriceOracle {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint8 decimals;
    }

    function getPrice(address asset) external view returns (uint256);
    function getPriceData(address asset) external view returns (PriceData memory);
    function getLatestRoundData(address asset) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    function updatePrice(address asset, uint256 price) external;
    function setFeed(address asset, address feed) external;

    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
}

// ============ CROSS-CHAIN INTERFACES ============

/**
 * @title ICrossChainBridge
 * @notice Cross-chain bridge interface
 */
interface ICrossChainBridge {
    struct BridgeMessage {
        uint256 nonce;
        address sender;
        address recipient;
        uint256 amount;
        uint256 sourceChainId;
        uint256 destChainId;
        bytes data;
    }

    function bridgeTokens(
        address token,
        uint256 amount,
        uint256 destChainId,
        address recipient
    ) external payable returns (bytes32 messageId);

    function receiveMessage(
        BridgeMessage calldata message,
        bytes calldata proof
    ) external;

    function estimateFee(
        uint256 destChainId,
        uint256 amount
    ) external view returns (uint256);

    function getMessageStatus(bytes32 messageId) external view returns (uint8);

    event TokensBridged(bytes32 indexed messageId, address indexed sender, uint256 amount, uint256 destChainId);
    event TokensReceived(bytes32 indexed messageId, address indexed recipient, uint256 amount);
}

// ============ CALLBACK INTERFACES ============

/**
 * @title IFlashLoanReceiver
 * @notice Flash loan callback interface
 */
interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/**
 * @title ISwapCallback
 * @notice Swap callback interface (Uniswap V3 style)
 */
interface ISwapCallback {
    function swapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}
