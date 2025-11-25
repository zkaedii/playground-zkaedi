// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title RegisterPythFeeds
 * @notice Configures Pyth Network price feeds for token pairs
 * @dev Usage: forge script script/oracle/RegisterPythFeeds.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - PYTH_ORACLE: Pyth oracle contract address
 * - PRIVATE_KEY: Owner private key
 *
 * Features:
 * - Maps tokens to Pyth price feed IDs
 * - Registers Pyth as oracle source
 * - Supports multiple chains
 * - Real Pyth feed IDs for major tokens
 */
contract RegisterPythFeeds is Script {

    struct PythFeedConfig {
        address token;
        bytes32 feedId;
        string symbol;
        string description;
    }

    struct OraclePairConfig {
        address base;
        address quote;
        uint256 heartbeat;
        uint8 priority;
        string description;
    }

    function run() external {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address pythOracle = vm.envAddress("PYTH_ORACLE");

        console.log("=== Registering Pyth Feeds ===");
        console.log("Oracle:", oracleAddress);
        console.log("Pyth Oracle:", pythOracle);
        console.log("Chain ID:", block.chainid);
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get Pyth feed configurations
        PythFeedConfig[] memory feedConfigs = getPythFeedIds(block.chainid);
        OraclePairConfig[] memory pairConfigs = getPythOraclePairs(block.chainid);

        vm.startBroadcast();

        // Step 1: Set token feed IDs
        console.log("Setting token feed IDs...\n");
        for (uint256 i = 0; i < feedConfigs.length; i++) {
            PythFeedConfig memory config = feedConfigs[i];

            console.log("Token", i + 1, ":", config.symbol);
            console.log("  Address:", config.token);
            console.log("  Feed ID:", vm.toString(config.feedId));
            console.log("  Description:", config.description);

            try oracle.setTokenFeedId(config.token, config.feedId) {
                console.log("  Status: SUCCESS\n");
            } catch Error(string memory reason) {
                console.log("  Status: FAILED -", reason, "\n");
            }
        }

        // Step 2: Register Pyth oracle for pairs
        console.log("\nRegistering Pyth oracle pairs...\n");
        for (uint256 i = 0; i < pairConfigs.length; i++) {
            OraclePairConfig memory pair = pairConfigs[i];

            console.log("Pair", i + 1, ":", pair.description);
            console.log("  Base:", pair.base);
            console.log("  Quote:", pair.quote);
            console.log("  Heartbeat:", pair.heartbeat, "seconds");
            console.log("  Priority:", pair.priority);

            IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
                oracle: pythOracle,
                oracleType: ISmartOracle.OracleType.PYTH,
                heartbeat: pair.heartbeat,
                priority: pair.priority,
                isActive: true
            });

            try oracle.registerOracle(pair.base, pair.quote, config) {
                console.log("  Status: SUCCESS\n");
            } catch Error(string memory reason) {
                console.log("  Status: FAILED -", reason, "\n");
            }
        }

        vm.stopBroadcast();

        console.log("\n=== Registration Complete ===");
        console.log("Feed IDs configured:", feedConfigs.length);
        console.log("Oracle pairs registered:", pairConfigs.length);
        console.log("===========================\n");
    }

    /**
     * @notice Get Pyth feed IDs by chain
     * @dev Real feed IDs from Pyth Network
     */
    function getPythFeedIds(uint256 chainId) internal pure returns (PythFeedConfig[] memory) {
        PythFeedConfig[] memory configs = new PythFeedConfig[](10);

        // ETH/USD - Real Pyth feed ID
        configs[0] = PythFeedConfig({
            token: getWETHAddress(chainId),
            feedId: 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            symbol: "ETH",
            description: "Ethereum"
        });

        // BTC/USD - Real Pyth feed ID
        configs[1] = PythFeedConfig({
            token: getWBTCAddress(chainId),
            feedId: 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43,
            symbol: "BTC",
            description: "Bitcoin"
        });

        // USDC/USD - Real Pyth feed ID
        configs[2] = PythFeedConfig({
            token: getUSDCAddress(chainId),
            feedId: 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a,
            symbol: "USDC",
            description: "USD Coin"
        });

        // USDT/USD - Real Pyth feed ID
        configs[3] = PythFeedConfig({
            token: getUSDTAddress(chainId),
            feedId: 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b,
            symbol: "USDT",
            description: "Tether"
        });

        // LINK/USD - Real Pyth feed ID
        configs[4] = PythFeedConfig({
            token: getLINKAddress(chainId),
            feedId: 0x8ac0c70fff57e9aefdf5edf44b51d62c2d433653cbb2cf5cc06bb115af04d221,
            symbol: "LINK",
            description: "Chainlink"
        });

        // MATIC/USD - Real Pyth feed ID
        configs[5] = PythFeedConfig({
            token: getMATICAddress(chainId),
            feedId: 0x5de33a9112c2b700b8d30b8a3402c103578ccfa2765696471cc672bd5cf6ac52,
            symbol: "MATIC",
            description: "Polygon"
        });

        // UNI/USD - Real Pyth feed ID
        configs[6] = PythFeedConfig({
            token: getUNIAddress(chainId),
            feedId: 0x78d185a741d07edb3412b09008b7c5cfb9bbbd7d568bf00ba737b456ba171501,
            symbol: "UNI",
            description: "Uniswap"
        });

        // DAI/USD - Real Pyth feed ID
        configs[7] = PythFeedConfig({
            token: getDAIAddress(chainId),
            feedId: 0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd,
            symbol: "DAI",
            description: "Dai Stablecoin"
        });

        // AVAX/USD - Real Pyth feed ID
        configs[8] = PythFeedConfig({
            token: getAVAXAddress(chainId),
            feedId: 0x93da3352f9f1d105fdfe4971cfa80e9dd777bfc5d0f683ebb6e1294b92137bb7,
            symbol: "AVAX",
            description: "Avalanche"
        });

        // ARB/USD - Real Pyth feed ID
        configs[9] = PythFeedConfig({
            token: getARBAddress(chainId),
            feedId: 0x3fa4252848f9f0a1480be62745a4629d9eb1322aebab8a791e344b3b9c1adcf5,
            symbol: "ARB",
            description: "Arbitrum"
        });

        return configs;
    }

    /**
     * @notice Get oracle pair configurations
     */
    function getPythOraclePairs(uint256 chainId) internal pure returns (OraclePairConfig[] memory) {
        address usdc = getUSDCAddress(chainId);

        OraclePairConfig[] memory pairs = new OraclePairConfig[](6);

        pairs[0] = OraclePairConfig({
            base: getWETHAddress(chainId),
            quote: usdc,
            heartbeat: 60, // Pyth updates every ~1 second
            priority: 2,
            description: "ETH/USD (Pyth)"
        });

        pairs[1] = OraclePairConfig({
            base: getWBTCAddress(chainId),
            quote: usdc,
            heartbeat: 60,
            priority: 2,
            description: "BTC/USD (Pyth)"
        });

        pairs[2] = OraclePairConfig({
            base: getLINKAddress(chainId),
            quote: usdc,
            heartbeat: 60,
            priority: 2,
            description: "LINK/USD (Pyth)"
        });

        pairs[3] = OraclePairConfig({
            base: getMATICAddress(chainId),
            quote: usdc,
            heartbeat: 60,
            priority: 2,
            description: "MATIC/USD (Pyth)"
        });

        pairs[4] = OraclePairConfig({
            base: getUNIAddress(chainId),
            quote: usdc,
            heartbeat: 60,
            priority: 2,
            description: "UNI/USD (Pyth)"
        });

        pairs[5] = OraclePairConfig({
            base: getDAIAddress(chainId),
            quote: usdc,
            heartbeat: 60,
            priority: 2,
            description: "DAI/USD (Pyth)"
        });

        return pairs;
    }

    // Helper functions for token addresses by chain
    function getWETHAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        if (chainId == 137) return 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        return address(0x1);
    }

    function getWBTCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        if (chainId == 137) return 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
        return address(0x2);
    }

    function getUSDCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (chainId == 137) return 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        return address(0x3);
    }

    function getUSDTAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        if (chainId == 137) return 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        return address(0x4);
    }

    function getLINKAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        if (chainId == 137) return 0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39;
        return address(0x5);
    }

    function getMATICAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        if (chainId == 137) return 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        return address(0x6);
    }

    function getUNIAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        return address(0x7);
    }

    function getDAIAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        if (chainId == 137) return 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        return address(0x8);
    }

    function getAVAXAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 43114) return 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        return address(0x9);
    }

    function getARBAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 42161) return 0x912CE59144191C1204E64559FE8253a0e49E6548;
        return address(0xA);
    }
}
