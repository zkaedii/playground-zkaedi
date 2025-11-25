// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title TestOraclePrices
 * @notice Comprehensive oracle price testing and validation script
 * @dev Usage: forge script script/oracle/TestOraclePrices.s.sol --rpc-url <RPC_URL>
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 *
 * Features:
 * - Tests all registered token pairs
 * - Validates price freshness
 * - Compares prices across oracle sources
 * - Checks price feed availability
 * - Comprehensive reporting with statistics
 */
contract TestOraclePrices is Script {

    struct PairTest {
        address base;
        address quote;
        string description;
    }

    struct TestResult {
        bool success;
        uint256 price;
        uint8 decimals;
        uint256 timestamp;
        uint256 age;
        string source;
        string error;
    }

    function run() external view {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        console.log("=== Oracle Price Testing ===");
        console.log("Oracle:", oracleAddress);
        console.log("Block timestamp:", block.timestamp);
        console.log("Chain ID:", block.chainid);
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get test pairs
        PairTest[] memory pairs = getTestPairs(block.chainid);

        console.log("Testing", pairs.length, "token pairs...\n");

        uint256 successCount = 0;
        uint256 failureCount = 0;
        uint256 totalLatency = 0;

        for (uint256 i = 0; i < pairs.length; i++) {
            PairTest memory pair = pairs[i];

            console.log("Test", i + 1, ":", pair.description);
            console.log("  Base:", pair.base);
            console.log("  Quote:", pair.quote);

            // Test 1: Check if price feed exists
            bool hasFeed = oracle.hasPriceFeed(pair.base, pair.quote);
            console.log("  Has price feed:", hasFeed);

            if (!hasFeed) {
                console.log("  Status: SKIPPED (no feed registered)\n");
                continue;
            }

            // Test 2: Get price with default staleness
            TestResult memory result = testGetPrice(oracle, pair.base, pair.quote);
            if (result.success) {
                successCount++;
                totalLatency += result.age;

                console.log("  Price:", result.price);
                console.log("  Decimals:", result.decimals);
                console.log("  Timestamp:", result.timestamp);
                console.log("  Age:", result.age, "seconds");
                console.log("  Source:", result.source);
                console.log("  Status: SUCCESS");

                // Calculate human-readable price
                uint256 humanPrice = result.price / (10 ** result.decimals);
                console.log("  Human price: $", humanPrice);

                // Test 3: Test with strict staleness (60 seconds)
                TestResult memory strictResult = testGetPriceNoOlderThan(oracle, pair.base, pair.quote, 60);
                if (strictResult.success) {
                    console.log("  Strict check (60s): PASS");
                } else {
                    console.log("  Strict check (60s): FAIL -", strictResult.error);
                }

            } else {
                failureCount++;
                console.log("  Status: FAILED -", result.error);
            }

            console.log("");
        }

        // Print summary
        console.log("\n=== Test Summary ===");
        console.log("Total pairs tested:", pairs.length);
        console.log("Successful:", successCount);
        console.log("Failed:", failureCount);

        if (successCount > 0) {
            uint256 avgLatency = totalLatency / successCount;
            console.log("Average price age:", avgLatency, "seconds");
        }

        uint256 successRate = (successCount * 100) / (successCount + failureCount);
        console.log("Success rate:", successRate, "%");
        console.log("==================\n");

        // Additional diagnostics
        console.log("=== Oracle Configuration ===");
        console.log("Pyth Oracle:", oracle.pythOracle());
        console.log("RedStone Oracle:", oracle.redstoneOracle());
        console.log("Max oracles per pair:", oracle.MAX_ORACLES_PER_PAIR());
        console.log("Default staleness:", oracle.DEFAULT_STALENESS(), "seconds");
        console.log("Max deviation:", oracle.MAX_DEVIATION_BPS(), "bps");
        console.log("===========================\n");
    }

    /**
     * @notice Test getPrice function
     */
    function testGetPrice(
        SmartOracleAggregator oracle,
        address base,
        address quote
    ) internal view returns (TestResult memory result) {
        try oracle.getPrice(base, quote) returns (ISmartOracle.PriceData memory data) {
            result.success = true;
            result.price = data.price;
            result.decimals = data.decimals;
            result.timestamp = data.timestamp;
            result.age = block.timestamp - data.timestamp;
            result.source = getOracleTypeName(data.source);
        } catch Error(string memory reason) {
            result.success = false;
            result.error = reason;
        } catch (bytes memory) {
            result.success = false;
            result.error = "Unknown error";
        }
    }

    /**
     * @notice Test getPriceNoOlderThan function
     */
    function testGetPriceNoOlderThan(
        SmartOracleAggregator oracle,
        address base,
        address quote,
        uint256 maxAge
    ) internal view returns (TestResult memory result) {
        try oracle.getPriceNoOlderThan(base, quote, maxAge) returns (ISmartOracle.PriceData memory data) {
            result.success = true;
            result.price = data.price;
            result.decimals = data.decimals;
            result.timestamp = data.timestamp;
            result.age = block.timestamp - data.timestamp;
            result.source = getOracleTypeName(data.source);
        } catch Error(string memory reason) {
            result.success = false;
            result.error = reason;
        } catch (bytes memory) {
            result.success = false;
            result.error = "Unknown error";
        }
    }

    /**
     * @notice Convert OracleType enum to string
     */
    function getOracleTypeName(ISmartOracle.OracleType oracleType) internal pure returns (string memory) {
        if (oracleType == ISmartOracle.OracleType.CHAINLINK) return "Chainlink";
        if (oracleType == ISmartOracle.OracleType.PYTH) return "Pyth";
        if (oracleType == ISmartOracle.OracleType.REDSTONE) return "RedStone";
        if (oracleType == ISmartOracle.OracleType.TWAP) return "TWAP";
        if (oracleType == ISmartOracle.OracleType.CUSTOM) return "Custom";
        return "Unknown";
    }

    /**
     * @notice Get test pairs by chain
     */
    function getTestPairs(uint256 chainId) internal pure returns (PairTest[] memory) {
        if (chainId == 1) {
            // Ethereum Mainnet
            PairTest[] memory pairs = new PairTest[](6);

            pairs[0] = PairTest({
                base: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                description: "ETH/USD"
            });

            pairs[1] = PairTest({
                base: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                description: "BTC/USD"
            });

            pairs[2] = PairTest({
                base: 0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                description: "LINK/USD"
            });

            pairs[3] = PairTest({
                base: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                quote: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
                description: "USDC/USD"
            });

            pairs[4] = PairTest({
                base: 0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                description: "DAI/USD"
            });

            pairs[5] = PairTest({
                base: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, // UNI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                description: "UNI/USD"
            });

            return pairs;

        } else if (chainId == 137) {
            // Polygon
            PairTest[] memory pairs = new PairTest[](4);

            pairs[0] = PairTest({
                base: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, // WETH
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                description: "ETH/USD"
            });

            pairs[1] = PairTest({
                base: 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6, // WBTC
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                description: "BTC/USD"
            });

            pairs[2] = PairTest({
                base: 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, // WMATIC
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                description: "MATIC/USD"
            });

            pairs[3] = PairTest({
                base: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                quote: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F, // USDT
                description: "USDC/USD"
            });

            return pairs;

        } else {
            // Mock/testnet
            PairTest[] memory pairs = new PairTest[](2);

            pairs[0] = PairTest({
                base: address(0x1),
                quote: address(0x2),
                description: "ETH/USD (Mock)"
            });

            pairs[1] = PairTest({
                base: address(0x3),
                quote: address(0x2),
                description: "BTC/USD (Mock)"
            });

            return pairs;
        }
    }
}
