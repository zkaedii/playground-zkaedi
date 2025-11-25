// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/dex/CrossChainDEXRouter.sol";
import "../../src/interfaces/IDEXAggregator.sol";

/**
 * @title ConfigureDEXRouter
 * @notice Script to configure CrossChainDEXRouter with chains and adapters
 * @dev Usage: forge script script/dex/ConfigureDEXRouter.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract ConfigureDEXRouter is Script {
    using stdJson for string;

    struct ChainConfig {
        uint256 chainId;
        uint64 ccipSelector;
        uint32 lzEid;
        bytes32 trustedRemote;
    }

    function run() external {
        address routerAddress = vm.envAddress("DEX_ROUTER_ADDRESS");
        CrossChainDEXRouter router = CrossChainDEXRouter(payable(routerAddress));

        console.log("Configuring CrossChainDEXRouter at:", routerAddress);
        console.log("Current owner:", router.owner());

        vm.startBroadcast();

        // Configure common chains
        _configureChains(router);

        // Register DEX adapters
        _registerAdapters(router);

        // Set protocol parameters
        _setProtocolParameters(router);

        vm.stopBroadcast();

        console.log("\n=== Configuration Complete ===");
        console.log("Max Price Impact:", router.maxPriceImpactBps(), "bps");
        console.log("Protocol Fee:", router.protocolFeeBps(), "bps");
        console.log("Fee Recipient:", router.feeRecipient());
    }

    function _configureChains(CrossChainDEXRouter router) internal {
        console.log("\nConfiguring cross-chain settings...");

        // Ethereum Mainnet
        if (router.ccipChainSelectors(1) == 0) {
            router.configureChain(
                1, // Ethereum
                5009297550715157269, // CCIP selector
                30101, // LayerZero EID
                bytes32(uint256(uint160(address(router)))) // Trusted remote
            );
            console.log("Configured Ethereum Mainnet");
        }

        // Arbitrum
        if (router.ccipChainSelectors(42161) == 0) {
            router.configureChain(
                42161, // Arbitrum
                4949039107694359620, // CCIP selector
                30110, // LayerZero EID
                bytes32(uint256(uint160(address(router))))
            );
            console.log("Configured Arbitrum");
        }

        // Optimism
        if (router.ccipChainSelectors(10) == 0) {
            router.configureChain(
                10, // Optimism
                3734403246176062136, // CCIP selector
                30111, // LayerZero EID
                bytes32(uint256(uint160(address(router))))
            );
            console.log("Configured Optimism");
        }

        // Polygon
        if (router.ccipChainSelectors(137) == 0) {
            router.configureChain(
                137, // Polygon
                4051577828743386545, // CCIP selector
                30109, // LayerZero EID
                bytes32(uint256(uint160(address(router))))
            );
            console.log("Configured Polygon");
        }

        // Base
        if (router.ccipChainSelectors(8453) == 0) {
            router.configureChain(
                8453, // Base
                15971525489660198786, // CCIP selector
                30184, // LayerZero EID
                bytes32(uint256(uint160(address(router))))
            );
            console.log("Configured Base");
        }
    }

    function _registerAdapters(CrossChainDEXRouter router) internal {
        console.log("\nRegistering DEX adapters...");

        // Load adapter addresses from environment
        address uniswapV2Adapter = vm.envOr("UNISWAP_V2_ADAPTER", address(0));
        address uniswapV3Adapter = vm.envOr("UNISWAP_V3_ADAPTER", address(0));
        address curveAdapter = vm.envOr("CURVE_ADAPTER", address(0));
        address balancerAdapter = vm.envOr("BALANCER_ADAPTER", address(0));
        address sushiswapAdapter = vm.envOr("SUSHISWAP_ADAPTER", address(0));

        if (uniswapV2Adapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.UNISWAP_V2, uniswapV2Adapter);
            console.log("Registered Uniswap V2 adapter:", uniswapV2Adapter);
        }

        if (uniswapV3Adapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.UNISWAP_V3, uniswapV3Adapter);
            console.log("Registered Uniswap V3 adapter:", uniswapV3Adapter);
        }

        if (curveAdapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.CURVE, curveAdapter);
            console.log("Registered Curve adapter:", curveAdapter);
        }

        if (balancerAdapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.BALANCER, balancerAdapter);
            console.log("Registered Balancer adapter:", balancerAdapter);
        }

        if (sushiswapAdapter != address(0)) {
            router.registerDEXAdapter(IDEXAggregator.DEXType.SUSHISWAP, sushiswapAdapter);
            console.log("Registered SushiSwap adapter:", sushiswapAdapter);
        }
    }

    function _setProtocolParameters(CrossChainDEXRouter router) internal {
        console.log("\nSetting protocol parameters...");

        // Set max price impact to 5% (500 bps)
        uint256 maxPriceImpact = vm.envOr("MAX_PRICE_IMPACT_BPS", uint256(500));
        router.setMaxPriceImpact(maxPriceImpact);
        console.log("Set max price impact:", maxPriceImpact, "bps");

        // Set protocol fee to 0.1% (10 bps)
        uint256 protocolFee = vm.envOr("PROTOCOL_FEE_BPS", uint256(10));
        router.setProtocolFee(protocolFee);
        console.log("Set protocol fee:", protocolFee, "bps");

        // Update fee recipient if provided
        address newFeeRecipient = vm.envOr("NEW_FEE_RECIPIENT", address(0));
        if (newFeeRecipient != address(0)) {
            router.setFeeRecipient(newFeeRecipient);
            console.log("Updated fee recipient:", newFeeRecipient);
        }
    }
}
