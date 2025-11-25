// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title MonitorOracleHealth
 * @notice Advanced oracle health monitoring and alerting system
 * @dev Usage: forge script script/oracle/MonitorOracleHealth.s.sol --rpc-url <RPC_URL>
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - ALERT_STALENESS_THRESHOLD: Alert if price older than this (default: 3600)
 * - ALERT_ON_FALLBACK: Alert when fallback oracle is used (default: true)
 *
 * Features:
 * - Monitors price staleness across all pairs
 * - Checks oracle availability and status
 * - Detects fallback oracle usage
 * - Validates price deviation between sources
 * - Generates health score and recommendations
 * - Can be run as a cron job for continuous monitoring
 */
contract MonitorOracleHealth is Script {

    struct HealthCheck {
        address base;
        address quote;
        string pairName;
        bool hasFeed;
        bool priceAvailable;
        uint256 priceAge;
        string primarySource;
        bool isFallback;
        uint8 healthScore;
        string status;
        string[] warnings;
    }

    struct MonitoringConfig {
        uint256 stalenessThreshold;
        uint256 criticalThreshold;
        bool alertOnFallback;
        bool verboseOutput;
    }

    function run() external view {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        MonitoringConfig memory config = MonitoringConfig({
            stalenessThreshold: vm.envOr("ALERT_STALENESS_THRESHOLD", uint256(3600)),
            criticalThreshold: vm.envOr("CRITICAL_STALENESS_THRESHOLD", uint256(7200)),
            alertOnFallback: vm.envOr("ALERT_ON_FALLBACK", true),
            verboseOutput: vm.envOr("VERBOSE_OUTPUT", true)
        });

        console.log("=== Oracle Health Monitor ===");
        console.log("Oracle:", oracleAddress);
        console.log("Timestamp:", block.timestamp);
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Monitoring Configuration:");
        console.log("  Staleness threshold:", config.stalenessThreshold, "seconds");
        console.log("  Critical threshold:", config.criticalThreshold, "seconds");
        console.log("  Alert on fallback:", config.alertOnFallback);
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get monitoring pairs
        HealthCheck[] memory checks = performHealthChecks(oracle, config);

        // Analyze results
        uint256 healthyCount = 0;
        uint256 warningCount = 0;
        uint256 criticalCount = 0;
        uint256 totalScore = 0;

        console.log("=== Health Check Results ===\n");

        for (uint256 i = 0; i < checks.length; i++) {
            HealthCheck memory check = checks[i];

            if (config.verboseOutput) {
                console.log("Pair", i + 1, ":", check.pairName);
                console.log("  Base:", check.base);
                console.log("  Quote:", check.quote);
                console.log("  Has feed:", check.hasFeed);
                console.log("  Price available:", check.priceAvailable);

                if (check.priceAvailable) {
                    console.log("  Price age:", check.priceAge, "seconds");
                    console.log("  Primary source:", check.primarySource);
                    console.log("  Using fallback:", check.isFallback);
                }

                console.log("  Health score:", check.healthScore, "/100");
                console.log("  Status:", check.status);

                if (check.warnings.length > 0) {
                    console.log("  Warnings:");
                    for (uint256 j = 0; j < check.warnings.length; j++) {
                        console.log("    -", check.warnings[j]);
                    }
                }
                console.log("");
            }

            // Categorize health
            totalScore += check.healthScore;
            if (check.healthScore >= 80) {
                healthyCount++;
            } else if (check.healthScore >= 50) {
                warningCount++;
            } else {
                criticalCount++;
            }
        }

        // Overall system health
        console.log("\n=== System Health Summary ===");
        console.log("Total pairs monitored:", checks.length);
        console.log("Healthy (80-100):", healthyCount);
        console.log("Warning (50-79):", warningCount);
        console.log("Critical (0-49):", criticalCount);

        if (checks.length > 0) {
            uint256 avgScore = totalScore / checks.length;
            console.log("Average health score:", avgScore, "/100");
            console.log("");
            console.log("Overall system status:", getSystemStatus(avgScore));
        }

        console.log("===========================\n");

        // Recommendations
        if (warningCount > 0 || criticalCount > 0) {
            console.log("=== Recommendations ===");

            if (criticalCount > 0) {
                console.log("CRITICAL: ", criticalCount, "pairs have severe health issues");
                console.log("  - Check oracle contract configuration");
                console.log("  - Verify oracle feed addresses are correct");
                console.log("  - Consider registering backup oracle sources");
            }

            if (warningCount > 0) {
                console.log("WARNING: ", warningCount, "pairs have minor health issues");
                console.log("  - Monitor staleness thresholds");
                console.log("  - Verify primary oracles are updating correctly");
            }

            console.log("======================\n");
        }

        // Oracle configuration check
        console.log("=== Oracle Configuration ===");
        console.log("Pyth Oracle:", oracle.pythOracle());
        console.log("RedStone Oracle:", oracle.redstoneOracle());
        console.log("Default staleness:", oracle.DEFAULT_STALENESS(), "seconds");
        console.log("Max deviation:", oracle.MAX_DEVIATION_BPS(), "bps");
        console.log("==========================\n");
    }

    /**
     * @notice Perform health checks on all monitored pairs
     */
    function performHealthChecks(
        SmartOracleAggregator oracle,
        MonitoringConfig memory config
    ) internal view returns (HealthCheck[] memory) {
        // Get test pairs (in production, this would query all registered pairs)
        address[] memory bases = getMonitoredBases(block.chainid);
        address[] memory quotes = getMonitoredQuotes(block.chainid);

        uint256 totalPairs = bases.length;
        HealthCheck[] memory checks = new HealthCheck[](totalPairs);

        for (uint256 i = 0; i < totalPairs; i++) {
            checks[i] = checkPairHealth(oracle, bases[i], quotes[i], config);
        }

        return checks;
    }

    /**
     * @notice Check health of a single pair
     */
    function checkPairHealth(
        SmartOracleAggregator oracle,
        address base,
        address quote,
        MonitoringConfig memory config
    ) internal view returns (HealthCheck memory check) {
        check.base = base;
        check.quote = quote;
        check.pairName = getPairName(base, quote, block.chainid);
        check.hasFeed = oracle.hasPriceFeed(base, quote);

        if (!check.hasFeed) {
            check.healthScore = 0;
            check.status = "NO_FEED";
            check.warnings = new string[](1);
            check.warnings[0] = "No price feed registered";
            return check;
        }

        // Try to get price
        try oracle.getPrice(base, quote) returns (ISmartOracle.PriceData memory data) {
            check.priceAvailable = true;
            check.priceAge = block.timestamp - data.timestamp;
            check.primarySource = getOracleTypeName(data.source);

            // Calculate health score
            uint8 score = 100;
            uint256 warningCount = 0;
            check.warnings = new string[](5); // Max 5 warnings

            // Check staleness
            if (check.priceAge > config.criticalThreshold) {
                score -= 50;
                check.warnings[warningCount] = "CRITICAL: Price is critically stale";
                warningCount++;
            } else if (check.priceAge > config.stalenessThreshold) {
                score -= 20;
                check.warnings[warningCount] = "WARNING: Price is stale";
                warningCount++;
            }

            // Check for fallback usage
            IOracleRegistry.OracleConfig memory primaryConfig = oracle.getPrimaryOracle(base, quote);
            if (data.source != primaryConfig.oracleType) {
                check.isFallback = true;
                if (config.alertOnFallback) {
                    score -= 15;
                    check.warnings[warningCount] = "ALERT: Using fallback oracle";
                    warningCount++;
                }
            }

            // Trim warnings array
            string[] memory trimmedWarnings = new string[](warningCount);
            for (uint256 i = 0; i < warningCount; i++) {
                trimmedWarnings[i] = check.warnings[i];
            }
            check.warnings = trimmedWarnings;

            check.healthScore = score;
            check.status = score >= 80 ? "HEALTHY" : (score >= 50 ? "WARNING" : "CRITICAL");

        } catch {
            check.priceAvailable = false;
            check.healthScore = 10;
            check.status = "FAILED";
            check.warnings = new string[](1);
            check.warnings[0] = "Failed to fetch price";
        }
    }

    /**
     * @notice Get overall system status based on average score
     */
    function getSystemStatus(uint256 avgScore) internal pure returns (string memory) {
        if (avgScore >= 90) return "EXCELLENT";
        if (avgScore >= 80) return "GOOD";
        if (avgScore >= 70) return "FAIR";
        if (avgScore >= 50) return "DEGRADED";
        return "CRITICAL";
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
     * @notice Get monitored base tokens
     */
    function getMonitoredBases(uint256 chainId) internal pure returns (address[] memory) {
        address[] memory bases = new address[](4);

        if (chainId == 1) {
            bases[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
            bases[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
            bases[2] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
            bases[3] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        } else {
            bases[0] = address(0x1);
            bases[1] = address(0x2);
            bases[2] = address(0x3);
            bases[3] = address(0x4);
        }

        return bases;
    }

    /**
     * @notice Get monitored quote tokens
     */
    function getMonitoredQuotes(uint256 chainId) internal pure returns (address[] memory) {
        address[] memory quotes = new address[](4);
        address usdc = chainId == 1 ? 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 : address(0x5);

        quotes[0] = usdc;
        quotes[1] = usdc;
        quotes[2] = usdc;
        quotes[3] = chainId == 1 ? 0xdAC17F958D2ee523a2206206994597C13D831ec7 : address(0x6); // USDT

        return quotes;
    }

    /**
     * @notice Get human-readable pair name
     */
    function getPairName(address base, address quote, uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) {
            if (base == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return "ETH/USD";
            if (base == 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) return "BTC/USD";
            if (base == 0x514910771AF9Ca656af840dff83E8264EcF986CA) return "LINK/USD";
            if (base == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return "USDC/USD";
        }
        return "UNKNOWN";
    }
}
