// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/dex/CrossChainDEXRouter.sol";
import "../../src/interfaces/IDEXAggregator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ExecuteSwap
 * @notice Script to execute token swaps through CrossChainDEXRouter
 * @dev Usage: forge script script/dex/ExecuteSwap.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract ExecuteSwap is Script {
    function run() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        // Swap parameters from environment
        address tokenIn = vm.envAddress("TOKEN_IN");
        address tokenOut = vm.envAddress("TOKEN_OUT");
        uint256 amountIn = vm.envUint("AMOUNT_IN");
        uint256 slippageBps = vm.envOr("SLIPPAGE_BPS", uint256(50)); // 0.5% default
        address recipient = vm.envOr("RECIPIENT", msg.sender);

        console.log("=== Executing Swap ===");
        console.log("Router:", routerAddress);
        console.log("Token In:", tokenIn);
        console.log("Token Out:", tokenOut);
        console.log("Amount In:", amountIn);
        console.log("Slippage:", slippageBps, "bps");
        console.log("Recipient:", recipient);

        // Get quote
        IDEXAggregator.SwapQuote memory quote = router.getQuote(tokenIn, tokenOut, amountIn);
        console.log("\nQuote:");
        console.log("Expected Amount Out:", quote.amountOut);
        console.log("Gas Estimate:", quote.gasEstimate);
        console.log("Best DEX:", uint256(quote.routes[0].dex));

        // Calculate minimum amount out with slippage
        uint256 minAmountOut = (quote.amountOut * (10000 - slippageBps)) / 10000;
        console.log("Min Amount Out (with slippage):", minAmountOut);

        vm.startBroadcast();

        // Approve router to spend tokens
        IERC20(tokenIn).approve(routerAddress, amountIn);
        console.log("\nApproved router to spend", amountIn, "tokens");

        // Check balance before
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);
        console.log("Balance before:", balanceBefore);

        // Execute swap
        uint256 deadline = block.timestamp + 300; // 5 minutes
        uint256 amountOut = router.swap(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            recipient,
            deadline
        );

        // Check balance after
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(recipient);
        console.log("Balance after:", balanceAfter);
        console.log("Actual Amount Out:", amountOut);
        console.log("Tokens received:", balanceAfter - balanceBefore);

        vm.stopBroadcast();

        // Calculate execution metrics
        uint256 priceImpact = quote.amountOut > amountOut
            ? ((quote.amountOut - amountOut) * 10000) / quote.amountOut
            : 0;

        console.log("\n=== Swap Complete ===");
        console.log("Price Impact:", priceImpact, "bps");
        console.log("Status: SUCCESS");
    }

    function executeMultiHopSwap() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        console.log("=== Executing Multi-Hop Swap ===");

        // Example: USDC -> WETH -> USDT
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        uint256 amountIn = 1000e6; // 1000 USDC

        // Build hops
        IDEXAggregator.SwapRoute[] memory hops = new IDEXAggregator.SwapRoute[](2);

        hops[0] = IDEXAggregator.SwapRoute({
            tokenIn: usdc,
            tokenOut: weth,
            amountIn: amountIn,
            dex: IDEXAggregator.DEXType.UNISWAP_V3,
            extraData: ""
        });

        hops[1] = IDEXAggregator.SwapRoute({
            tokenIn: weth,
            tokenOut: usdt,
            amountIn: 0, // Filled from previous hop
            dex: IDEXAggregator.DEXType.UNISWAP_V3,
            extraData: ""
        });

        IDEXAggregator.MultiHopSwap memory params = IDEXAggregator.MultiHopSwap({
            hops: hops,
            minAmountOut: 900e6, // Min 900 USDT
            deadline: block.timestamp + 300
        });

        vm.startBroadcast();

        IERC20(usdc).approve(routerAddress, amountIn);
        uint256 amountOut = router.multiHopSwap(params, msg.sender);

        console.log("Multi-hop swap complete. Amount out:", amountOut);

        vm.stopBroadcast();
    }
}
