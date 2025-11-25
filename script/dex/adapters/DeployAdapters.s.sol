// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../../src/dex/adapters/DEXAdapters.sol";

/**
 * @title DeployAdapters
 * @notice Script to deploy all DEX adapters
 * @dev Usage: forge script script/dex/adapters/DeployAdapters.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployAdapters is Script {
    struct NetworkConfig {
        address uniswapV2Router;
        address uniswapV3Router;
        address uniswapV3Quoter;
        address uniswapV3Factory;
        address curveRegistry;
        address balancerVault;
        address balancerQueries;
        address sushiswapRouter;
    }

    function run() external {
        NetworkConfig memory config = getNetworkConfig();

        console.log("=== Deploying DEX Adapters ===");
        console.log("Network:", block.chainid);

        vm.startBroadcast();

        // Deploy Uniswap V2 adapter
        address uniswapV2Adapter = deployUniswapV2Adapter(config.uniswapV2Router);

        // Deploy Uniswap V3 adapter
        address uniswapV3Adapter = deployUniswapV3Adapter(
            config.uniswapV3Router,
            config.uniswapV3Quoter,
            config.uniswapV3Factory
        );

        // Deploy Curve adapter
        address curveAdapter = deployCurveAdapter(config.curveRegistry);

        // Deploy Balancer V2 adapter
        address balancerAdapter = deployBalancerV2Adapter(
            config.balancerVault,
            config.balancerQueries
        );

        // Deploy SushiSwap adapter (uses Uniswap V2 interface)
        address sushiswapAdapter = deploySushiSwapAdapter(config.sushiswapRouter);

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Uniswap V2 Adapter:", uniswapV2Adapter);
        console.log("Uniswap V3 Adapter:", uniswapV3Adapter);
        console.log("Curve Adapter:", curveAdapter);
        console.log("Balancer V2 Adapter:", balancerAdapter);
        console.log("SushiSwap Adapter:", sushiswapAdapter);
        console.log("========================\n");

        // Save addresses to file
        _saveAddresses(
            uniswapV2Adapter,
            uniswapV3Adapter,
            curveAdapter,
            balancerAdapter,
            sushiswapAdapter
        );
    }

    function deployUniswapV2Adapter(address router) internal returns (address) {
        if (router == address(0)) {
            console.log("Skipping Uniswap V2 adapter (no router configured)");
            return address(0);
        }

        console.log("\nDeploying Uniswap V2 adapter...");
        console.log("Router:", router);

        UniswapV2Adapter adapter = new UniswapV2Adapter(router, "UniswapV2");
        console.log("Deployed at:", address(adapter));
        console.log("Name:", adapter.name());
        console.log("WETH:", adapter.weth());

        return address(adapter);
    }

    function deployUniswapV3Adapter(
        address router,
        address quoter,
        address factory
    ) internal returns (address) {
        if (router == address(0) || quoter == address(0) || factory == address(0)) {
            console.log("Skipping Uniswap V3 adapter (missing configuration)");
            return address(0);
        }

        console.log("\nDeploying Uniswap V3 adapter...");
        console.log("Router:", router);
        console.log("Quoter:", quoter);
        console.log("Factory:", factory);

        UniswapV3Adapter adapter = new UniswapV3Adapter(router, quoter, factory);
        console.log("Deployed at:", address(adapter));
        console.log("Name:", adapter.name());

        return address(adapter);
    }

    function deployCurveAdapter(address registry) internal returns (address) {
        if (registry == address(0)) {
            console.log("Skipping Curve adapter (no registry configured)");
            return address(0);
        }

        console.log("\nDeploying Curve adapter...");
        console.log("Registry:", registry);

        CurveAdapter adapter = new CurveAdapter(registry);
        console.log("Deployed at:", address(adapter));
        console.log("Name:", adapter.name());

        return address(adapter);
    }

    function deployBalancerV2Adapter(
        address vault,
        address queries
    ) internal returns (address) {
        if (vault == address(0) || queries == address(0)) {
            console.log("Skipping Balancer V2 adapter (missing configuration)");
            return address(0);
        }

        console.log("\nDeploying Balancer V2 adapter...");
        console.log("Vault:", vault);
        console.log("Queries:", queries);

        BalancerV2Adapter adapter = new BalancerV2Adapter(vault, queries);
        console.log("Deployed at:", address(adapter));
        console.log("Name:", adapter.name());

        return address(adapter);
    }

    function deploySushiSwapAdapter(address router) internal returns (address) {
        if (router == address(0)) {
            console.log("Skipping SushiSwap adapter (no router configured)");
            return address(0);
        }

        console.log("\nDeploying SushiSwap adapter...");
        console.log("Router:", router);

        UniswapV2Adapter adapter = new UniswapV2Adapter(router, "SushiSwap");
        console.log("Deployed at:", address(adapter));
        console.log("Name:", adapter.name());

        return address(adapter);
    }

    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        // Ethereum Mainnet
        if (block.chainid == 1) {
            return NetworkConfig({
                uniswapV2Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
                uniswapV3Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                uniswapV3Quoter: 0x61fFE014bA17989E743c5F6cB21bF9697530B21e,
                uniswapV3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
                curveRegistry: 0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5,
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                balancerQueries: 0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5,
                sushiswapRouter: 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
            });
        }
        // Arbitrum
        else if (block.chainid == 42161) {
            return NetworkConfig({
                uniswapV2Router: 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506,
                uniswapV3Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                uniswapV3Quoter: 0x61fFE014bA17989E743c5F6cB21bF9697530B21e,
                uniswapV3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
                curveRegistry: address(0),
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                balancerQueries: address(0),
                sushiswapRouter: 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
            });
        }
        // Optimism
        else if (block.chainid == 10) {
            return NetworkConfig({
                uniswapV2Router: address(0),
                uniswapV3Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                uniswapV3Quoter: 0x61fFE014bA17989E743c5F6cB21bF9697530B21e,
                uniswapV3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
                curveRegistry: address(0),
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                balancerQueries: address(0),
                sushiswapRouter: address(0)
            });
        }
        // Polygon
        else if (block.chainid == 137) {
            return NetworkConfig({
                uniswapV2Router: 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff,
                uniswapV3Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                uniswapV3Quoter: 0x61fFE014bA17989E743c5F6cB21bF9697530B21e,
                uniswapV3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
                curveRegistry: address(0),
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                balancerQueries: address(0),
                sushiswapRouter: 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
            });
        }
        // Base
        else if (block.chainid == 8453) {
            return NetworkConfig({
                uniswapV2Router: address(0),
                uniswapV3Router: 0x2626664c2603336E57B271c5C0b26F421741e481,
                uniswapV3Quoter: 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a,
                uniswapV3Factory: 0x33128a8fC17869897dcE68Ed026d694621f6FDfD,
                curveRegistry: address(0),
                balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                balancerQueries: address(0),
                sushiswapRouter: address(0)
            });
        }
        // Default (use env vars)
        else {
            return NetworkConfig({
                uniswapV2Router: vm.envOr("UNISWAP_V2_ROUTER", address(0)),
                uniswapV3Router: vm.envOr("UNISWAP_V3_ROUTER", address(0)),
                uniswapV3Quoter: vm.envOr("UNISWAP_V3_QUOTER", address(0)),
                uniswapV3Factory: vm.envOr("UNISWAP_V3_FACTORY", address(0)),
                curveRegistry: vm.envOr("CURVE_REGISTRY", address(0)),
                balancerVault: vm.envOr("BALANCER_VAULT", address(0)),
                balancerQueries: vm.envOr("BALANCER_QUERIES", address(0)),
                sushiswapRouter: vm.envOr("SUSHISWAP_ROUTER", address(0))
            });
        }
    }

    function _saveAddresses(
        address uniswapV2,
        address uniswapV3,
        address curve,
        address balancer,
        address sushiswap
    ) internal {
        string memory output = string.concat(
            "# DEX Adapter Addresses\n\n",
            "Network: ", vm.toString(block.chainid), "\n\n",
            "UNISWAP_V2_ADAPTER=", vm.toString(uniswapV2), "\n",
            "UNISWAP_V3_ADAPTER=", vm.toString(uniswapV3), "\n",
            "CURVE_ADAPTER=", vm.toString(curve), "\n",
            "BALANCER_ADAPTER=", vm.toString(balancer), "\n",
            "SUSHISWAP_ADAPTER=", vm.toString(sushiswap), "\n"
        );

        console.log("\n", output);
    }
}
