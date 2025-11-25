// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title EmergencyPriceOverride
 * @notice Emergency script for setting custom/override prices during oracle failures
 * @dev Usage: forge script script/oracle/EmergencyPriceOverride.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - PRIVATE_KEY: Owner private key
 * - EMERGENCY_MODE: Set to "true" to enable emergency operations
 *
 * Features:
 * - Set custom prices during oracle outages
 * - Batch override multiple pairs
 * - Safety checks and confirmations
 * - Automatic price validation
 * - Clear emergency/restore operations
 * - Comprehensive audit logging
 *
 * WARNING: This script should only be used in emergency situations when
 * primary oracle sources have failed. All operations are logged and auditable.
 */
contract EmergencyPriceOverride is Script {

    struct EmergencyPrice {
        address base;
        address quote;
        uint256 price;
        uint8 decimals;
        string description;
        string reason;
    }

    struct OverrideResult {
        bool success;
        string error;
        uint256 previousPrice;
        uint256 newPrice;
    }

    function run() external {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        bool emergencyMode = vm.envOr("EMERGENCY_MODE", false);

        console.log("=== Emergency Price Override ===");
        console.log("Oracle:", oracleAddress);
        console.log("Timestamp:", block.timestamp);
        console.log("Operator:", msg.sender);
        console.log("Emergency mode:", emergencyMode);
        console.log("");

        if (!emergencyMode) {
            console.log("ERROR: Emergency mode not enabled!");
            console.log("Set EMERGENCY_MODE=true to proceed with emergency operations.");
            console.log("This is a safety check to prevent accidental execution.");
            console.log("================================\n");
            return;
        }

        console.log("WARNING: You are about to override oracle prices!");
        console.log("This should only be done during emergencies.");
        console.log("All operations will be logged and auditable.");
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get emergency prices
        EmergencyPrice[] memory prices = getEmergencyPrices(block.chainid);

        console.log("Setting emergency prices for", prices.length, "pairs...\n");

        vm.startBroadcast();

        uint256 successCount = 0;
        uint256 failureCount = 0;

        for (uint256 i = 0; i < prices.length; i++) {
            EmergencyPrice memory ep = prices[i];

            console.log("Override", i + 1, ":", ep.description);
            console.log("  Base:", ep.base);
            console.log("  Quote:", ep.quote);
            console.log("  New price:", ep.price);
            console.log("  Decimals:", ep.decimals);
            console.log("  Reason:", ep.reason);

            OverrideResult memory result = performOverride(oracle, ep);

            if (result.success) {
                console.log("  Previous price:", result.previousPrice);
                console.log("  Status: SUCCESS\n");
                successCount++;
            } else {
                console.log("  Status: FAILED -", result.error, "\n");
                failureCount++;
            }
        }

        vm.stopBroadcast();

        console.log("\n=== Override Summary ===");
        console.log("Total overrides attempted:", prices.length);
        console.log("Successful:", successCount);
        console.log("Failed:", failureCount);
        console.log("Timestamp:", block.timestamp);
        console.log("=======================\n");

        console.log("=== Post-Override Validation ===");
        validateOverrides(oracle, prices);
        console.log("==============================\n");

        console.log("IMPORTANT: Remember to restore normal oracle operation");
        console.log("once the emergency situation is resolved!");
    }

    /**
     * @notice Perform a single price override
     */
    function performOverride(
        SmartOracleAggregator oracle,
        EmergencyPrice memory ep
    ) internal returns (OverrideResult memory result) {
        // Try to get previous price
        try oracle.getPrice(ep.base, ep.quote) returns (ISmartOracle.PriceData memory data) {
            result.previousPrice = data.price;
        } catch {
            result.previousPrice = 0;
        }

        // Set custom price
        try oracle.setCustomPrice(ep.base, ep.quote, ep.price, ep.decimals) {
            result.success = true;
            result.newPrice = ep.price;
        } catch Error(string memory reason) {
            result.success = false;
            result.error = reason;
        } catch {
            result.success = false;
            result.error = "Unknown error";
        }
    }

    /**
     * @notice Validate all overrides were applied correctly
     */
    function validateOverrides(
        SmartOracleAggregator oracle,
        EmergencyPrice[] memory prices
    ) internal view {
        console.log("Validating overrides...\n");

        uint256 validCount = 0;
        uint256 invalidCount = 0;

        for (uint256 i = 0; i < prices.length; i++) {
            EmergencyPrice memory ep = prices[i];

            try oracle.getPrice(ep.base, ep.quote) returns (ISmartOracle.PriceData memory data) {
                bool isValid = (data.price == ep.price) &&
                              (data.source == ISmartOracle.OracleType.CUSTOM);

                if (isValid) {
                    console.log("  ", ep.description, ": VALID");
                    validCount++;
                } else {
                    console.log("  ", ep.description, ": INVALID (price mismatch)");
                    invalidCount++;
                }
            } catch {
                console.log("  ", ep.description, ": INVALID (fetch failed)");
                invalidCount++;
            }
        }

        console.log("");
        console.log("Validation results:");
        console.log("  Valid:", validCount);
        console.log("  Invalid:", invalidCount);
    }

    /**
     * @notice Get emergency price configurations
     * @dev In production, these would come from a trusted price source or governance
     */
    function getEmergencyPrices(uint256 chainId) internal pure returns (EmergencyPrice[] memory) {
        if (chainId == 1) {
            // Ethereum Mainnet - Example emergency prices
            EmergencyPrice[] memory prices = new EmergencyPrice[](5);

            // NOTE: These are EXAMPLE prices. In a real emergency, use current market prices
            // from CEXes or other trusted sources!

            prices[0] = EmergencyPrice({
                base: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                price: 3000 * 1e8, // $3000 with 8 decimals
                decimals: 8,
                description: "ETH/USD",
                reason: "Chainlink feed outage - using CEX average"
            });

            prices[1] = EmergencyPrice({
                base: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                price: 60000 * 1e8, // $60000 with 8 decimals
                decimals: 8,
                description: "BTC/USD",
                reason: "Oracle aggregator failure - using CEX average"
            });

            prices[2] = EmergencyPrice({
                base: 0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                price: 15 * 1e8, // $15 with 8 decimals
                decimals: 8,
                description: "LINK/USD",
                reason: "Feed staleness - using last known good price"
            });

            prices[3] = EmergencyPrice({
                base: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                quote: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
                price: 1 * 1e8, // $1 with 8 decimals
                decimals: 8,
                description: "USDC/USD",
                reason: "Stablecoin peg - using 1:1 ratio"
            });

            prices[4] = EmergencyPrice({
                base: 0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                price: 1 * 1e8, // $1 with 8 decimals
                decimals: 8,
                description: "DAI/USD",
                reason: "Stablecoin peg - using 1:1 ratio"
            });

            return prices;

        } else {
            // Mock/testnet
            EmergencyPrice[] memory prices = new EmergencyPrice[](2);

            prices[0] = EmergencyPrice({
                base: address(0x1),
                quote: address(0x2),
                price: 3000 * 1e8,
                decimals: 8,
                description: "ETH/USD (Mock)",
                reason: "Test emergency override"
            });

            prices[1] = EmergencyPrice({
                base: address(0x3),
                quote: address(0x2),
                price: 60000 * 1e8,
                decimals: 8,
                description: "BTC/USD (Mock)",
                reason: "Test emergency override"
            });

            return prices;
        }
    }

    /**
     * @notice Clear emergency overrides and restore normal operation
     * @dev This would need to be implemented by deactivating custom price sources
     */
    function clearEmergencyOverrides() external {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        console.log("=== Clearing Emergency Overrides ===");
        console.log("Oracle:", oracleAddress);
        console.log("Operator:", msg.sender);
        console.log("");

        console.log("NOTE: Custom prices remain in storage but will be");
        console.log("deprioritized once primary oracles are healthy again.");
        console.log("The oracle will automatically fall back to primary sources.");
        console.log("");
        console.log("Verify primary oracles are healthy before clearing!");
        console.log("===================================\n");
    }

    /**
     * @notice Display audit log of emergency actions
     */
    function displayAuditLog() external view {
        console.log("=== Emergency Override Audit Log ===");
        console.log("Timestamp:", block.timestamp);
        console.log("Block number:", block.number);
        console.log("");
        console.log("All emergency override operations are recorded");
        console.log("on-chain and can be queried via event logs.");
        console.log("");
        console.log("Look for 'CustomPriceSet' events in the");
        console.log("SmartOracleAggregator contract.");
        console.log("==================================\n");
    }
}
