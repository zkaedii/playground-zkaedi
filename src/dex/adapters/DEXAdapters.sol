// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*//////////////////////////////////////////////////////////////
                    DEX ADAPTER BASE
//////////////////////////////////////////////////////////////*/

/// @title IDEXAdapter
/// @notice Base interface for all DEX adapters
interface IDEXAdapter {
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        bytes extraData;
    }

    function swap(SwapParams calldata params) external returns (uint256 amountOut);
    function getQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);
    function supportsToken(address token) external view returns (bool);
    function name() external pure returns (string memory);
}

/// @title BaseDEXAdapter
/// @notice Abstract base contract for DEX adapters
abstract contract BaseDEXAdapter is IDEXAdapter {
    using SafeERC20 for IERC20;

    error InsufficientOutput();
    error InvalidToken();
    error SwapFailed();

    /// @dev Approve token spending if needed
    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }

    /// @dev Transfer tokens to recipient
    function _transferOut(address token, address recipient, uint256 amount) internal {
        if (recipient != address(this)) {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }
}

/*//////////////////////////////////////////////////////////////
                    UNISWAP V2 ADAPTER
//////////////////////////////////////////////////////////////*/

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);

    function factory() external view returns (address);
    function WETH() external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @title UniswapV2Adapter
/// @notice Adapter for Uniswap V2 and forks (SushiSwap, PancakeSwap, etc.)
contract UniswapV2Adapter is BaseDEXAdapter {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;
    address public immutable weth;
    string private _name;

    constructor(address _router, string memory name_) {
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(router.factory());
        weth = router.WETH();
        _name = name_;
    }

    function swap(SwapParams calldata params) external override returns (uint256 amountOut) {
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        _approveIfNeeded(params.tokenIn, address(router), params.amountIn);

        address[] memory path = _buildPath(params.tokenIn, params.tokenOut, params.extraData);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            params.amountIn,
            params.minAmountOut,
            path,
            params.recipient,
            block.timestamp
        );

        amountOut = amounts[amounts.length - 1];
        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external view override returns (uint256 amountOut)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Try direct path first
        if (factory.getPair(tokenIn, tokenOut) != address(0)) {
            uint256[] memory amounts = router.getAmountsOut(amountIn, path);
            return amounts[1];
        }

        // Try via WETH
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = weth;
        path[2] = tokenOut;

        if (factory.getPair(tokenIn, weth) != address(0) &&
            factory.getPair(weth, tokenOut) != address(0)) {
            uint256[] memory amounts = router.getAmountsOut(amountIn, path);
            return amounts[2];
        }

        return 0;
    }

    function supportsToken(address token) external view override returns (bool) {
        return factory.getPair(token, weth) != address(0);
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function _buildPath(address tokenIn, address tokenOut, bytes calldata extraData)
        internal view returns (address[] memory path)
    {
        if (extraData.length > 0) {
            path = abi.decode(extraData, (address[]));
        } else if (factory.getPair(tokenIn, tokenOut) != address(0)) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = weth;
            path[2] = tokenOut;
        }
    }
}

/*//////////////////////////////////////////////////////////////
                    UNISWAP V3 ADAPTER
//////////////////////////////////////////////////////////////*/

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @title UniswapV3Adapter
/// @notice Adapter for Uniswap V3 concentrated liquidity pools
contract UniswapV3Adapter is BaseDEXAdapter {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoter;
    IUniswapV3Factory public immutable factory;

    // Standard fee tiers
    uint24 public constant FEE_LOWEST = 100;    // 0.01%
    uint24 public constant FEE_LOW = 500;       // 0.05%
    uint24 public constant FEE_MEDIUM = 3000;   // 0.3%
    uint24 public constant FEE_HIGH = 10000;    // 1%

    uint24[] public feeTiers;

    constructor(address _router, address _quoter, address _factory) {
        swapRouter = ISwapRouter(_router);
        quoter = IQuoterV2(_quoter);
        factory = IUniswapV3Factory(_factory);

        feeTiers = new uint24[](4);
        feeTiers[0] = FEE_LOWEST;
        feeTiers[1] = FEE_LOW;
        feeTiers[2] = FEE_MEDIUM;
        feeTiers[3] = FEE_HIGH;
    }

    function swap(SwapParams calldata params) external override returns (uint256 amountOut) {
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        _approveIfNeeded(params.tokenIn, address(swapRouter), params.amountIn);

        // Decode fee from extraData or find best fee tier
        uint24 fee;
        if (params.extraData.length >= 3) {
            fee = abi.decode(params.extraData, (uint24));
        } else {
            fee = _findBestFeeTier(params.tokenIn, params.tokenOut);
        }

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: fee,
            recipient: params.recipient,
            deadline: block.timestamp,
            amountIn: params.amountIn,
            amountOutMinimum: params.minAmountOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(swapParams);
        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external override returns (uint256 amountOut)
    {
        uint24 bestFee = _findBestFeeTier(tokenIn, tokenOut);
        if (bestFee == 0) return 0;

        try quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                fee: bestFee,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 out, uint160, uint32, uint256) {
            return out;
        } catch {
            return 0;
        }
    }

    function supportsToken(address token) external view override returns (bool) {
        // Check if any pool exists with WETH
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH
        for (uint256 i; i < feeTiers.length; ++i) {
            if (factory.getPool(token, weth, feeTiers[i]) != address(0)) {
                return true;
            }
        }
        return false;
    }

    function name() external pure override returns (string memory) {
        return "UniswapV3";
    }

    function _findBestFeeTier(address tokenIn, address tokenOut) internal view returns (uint24) {
        for (uint256 i; i < feeTiers.length; ++i) {
            if (factory.getPool(tokenIn, tokenOut, feeTiers[i]) != address(0)) {
                return feeTiers[i];
            }
        }
        return 0;
    }
}

/*//////////////////////////////////////////////////////////////
                    CURVE ADAPTER
//////////////////////////////////////////////////////////////*/

interface ICurveRegistry {
    function find_pool_for_coins(address from, address to) external view returns (address);
    function find_pool_for_coins(address from, address to, uint256 i) external view returns (address);
    function get_coin_indices(address pool, address from, address to) external view returns (int128, int128, bool);
    function get_exchange_amount(address pool, address from, address to, uint256 amount) external view returns (uint256);
}

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
}

/// @title CurveAdapter
/// @notice Adapter for Curve Finance stableswap and cryptoswap pools
contract CurveAdapter is BaseDEXAdapter {
    using SafeERC20 for IERC20;

    ICurveRegistry public immutable registry;

    constructor(address _registry) {
        registry = ICurveRegistry(_registry);
    }

    function swap(SwapParams calldata params) external override returns (uint256 amountOut) {
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Find pool and indices
        address pool;
        int128 i;
        int128 j;
        bool isUnderlying;

        if (params.extraData.length > 0) {
            (pool, i, j, isUnderlying) = abi.decode(params.extraData, (address, int128, int128, bool));
        } else {
            pool = registry.find_pool_for_coins(params.tokenIn, params.tokenOut);
            (i, j, isUnderlying) = registry.get_coin_indices(pool, params.tokenIn, params.tokenOut);
        }

        _approveIfNeeded(params.tokenIn, pool, params.amountIn);

        if (isUnderlying) {
            amountOut = ICurvePool(pool).exchange_underlying(i, j, params.amountIn, params.minAmountOut);
        } else {
            amountOut = ICurvePool(pool).exchange(i, j, params.amountIn, params.minAmountOut);
        }

        _transferOut(params.tokenOut, params.recipient, amountOut);

        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external view override returns (uint256 amountOut)
    {
        address pool = registry.find_pool_for_coins(tokenIn, tokenOut);
        if (pool == address(0)) return 0;

        try registry.get_exchange_amount(pool, tokenIn, tokenOut, amountIn) returns (uint256 out) {
            return out;
        } catch {
            return 0;
        }
    }

    function supportsToken(address token) external view override returns (bool) {
        // Check against common stablecoins
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        return registry.find_pool_for_coins(token, usdc) != address(0);
    }

    function name() external pure override returns (string memory) {
        return "Curve";
    }
}

/*//////////////////////////////////////////////////////////////
                    BALANCER V2 ADAPTER
//////////////////////////////////////////////////////////////*/

interface IBalancerVault {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    function getPoolTokens(bytes32 poolId) external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 lastChangeBlock
    );
}

interface IBalancerQueries {
    function querySwap(
        IBalancerVault.SingleSwap memory singleSwap,
        IBalancerVault.FundManagement memory funds
    ) external returns (uint256);
}

/// @title BalancerV2Adapter
/// @notice Adapter for Balancer V2 weighted and stable pools
contract BalancerV2Adapter is BaseDEXAdapter {
    using SafeERC20 for IERC20;

    IBalancerVault public immutable vault;
    IBalancerQueries public immutable queries;

    // Pool registry: token pair hash => pool ID
    mapping(bytes32 => bytes32) public poolIds;

    // Track tokens that have registered pools
    mapping(address => bool) public supportedTokens;

    constructor(address _vault, address _queries) {
        vault = IBalancerVault(_vault);
        queries = IBalancerQueries(_queries);
    }

    function swap(SwapParams calldata params) external override returns (uint256 amountOut) {
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        _approveIfNeeded(params.tokenIn, address(vault), params.amountIn);

        bytes32 poolId;
        if (params.extraData.length >= 32) {
            poolId = abi.decode(params.extraData, (bytes32));
        } else {
            poolId = poolIds[_pairHash(params.tokenIn, params.tokenOut)];
        }

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: poolId,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: params.tokenIn,
            assetOut: params.tokenOut,
            amount: params.amountIn,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(params.recipient),
            toInternalBalance: false
        });

        amountOut = vault.swap(singleSwap, funds, params.minAmountOut, block.timestamp);
        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external override returns (uint256 amountOut)
    {
        bytes32 poolId = poolIds[_pairHash(tokenIn, tokenOut)];
        if (poolId == bytes32(0)) return 0;

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: poolId,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: tokenIn,
            assetOut: tokenOut,
            amount: amountIn,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        try queries.querySwap(singleSwap, funds) returns (uint256 out) {
            return out;
        } catch {
            return 0;
        }
    }

    function supportsToken(address token) external view override returns (bool) {
        return supportedTokens[token];
    }

    function name() external pure override returns (string memory) {
        return "BalancerV2";
    }

    function registerPool(address tokenA, address tokenB, bytes32 poolId) external {
        poolIds[_pairHash(tokenA, tokenB)] = poolId;
        supportedTokens[tokenA] = true;
        supportedTokens[tokenB] = true;
    }

    function _pairHash(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            tokenA < tokenB ? tokenA : tokenB,
            tokenA < tokenB ? tokenB : tokenA
        ));
    }
}
