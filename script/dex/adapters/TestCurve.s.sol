// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../../src/dex/adapters/DEXAdapters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestCurve
 * @notice Script to test Curve adapter functionality
 * @dev Usage: forge script script/dex/adapters/TestCurve.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract TestCurve is Script {
    function run() external {
        address adapterAddress = vm.envAddress("CURVE_ADAPTER");
        CurveAdapter adapter = CurveAdapter(adapterAddress);

        console.log("=== Testing Curve Adapter ===");
        console.log("Adapter:", adapterAddress);
        console.log("Name:", adapter.name());
        console.log("Registry:", address(adapter.registry()));

        // Test stablecoin swaps (Curve's specialty)
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        console.log("\n=== Common Stablecoins ===");
        console.log("USDC:", usdc);
        console.log("USDT:", usdt);
        console.log("DAI:", dai);

        // Test pool finding
        testPoolFinding(adapter, usdc, usdt);
        testPoolFinding(adapter, usdc, dai);
        testPoolFinding(adapter, usdt, dai);

        // Test quotes
        uint256 amount = 1000e6; // 1000 USDC
        testGetQuote(adapter, usdc, usdt, amount);
        testGetQuote(adapter, usdc, dai, amount);

        // Test swap (if enabled)
        bool executeSwap = vm.envOr("EXECUTE_SWAP", false);
        if (executeSwap) {
            address tokenIn = vm.envAddress("TOKEN_IN");
            address tokenOut = vm.envAddress("TOKEN_OUT");
            uint256 amountIn = vm.envUint("AMOUNT_IN");
            testSwap(adapter, tokenIn, tokenOut, amountIn);
        } else {
            console.log("\nSkipping swap execution (set EXECUTE_SWAP=true to enable)");
        }
    }

    function testPoolFinding(
        CurveAdapter adapter,
        address tokenA,
        address tokenB
    ) internal view {
        console.log("\n=== Finding Pool ===");
        console.log("Token A:", tokenA);
        console.log("Token B:", tokenB);

        ICurveRegistry registry = adapter.registry();
        address pool = registry.find_pool_for_coins(tokenA, tokenB);

        console.log("Pool:", pool);

        if (pool != address(0)) {
            console.log("Status: POOL FOUND");

            // Try to get coin indices
            try registry.get_coin_indices(pool, tokenA, tokenB) returns (
                int128 i,
                int128 j,
                bool underlying
            ) {
                console.log("Token A index:", vm.toString(uint128(i)));
                console.log("Token B index:", vm.toString(uint128(j)));
                console.log("Is underlying:", underlying);

                // Check pool coins
                _displayPoolCoins(pool, i, j);
            } catch {
                console.log("Could not get coin indices");
            }
        } else {
            console.log("Status: NO POOL FOUND");
        }
    }

    function _displayPoolCoins(address pool, int128 i, int128 j) internal view {
        console.log("\nPool coins:");

        try ICurvePool(pool).coins(uint256(uint128(i))) returns (address coin) {
            console.log("Coin", vm.toString(uint128(i)), ":", coin);
        } catch {
            console.log("Could not read coin", vm.toString(uint128(i)));
        }

        try ICurvePool(pool).coins(uint256(uint128(j))) returns (address coin) {
            console.log("Coin", vm.toString(uint128(j)), ":", coin);
        } catch {
            console.log("Could not read coin", vm.toString(uint128(j)));
        }
    }

    function testGetQuote(
        CurveAdapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view {
        console.log("\n=== Testing Quote ===");
        console.log("Token In:", tokenIn);
        console.log("Token Out:", tokenOut);
        console.log("Amount In:", amountIn);

        uint256 amountOut = adapter.getQuote(tokenIn, tokenOut, amountIn);
        console.log("Quoted Amount Out:", amountOut);

        if (amountOut > 0) {
            // Calculate exchange rate
            uint256 rate = (amountOut * 1e18) / amountIn;
            console.log("Exchange rate:", rate);

            // Calculate price impact (for stablecoins should be near 1.0)
            if (amountOut > amountIn) {
                console.log("Favorable rate (getting more out)");
            } else {
                uint256 diff = ((amountIn - amountOut) * 10000) / amountIn;
                console.log("Price impact:", diff, "bps");
            }

            console.log("Status: SUCCESS");
        } else {
            console.log("Status: FAILED (no quote)");
        }
    }

    function testSwap(
        CurveAdapter adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        console.log("\n=== Testing Swap ===");

        // Get quote first
        uint256 expectedOut = adapter.getQuote(tokenIn, tokenOut, amountIn);
        require(expectedOut > 0, "Quote is 0, cannot execute swap");

        // For stablecoins, use tighter slippage (0.1%)
        uint256 minAmountOut = (expectedOut * 999) / 1000;
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
            extraData: "" // Let adapter find pool
        });

        uint256 amountOut = adapter.swap(params);
        console.log("Swap executed successfully");
        console.log("Amount out:", amountOut);

        // Check final balance
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);
        console.log("Balance after:", balanceAfter);
        console.log("Received:", balanceAfter - (balanceBefore - amountIn));

        vm.stopBroadcast();

        // Calculate execution metrics
        uint256 slippage = expectedOut > amountOut
            ? ((expectedOut - amountOut) * 10000) / expectedOut
            : 0;

        console.log("\n=== Swap Results ===");
        console.log("Slippage:", slippage, "bps");
        console.log("Status: SUCCESS");
    }

    function analyzeStablecoinPools() external view {
        address adapterAddress = vm.envAddress("CURVE_ADAPTER");
        CurveAdapter adapter = CurveAdapter(adapterAddress);

        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        console.log("=== Stablecoin Pool Analysis ===");

        // Test different amounts
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100e6;      // $100
        amounts[1] = 1000e6;     // $1,000
        amounts[2] = 10000e6;    // $10,000
        amounts[3] = 100000e6;   // $100,000
        amounts[4] = 1000000e6;  // $1,000,000

        console.log("\nUSDC -> USDT rates:");
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 quote = adapter.getQuote(usdc, usdt, amounts[i]);
            uint256 slippage = amounts[i] > quote
                ? ((amounts[i] - quote) * 10000) / amounts[i]
                : 0;
            console.log("Amount:", amounts[i], "- Quote:", quote, "- Slippage:", slippage, "bps");
        }

        console.log("\nUSDC -> DAI rates:");
        for (uint256 i = 0; i < amounts.length; i++) {
            // Adjust for DAI decimals (18)
            uint256 daiAmount = amounts[i] * 1e12;
            uint256 quote = adapter.getQuote(usdc, dai, amounts[i]);
            console.log("Amount:", amounts[i], "- Quote:", quote);
        }
    }

    function testTokenSupport() external view {
        address adapterAddress = vm.envAddress("CURVE_ADAPTER");
        CurveAdapter adapter = CurveAdapter(adapterAddress);

        address[] memory tokens = new address[](10);
        tokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        tokens[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        tokens[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        tokens[3] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        tokens[4] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        tokens[5] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        tokens[6] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        tokens[7] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        tokens[8] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA; // FEI
        tokens[9] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI

        console.log("=== Token Support Check ===");

        for (uint256 i = 0; i < tokens.length; i++) {
            bool supported = adapter.supportsToken(tokens[i]);
            console.log("Token", i, ":", tokens[i]);
            console.log("Supported:", supported);
        }
    }

    function findAllPools() external view {
        address adapterAddress = vm.envAddress("CURVE_ADAPTER");
        CurveAdapter adapter = CurveAdapter(adapterAddress);

        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");

        console.log("=== Finding All Pools ===");
        console.log("Token A:", tokenA);
        console.log("Token B:", tokenB);

        ICurveRegistry registry = adapter.registry();

        // Try to find multiple pools (Curve can have multiple pools for same pair)
        for (uint256 i = 0; i < 10; i++) {
            try registry.find_pool_for_coins(tokenA, tokenB, i) returns (address pool) {
                if (pool == address(0)) break;
                console.log("\nPool", i, ":", pool);
            } catch {
                break;
            }
        }
    }
}
