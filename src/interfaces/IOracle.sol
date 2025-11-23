// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////
                    ORACLE INTERFACES
//////////////////////////////////////////////////////////////*/

/// @title IChainlinkPriceFeed
/// @notice Interface for Chainlink V3 Aggregator price feeds
interface IChainlinkPriceFeed {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/// @title IPythPriceFeed
/// @notice Interface for Pyth Network price feeds (pull-based oracle)
interface IPythPriceFeed {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    /// @notice Get the latest price for a price feed
    /// @param id The price feed ID
    /// @return price The price struct
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);

    /// @notice Get price with staleness check
    /// @param id The price feed ID
    /// @param age Maximum acceptable age in seconds
    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);

    /// @notice Update price feeds with new data
    /// @param updateData Encoded price update data from Pyth
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    /// @notice Get the update fee for price feed data
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256);
}

/// @title IRedstoneOracle
/// @notice Interface for RedStone oracle (modular push/pull)
interface IRedstoneOracle {
    function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256);
    function getTimestampForDataFeed(bytes32 dataFeedId) external view returns (uint256);
    function getDataFeedIdForSymbol(string memory symbol) external view returns (bytes32);
}

/// @title ISmartOracle
/// @notice Unified oracle interface supporting multiple providers
interface ISmartOracle {
    enum OracleType {
        CHAINLINK,
        PYTH,
        REDSTONE,
        TWAP,
        CUSTOM
    }

    struct PriceData {
        uint256 price;          // Price in base units (scaled by decimals)
        uint8 decimals;         // Decimal precision
        uint256 timestamp;      // Last update timestamp
        uint256 confidence;     // Confidence interval (if available)
        OracleType source;      // Oracle source type
    }

    /// @notice Get the price for a token pair
    /// @param base Base token address
    /// @param quote Quote token address
    /// @return data Price data struct
    function getPrice(address base, address quote) external view returns (PriceData memory data);

    /// @notice Get price with freshness requirement
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param maxAge Maximum acceptable price age in seconds
    function getPriceNoOlderThan(
        address base,
        address quote,
        uint256 maxAge
    ) external view returns (PriceData memory data);

    /// @notice Check if a price feed is available
    function hasPriceFeed(address base, address quote) external view returns (bool);

    /// @notice Get TWAP price over a period
    /// @param base Base token address
    /// @param quote Quote token address
    /// @param period TWAP period in seconds
    function getTWAP(
        address base,
        address quote,
        uint32 period
    ) external view returns (uint256 price);
}

/// @title IOracleRegistry
/// @notice Registry for managing oracle configurations
interface IOracleRegistry {
    struct OracleConfig {
        address oracle;
        ISmartOracle.OracleType oracleType;
        uint256 heartbeat;      // Expected update frequency
        uint8 priority;         // Priority for fallback (lower = higher priority)
        bool isActive;
    }

    /// @notice Register a new oracle for a token pair
    function registerOracle(
        address base,
        address quote,
        OracleConfig calldata config
    ) external;

    /// @notice Get all oracles for a token pair
    function getOracles(address base, address quote) external view returns (OracleConfig[] memory);

    /// @notice Get the primary oracle for a token pair
    function getPrimaryOracle(address base, address quote) external view returns (OracleConfig memory);
}
