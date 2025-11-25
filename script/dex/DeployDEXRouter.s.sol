// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/dex/CrossChainDEXRouter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployDEXRouter
 * @notice Script to deploy CrossChainDEXRouter with UUPS proxy
 * @dev Usage: forge script script/dex/DeployDEXRouter.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployDEXRouter is Script {
    function run() external {
        // Load environment variables
        address oracle = vm.envOr("ORACLE_ADDRESS", address(0));
        address ccipRouter = vm.envOr("CCIP_ROUTER", address(0));
        address lzEndpoint = vm.envOr("LZ_ENDPOINT", address(0));
        address wrappedNative = vm.envOr("WRAPPED_NATIVE", address(0));
        address feeRecipient = vm.envOr("FEE_RECIPIENT", msg.sender);

        console.log("Deploying CrossChainDEXRouter...");
        console.log("Oracle:", oracle);
        console.log("CCIP Router:", ccipRouter);
        console.log("LayerZero Endpoint:", lzEndpoint);
        console.log("Wrapped Native:", wrappedNative);
        console.log("Fee Recipient:", feeRecipient);

        vm.startBroadcast();

        // Deploy implementation
        CrossChainDEXRouter implementation = new CrossChainDEXRouter();
        console.log("Implementation deployed at:", address(implementation));

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            CrossChainDEXRouter.initialize.selector,
            oracle,
            ccipRouter,
            lzEndpoint,
            wrappedNative,
            feeRecipient
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        CrossChainDEXRouter router = CrossChainDEXRouter(payable(address(proxy)));
        console.log("Router version:", router.version());
        console.log("Router owner:", router.owner());

        vm.stopBroadcast();

        // Output deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Router):", address(proxy));
        console.log("========================\n");
    }
}
