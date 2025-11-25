// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployOracle
 * @notice Deploys SmartOracleAggregator with UUPS proxy pattern
 * @dev Usage: forge script script/oracle/DeployOracle.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 * - PYTH_ORACLE: Address of Pyth oracle contract
 * - REDSTONE_ORACLE: Address of RedStone oracle contract
 * - PRIVATE_KEY: Deployer private key
 *
 * Features:
 * - Deploys implementation contract
 * - Deploys ERC1967 proxy
 * - Initializes with oracle addresses
 * - Outputs comprehensive deployment info
 */
contract DeployOracle is Script {

    function run() external {
        // Load environment variables
        address pythOracle = vm.envOr("PYTH_ORACLE", address(0));
        address redstoneOracle = vm.envOr("REDSTONE_ORACLE", address(0));

        console.log("=== SmartOracleAggregator Deployment ===");
        console.log("Deployer:", msg.sender);
        console.log("Pyth Oracle:", pythOracle);
        console.log("RedStone Oracle:", redstoneOracle);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast();

        // Deploy implementation
        console.log("Deploying SmartOracleAggregator implementation...");
        SmartOracleAggregator implementation = new SmartOracleAggregator();
        console.log("Implementation deployed:", address(implementation));

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            SmartOracleAggregator.initialize.selector,
            pythOracle,
            redstoneOracle
        );

        // Deploy proxy
        console.log("Deploying ERC1967 proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed:", address(proxy));

        // Get proxy instance
        SmartOracleAggregator oracle = SmartOracleAggregator(address(proxy));

        // Verify deployment
        console.log("\n=== Verification ===");
        console.log("Oracle version:", oracle.version());
        console.log("Oracle owner:", oracle.owner());
        console.log("Pyth Oracle configured:", oracle.pythOracle());
        console.log("RedStone Oracle configured:", oracle.redstoneOracle());
        console.log("Max oracles per pair:", oracle.MAX_ORACLES_PER_PAIR());
        console.log("Default staleness (seconds):", oracle.DEFAULT_STALENESS());
        console.log("Max deviation (bps):", oracle.MAX_DEVIATION_BPS());

        vm.stopBroadcast();

        // Output deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Oracle):", address(proxy));
        console.log("Status: SUCCESS");
        console.log("========================\n");

        // Save deployment info to file
        string memory deploymentInfo = string.concat(
            "SmartOracleAggregator Deployment\n",
            "Network: ", vm.toString(block.chainid), "\n",
            "Implementation: ", vm.toString(address(implementation)), "\n",
            "Proxy: ", vm.toString(address(proxy)), "\n",
            "Pyth Oracle: ", vm.toString(pythOracle), "\n",
            "RedStone Oracle: ", vm.toString(redstoneOracle), "\n",
            "Timestamp: ", vm.toString(block.timestamp), "\n"
        );

        vm.writeFile("deployments/oracle-latest.txt", deploymentInfo);
        console.log("Deployment info saved to: deployments/oracle-latest.txt");
    }
}
