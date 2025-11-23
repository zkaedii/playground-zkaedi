// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UUPSTokenV2.sol";

/**
 * @title GenerateCalldata
 * @notice Generate raw calldata for manual deployment via MetaMask
 * @dev Run with: forge script script/GenerateCalldata.s.sol
 */
contract GenerateCalldata is Script {
    address constant IMPLEMENTATION = 0x74c2C1898578C04070F7aDa5d7CE0a40f3792db4;

    function run() external pure {
        // Token parameters - CUSTOMIZE THESE
        string memory tokenName = "UUPS Token";
        string memory tokenSymbol = "UUPS";
        uint256 initialSupply = 1_000_000 * 1e18; // 1M tokens
        uint256 burnRate = 50; // 0.5% = 50 basis points

        // Encode initializeV2 call
        bytes memory initData = abi.encodeCall(
            UUPSTokenV2.initializeV2,
            (tokenName, tokenSymbol, initialSupply, burnRate)
        );

        // Encode full constructor call for ERC1967Proxy
        bytes memory constructorArgs = abi.encode(IMPLEMENTATION, initData);

        console.log("================================================================");
        console.log("RAW CALLDATA FOR METAMASK DEPLOYMENT");
        console.log("================================================================");
        console.log("");
        console.log("Token Name:     ", tokenName);
        console.log("Token Symbol:   ", tokenSymbol);
        console.log("Initial Supply: ", initialSupply / 1e18, "tokens");
        console.log("Burn Rate:      ", burnRate, "bps (0.5%)");
        console.log("");
        console.log("Implementation: ", IMPLEMENTATION);
        console.log("");
        console.log("================================================================");
        console.log("INIT DATA (for initializeV2):");
        console.log("================================================================");
        console.logBytes(initData);
        console.log("");
        console.log("================================================================");
        console.log("CONSTRUCTOR ARGS (implementation, initData):");
        console.log("================================================================");
        console.logBytes(constructorArgs);
        console.log("");
        console.log("================================================================");
        console.log("DEPLOYMENT INSTRUCTIONS:");
        console.log("================================================================");
        console.log("1. Go to: https://remix.ethereum.org");
        console.log("2. Import @openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol");
        console.log("3. Compile with Solidity 0.8.26+");
        console.log("4. Deploy ERC1967Proxy with constructor args:");
        console.log("   - _implementation: 0x74c2C1898578C04070F7aDa5d7CE0a40f3792db4");
        console.log("   - _data: [paste initData hex above]");
        console.log("5. Connect MetaMask to Arbitrum One");
        console.log("6. Deploy!");
        console.log("================================================================");
    }
}
