// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/oracles/SmartOracleAggregator.sol";
import "../../src/interfaces/IOracle.sol";

/**
 * @title RegisterChainlinkFeeds
 * @notice Batch registers Chainlink price feeds for multiple token pairs
 * @dev Usage: forge script script/oracle/RegisterChainlinkFeeds.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Environment Variables:
 * - ORACLE_ADDRESS: Deployed SmartOracleAggregator address
 * - PRIVATE_KEY: Owner private key
 *
 * Features:
 * - Registers popular token pairs (ETH, BTC, USDC, USDT, etc.)
 * - Configurable priority and heartbeat
 * - Network-specific feed addresses
 * - Comprehensive logging
 */
contract RegisterChainlinkFeeds is Script {

    struct FeedConfig {
        address base;
        address quote;
        address feed;
        uint256 heartbeat;
        uint8 priority;
        string description;
    }

    function run() external {
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        console.log("=== Registering Chainlink Feeds ===");
        console.log("Oracle:", oracleAddress);
        console.log("Chain ID:", block.chainid);
        console.log("");

        SmartOracleAggregator oracle = SmartOracleAggregator(oracleAddress);

        // Get feed configurations based on network
        FeedConfig[] memory feeds = getChainlinkFeeds(block.chainid);

        vm.startBroadcast();

        console.log("Registering", feeds.length, "Chainlink feeds...\n");

        for (uint256 i = 0; i < feeds.length; i++) {
            FeedConfig memory feed = feeds[i];

            console.log("Feed", i + 1, ":", feed.description);
            console.log("  Base:", feed.base);
            console.log("  Quote:", feed.quote);
            console.log("  Feed:", feed.feed);
            console.log("  Heartbeat:", feed.heartbeat, "seconds");
            console.log("  Priority:", feed.priority);

            IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
                oracle: feed.feed,
                oracleType: ISmartOracle.OracleType.CHAINLINK,
                heartbeat: feed.heartbeat,
                priority: feed.priority,
                isActive: true
            });

            try oracle.registerOracle(feed.base, feed.quote, config) {
                console.log("  Status: SUCCESS\n");
            } catch Error(string memory reason) {
                console.log("  Status: FAILED -", reason, "\n");
            }
        }

        vm.stopBroadcast();

        console.log("\n=== Registration Complete ===");
        console.log("Total feeds processed:", feeds.length);
        console.log("==========================\n");
    }

    /**
     * @notice Get Chainlink feed configurations by chain ID
     * @param chainId The chain ID
     * @return feeds Array of feed configurations
     */
    function getChainlinkFeeds(uint256 chainId) internal pure returns (FeedConfig[] memory feeds) {
        if (chainId == 1) {
            // Ethereum Mainnet
            feeds = new FeedConfig[](8);

            feeds[0] = FeedConfig({
                base: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4, // ETH/USD
                heartbeat: 3600,
                priority: 1,
                description: "ETH/USD"
            });

            feeds[1] = FeedConfig({
                base: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // BTC/USD
                heartbeat: 3600,
                priority: 1,
                description: "BTC/USD"
            });

            feeds[2] = FeedConfig({
                base: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                quote: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
                feed: 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D, // USDC/USD
                heartbeat: 86400,
                priority: 1,
                description: "USDC/USD"
            });

            feeds[3] = FeedConfig({
                base: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D, // USDT/USD
                heartbeat: 86400,
                priority: 1,
                description: "USDT/USD"
            });

            feeds[4] = FeedConfig({
                base: 0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c, // LINK/USD
                heartbeat: 3600,
                priority: 1,
                description: "LINK/USD"
            });

            feeds[5] = FeedConfig({
                base: 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0, // MATIC
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676, // MATIC/USD
                heartbeat: 3600,
                priority: 1,
                description: "MATIC/USD"
            });

            feeds[6] = FeedConfig({
                base: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, // UNI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0x553303d460EE0afB37EdFf9bE42922D8FF63220e, // UNI/USD
                heartbeat: 3600,
                priority: 1,
                description: "UNI/USD"
            });

            feeds[7] = FeedConfig({
                base: 0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                quote: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                feed: 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, // DAI/USD
                heartbeat: 3600,
                priority: 1,
                description: "DAI/USD"
            });

        } else if (chainId == 137) {
            // Polygon
            feeds = new FeedConfig[](4);

            feeds[0] = FeedConfig({
                base: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, // WETH
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                feed: 0xF9680D99D6C9589e2a93a78A04A279e509205945, // ETH/USD
                heartbeat: 3600,
                priority: 1,
                description: "ETH/USD (Polygon)"
            });

            feeds[1] = FeedConfig({
                base: 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6, // WBTC
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                feed: 0xc907E116054Ad103354f2D350FD2514433D57F6f, // BTC/USD
                heartbeat: 3600,
                priority: 1,
                description: "BTC/USD (Polygon)"
            });

            feeds[2] = FeedConfig({
                base: 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, // WMATIC
                quote: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                feed: 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0, // MATIC/USD
                heartbeat: 3600,
                priority: 1,
                description: "MATIC/USD (Polygon)"
            });

            feeds[3] = FeedConfig({
                base: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
                quote: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F, // USDT
                feed: 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7, // USDC/USD
                heartbeat: 86400,
                priority: 1,
                description: "USDC/USD (Polygon)"
            });

        } else {
            // Default/testnet configuration
            feeds = new FeedConfig[](2);

            feeds[0] = FeedConfig({
                base: address(0x1), // Mock WETH
                quote: address(0x2), // Mock USDC
                feed: address(0x3), // Mock feed
                heartbeat: 3600,
                priority: 1,
                description: "ETH/USD (Mock)"
            });

            feeds[1] = FeedConfig({
                base: address(0x4), // Mock WBTC
                quote: address(0x2), // Mock USDC
                feed: address(0x5), // Mock feed
                heartbeat: 3600,
                priority: 1,
                description: "BTC/USD (Mock)"
            });
        }

        return feeds;
    }
}
