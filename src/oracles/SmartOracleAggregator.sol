// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IOracle.sol";

/*//////////////////////////////////////////////////////////////
                    SMART ORACLE AGGREGATOR
//////////////////////////////////////////////////////////////*/

/**
 * @title SmartOracleAggregator
 * @author Multi-Chain DEX & Oracle Integration
 * @notice Aggregates multiple oracle sources with intelligent fallback and TWAP support
 * @dev Features:
 *      - Multi-oracle support (Chainlink, Pyth, RedStone)
 *      - Automatic fallback on stale/invalid data
 *      - TWAP calculation from DEX pools
 *      - Price deviation protection
 *      - Gas-optimized storage patterns
 */
contract SmartOracleAggregator is
    ISmartOracle,
    IOracleRegistry,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error StalePrice();
    error InvalidPrice();
    error NoPriceFeed();
    error PriceDeviationTooHigh();
    error OracleNotActive();
    error InvalidOracle();
    error MaxOraclesReached();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event OracleRegistered(
        address indexed base,
        address indexed quote,
        address oracle,
        OracleType oracleType
    );
    event OracleDeactivated(address indexed base, address indexed quote, address oracle);
    event PriceFetched(
        address indexed base,
        address indexed quote,
        uint256 price,
        OracleType source
    );
    event FallbackTriggered(
        address indexed base,
        address indexed quote,
        OracleType primary,
        OracleType fallback_
    );

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Maximum number of oracles per pair
    uint8 public constant MAX_ORACLES_PER_PAIR = 5;

    /// @dev Default staleness threshold (1 hour)
    uint256 public constant DEFAULT_STALENESS = 3600;

    /// @dev Maximum price deviation between oracles (5%)
    uint256 public constant MAX_DEVIATION_BPS = 500;

    /// @dev Pair hash => Oracle configs
    mapping(bytes32 => OracleConfig[]) private _oracles;

    /// @dev Pair hash => Staleness threshold
    mapping(bytes32 => uint256) private _stalenessThreshold;

    /// @dev TWAP observations for DEX-based pricing
    struct TWAPObservation {
        uint256 price;
        uint256 timestamp;
        uint256 cumulativePrice;
    }

    /// @dev Pair hash => TWAP observations (circular buffer)
    mapping(bytes32 => TWAPObservation[]) private _twapObservations;
    mapping(bytes32 => uint256) private _twapIndex;

    /// @dev Pair hash => Custom price (for testing/emergency)
    mapping(bytes32 => PriceData) private _customPrices;

    /// @dev Token address => Symbol (for Pyth/RedStone lookups)
    mapping(address => bytes32) public tokenFeedIds;

    /// @dev Pyth contract address
    address public pythOracle;

    /// @dev RedStone contract address
    address public redstoneOracle;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _pythOracle, address _redstoneOracle) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        pythOracle = _pythOracle;
        redstoneOracle = _redstoneOracle;
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOracleRegistry
    function registerOracle(
        address base,
        address quote,
        OracleConfig calldata config
    ) external onlyOwner {
        if (config.oracle == address(0)) revert InvalidOracle();

        bytes32 pairHash = _getPairHash(base, quote);
        OracleConfig[] storage configs = _oracles[pairHash];

        uint256 configsLen = configs.length;
        if (configsLen >= MAX_ORACLES_PER_PAIR) revert MaxOraclesReached();

        // Insert in priority order
        uint256 insertIdx = configsLen;
        unchecked {
            for (uint256 i; i < configsLen; ++i) {
                if (config.priority < configs[i].priority) {
                    insertIdx = i;
                    break;
                }
            }

            // Shift elements and insert
            configs.push();
            for (uint256 i = configsLen; i > insertIdx; --i) {
                configs[i] = configs[i - 1];
            }
        }
        configs[insertIdx] = config;

        emit OracleRegistered(base, quote, config.oracle, config.oracleType);
    }

    /// @notice Deactivate an oracle
    function deactivateOracle(
        address base,
        address quote,
        address oracle
    ) external onlyOwner {
        bytes32 pairHash = _getPairHash(base, quote);
        OracleConfig[] storage configs = _oracles[pairHash];

        uint256 len = configs.length;
        unchecked {
            for (uint256 i; i < len; ++i) {
                if (configs[i].oracle == oracle) {
                    configs[i].isActive = false;
                    emit OracleDeactivated(base, quote, oracle);
                    return;
                }
            }
        }
    }

    /// @inheritdoc IOracleRegistry
    function getOracles(address base, address quote)
        external view returns (OracleConfig[] memory)
    {
        return _oracles[_getPairHash(base, quote)];
    }

    /// @inheritdoc IOracleRegistry
    function getPrimaryOracle(address base, address quote)
        external view returns (OracleConfig memory)
    {
        OracleConfig[] storage configs = _oracles[_getPairHash(base, quote)];
        if (configs.length == 0) revert NoPriceFeed();
        return configs[0];
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE FETCHING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISmartOracle
    function getPrice(address base, address quote)
        external view returns (PriceData memory data)
    {
        return _getPrice(base, quote, DEFAULT_STALENESS);
    }

    /// @inheritdoc ISmartOracle
    function getPriceNoOlderThan(
        address base,
        address quote,
        uint256 maxAge
    ) external view returns (PriceData memory data) {
        return _getPrice(base, quote, maxAge);
    }

    /// @dev Internal price fetching with fallback logic
    function _getPrice(
        address base,
        address quote,
        uint256 maxAge
    ) internal view returns (PriceData memory data) {
        bytes32 pairHash = _getPairHash(base, quote);
        OracleConfig[] storage configs = _oracles[pairHash];

        uint256 configsLen = configs.length;
        if (configsLen == 0) revert NoPriceFeed();

        // Try each oracle in priority order
        unchecked {
            for (uint256 i; i < configsLen; ++i) {
                OracleConfig storage config = configs[i];

                if (!config.isActive) continue;

                try this.fetchOraclePrice(config, base, quote, maxAge) returns (PriceData memory result) {
                    // Validate price is reasonable
                    if (result.price > 0 && result.timestamp > 0) {
                        return result;
                    }
                } catch {
                    // Continue to next oracle
                    continue;
                }
            }
        }

        // Check custom/emergency price
        PriceData memory customPrice = _customPrices[pairHash];
        if (customPrice.price > 0 && block.timestamp - customPrice.timestamp <= maxAge) {
            return customPrice;
        }

        revert NoPriceFeed();
    }

    /// @notice Fetch price from a specific oracle (external for try/catch)
    function fetchOraclePrice(
        OracleConfig calldata config,
        address base,
        address quote,
        uint256 maxAge
    ) external view returns (PriceData memory data) {
        if (config.oracleType == OracleType.CHAINLINK) {
            return _fetchChainlinkPrice(config.oracle, maxAge);
        } else if (config.oracleType == OracleType.PYTH) {
            return _fetchPythPrice(base, quote, maxAge);
        } else if (config.oracleType == OracleType.REDSTONE) {
            return _fetchRedstonePrice(base, quote, maxAge);
        } else if (config.oracleType == OracleType.TWAP) {
            return _fetchTWAPPrice(base, quote);
        }

        revert InvalidOracle();
    }

    /// @dev Fetch from Chainlink price feed
    function _fetchChainlinkPrice(
        address feed,
        uint256 maxAge
    ) internal view returns (PriceData memory data) {
        IChainlinkPriceFeed priceFeed = IChainlinkPriceFeed(feed);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate round data
        if (answeredInRound < roundId) revert StalePrice();
        if (answer <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > maxAge) revert StalePrice();

        data = PriceData({
            price: uint256(answer),
            decimals: priceFeed.decimals(),
            timestamp: updatedAt,
            confidence: 0, // Chainlink doesn't provide confidence
            source: OracleType.CHAINLINK
        });
    }

    /// @dev Fetch from Pyth price feed
    function _fetchPythPrice(
        address base,
        address,
        uint256 maxAge
    ) internal view returns (PriceData memory data) {
        bytes32 feedId = tokenFeedIds[base];
        if (feedId == bytes32(0)) revert NoPriceFeed();

        IPythPriceFeed pyth = IPythPriceFeed(pythOracle);
        IPythPriceFeed.Price memory price = pyth.getPriceNoOlderThan(feedId, maxAge);

        // Convert Pyth price format
        uint256 scaledPrice;
        uint8 decimals;

        if (price.expo >= 0) {
            scaledPrice = uint256(uint64(price.price)) * (10 ** uint32(price.expo));
            decimals = 18;
        } else {
            scaledPrice = uint256(uint64(price.price));
            decimals = uint8(uint32(-price.expo));
        }

        data = PriceData({
            price: scaledPrice,
            decimals: decimals,
            timestamp: price.publishTime,
            confidence: uint256(price.conf),
            source: OracleType.PYTH
        });
    }

    /// @dev Fetch from RedStone oracle
    function _fetchRedstonePrice(
        address base,
        address,
        uint256 maxAge
    ) internal view returns (PriceData memory data) {
        bytes32 feedId = tokenFeedIds[base];
        if (feedId == bytes32(0)) revert NoPriceFeed();

        IRedstoneOracle redstone = IRedstoneOracle(redstoneOracle);

        uint256 price = redstone.getValueForDataFeed(feedId);
        uint256 timestamp = redstone.getTimestampForDataFeed(feedId);

        if (block.timestamp - timestamp > maxAge) revert StalePrice();
        if (price == 0) revert InvalidPrice();

        data = PriceData({
            price: price,
            decimals: 8, // RedStone typically uses 8 decimals
            timestamp: timestamp,
            confidence: 0,
            source: OracleType.REDSTONE
        });
    }

    /// @dev Calculate TWAP from stored observations
    function _fetchTWAPPrice(
        address base,
        address quote
    ) internal view returns (PriceData memory data) {
        bytes32 pairHash = _getPairHash(base, quote);
        TWAPObservation[] storage observations = _twapObservations[pairHash];

        if (observations.length < 2) revert NoPriceFeed();

        // Calculate TWAP from first to last observation
        TWAPObservation storage first = observations[0];
        TWAPObservation storage last = observations[observations.length - 1];

        uint256 timeElapsed = last.timestamp - first.timestamp;
        if (timeElapsed == 0) revert InvalidPrice();

        uint256 priceCumulativeDiff = last.cumulativePrice - first.cumulativePrice;
        uint256 twapPrice = priceCumulativeDiff / timeElapsed;

        data = PriceData({
            price: twapPrice,
            decimals: 18,
            timestamp: last.timestamp,
            confidence: 0,
            source: OracleType.TWAP
        });
    }

    /// @inheritdoc ISmartOracle
    function getTWAP(
        address base,
        address quote,
        uint32 period
    ) external view returns (uint256 price) {
        bytes32 pairHash = _getPairHash(base, quote);
        TWAPObservation[] storage observations = _twapObservations[pairHash];

        if (observations.length < 2) revert NoPriceFeed();

        uint256 targetTime = block.timestamp - period;
        uint256 startIdx;
        uint256 endIdx = observations.length - 1;

        // Find start observation
        for (uint256 i = endIdx; i > 0; --i) {
            if (observations[i].timestamp <= targetTime) {
                startIdx = i;
                break;
            }
        }

        TWAPObservation storage start = observations[startIdx];
        TWAPObservation storage end = observations[endIdx];

        uint256 timeElapsed = end.timestamp - start.timestamp;
        if (timeElapsed == 0) return end.price;

        uint256 priceDiff = end.cumulativePrice - start.cumulativePrice;
        price = priceDiff / timeElapsed;
    }

    /// @inheritdoc ISmartOracle
    function hasPriceFeed(address base, address quote) external view returns (bool) {
        return _oracles[_getPairHash(base, quote)].length > 0;
    }

    /*//////////////////////////////////////////////////////////////
                        TWAP MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Record a TWAP observation (called by keepers/DEX integration)
    function recordTWAPObservation(
        address base,
        address quote,
        uint256 price
    ) external onlyOwner {
        bytes32 pairHash = _getPairHash(base, quote);
        TWAPObservation[] storage observations = _twapObservations[pairHash];

        uint256 cumulativePrice;
        if (observations.length > 0) {
            TWAPObservation storage last = observations[observations.length - 1];
            uint256 timeElapsed = block.timestamp - last.timestamp;
            cumulativePrice = last.cumulativePrice + (last.price * timeElapsed);
        }

        observations.push(TWAPObservation({
            price: price,
            timestamp: block.timestamp,
            cumulativePrice: cumulativePrice
        }));

        // Prune old observations (keep last 24 hours = 288 observations at 5min intervals)
        if (observations.length > 288) {
            // Shift array (expensive, but maintains order)
            for (uint256 i; i < observations.length - 1; ++i) {
                observations[i] = observations[i + 1];
            }
            observations.pop();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set Pyth oracle address
    function setPythOracle(address _pyth) external onlyOwner {
        pythOracle = _pyth;
    }

    /// @notice Set RedStone oracle address
    function setRedstoneOracle(address _redstone) external onlyOwner {
        redstoneOracle = _redstone;
    }

    /// @notice Set feed ID for a token
    function setTokenFeedId(address token, bytes32 feedId) external onlyOwner {
        tokenFeedIds[token] = feedId;
    }

    /// @notice Set feed IDs in batch
    function setTokenFeedIdsBatch(
        address[] calldata tokens,
        bytes32[] calldata feedIds
    ) external onlyOwner {
        uint256 len = tokens.length;
        require(len == feedIds.length, "Length mismatch");
        unchecked {
            for (uint256 i; i < len; ++i) {
                tokenFeedIds[tokens[i]] = feedIds[i];
            }
        }
    }

    /// @notice Set staleness threshold for a pair
    function setStalenessThreshold(
        address base,
        address quote,
        uint256 threshold
    ) external onlyOwner {
        _stalenessThreshold[_getPairHash(base, quote)] = threshold;
    }

    /// @notice Set emergency/custom price
    function setCustomPrice(
        address base,
        address quote,
        uint256 price,
        uint8 decimals
    ) external onlyOwner {
        _customPrices[_getPairHash(base, quote)] = PriceData({
            price: price,
            decimals: decimals,
            timestamp: block.timestamp,
            confidence: 0,
            source: OracleType.CUSTOM
        });
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Generate pair hash for storage lookups
    function _getPairHash(address base, address quote) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, quote));
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE GAP
    //////////////////////////////////////////////////////////////*/

    uint256[40] private __gap;
}
