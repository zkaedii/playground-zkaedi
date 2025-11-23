// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UUPSTokenV2.sol";

/**
 * @title DeployProxy
 * @notice Deploy ERC1967Proxy pointing to existing UUPSTokenV2 implementation
 * @dev Run with: forge script script/DeployProxy.s.sol --rpc-url arbitrum --broadcast
 */
contract DeployProxy is Script {
    // Your already-deployed implementation on Arbitrum One
    address constant IMPLEMENTATION = 0x74c2C1898578C04070F7aDa5d7CE0a40f3792db4;

    function run() external {
        // Load deployment parameters from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory tokenName = vm.envOr("TOKEN_NAME", string("UUPS Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("UUPS"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 * 1e18)); // 1M tokens
        uint256 burnRate = vm.envOr("BURN_RATE", uint256(50)); // 0.5%

        address deployer = vm.addr(deployerPrivateKey);

        console.log("==============================================");
        console.log("UUPS Token V2 Proxy Deployment");
        console.log("==============================================");
        console.log("Deployer:        ", deployer);
        console.log("Implementation:  ", IMPLEMENTATION);
        console.log("Token Name:      ", tokenName);
        console.log("Token Symbol:    ", tokenSymbol);
        console.log("Initial Supply:  ", initialSupply / 1e18, "tokens");
        console.log("Burn Rate:       ", burnRate, "bps (", burnRate * 100 / 10000, "% )");
        console.log("==============================================");

        vm.startBroadcast(deployerPrivateKey);

        // Encode the initializeV2 call
        bytes memory initData = abi.encodeCall(
            UUPSTokenV2.initializeV2,
            (tokenName, tokenSymbol, initialSupply, burnRate)
        );

        // Deploy ERC1967Proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(IMPLEMENTATION, initData);

        address proxyAddress = address(proxy);

        // Verify deployment
        UUPSTokenV2 token = UUPSTokenV2(proxyAddress);

        console.log("==============================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("==============================================");
        console.log("Proxy Address:   ", proxyAddress);
        console.log("Owner:           ", token.owner());
        console.log("Total Supply:    ", token.totalSupply() / 1e18, "tokens");
        console.log("Burn Rate:       ", token.burnRate(), "bps");
        console.log("Version:         ", token.version());
        console.log("==============================================");

        vm.stopBroadcast();
    }
}

/**
 * @title DeployProxyDryRun
 * @notice Simulate deployment without broadcasting (for testing)
 * @dev Run with: forge script script/DeployProxy.s.sol:DeployProxyDryRun --rpc-url arbitrum
 */
contract DeployProxyDryRun is Script {
    address constant IMPLEMENTATION = 0x74c2C1898578C04070F7aDa5d7CE0a40f3792db4;

    function run() external view {
        string memory tokenName = "UUPS Token";
        string memory tokenSymbol = "UUPS";
        uint256 initialSupply = 1_000_000 * 1e18;
        uint256 burnRate = 50;

        // Encode the initializeV2 call
        bytes memory initData = abi.encodeCall(
            UUPSTokenV2.initializeV2,
            (tokenName, tokenSymbol, initialSupply, burnRate)
        );

        console.log("==============================================");
        console.log("DEPLOYMENT SIMULATION (DRY RUN)");
        console.log("==============================================");
        console.log("Implementation:", IMPLEMENTATION);
        console.log("");
        console.log("Init Data (hex):");
        console.logBytes(initData);
        console.log("");
        console.log("For MetaMask manual deployment:");
        console.log("1. Deploy ERC1967Proxy contract");
        console.log("2. Constructor args: (implementation, initData)");
        console.log("==============================================");
    }
}
