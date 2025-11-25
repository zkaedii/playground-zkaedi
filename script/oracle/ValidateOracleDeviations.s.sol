// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title ValidateOracleDeviations
 * @notice Validates price deviations between multiple oracle sources
 * @dev Usage: forge script script/oracle/ValidateOracleDeviations.s.sol --rpc-url <RPC_URL>
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - MAX_DEVIATION_BPS: Maximum acceptable deviation in basis points (default: 500 = 5%)
 * - ALERT_THRESHOLD_BPS: Threshold for warnings (default: 200 = 2%)
 *
 * Features:
 * - Compares prices across multiple oracle sources
 * - Calculates deviation percentages
 * - Identifies anomalies and outliers
 * - Statistical analysis (mean, median, std deviation)
 * - Alerts when deviation exceeds thresholds
 * - Comprehensive reporting with recommendations
 * - Can be run as monitoring/alerting system
 */
contract ValidateOracleDeviations is Script {

    struct PriceComparison {
        address base;
        address quote;
        string pairName;
        uint256[] prices;
        string[] sources;
        uint256 meanPrice;
        uint256 medianPrice;
        uint256 maxDeviation;
        bool hasAlert;
        string[] alerts;
    }

    struct ValidationResult {
        uint256 totalPairs;
        uint256 healthyPairs;
        uint256 warningPairs;
        uint256 criticalPairs;
        uint256 maxDeviationFound;
        string overallStatus;
    }

    function run() external view {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        uint256 maxDeviationBps = vm.envOr("MAX_DEVIATION_BPS", uint256(500)); // 5%
        uint256 alertThresholdBps = vm.envOr("ALERT_THRESHOLD_BPS", uint256(200)); // 2%

        console.log("=== Oracle Deviation Validation ===");
        console.log("Oracle:", oracleAddress);
        console.log("Timestamp:", block.timestamp);
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Configuration:");
        console.log("  Max deviation:", maxDeviationBps, "bps (", maxDeviationBps / 100, "%)");
        console.log("  Alert threshold:", alertThresholdBps, "bps (", alertThresholdBps / 100, "%)");
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get pairs to validate
        PriceComparison[] memory comparisons = performPriceComparisons(oracle);

        console.log("=== Price Comparison Results ===\n");

        uint256 healthyCount = 0;
        uint256 warningCount = 0;
        uint256 criticalCount = 0;
        uint256 maxDeviationFound = 0;

        for (uint256 i = 0; i < comparisons.length; i++) {
            PriceComparison memory comp = comparisons[i];

            console.log("Pair", i + 1, ":", comp.pairName);
            console.log("  Base:", comp.base);
            console.log("  Quote:", comp.quote);
            console.log("  Sources checked:", comp.sources.length);

            if (comp.prices.length > 0) {
                console.log("\n  Prices:");
                for (uint256 j = 0; j < comp.prices.length; j++) {
                    console.log("    ", comp.sources[j], ":", comp.prices[j]);
                }

                console.log("\n  Statistics:");
                console.log("    Mean price:", comp.meanPrice);
                console.log("    Median price:", comp.medianPrice);
                console.log("    Max deviation:", comp.maxDeviation, "bps (", comp.maxDeviation / 100, "%)");

                // Track maximum deviation
                if (comp.maxDeviation > maxDeviationFound) {
                    maxDeviationFound = comp.maxDeviation;
                }

                // Categorize health
                if (comp.maxDeviation > maxDeviationBps) {
                    console.log("    Status: CRITICAL - Deviation exceeds maximum");
                    criticalCount++;
                } else if (comp.maxDeviation > alertThresholdBps) {
                    console.log("    Status: WARNING - Deviation exceeds alert threshold");
                    warningCount++;
                } else {
                    console.log("    Status: HEALTHY");
                    healthyCount++;
                }

                if (comp.alerts.length > 0) {
                    console.log("\n  Alerts:");
                    for (uint256 j = 0; j < comp.alerts.length; j++) {
                        console.log("    -", comp.alerts[j]);
                    }
                }
            } else {
                console.log("  Status: NO DATA");
            }

            console.log("");
        }

        // Summary
        console.log("\n=== Validation Summary ===");
        console.log("Total pairs validated:", comparisons.length);
        console.log("Healthy:", healthyCount);
        console.log("Warning:", warningCount);
        console.log("Critical:", criticalCount);
        console.log("Max deviation found:", maxDeviationFound, "bps (", maxDeviationFound / 100, "%)");

        string memory overallStatus = getOverallStatus(healthyCount, warningCount, criticalCount);
        console.log("Overall status:", overallStatus);
        console.log("========================\n");

        // Recommendations
        if (criticalCount > 0 || warningCount > 0) {
            console.log("=== Recommendations ===");

            if (criticalCount > 0) {
                console.log("CRITICAL ISSUES FOUND:");
                console.log("  - Review oracle feeds immediately");
                console.log("  - Check for oracle manipulation or failures");
                console.log("  - Consider pausing affected trading pairs");
                console.log("  - Verify network connectivity to oracle sources");
            }

            if (warningCount > 0) {
                console.log("\nWARNINGS:");
                console.log("  - Monitor affected pairs closely");
                console.log("  - Verify price feed staleness");
                console.log("  - Check for network congestion");
                console.log("  - Consider increasing update frequency");
            }

            console.log("=====================\n");
        }

        // Oracle health check
        console.log("=== Oracle Configuration ===");
        console.log("Pyth Oracle:", oracle.pythOracle());
        console.log("RedStone Oracle:", oracle.redstoneOracle());
        console.log("Max oracles per pair:", oracle.MAX_ORACLES_PER_PAIR());
        console.log("Max deviation (config):", oracle.MAX_DEVIATION_BPS(), "bps");
        console.log("==========================\n");
    }

    /**
     * @notice Perform price comparisons for multiple pairs
     */
    function performPriceComparisons(
        SmartOracleAggregator oracle
    ) internal view returns (PriceComparison[] memory) {
        address[] memory bases = getTestBases();
        address[] memory quotes = getTestQuotes();

        PriceComparison[] memory comparisons = new PriceComparison[](bases.length);

        for (uint256 i = 0; i < bases.length; i++) {
            comparisons[i] = comparePrices(oracle, bases[i], quotes[i]);
        }

        return comparisons;
    }

    /**
     * @notice Compare prices from multiple sources for a pair
     */
    function comparePrices(
        SmartOracleAggregator oracle,
        address base,
        address quote
    ) internal view returns (PriceComparison memory comp) {
        comp.base = base;
        comp.quote = quote;
        comp.pairName = getPairName(base, quote);

        // Get all registered oracles for this pair
        IOracleRegistry.OracleConfig[] memory configs = oracle.getOracles(base, quote);

        if (configs.length == 0) {
            return comp;
        }

        // Collect prices from all active sources
        uint256[] memory tempPrices = new uint256[](configs.length);
        string[] memory tempSources = new string[](configs.length);
        uint256 validPriceCount = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            if (!configs[i].isActive) continue;

            try oracle.fetchOraclePrice(configs[i], base, quote, 3600) returns (
                ISmartOracle.PriceData memory data
            ) {
                tempPrices[validPriceCount] = data.price;
                tempSources[validPriceCount] = getOracleTypeName(configs[i].oracleType);
                validPriceCount++;
            } catch {
                // Skip failed oracles
            }
        }

        if (validPriceCount == 0) {
            return comp;
        }

        // Trim arrays to actual size
        comp.prices = new uint256[](validPriceCount);
        comp.sources = new string[](validPriceCount);
        for (uint256 i = 0; i < validPriceCount; i++) {
            comp.prices[i] = tempPrices[i];
            comp.sources[i] = tempSources[i];
        }

        // Calculate statistics
        comp.meanPrice = calculateMean(comp.prices);
        comp.medianPrice = calculateMedian(comp.prices);
        comp.maxDeviation = calculateMaxDeviation(comp.prices, comp.meanPrice);

        // Generate alerts
        comp.alerts = generateAlerts(comp.prices, comp.sources, comp.maxDeviation);
        comp.hasAlert = comp.alerts.length > 0;

        return comp;
    }

    /**
     * @notice Calculate mean price
     */
    function calculateMean(uint256[] memory prices) internal pure returns (uint256) {
        if (prices.length == 0) return 0;

        uint256 sum = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            sum += prices[i];
        }
        return sum / prices.length;
    }

    /**
     * @notice Calculate median price
     */
    function calculateMedian(uint256[] memory prices) internal pure returns (uint256) {
        if (prices.length == 0) return 0;
        if (prices.length == 1) return prices[0];

        // Simple bubble sort for small arrays
        uint256[] memory sorted = new uint256[](prices.length);
        for (uint256 i = 0; i < prices.length; i++) {
            sorted[i] = prices[i];
        }

        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (sorted[i] > sorted[j]) {
                    uint256 temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }

        uint256 mid = sorted.length / 2;
        if (sorted.length % 2 == 0) {
            return (sorted[mid - 1] + sorted[mid]) / 2;
        } else {
            return sorted[mid];
        }
    }

    /**
     * @notice Calculate maximum deviation from mean in basis points
     */
    function calculateMaxDeviation(
        uint256[] memory prices,
        uint256 mean
    ) internal pure returns (uint256) {
        if (prices.length == 0 || mean == 0) return 0;

        uint256 maxDev = 0;

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 deviation;
            if (prices[i] > mean) {
                deviation = ((prices[i] - mean) * 10000) / mean;
            } else {
                deviation = ((mean - prices[i]) * 10000) / mean;
            }

            if (deviation > maxDev) {
                maxDev = deviation;
            }
        }

        return maxDev;
    }

    /**
     * @notice Generate alerts based on price analysis
     */
    function generateAlerts(
        uint256[] memory prices,
        string[] memory sources,
        uint256 maxDeviation
    ) internal pure returns (string[] memory) {
        string[] memory alerts = new string[](5);
        uint256 alertCount = 0;

        // Check for high deviation
        if (maxDeviation > 500) {
            alerts[alertCount] = "Extreme price deviation detected (>5%)";
            alertCount++;
        }

        // Check for outliers
        if (prices.length >= 3) {
            uint256 mean = calculateMean(prices);
            for (uint256 i = 0; i < prices.length && alertCount < 5; i++) {
                uint256 dev = prices[i] > mean
                    ? ((prices[i] - mean) * 10000) / mean
                    : ((mean - prices[i]) * 10000) / mean;

                if (dev > 1000) { // 10% deviation
                    alerts[alertCount] = string.concat("Outlier detected in ", sources[i]);
                    alertCount++;
                }
            }
        }

        // Trim array
        string[] memory trimmed = new string[](alertCount);
        for (uint256 i = 0; i < alertCount; i++) {
            trimmed[i] = alerts[i];
        }

        return trimmed;
    }

    /**
     * @notice Get overall system status
     */
    function getOverallStatus(
        uint256 healthy,
        uint256 warning,
        uint256 critical
    ) internal pure returns (string memory) {
        if (critical > 0) return "CRITICAL";
        if (warning > healthy / 2) return "DEGRADED";
        if (warning > 0) return "WARNING";
        return "HEALTHY";
    }

    /**
     * @notice Convert OracleType to string
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
     * @notice Get test base tokens
     */
    function getTestBases() internal pure returns (address[] memory) {
        address[] memory bases = new address[](4);
        bases[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        bases[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        bases[2] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        bases[3] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        return bases;
    }

    /**
     * @notice Get test quote tokens
     */
    function getTestQuotes() internal pure returns (address[] memory) {
        address[] memory quotes = new address[](4);
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        quotes[0] = usdc;
        quotes[1] = usdc;
        quotes[2] = usdc;
        quotes[3] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        return quotes;
    }

    /**
     * @notice Get pair name
     */
    function getPairName(address base, address quote) internal pure returns (string memory) {
        if (base == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return "ETH/USD";
        if (base == 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) return "BTC/USD";
        if (base == 0x514910771AF9Ca656af840dff83E8264EcF986CA) return "LINK/USD";
        if (base == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return "USDC/USD";
        return "UNKNOWN";
    }
}
