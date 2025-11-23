// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
                    DEX AGGREGATOR INTERFACES
//////////////////////////////////////////////////////////////*/

/// @title IUniswapV3Router
/// @notice Interface for Uniswap V3 swap router
interface IUniswapV3Router {
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

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

/// @title IUniswapV2Router
/// @notice Interface for Uniswap V2 style routers (SushiSwap, PancakeSwap, etc.)
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    function factory() external view returns (address);
    function WETH() external view returns (address);
}

/// @title ICurvePool
/// @notice Interface for Curve Finance pools
interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
}

/// @title IBalancerVault
/// @notice Interface for Balancer V2 Vault
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

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds
    ) external returns (int256[] memory assetDeltas);
}

/// @title IDEXAggregator
/// @notice Unified DEX aggregator interface
interface IDEXAggregator {
    enum DEXType {
        UNISWAP_V2,
        UNISWAP_V3,
        SUSHISWAP,
        CURVE,
        BALANCER,
        PANCAKESWAP,
        CAMELOT,
        GMX,
        CUSTOM
    }

    struct SwapRoute {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        DEXType dex;
        bytes extraData;            // DEX-specific data (pool addresses, fees, etc.)
    }

    struct SwapQuote {
        uint256 amountOut;          // Expected output amount
        uint256 gasEstimate;        // Estimated gas cost
        uint256 priceImpact;        // Price impact in basis points
        SwapRoute[] routes;         // Optimal route(s)
    }

    struct MultiHopSwap {
        SwapRoute[] hops;           // Sequential swap steps
        uint256 minAmountOut;       // Minimum acceptable output
        uint256 deadline;           // Transaction deadline
    }

    struct SplitSwap {
        SwapRoute[] routes;         // Parallel routes with portions
        uint256[] portions;         // Portion for each route (BPS, sum = 10000)
        uint256 minAmountOut;
        uint256 deadline;
    }

    /// @notice Execute a simple swap
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    /// @notice Execute a multi-hop swap
    function multiHopSwap(MultiHopSwap calldata params, address recipient)
        external payable returns (uint256 amountOut);

    /// @notice Execute a split swap across multiple DEXs
    function splitSwap(SplitSwap calldata params, address recipient)
        external payable returns (uint256 amountOut);

    /// @notice Get the best quote for a swap
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (SwapQuote memory quote);

    /// @notice Get quotes from multiple DEXs
    function getMultiQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        DEXType[] calldata dexes
    ) external view returns (SwapQuote[] memory quotes);
}

/// @title ICrossChainDEX
/// @notice Interface for cross-chain DEX operations
interface ICrossChainDEX {
    struct CrossChainSwap {
        address tokenIn;            // Source token
        address tokenOut;           // Destination token
        uint256 amountIn;           // Input amount
        uint256 minAmountOut;       // Minimum output
        uint256 srcChainId;         // Source chain
        uint256 dstChainId;         // Destination chain
        address recipient;          // Recipient on destination
        bytes bridgeData;           // Bridge-specific data
        bytes swapData;             // DEX-specific swap data
    }

    struct CrossChainQuote {
        uint256 estimatedAmountOut;
        uint256 bridgeFee;
        uint256 swapFee;
        uint256 estimatedTime;
        bytes32 routeId;
    }

    /// @notice Execute a cross-chain swap
    function crossChainSwap(CrossChainSwap calldata params)
        external payable returns (bytes32 txId);

    /// @notice Get a quote for cross-chain swap
    function getCrossChainQuote(CrossChainSwap calldata params)
        external view returns (CrossChainQuote memory quote);

    /// @notice Check the status of a cross-chain swap
    function getCrossChainStatus(bytes32 txId) external view returns (uint8 status, bytes memory data);
}
