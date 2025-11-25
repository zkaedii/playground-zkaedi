// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../../src/dex/adapters/DEXAdapters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestUniswapV2
 * @notice Script to test Uniswap V2 adapter functionality
 * @dev Usage: forge script script/dex/adapters/TestUniswapV2.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract TestUniswapV2 is Script {
    function run() external {
        address adapterAddress = vm.envAddress("UNISWAP_V2_ADAPTER");
        UniswapV2Adapter adapter = UniswapV2Adapter(adapterAddress);

        console.log("=== Testing Uniswap V2 Adapter ===");
        console.log("Adapter:", adapterAddress);
        console.log("Name:", adapter.name());
        console.log("Router:", address(adapter.router()));
        console.log("Factory:", address(adapter.factory()));
        console.log("WETH:", adapter.weth());

        // Test tokens
        address tokenIn = vm.envOr("TOKEN_IN", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        address tokenOut = vm.envOr("TOKEN_OUT", adapter.weth()); // WETH
        uint256 amountIn = vm.envOr("AMOUNT_IN", uint256(1000e6)); // 1000 USDC

        console.log("\n=== Test Parameters ===");
        console.log("Token In:", tokenIn);
        console.log("Token Out:", tokenOut);
        console.log("Amount In:", amountIn);

        // Test token support
        testTokenSupport(adapter, tokenIn);

        // Test quote
        testGetQuote(adapter, tokenIn, tokenOut, amountIn);

        // Test swap (if enabled)
        bool executeSwap = vm.envOr("EXECUTE_SWAP", false);
        if (executeSwap) {
            testSwap(adapter, tokenIn, tokenOut, amountIn);
        } else {
            console.log("\nSkipping swap execution (set EXECUTE_SWAP=true to enable)");
        }
    }

    function testTokenSupport(UniswapV2Adapter adapter, address token) internal view {
        console.log("\n=== Testing Token Support ===");
        bool supported = adapter.supportsToken(token);
        console.log("Token supported:", supported);

        if (supported) {
            console.log("Token has liquidity pool with WETH");
        } else {
            console.log("Warning: No direct WETH pair found");
        }
    }

    function testGetQuote(
        UniswapV2Adapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view {
        console.log("\n=== Testing Get Quote ===");

        uint256 amountOut = adapter.getQuote(tokenIn, tokenOut, amountIn);
        console.log("Quoted amount out:", amountOut);

        if (amountOut > 0) {
            // Calculate effective price
            uint256 price = (amountOut * 1e18) / amountIn;
            console.log("Effective price:", price);
            console.log("Quote successful");
        } else {
            console.log("Warning: Quote returned 0 (no liquidity or invalid pair)");
        }
    }

    function testSwap(
        UniswapV2Adapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        console.log("\n=== Testing Swap ===");

        // Get quote first
        uint256 expectedOut = adapter.getQuote(tokenIn, tokenOut, amountIn);
        require(expectedOut > 0, "Quote is 0, cannot execute swap");

        uint256 minAmountOut = (expectedOut * 95) / 100; // 5% slippage
        console.log("Expected out:", expectedOut);
        console.log("Min amount out:", minAmountOut);

        vm.startBroadcast();

        // Check balance
        uint256 balanceBefore = IERC20(tokenIn).balanceOf(msg.sender);
        console.log("Balance before:", balanceBefore);
        require(balanceBefore >= amountIn, "Insufficient balance");

        // Approve adapter
        IERC20(tokenIn).approve(address(adapter), amountIn);
        console.log("Approved adapter");

        // Execute swap
        IDEXAdapter.SwapParams memory params = IDEXAdapter.SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            recipient: msg.sender,
            extraData: ""
        });

        uint256 amountOut = adapter.swap(params);
        console.log("Swap executed successfully");
        console.log("Amount out:", amountOut);

        // Check final balance
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);
        console.log("Balance after:", balanceAfter);

        vm.stopBroadcast();

        // Calculate slippage
        uint256 slippage = expectedOut > amountOut
            ? ((expectedOut - amountOut) * 10000) / expectedOut
            : 0;
        console.log("\n=== Swap Results ===");
        console.log("Slippage:", slippage, "bps");
        console.log("Status: SUCCESS");
    }

    function testMultipleQuotes() external view {
        address adapterAddress = vm.envAddress("UNISWAP_V2_ADAPTER");
        UniswapV2Adapter adapter = UniswapV2Adapter(adapterAddress);

        address weth = adapter.weth();
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        console.log("=== Testing Multiple Quotes ===");

        // Test different pairs
        _testQuote(adapter, weth, usdc, 1 ether, "WETH -> USDC");
        _testQuote(adapter, usdc, weth, 1000e6, "USDC -> WETH");
        _testQuote(adapter, usdc, usdt, 1000e6, "USDC -> USDT");
        _testQuote(adapter, dai, usdc, 1000e18, "DAI -> USDC");
    }

    function _testQuote(
        UniswapV2Adapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        string memory label
    ) internal view {
        console.log("\n", label);
        console.log("Amount in:", amountIn);

        uint256 amountOut = adapter.getQuote(tokenIn, tokenOut, amountIn);
        console.log("Amount out:", amountOut);

        if (amountOut > 0) {
            console.log("Status: SUCCESS");
        } else {
            console.log("Status: NO LIQUIDITY");
        }
    }

    function testDirectVsWETHRoute() external view {
        address adapterAddress = vm.envAddress("UNISWAP_V2_ADAPTER");
        UniswapV2Adapter adapter = UniswapV2Adapter(adapterAddress);

        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");
        uint256 amountIn = vm.envUint("AMOUNT_IN");

        console.log("=== Comparing Routes ===");
        console.log("Token A:", tokenA);
        console.log("Token B:", tokenB);
        console.log("Amount:", amountIn);

        // Try direct route
        IUniswapV2Factory factory = adapter.factory();
        address directPair = factory.getPair(tokenA, tokenB);

        console.log("\nDirect pair:", directPair);

        if (directPair != address(0)) {
            uint256 directQuote = adapter.getQuote(tokenA, tokenB, amountIn);
            console.log("Direct route quote:", directQuote);
        } else {
            console.log("No direct pair exists");
        }

        // WETH route is automatic fallback in adapter
        console.log("\nAdapter will use optimal route automatically");
    }

    function checkLiquidity() external view {
        address adapterAddress = vm.envAddress("UNISWAP_V2_ADAPTER");
        UniswapV2Adapter adapter = UniswapV2Adapter(adapterAddress);

        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");

        IUniswapV2Factory factory = adapter.factory();
        address pair = factory.getPair(tokenA, tokenB);

        console.log("=== Liquidity Check ===");
        console.log("Token A:", tokenA);
        console.log("Token B:", tokenB);
        console.log("Pair address:", pair);

        if (pair != address(0)) {
            uint256 reserveA = IERC20(tokenA).balanceOf(pair);
            uint256 reserveB = IERC20(tokenB).balanceOf(pair);

            console.log("Reserve A:", reserveA);
            console.log("Reserve B:", reserveB);
            console.log("Liquidity: AVAILABLE");
        } else {
            console.log("Liquidity: NOT AVAILABLE");
        }
    }
}
