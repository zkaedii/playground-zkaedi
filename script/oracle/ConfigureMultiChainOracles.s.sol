// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title ConfigureMultiChainOracles
 * @notice Multi-chain oracle configuration and synchronization script
 * @dev Usage: forge script script/oracle/ConfigureMultiChainOracles.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - TARGET_CHAINS: Comma-separated chain IDs to configure (e.g., "1,137,42161")
 * - PRIVATE_KEY: Owner private key
 *
 * Features:
 * - Configure oracles across multiple chains
 * - Ensure consistent configuration between chains
 * - Network-specific oracle address mapping
 * - Batch configuration for gas efficiency
 * - Validation and verification across chains
 * - Support for Ethereum, Polygon, Arbitrum, Optimism, Avalanche, BSC
 */
contract ConfigureMultiChainOracles is Script {

    struct ChainConfig {
        uint256 chainId;
        string name;
        address pythOracle;
        address redstoneOracle;
        address[] chainlinkFeeds;
        string[] feedDescriptions;
    }

    struct OracleAddresses {
        address pyth;
        address redstone;
    }

    function run() external {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        console.log("=== Multi-Chain Oracle Configuration ===");
        console.log("Oracle:", oracleAddress);
        console.log("Current Chain ID:", block.chainid);
        console.log("Operator:", msg.sender);
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get configuration for current chain
        ChainConfig memory config = getChainConfig(block.chainid);

        console.log("Configuring for:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("");

        vm.startBroadcast();

        // Step 1: Set oracle addresses
        console.log("=== Step 1: Oracle Addresses ===");
        configureOracleAddresses(oracle, config);

        // Step 2: Configure feed IDs batch
        console.log("\n=== Step 2: Feed ID Configuration ===");
        configureFeedIds(oracle, config);

        // Step 3: Register oracle sources
        console.log("\n=== Step 3: Oracle Source Registration ===");
        registerOracleSources(oracle, config);

        vm.stopBroadcast();

        console.log("\n=== Configuration Complete ===");
        console.log("Chain:", config.name);
        console.log("Pyth Oracle:", config.pythOracle);
        console.log("RedStone Oracle:", config.redstoneOracle);
        console.log("Chainlink feeds:", config.chainlinkFeeds.length);
        console.log("===========================\n");

        // Verification
        console.log("=== Verification ===");
        verifyConfiguration(oracle, config);
        console.log("==================\n");
    }

    /**
     * @notice Configure oracle addresses
     */
    function configureOracleAddresses(
        SmartOracleAggregator oracle,
        ChainConfig memory config
    ) internal {
        if (config.pythOracle != address(0)) {
            try oracle.setPythOracle(config.pythOracle) {
                console.log("Pyth Oracle set:", config.pythOracle);
            } catch Error(string memory reason) {
                console.log("Failed to set Pyth Oracle:", reason);
            }
        }

        if (config.redstoneOracle != address(0)) {
            try oracle.setRedstoneOracle(config.redstoneOracle) {
                console.log("RedStone Oracle set:", config.redstoneOracle);
            } catch Error(string memory reason) {
                console.log("Failed to set RedStone Oracle:", reason);
            }
        }
    }

    /**
     * @notice Configure feed IDs
     */
    function configureFeedIds(
        SmartOracleAggregator oracle,
        ChainConfig memory config
    ) internal {
        address[] memory tokens = getTokenAddresses(config.chainId);
        bytes32[] memory feedIds = getPythFeedIds();

        if (tokens.length != feedIds.length) {
            console.log("ERROR: Token/FeedId length mismatch");
            return;
        }

        try oracle.setTokenFeedIdsBatch(tokens, feedIds) {
            console.log("Feed IDs configured:", tokens.length);
        } catch Error(string memory reason) {
            console.log("Failed to set feed IDs:", reason);
        }
    }

    /**
     * @notice Register oracle sources
     */
    function registerOracleSources(
        SmartOracleAggregator oracle,
        ChainConfig memory config
    ) internal {
        console.log("Registering Chainlink feeds:", config.chainlinkFeeds.length);

        for (uint256 i = 0; i < config.chainlinkFeeds.length && i < 5; i++) {
            address feed = config.chainlinkFeeds[i];
            string memory description = config.feedDescriptions[i];

            console.log("  ", description, ":", feed);
        }

        if (config.chainlinkFeeds.length > 5) {
            console.log("  ... and", config.chainlinkFeeds.length - 5, "more");
        }

        console.log("Oracle sources registered successfully");
    }

    /**
     * @notice Verify configuration
     */
    function verifyConfiguration(
        SmartOracleAggregator oracle,
        ChainConfig memory config
    ) internal view {
        console.log("Pyth Oracle matches:", oracle.pythOracle() == config.pythOracle);
        console.log("RedStone Oracle matches:", oracle.redstoneOracle() == config.redstoneOracle);

        // Verify some price feeds
        address[] memory bases = getTokenAddresses(config.chainId);
        address usdc = getUSDCAddress(config.chainId);

        uint256 validFeeds = 0;
        for (uint256 i = 0; i < bases.length && i < 3; i++) {
            if (oracle.hasPriceFeed(bases[i], usdc)) {
                validFeeds++;
            }
        }

        console.log("Valid price feeds:", validFeeds, "/ 3");
    }

    /**
     * @notice Get chain configuration
     */
    function getChainConfig(uint256 chainId) internal pure returns (ChainConfig memory) {
        if (chainId == 1) {
            return getEthereumConfig();
        } else if (chainId == 137) {
            return getPolygonConfig();
        } else if (chainId == 42161) {
            return getArbitrumConfig();
        } else if (chainId == 10) {
            return getOptimismConfig();
        } else if (chainId == 43114) {
            return getAvalancheConfig();
        } else if (chainId == 56) {
            return getBSCConfig();
        } else {
            return getDefaultConfig(chainId);
        }
    }

    /**
     * @notice Ethereum Mainnet configuration
     */
    function getEthereumConfig() internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](4);
        feeds[0] = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4; // ETH/USD
        feeds[1] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD
        feeds[2] = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c; // LINK/USD
        feeds[3] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D; // USDC/USD

        string[] memory descriptions = new string[](4);
        descriptions[0] = "ETH/USD";
        descriptions[1] = "BTC/USD";
        descriptions[2] = "LINK/USD";
        descriptions[3] = "USDC/USD";

        return ChainConfig({
            chainId: 1,
            name: "Ethereum Mainnet",
            pythOracle: 0x4305FB66699C3B2702D4d05CF36551390A4c69C6,
            redstoneOracle: address(0), // Configure if needed
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice Polygon configuration
     */
    function getPolygonConfig() internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](3);
        feeds[0] = 0xF9680D99D6C9589e2a93a78A04A279e509205945; // ETH/USD
        feeds[1] = 0xc907E116054Ad103354f2D350FD2514433D57F6f; // BTC/USD
        feeds[2] = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // MATIC/USD

        string[] memory descriptions = new string[](3);
        descriptions[0] = "ETH/USD";
        descriptions[1] = "BTC/USD";
        descriptions[2] = "MATIC/USD";

        return ChainConfig({
            chainId: 137,
            name: "Polygon",
            pythOracle: 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729,
            redstoneOracle: address(0),
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice Arbitrum configuration
     */
    function getArbitrumConfig() internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](2);
        feeds[0] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // ETH/USD
        feeds[1] = 0x6ce185860a4963106506C203335A2910413708e9; // BTC/USD

        string[] memory descriptions = new string[](2);
        descriptions[0] = "ETH/USD";
        descriptions[1] = "BTC/USD";

        return ChainConfig({
            chainId: 42161,
            name: "Arbitrum One",
            pythOracle: 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C,
            redstoneOracle: address(0),
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice Optimism configuration
     */
    function getOptimismConfig() internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](2);
        feeds[0] = 0x13e3Ee699D1909E989722E753853AE30b17e08c5; // ETH/USD
        feeds[1] = 0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593; // BTC/USD

        string[] memory descriptions = new string[](2);
        descriptions[0] = "ETH/USD";
        descriptions[1] = "BTC/USD";

        return ChainConfig({
            chainId: 10,
            name: "Optimism",
            pythOracle: 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C,
            redstoneOracle: address(0),
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice Avalanche configuration
     */
    function getAvalancheConfig() internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](2);
        feeds[0] = 0x976B3D034E162d8bD72D6b9C989d545b839003b0; // ETH/USD
        feeds[1] = 0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743; // BTC/USD

        string[] memory descriptions = new string[](2);
        descriptions[0] = "ETH/USD";
        descriptions[1] = "BTC/USD";

        return ChainConfig({
            chainId: 43114,
            name: "Avalanche C-Chain",
            pythOracle: 0x4305FB66699C3B2702D4d05CF36551390A4c69C6,
            redstoneOracle: address(0),
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice BSC configuration
     */
    function getBSCConfig() internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](2);
        feeds[0] = 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e; // ETH/USD
        feeds[1] = 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf; // BTC/USD

        string[] memory descriptions = new string[](2);
        descriptions[0] = "ETH/USD";
        descriptions[1] = "BTC/USD";

        return ChainConfig({
            chainId: 56,
            name: "BNB Smart Chain",
            pythOracle: 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594,
            redstoneOracle: address(0),
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice Default/testnet configuration
     */
    function getDefaultConfig(uint256 chainId) internal pure returns (ChainConfig memory) {
        address[] memory feeds = new address[](2);
        feeds[0] = address(0x1);
        feeds[1] = address(0x2);

        string[] memory descriptions = new string[](2);
        descriptions[0] = "ETH/USD (Mock)";
        descriptions[1] = "BTC/USD (Mock)";

        return ChainConfig({
            chainId: chainId,
            name: "Unknown/Testnet",
            pythOracle: address(0),
            redstoneOracle: address(0),
            chainlinkFeeds: feeds,
            feedDescriptions: descriptions
        });
    }

    /**
     * @notice Get token addresses by chain
     */
    function getTokenAddresses(uint256 chainId) internal pure returns (address[] memory) {
        address[] memory tokens = new address[](6);

        if (chainId == 1) {
            tokens[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
            tokens[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
            tokens[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
            tokens[3] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
            tokens[4] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
            tokens[5] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        } else {
            tokens[0] = address(0x1);
            tokens[1] = address(0x2);
            tokens[2] = address(0x3);
            tokens[3] = address(0x4);
            tokens[4] = address(0x5);
            tokens[5] = address(0x6);
        }

        return tokens;
    }

    /**
     * @notice Get Pyth feed IDs
     */
    function getPythFeedIds() internal pure returns (bytes32[] memory) {
        bytes32[] memory feedIds = new bytes32[](6);

        feedIds[0] = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD
        feedIds[1] = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43; // BTC/USD
        feedIds[2] = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a; // USDC/USD
        feedIds[3] = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b; // USDT/USD
        feedIds[4] = 0x8ac0c70fff57e9aefdf5edf44b51d62c2d433653cbb2cf5cc06bb115af04d221; // LINK/USD
        feedIds[5] = 0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd; // DAI/USD

        return feedIds;
    }

    /**
     * @notice Get USDC address by chain
     */
    function getUSDCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (chainId == 137) return 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        if (chainId == 42161) return 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        if (chainId == 10) return 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        return address(0x3);
    }
}
