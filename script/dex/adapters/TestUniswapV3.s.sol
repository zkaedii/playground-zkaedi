// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../../src/dex/adapters/DEXAdapters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestUniswapV3
 * @notice Script to test Uniswap V3 adapter functionality
 * @dev Usage: forge script script/dex/adapters/TestUniswapV3.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract TestUniswapV3 is Script {
    function run() external {
        address adapterAddress = vm.envAddress("UNISWAP_V3_ADAPTER");
        UniswapV3Adapter adapter = UniswapV3Adapter(adapterAddress);

        console.log("=== Testing Uniswap V3 Adapter ===");
        console.log("Adapter:", adapterAddress);
        console.log("Name:", adapter.name());
        console.log("Router:", address(adapter.swapRouter()));
        console.log("Quoter:", address(adapter.quoter()));
        console.log("Factory:", address(adapter.factory()));

        // Test tokens
        address tokenIn = vm.envOr("TOKEN_IN", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        address tokenOut = vm.envOr("TOKEN_OUT", 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
        uint256 amountIn = vm.envOr("AMOUNT_IN", uint256(1000e6)); // 1000 USDC

        console.log("\n=== Test Parameters ===");
        console.log("Token In:", tokenIn);
        console.log("Token Out:", tokenOut);
        console.log("Amount In:", amountIn);

        // Test all fee tiers
        testAllFeeTiers(adapter, tokenIn, tokenOut);

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

    function testAllFeeTiers(
        UniswapV3Adapter adapter,
        address tokenIn,
        address tokenOut
    ) internal view {
        console.log("\n=== Testing Fee Tiers ===");

        IUniswapV3Factory factory = adapter.factory();

        uint24[4] memory fees = [
            adapter.FEE_LOWEST(),  // 0.01%
            adapter.FEE_LOW(),     // 0.05%
            adapter.FEE_MEDIUM(),  // 0.3%
            adapter.FEE_HIGH()     // 1%
        ];

        string[4] memory labels = [
            "0.01%",
            "0.05%",
            "0.3%",
            "1%"
        ];

        for (uint256 i = 0; i < fees.length; i++) {
            address pool = factory.getPool(tokenIn, tokenOut, fees[i]);

            console.log("\nFee tier:", labels[i], "(", fees[i], ")");
            console.log("Pool:", pool);

            if (pool != address(0)) {
                console.log("Status: ACTIVE");

                // Check liquidity
                uint256 liquidityIn = IERC20(tokenIn).balanceOf(pool);
                uint256 liquidityOut = IERC20(tokenOut).balanceOf(pool);
                console.log("Token In liquidity:", liquidityIn);
                console.log("Token Out liquidity:", liquidityOut);
            } else {
                console.log("Status: NOT AVAILABLE");
            }
        }
    }

    function testGetQuote(
        UniswapV3Adapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        console.log("\n=== Testing Get Quote ===");

        uint256 amountOut = adapter.getQuote(tokenIn, tokenOut, amountIn);
        console.log("Quoted amount out:", amountOut);

        if (amountOut > 0) {
            // Calculate effective price
            uint256 price = (amountOut * 1e18) / amountIn;
            console.log("Effective price:", price);
            console.log("Quote successful");

            // Compare with different fee tiers manually
            _compareFeeTiers(adapter, tokenIn, tokenOut, amountIn);
        } else {
            console.log("Warning: Quote returned 0 (no liquidity or invalid pair)");
        }
    }

    function _compareFeeTiers(
        UniswapV3Adapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        console.log("\n=== Comparing Fee Tiers ===");

        uint24[4] memory fees = [
            adapter.FEE_LOWEST(),
            adapter.FEE_LOW(),
            adapter.FEE_MEDIUM(),
            adapter.FEE_HIGH()
        ];

        IUniswapV3Factory factory = adapter.factory();
        uint256 bestQuote = 0;
        uint24 bestFee = 0;

        for (uint256 i = 0; i < fees.length; i++) {
            address pool = factory.getPool(tokenIn, tokenOut, fees[i]);
            if (pool == address(0)) continue;

            // Try to get quote for this fee tier
            try adapter.quoter().quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: fees[i],
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountOut, uint160, uint32, uint256) {
                console.log("Fee", fees[i], "bps - Quote:", amountOut);

                if (amountOut > bestQuote) {
                    bestQuote = amountOut;
                    bestFee = fees[i];
                }
            } catch {
                console.log("Fee", fees[i], "bps - No quote available");
            }
        }

        console.log("\nBest fee tier:", bestFee, "bps");
        console.log("Best quote:", bestQuote);
    }

    function testSwap(
        UniswapV3Adapter adapter,
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

        // Execute swap (adapter will auto-select best fee tier)
        IDEXAdapter.SwapParams memory params = IDEXAdapter.SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            recipient: msg.sender,
            extraData: "" // Auto-select fee tier
        });

        uint256 amountOut = adapter.swap(params);
        console.log("Swap executed successfully");
        console.log("Amount out:", amountOut);

        // Check final balance
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);
        console.log("Balance after:", balanceAfter);

        vm.stopBroadcast();

        // Calculate metrics
        uint256 slippage = expectedOut > amountOut
            ? ((expectedOut - amountOut) * 10000) / expectedOut
            : 0;

        console.log("\n=== Swap Results ===");
        console.log("Slippage:", slippage, "bps");
        console.log("Status: SUCCESS");
    }

    function testSpecificFeeTier() external {
        address adapterAddress = vm.envAddress("UNISWAP_V3_ADAPTER");
        UniswapV3Adapter adapter = UniswapV3Adapter(adapterAddress);

        address tokenIn = vm.envAddress("TOKEN_IN");
        address tokenOut = vm.envAddress("TOKEN_OUT");
        uint256 amountIn = vm.envUint("AMOUNT_IN");
        uint24 feeTier = uint24(vm.envUint("FEE_TIER"));

        console.log("=== Testing Specific Fee Tier ===");
        console.log("Fee tier:", feeTier, "bps");

        vm.startBroadcast();

        IERC20(tokenIn).approve(address(adapter), amountIn);

        // Encode fee tier in extraData
        bytes memory extraData = abi.encode(feeTier);

        IDEXAdapter.SwapParams memory params = IDEXAdapter.SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: 0,
            recipient: msg.sender,
            extraData: extraData
        });

        uint256 amountOut = adapter.swap(params);
        console.log("Amount out:", amountOut);

        vm.stopBroadcast();
    }

    function analyzePool() external view {
        address adapterAddress = vm.envAddress("UNISWAP_V3_ADAPTER");
        UniswapV3Adapter adapter = UniswapV3Adapter(adapterAddress);

        address tokenIn = vm.envAddress("TOKEN_IN");
        address tokenOut = vm.envAddress("TOKEN_OUT");
        uint24 feeTier = uint24(vm.envUint("FEE_TIER"));

        IUniswapV3Factory factory = adapter.factory();
        address pool = factory.getPool(tokenIn, tokenOut, feeTier);

        console.log("=== Pool Analysis ===");
        console.log("Pool:", pool);

        if (pool == address(0)) {
            console.log("Pool does not exist");
            return;
        }

        console.log("Token 0:", tokenIn);
        console.log("Token 1:", tokenOut);
        console.log("Fee tier:", feeTier);

        // Check balances
        uint256 balance0 = IERC20(tokenIn).balanceOf(pool);
        uint256 balance1 = IERC20(tokenOut).balanceOf(pool);

        console.log("\nLiquidity:");
        console.log("Token 0 balance:", balance0);
        console.log("Token 1 balance:", balance1);

        if (balance0 > 0 && balance1 > 0) {
            console.log("Status: ACTIVE LIQUIDITY");
        } else {
            console.log("Status: LOW/NO LIQUIDITY");
        }
    }

    function benchmarkFeeTiers() external view {
        address adapterAddress = vm.envAddress("UNISWAP_V3_ADAPTER");
        UniswapV3Adapter adapter = UniswapV3Adapter(adapterAddress);

        address tokenIn = vm.envAddress("TOKEN_IN");
        address tokenOut = vm.envAddress("TOKEN_OUT");

        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 100e6;   // $100
        testAmounts[1] = 1000e6;  // $1,000
        testAmounts[2] = 10000e6; // $10,000
        testAmounts[3] = 50000e6; // $50,000
        testAmounts[4] = 100000e6; // $100,000

        console.log("=== Benchmarking Fee Tiers ===");

        for (uint256 i = 0; i < testAmounts.length; i++) {
            console.log("\nAmount:", testAmounts[i]);
            uint256 quote = adapter.getQuote(tokenIn, tokenOut, testAmounts[i]);
            console.log("Best quote:", quote);
        }
    }
}
