// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UUPSTokenV3.sol";

/**
 * @title DeployProxyV3
 * @notice Deploy ERC1967Proxy with optimized UUPSTokenV3 implementation
 */
contract DeployProxyV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory tokenName = vm.envOr("TOKEN_NAME", string("UUPS Token V3"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("UUPSV3"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 * 1e18));
        uint256 maxSupply = vm.envOr("MAX_SUPPLY", uint256(10_000_000 * 1e18));
        uint16 burnRate = uint16(vm.envOr("BURN_RATE", uint256(50)));

        address deployer = vm.addr(deployerPrivateKey);

        console.log("==============================================");
        console.log("UUPS Token V3 Deployment (Optimized)");
        console.log("==============================================");
        console.log("Deployer:       ", deployer);
        console.log("Token Name:     ", tokenName);
        console.log("Token Symbol:   ", tokenSymbol);
        console.log("Initial Supply: ", initialSupply / 1e18, "tokens");
        console.log("Max Supply:     ", maxSupply / 1e18, "tokens");
        console.log("Burn Rate:      ", burnRate, "bps");
        console.log("==============================================");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        UUPSTokenV3 implementation = new UUPSTokenV3();
        console.log("Implementation deployed:", address(implementation));

        // Encode initializer
        bytes memory initData = abi.encodeCall(
            UUPSTokenV3.initializeV3,
            (tokenName, tokenSymbol, initialSupply, maxSupply, burnRate)
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        UUPSTokenV3 token = UUPSTokenV3(address(proxy));

        console.log("==============================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("==============================================");
        console.log("Proxy:           ", address(proxy));
        console.log("Implementation:  ", address(implementation));
        console.log("Owner:           ", token.owner());
        console.log("Total Supply:    ", token.totalSupply() / 1e18, "tokens");
        console.log("Max Supply:      ", token.maxSupply() / 1e18, "tokens");
        console.log("Burn Rate:       ", token.burnRate(), "bps");
        console.log("Version:         ", token.version());
        console.log("==============================================");

        vm.stopBroadcast();
    }
}

/**
 * @title UpgradeToV3
 * @notice Upgrade existing V2 proxy to V3 implementation
 */
contract UpgradeToV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        uint256 maxSupply = vm.envOr("MAX_SUPPLY", uint256(10_000_000 * 1e18));

        console.log("==============================================");
        console.log("Upgrading to V3");
        console.log("==============================================");
        console.log("Proxy:", proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        UUPSTokenV3 newImplementation = new UUPSTokenV3();
        console.log("New implementation:", address(newImplementation));

        // Encode reinitializer
        bytes memory reinitData = abi.encodeCall(
            UUPSTokenV3.reinitializeV3,
            (maxSupply)
        );

        // Upgrade
        UUPSTokenV3 token = UUPSTokenV3(proxyAddress);
        token.upgradeToAndCall(address(newImplementation), reinitData);

        console.log("==============================================");
        console.log("UPGRADE SUCCESSFUL");
        console.log("==============================================");
        console.log("New Version:", token.version());
        console.log("Max Supply: ", token.maxSupply() / 1e18, "tokens");
        console.log("==============================================");

        vm.stopBroadcast();
    }
}
