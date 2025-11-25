// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/dex/CrossChainDEXRouter.sol";
import "../../src/interfaces/ICrossChain.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CrossChainSwapExample
 * @notice Script to execute cross-chain swaps via CCIP or LayerZero
 * @dev Usage: forge script script/dex/CrossChainSwapExample.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract CrossChainSwapExample is Script {
    function run() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        // Load parameters
        address tokenIn = vm.envAddress("TOKEN_IN");
        address tokenOut = vm.envAddress("TOKEN_OUT");
        uint256 amountIn = vm.envUint("AMOUNT_IN");
        uint256 dstChainId = vm.envUint("DST_CHAIN_ID");
        address recipient = vm.envOr("RECIPIENT", msg.sender);

        console.log("=== Cross-Chain Swap Parameters ===");
        console.log("Router:", routerAddress);
        console.log("Source Chain:", block.chainid);
        console.log("Destination Chain:", dstChainId);
        console.log("Token In:", tokenIn);
        console.log("Token Out:", tokenOut);
        console.log("Amount In:", amountIn);
        console.log("Recipient:", recipient);

        // Build cross-chain swap params
        ICrossChainDEX.CrossChainSwap memory params = ICrossChainDEX.CrossChainSwap({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: (amountIn * 95) / 100, // 5% slippage
            recipient: recipient,
            srcChainId: block.chainid,
            dstChainId: dstChainId,
            swapData: "", // No source chain swap
            bridgeData: "" // Use default bridge token
        });

        // Get quote
        ICrossChainDEX.CrossChainQuote memory quote = router.getCrossChainQuote(params);
        console.log("\n=== Quote ===");
        console.log("Estimated Amount Out:", quote.estimatedAmountOut);
        console.log("Bridge Fee:", quote.bridgeFee);
        console.log("Swap Fee:", quote.swapFee);
        console.log("Estimated Time:", quote.estimatedTime, "seconds");

        uint256 totalFee = quote.bridgeFee + quote.swapFee;
        console.log("Total Fees:", totalFee);

        vm.startBroadcast();

        // Approve tokens
        IERC20(tokenIn).approve(routerAddress, amountIn);
        console.log("\nApproved router to spend tokens");

        // Execute cross-chain swap
        bytes32 txId = router.crossChainSwap{value: quote.bridgeFee}(params);

        console.log("\n=== Cross-Chain Swap Initiated ===");
        console.log("Transaction ID:", vm.toString(txId));
        console.log("Bridge fee paid:", quote.bridgeFee);

        // Check status
        (uint8 status, bytes memory data) = router.getCrossChainStatus(txId);
        console.log("Initial status:", _statusToString(status));

        vm.stopBroadcast();

        console.log("\n=== Instructions ===");
        console.log("1. Wait for cross-chain message to be delivered");
        console.log("2. Check status on destination chain");
        console.log("3. Transaction ID:", vm.toString(txId));
    }

    function checkCrossChainStatus() external view {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        bytes32 txId = vm.envBytes32("TX_ID");

        (uint8 status, bytes memory data) = router.getCrossChainStatus(txId);

        console.log("=== Cross-Chain Swap Status ===");
        console.log("Transaction ID:", vm.toString(txId));
        console.log("Status:", _statusToString(status));

        if (data.length > 0) {
            // Decode swap status
            console.log("Additional data available");
        }
    }

    function estimateCrossChainFees() external view {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        uint256[] memory chainIds = new uint256[](4);
        chainIds[0] = 42161; // Arbitrum
        chainIds[1] = 10;    // Optimism
        chainIds[2] = 137;   // Polygon
        chainIds[3] = 8453;  // Base

        console.log("=== Cross-Chain Fee Estimates ===");
        console.log("From chain:", block.chainid);

        for (uint256 i = 0; i < chainIds.length; i++) {
            ICrossChainDEX.CrossChainSwap memory params = ICrossChainDEX.CrossChainSwap({
                tokenIn: address(0),
                tokenOut: address(0),
                amountIn: 1e18,
                minAmountOut: 0,
                recipient: msg.sender,
                srcChainId: block.chainid,
                dstChainId: chainIds[i],
                swapData: "",
                bridgeData: ""
            });

            try router.getCrossChainQuote(params) returns (ICrossChainDEX.CrossChainQuote memory quote) {
                console.log("\nTo chain:", chainIds[i]);
                console.log("  Bridge fee:", quote.bridgeFee);
                console.log("  Estimated time:", quote.estimatedTime, "seconds");
            } catch {
                console.log("\nChain", chainIds[i], "not configured");
            }
        }
    }

    function _statusToString(uint8 status) internal pure returns (string memory) {
        if (status == 0) return "PENDING";
        if (status == 1) return "COMPLETED";
        if (status == 2) return "FAILED";
        if (status == 3) return "REFUNDED";
        return "UNKNOWN";
    }
}
