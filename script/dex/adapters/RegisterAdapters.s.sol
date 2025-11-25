// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../../src/dex/CrossChainDEXRouter.sol";
import "../../../src/interfaces/IDEXAggregator.sol";

/**
 * @title RegisterAdapters
 * @notice Script to register DEX adapters with CrossChainDEXRouter
 * @dev Usage: forge script script/dex/adapters/RegisterAdapters.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract RegisterAdapters is Script {
    function run() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        console.log("=== Registering DEX Adapters ===");
        console.log("Router:", routerAddress);
        console.log("Owner:", router.owner());

        // Load adapter addresses
        address uniswapV2Adapter = vm.envOr("UNISWAP_V2_ADAPTER", address(0));
        address uniswapV3Adapter = vm.envOr("UNISWAP_V3_ADAPTER", address(0));
        address curveAdapter = vm.envOr("CURVE_ADAPTER", address(0));
        address balancerAdapter = vm.envOr("BALANCER_ADAPTER", address(0));
        address sushiswapAdapter = vm.envOr("SUSHISWAP_ADAPTER", address(0));

        vm.startBroadcast();

        uint256 registeredCount = 0;

        if (uniswapV2Adapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.UNISWAP_V2, uniswapV2Adapter);
            console.log("\nRegistered Uniswap V2:", uniswapV2Adapter);
            registeredCount++;
        }

        if (uniswapV3Adapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.UNISWAP_V3, uniswapV3Adapter);
            console.log("Registered Uniswap V3:", uniswapV3Adapter);
            registeredCount++;
        }

        if (curveAdapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.CURVE, curveAdapter);
            console.log("Registered Curve:", curveAdapter);
            registeredCount++;
        }

        if (balancerAdapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.BALANCER, balancerAdapter);
            console.log("Registered Balancer:", balancerAdapter);
            registeredCount++;
        }

        if (sushiswapAdapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.SUSHISWAP, sushiswapAdapter);
            console.log("Registered SushiSwap:", sushiswapAdapter);
            registeredCount++;
        }

        vm.stopBroadcast();

        console.log("\n=== Registration Complete ===");
        console.log("Total adapters registered:", registeredCount);

        // Verify registration
        _verifyAdapters(router);
    }

    function _verifyAdapters(CrossChainDEXRouter router) internal view {
        console.log("\n=== Verifying Adapter Registration ===");

        address uniV2 = router.dexAdapters(IDEXAggregator.DEXType.UNISWAP_V2);
        address uniV3 = router.dexAdapters(IDEXAggregator.DEXType.UNISWAP_V3);
        address curve = router.dexAdapters(IDEXAggregator.DEXType.CURVE);
        address balancer = router.dexAdapters(IDEXAggregator.DEXType.BALANCER);
        address sushiswap = router.dexAdapters(IDEXAggregator.DEXType.SUSHISWAP);

        _logAdapter("Uniswap V2", uniV2);
        _logAdapter("Uniswap V3", uniV3);
        _logAdapter("Curve", curve);
        _logAdapter("Balancer", balancer);
        _logAdapter("SushiSwap", sushiswap);
    }

    function _logAdapter(string memory name, address adapter) internal pure {
        if (adapter != address(0)) {
            console.log(name, "- REGISTERED:", adapter);
        } else {
            console.log(name, "- NOT REGISTERED");
        }
    }

    function unregisterAdapter() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        string memory dexTypeStr = vm.envString("DEX_TYPE");
        IDEXAggregator.DEXType dexType = _parseDEXType(dexTypeStr);

        console.log("Unregistering adapter for:", dexTypeStr);

        vm.startBroadcast();
        router.registerDEXAdapter(dexType, address(0));
        vm.stopBroadcast();

        console.log("Adapter unregistered successfully");
    }

    function updateAdapter() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        string memory dexTypeStr = vm.envString("DEX_TYPE");
        address newAdapter = vm.envAddress("NEW_ADAPTER");

        IDEXAggregator.DEXType dexType = _parseDEXType(dexTypeStr);

        console.log("Updating adapter for:", dexTypeStr);
        console.log("New adapter:", newAdapter);

        vm.startBroadcast();
        router.registerDEXAdapter(dexType, newAdapter);
        vm.stopBroadcast();

        console.log("Adapter updated successfully");
    }

    function _parseDEXType(string memory dexTypeStr) internal pure returns (IDEXAggregator.DEXType) {
        bytes32 hash = keccak256(bytes(dexTypeStr));

        if (hash == keccak256(bytes("UNISWAP_V2"))) {
            return IDEXAggregator.DEXType.UNISWAP_V2;
        } else if (hash == keccak256(bytes("UNISWAP_V3"))) {
            return IDEXAggregator.DEXType.UNISWAP_V3;
        } else if (hash == keccak256(bytes("CURVE"))) {
            return IDEXAggregator.DEXType.CURVE;
        } else if (hash == keccak256(bytes("BALANCER"))) {
            return IDEXAggregator.DEXType.BALANCER;
        } else if (hash == keccak256(bytes("SUSHISWAP"))) {
            return IDEXAggregator.DEXType.SUSHISWAP;
        }

        revert("Invalid DEX type");
    }

    function registerBalancerPools() external {
        address balancerAdapter = vm.envAddress("BALANCER_ADAPTER");

        console.log("Registering Balancer pools...");
        console.log("Adapter:", balancerAdapter);

        // Example pool registrations (customize based on network)
        vm.startBroadcast();

        // WETH/USDC pool
        _registerBalancerPool(
            balancerAdapter,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019 // Pool ID
        );

        vm.stopBroadcast();

        console.log("Balancer pools registered");
    }

    function _registerBalancerPool(
        address adapter,
        address tokenA,
        address tokenB,
        bytes32 poolId
    ) internal {
        console.log("Registering pool:");
        console.log("  Token A:", tokenA);
        console.log("  Token B:", tokenB);
        console.log("  Pool ID:", vm.toString(poolId));

        BalancerV2Adapter(adapter).registerPool(tokenA, tokenB, poolId);
    }
}
