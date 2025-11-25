// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title UpdateTWAPObservations
 * @notice Keeper script for recording TWAP observations from DEX pools
 * @dev Usage: forge script script/oracle/UpdateTWAPObservations.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - DEX_ROUTER: DEX router address for fetching spot prices
 * - PRIVATE_KEY: Keeper private key
 *
 * Features:
 * - Fetches current prices from primary oracles
 * - Records TWAP observations for configured pairs
 * - Supports multiple DEX sources (Uniswap V2/V3, Curve, etc.)
 * - Can be run as automated keeper/cron job
 * - Batch processing for gas efficiency
 * - Comprehensive logging and error handling
 */
contract UpdateTWAPObservations is Script {

    struct TWAPPair {
        address base;
        address quote;
        address dexPool;
        string description;
    }

    struct ObservationResult {
        bool success;
        uint256 price;
        string error;
    }

    function run() external {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        console.log("=== TWAP Observations Update ===");
        console.log("Oracle:", oracleAddress);
        console.log("Timestamp:", block.timestamp);
        console.log("Block number:", block.number);
        console.log("Chain ID:", block.chainid);
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get TWAP pairs to update
        TWAPPair[] memory pairs = getTWAPPairs(block.chainid);

        console.log("Updating TWAP observations for", pairs.length, "pairs...\n");

        vm.startBroadcast();

        uint256 successCount = 0;
        uint256 failureCount = 0;

        for (uint256 i = 0; i < pairs.length; i++) {
            TWAPPair memory pair = pairs[i];

            console.log("Pair", i + 1, ":", pair.description);
            console.log("  Base:", pair.base);
            console.log("  Quote:", pair.quote);
            console.log("  DEX Pool:", pair.dexPool);

            // Fetch current price from primary oracle
            ObservationResult memory result = fetchPrice(oracle, pair);

            if (result.success) {
                console.log("  Current price:", result.price);

                try oracle.recordTWAPObservation(pair.base, pair.quote, result.price) {
                    console.log("  Status: SUCCESS - TWAP recorded\n");
                    successCount++;
                } catch Error(string memory reason) {
                    console.log("  Status: FAILED - Could not record:", reason, "\n");
                    failureCount++;
                }
            } else {
                console.log("  Status: FAILED - Could not fetch price:", result.error, "\n");
                failureCount++;
            }
        }

        vm.stopBroadcast();

        console.log("\n=== Update Summary ===");
        console.log("Total pairs:", pairs.length);
        console.log("Successfully updated:", successCount);
        console.log("Failed:", failureCount);
        console.log("Success rate:", (successCount * 100) / pairs.length, "%");
        console.log("===================\n");

        // Display TWAP info
        console.log("=== TWAP Information ===");
        console.log("Observation timestamp:", block.timestamp);
        console.log("Next update recommended: ~5 minutes");
        console.log("TWAP window: 24 hours");
        console.log("Max observations: 288 (5min intervals)");
        console.log("=======================\n");
    }

    /**
     * @notice Fetch current price for a pair
     */
    function fetchPrice(
        SmartOracleAggregator oracle,
        TWAPPair memory pair
    ) internal view returns (ObservationResult memory result) {
        try oracle.getPrice(pair.base, pair.quote) returns (ISmartOracle.PriceData memory data) {
            result.success = true;
            result.price = data.price;
        } catch Error(string memory reason) {
            result.success = false;
            result.error = reason;
        } catch {
            result.success = false;
            result.error = "Unknown error";
        }
    }

    /**
     * @notice Get TWAP pairs by chain
     */
    function getTWAPPairs(uint256 chainId) internal pure returns (TWAPPair[] memory) {
        if (chainId == 1) {
            // Ethereum Mainnet
            TWAPPair[] memory pairs = new TWAPPair[](6);

            pairs[0] = TWAPPair({
                base: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                dexPool: 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, // Uniswap V3 ETH/USDC
                description: "ETH/USDC"
            });

            pairs[1] = TWAPPair({
                base: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                dexPool: 0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35, // Uniswap V3 WBTC/USDC
                description: "WBTC/USDC"
            });

            pairs[2] = TWAPPair({
                base: 0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                dexPool: 0xfAd57d2039C21811C8F2B5D5B65308aa99D31559, // Uniswap V3 LINK/USDC
                description: "LINK/USDC"
            });

            pairs[3] = TWAPPair({
                base: 0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                dexPool: 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168, // Uniswap V3 DAI/USDC
                description: "DAI/USDC"
            });

            pairs[4] = TWAPPair({
                base: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, // UNI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                dexPool: 0xd0Fc8bA7E267f2bc56044A7715A489d851dC6D78, // Uniswap V3 UNI/USDC
                description: "UNI/USDC"
            });

            pairs[5] = TWAPPair({
                base: 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0, // MATIC
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                dexPool: 0xA374094527e1673A86dE625aa59517c5dE346d32, // Uniswap V3 MATIC/USDC
                description: "MATIC/USDC"
            });

            return pairs;

        } else if (chainId == 137) {
            // Polygon
            TWAPPair[] memory pairs = new TWAPPair[](3);

            pairs[0] = TWAPPair({
                base: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, // WETH
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                dexPool: 0x45dDa9cb7c25131DF268515131f647d726f50608, // Uniswap V3 ETH/USDC
                description: "ETH/USDC (Polygon)"
            });

            pairs[1] = TWAPPair({
                base: 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6, // WBTC
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                dexPool: 0x847b64f9d3A95e977D157866447a5C0A5dFa0Ee5, // Uniswap V3 WBTC/USDC
                description: "WBTC/USDC (Polygon)"
            });

            pairs[2] = TWAPPair({
                base: 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, // WMATIC
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                dexPool: 0xA374094527e1673A86dE625aa59517c5dE346d32, // Uniswap V3 MATIC/USDC
                description: "MATIC/USDC (Polygon)"
            });

            return pairs;

        } else {
            // Mock/testnet
            TWAPPair[] memory pairs = new TWAPPair[](2);

            pairs[0] = TWAPPair({
                base: address(0x1),
                quote: address(0x2),
                dexPool: address(0x3),
                description: "ETH/USDC (Mock)"
            });

            pairs[1] = TWAPPair({
                base: address(0x4),
                quote: address(0x2),
                dexPool: address(0x5),
                description: "BTC/USDC (Mock)"
            });

            return pairs;
        }
    }

    /**
     * @notice Utility function to calculate TWAP from observations
     * @dev This is a helper for testing TWAP calculations
     */
    function viewTWAP(
        address oracleAddress,
        address base,
        address quote,
        uint32 period
    ) external view {
        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        console.log("=== TWAP Query ===");
        console.log("Base:", base);
        console.log("Quote:", quote);
        console.log("Period:", period, "seconds");

        try oracle.getTWAP(base, quote, period) returns (uint256 twapPrice) {
            console.log("TWAP price:", twapPrice);
            console.log("Status: SUCCESS");
        } catch Error(string memory reason) {
            console.log("Status: FAILED -", reason);
        }

        console.log("================\n");
    }
}
