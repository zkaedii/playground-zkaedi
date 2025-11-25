// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/dex/CrossChainDEXRouter.sol";
import "../../src/interfaces/IDEXAggregator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ManageDEXRouter
 * @notice Script for administrative operations on CrossChainDEXRouter
 * @dev Usage: forge script script/dex/ManageDEXRouter.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract ManageDEXRouter is Script {
    function run() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        console.log("=== DEX Router Management ===");
        console.log("Router:", routerAddress);
        console.log("Current owner:", router.owner());
        console.log("Protocol fee:", router.protocolFeeBps(), "bps");
        console.log("Max price impact:", router.maxPriceImpactBps(), "bps");
        console.log("Fee recipient:", router.feeRecipient());

        // Select operation
        string memory operation = vm.envOr("OPERATION", string("status"));

        if (keccak256(bytes(operation)) == keccak256(bytes("status"))) {
            displayStatus(router);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("update-fees"))) {
            updateFees(router);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("rescue-tokens"))) {
            rescueTokens(router);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("upgrade"))) {
            upgradeImplementation(router);
        } else {
            console.log("Unknown operation:", operation);
            console.log("Available operations: status, update-fees, rescue-tokens, upgrade");
        }
    }

    function displayStatus(CrossChainDEXRouter router) internal view {
        console.log("\n=== Router Status ===");

        // Protocol parameters
        console.log("\nProtocol Parameters:");
        console.log("  Version:", router.version());
        console.log("  Protocol Fee:", router.protocolFeeBps(), "bps");
        console.log("  Max Price Impact:", router.maxPriceImpactBps(), "bps");
        console.log("  Fee Recipient:", router.feeRecipient());
        console.log("  Wrapped Native:", router.wrappedNative());

        // Oracle and bridges
        console.log("\nOracle & Bridges:");
        console.log("  Oracle:", address(router.oracle()));
        console.log("  CCIP Router:", address(router.ccipRouter()));
        console.log("  LayerZero Endpoint:", address(router.lzEndpoint()));

        // DEX adapters
        console.log("\nDEX Adapters:");
        _displayAdapter(router, IDEXAggregator.DEXType.UNISWAP_V2, "Uniswap V2");
        _displayAdapter(router, IDEXAggregator.DEXType.UNISWAP_V3, "Uniswap V3");
        _displayAdapter(router, IDEXAggregator.DEXType.CURVE, "Curve");
        _displayAdapter(router, IDEXAggregator.DEXType.BALANCER, "Balancer");
        _displayAdapter(router, IDEXAggregator.DEXType.SUSHISWAP, "SushiSwap");

        // Chain configurations
        console.log("\nSupported Chains:");
        _displayChain(router, 1, "Ethereum");
        _displayChain(router, 42161, "Arbitrum");
        _displayChain(router, 10, "Optimism");
        _displayChain(router, 137, "Polygon");
        _displayChain(router, 8453, "Base");

        // Balances
        console.log("\nRouter Balances:");
        console.log("  ETH:", address(router).balance);
    }

    function _displayAdapter(CrossChainDEXRouter router, IDEXAggregator.DEXType dexType, string memory name) internal view {
        address adapter = router.dexAdapters(dexType);
        if (adapter != address(0)) {
            console.log("  ", name, ":", adapter);
        } else {
            console.log("  ", name, ": NOT CONFIGURED");
        }
    }

    function _displayChain(CrossChainDEXRouter router, uint256 chainId, string memory name) internal view {
        uint64 ccipSelector = router.ccipChainSelectors(chainId);
        uint32 lzEid = router.lzEndpointIds(chainId);

        if (ccipSelector != 0 || lzEid != 0) {
            console.log("  ", name, "(", vm.toString(chainId), ")");
            if (ccipSelector != 0) console.log("    CCIP Selector:", ccipSelector);
            if (lzEid != 0) console.log("    LZ EID:", lzEid);
        }
    }

    function updateFees(CrossChainDEXRouter router) internal {
        uint256 newProtocolFee = vm.envOr("NEW_PROTOCOL_FEE_BPS", uint256(0));
        uint256 newMaxPriceImpact = vm.envOr("NEW_MAX_PRICE_IMPACT_BPS", uint256(0));
        address newFeeRecipient = vm.envOr("NEW_FEE_RECIPIENT", address(0));

        console.log("\n=== Updating Fees ===");

        vm.startBroadcast();

        if (newProtocolFee > 0) {
            router.setProtocolFee(newProtocolFee);
            console.log("Updated protocol fee to:", newProtocolFee, "bps");
        }

        if (newMaxPriceImpact > 0) {
            router.setMaxPriceImpact(newMaxPriceImpact);
            console.log("Updated max price impact to:", newMaxPriceImpact, "bps");
        }

        if (newFeeRecipient != address(0)) {
            router.setFeeRecipient(newFeeRecipient);
            console.log("Updated fee recipient to:", newFeeRecipient);
        }

        vm.stopBroadcast();

        console.log("\n=== Fees Updated ===");
    }

    function rescueTokens(CrossChainDEXRouter router) internal {
        address tokenAddress = vm.envAddress("RESCUE_TOKEN");
        uint256 amount = vm.envOr("RESCUE_AMOUNT", uint256(0));

        console.log("\n=== Rescuing Tokens ===");
        console.log("Token:", tokenAddress);

        // If amount is 0, rescue all
        if (amount == 0) {
            amount = IERC20(tokenAddress).balanceOf(address(router));
        }
        console.log("Amount:", amount);

        if (amount == 0) {
            console.log("No tokens to rescue");
            return;
        }

        vm.startBroadcast();

        router.rescueTokens(tokenAddress, amount);
        console.log("Rescued", amount, "tokens to:", msg.sender);

        vm.stopBroadcast();

        // Rescue ETH if requested
        bool rescueETH = vm.envOr("RESCUE_ETH", false);
        if (rescueETH && address(router).balance > 0) {
            console.log("\nRescuing ETH:", address(router).balance);

            vm.startBroadcast();
            router.rescueETH();
            console.log("Rescued ETH to:", msg.sender);
            vm.stopBroadcast();
        }
    }

    function upgradeImplementation(CrossChainDEXRouter router) internal {
        console.log("\n=== Upgrading Implementation ===");
        console.log("Current version:", router.version());

        vm.startBroadcast();

        // Deploy new implementation
        CrossChainDEXRouter newImplementation = new CrossChainDEXRouter();
        console.log("New implementation deployed at:", address(newImplementation));

        // Upgrade
        router.upgradeToAndCall(address(newImplementation), "");
        console.log("Upgraded successfully");
        console.log("New version:", router.version());

        vm.stopBroadcast();

        console.log("\n=== Upgrade Complete ===");
    }

    function setOracle() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        address newOracle = vm.envAddress("NEW_ORACLE");

        console.log("Setting oracle to:", newOracle);

        vm.startBroadcast();
        router.setOracle(newOracle);
        vm.stopBroadcast();

        console.log("Oracle updated successfully");
    }

    function updateBridgeEndpoints() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        address newCCIPRouter = vm.envOr("NEW_CCIP_ROUTER", address(0));
        address newLZEndpoint = vm.envOr("NEW_LZ_ENDPOINT", address(0));

        console.log("=== Updating Bridge Endpoints ===");

        vm.startBroadcast();

        if (newCCIPRouter != address(0)) {
            router.setCCIPRouter(newCCIPRouter);
            console.log("Updated CCIP Router to:", newCCIPRouter);
        }

        if (newLZEndpoint != address(0)) {
            router.setLZEndpoint(newLZEndpoint);
            console.log("Updated LayerZero Endpoint to:", newLZEndpoint);
        }

        vm.stopBroadcast();
    }
}
