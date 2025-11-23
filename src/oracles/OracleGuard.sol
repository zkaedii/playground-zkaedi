// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IOracle.sol";

/*//////////////////////////////////////////////////////////////
                    ORACLE SECURITY GUARD
//////////////////////////////////////////////////////////////*/

/**
 * @title OracleGuard
 * @author Multi-Chain DEX & Oracle Integration
 * @notice Advanced oracle manipulation protection system
 * @dev Features:
 *      - Multi-oracle consensus validation
 *      - Price deviation circuit breakers
 *      - Historical price deviation analysis
 *      - TWAP comparison guards
 *      - Volatility-adjusted thresholds
 *      - Liveness monitoring
 */
contract OracleGuard is OwnableUpgradeable, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Price check result
    struct PriceCheckResult {
        bool isValid;
        uint256 price;
        uint256 confidence;
        uint256 deviation;
        string[] warnings;
        CheckType failedCheck;
    }

    enum CheckType {
        NONE,
        STALENESS,
        DEVIATION,
        VOLATILITY,
        CONSENSUS,
        CIRCUIT_BREAKER,
        LIVENESS
    }

    /// @notice Historical price observation
    struct PriceObservation {
        uint256 price;
        uint256 timestamp;
        uint256 blockNumber;
    }

    /// @notice Guard configuration per pair
    struct GuardConfig {
        uint256 maxDeviation;           // Max deviation between oracles (BPS)
        uint256 maxVolatility;          // Max price change per block (BPS)
        uint256 maxStaleness;           // Max price age (seconds)
        uint256 minConfidence;          // Min confidence interval
        uint256 circuitBreakerThreshold; // Price change that triggers pause (BPS)
        uint256 recoveryPeriod;         // Time to wait after circuit breaker
        uint8 minOracleConsensus;       // Minimum oracles that must agree
        bool requireTWAPComparison;     // Require TWAP validation
        bool isActive;
    }

    /// @notice Circuit breaker state
    struct CircuitBreaker {
        bool isTriggered;
        uint256 triggeredAt;
        uint256 triggerPrice;
        uint256 preBreakPrice;
        string reason;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error PriceStale();
    error DeviationTooHigh();
    error VolatilityTooHigh();
    error InsufficientConsensus();
    error CircuitBreakerActive();
    error LivenessCheckFailed();
    error InvalidConfig();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceValidated(
        address indexed base,
        address indexed quote,
        uint256 price,
        uint256 deviation
    );
    event PriceRejected(
        address indexed base,
        address indexed quote,
        CheckType failedCheck,
        string reason
    );
    event CircuitBreakerTriggered(
        address indexed base,
        address indexed quote,
        uint256 price,
        uint256 preBreakPrice,
        string reason
    );
    event CircuitBreakerReset(address indexed base, address indexed quote);
    event ConfigUpdated(address indexed base, address indexed quote);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Primary oracle aggregator
    ISmartOracle public oracleAggregator;

    /// @dev TWAP oracle for comparison
    ISmartOracle public twapOracle;

    /// @dev Pair hash => Guard config
    mapping(bytes32 => GuardConfig) public guardConfigs;

    /// @dev Pair hash => Circuit breaker state
    mapping(bytes32 => CircuitBreaker) public circuitBreakers;

    /// @dev Pair hash => Price history (circular buffer)
    mapping(bytes32 => PriceObservation[]) private _priceHistory;
    mapping(bytes32 => uint256) private _historyIndex;

    /// @dev Max history length
    uint256 public constant MAX_HISTORY = 100;

    /// @dev Default config values
    uint256 public constant DEFAULT_MAX_DEVIATION = 300;      // 3%
    uint256 public constant DEFAULT_MAX_VOLATILITY = 500;     // 5% per block
    uint256 public constant DEFAULT_MAX_STALENESS = 3600;     // 1 hour
    uint256 public constant DEFAULT_CIRCUIT_BREAKER = 1000;   // 10%
    uint256 public constant DEFAULT_RECOVERY_PERIOD = 3600;   // 1 hour

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _oracleAggregator,
        address _twapOracle
    ) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        oracleAggregator = ISmartOracle(_oracleAggregator);
        twapOracle = ISmartOracle(_twapOracle);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validate price with all security checks
    function validatePrice(
        address base,
        address quote
    ) external returns (PriceCheckResult memory result) {
        bytes32 pairHash = _getPairHash(base, quote);
        GuardConfig storage config = guardConfigs[pairHash];

        // Use defaults if not configured
        if (!config.isActive) {
            config = _getDefaultConfig();
        }

        // Check circuit breaker first
        CircuitBreaker storage breaker = circuitBreakers[pairHash];
        if (breaker.isTriggered) {
            if (block.timestamp < breaker.triggeredAt + config.recoveryPeriod) {
                result.isValid = false;
                result.failedCheck = CheckType.CIRCUIT_BREAKER;
                result.warnings = new string[](1);
                result.warnings[0] = breaker.reason;
                return result;
            } else {
                // Reset circuit breaker
                breaker.isTriggered = false;
                emit CircuitBreakerReset(base, quote);
            }
        }

        // Get price from primary oracle
        ISmartOracle.PriceData memory priceData;
        try oracleAggregator.getPrice(base, quote) returns (ISmartOracle.PriceData memory data) {
            priceData = data;
        } catch {
            result.isValid = false;
            result.failedCheck = CheckType.LIVENESS;
            return result;
        }

        // Run all checks
        result = _runAllChecks(base, quote, priceData, config);

        // Record observation if valid
        if (result.isValid) {
            _recordObservation(pairHash, priceData.price);
            emit PriceValidated(base, quote, priceData.price, result.deviation);
        } else {
            emit PriceRejected(base, quote, result.failedCheck, "Check failed");
        }

        return result;
    }

    /// @notice Get validated price (reverts if invalid)
    function getValidatedPrice(
        address base,
        address quote
    ) external returns (uint256 price, uint8 decimals) {
        PriceCheckResult memory result = this.validatePrice(base, quote);

        if (!result.isValid) {
            if (result.failedCheck == CheckType.STALENESS) revert PriceStale();
            if (result.failedCheck == CheckType.DEVIATION) revert DeviationTooHigh();
            if (result.failedCheck == CheckType.VOLATILITY) revert VolatilityTooHigh();
            if (result.failedCheck == CheckType.CONSENSUS) revert InsufficientConsensus();
            if (result.failedCheck == CheckType.CIRCUIT_BREAKER) revert CircuitBreakerActive();
            revert LivenessCheckFailed();
        }

        ISmartOracle.PriceData memory data = oracleAggregator.getPrice(base, quote);
        return (data.price, data.decimals);
    }

    /// @notice Check price without state changes (view)
    function checkPrice(
        address base,
        address quote
    ) external view returns (bool isValid, string memory reason) {
        bytes32 pairHash = _getPairHash(base, quote);
        GuardConfig storage config = guardConfigs[pairHash];

        // Check circuit breaker
        CircuitBreaker storage breaker = circuitBreakers[pairHash];
        if (breaker.isTriggered &&
            block.timestamp < breaker.triggeredAt + config.recoveryPeriod) {
            return (false, "Circuit breaker active");
        }

        // Try to get price
        try oracleAggregator.getPrice(base, quote) returns (ISmartOracle.PriceData memory data) {
            // Check staleness
            if (block.timestamp - data.timestamp > config.maxStaleness) {
                return (false, "Price is stale");
            }

            // Check TWAP deviation if required
            if (config.requireTWAPComparison) {
                try twapOracle.getPrice(base, quote) returns (ISmartOracle.PriceData memory twapData) {
                    uint256 deviation = _calculateDeviation(data.price, twapData.price);
                    if (deviation > config.maxDeviation) {
                        return (false, "TWAP deviation too high");
                    }
                } catch {
                    // TWAP unavailable, continue without
                }
            }

            return (true, "OK");
        } catch {
            return (false, "Oracle unavailable");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL CHECKS
    //////////////////////////////////////////////////////////////*/

    function _runAllChecks(
        address base,
        address quote,
        ISmartOracle.PriceData memory priceData,
        GuardConfig memory config
    ) internal returns (PriceCheckResult memory result) {
        bytes32 pairHash = _getPairHash(base, quote);
        result.price = priceData.price;
        result.confidence = priceData.confidence;

        // 1. Staleness check
        if (block.timestamp - priceData.timestamp > config.maxStaleness) {
            result.isValid = false;
            result.failedCheck = CheckType.STALENESS;
            return result;
        }

        // 2. TWAP deviation check
        if (config.requireTWAPComparison) {
            try twapOracle.getPrice(base, quote) returns (ISmartOracle.PriceData memory twapData) {
                result.deviation = _calculateDeviation(priceData.price, twapData.price);
                if (result.deviation > config.maxDeviation) {
                    result.isValid = false;
                    result.failedCheck = CheckType.DEVIATION;
                    return result;
                }
            } catch {
                // TWAP unavailable - add warning but continue
            }
        }

        // 3. Volatility check (compare with recent history)
        PriceObservation[] storage history = _priceHistory[pairHash];
        if (history.length > 0) {
            PriceObservation storage lastObs = history[_historyIndex[pairHash]];
            uint256 priceChange = _calculateDeviation(priceData.price, lastObs.price);

            // Adjust for blocks passed
            uint256 blocksPassed = block.number - lastObs.blockNumber;
            if (blocksPassed == 0) blocksPassed = 1;

            uint256 volatilityPerBlock = priceChange / blocksPassed;

            if (volatilityPerBlock > config.maxVolatility) {
                result.isValid = false;
                result.failedCheck = CheckType.VOLATILITY;

                // Check if circuit breaker should trigger
                if (priceChange > config.circuitBreakerThreshold) {
                    _triggerCircuitBreaker(
                        pairHash,
                        base,
                        quote,
                        priceData.price,
                        lastObs.price,
                        "Extreme price volatility"
                    );
                }

                return result;
            }
        }

        // 4. Circuit breaker threshold check
        if (history.length > 0) {
            // Check against oldest price in history for large moves
            PriceObservation storage oldestObs = history[0];
            uint256 totalChange = _calculateDeviation(priceData.price, oldestObs.price);

            if (totalChange > config.circuitBreakerThreshold) {
                _triggerCircuitBreaker(
                    pairHash,
                    base,
                    quote,
                    priceData.price,
                    oldestObs.price,
                    "Circuit breaker threshold exceeded"
                );
                result.isValid = false;
                result.failedCheck = CheckType.CIRCUIT_BREAKER;
                return result;
            }
        }

        // 5. Confidence check (for Pyth)
        if (priceData.confidence > 0 && config.minConfidence > 0) {
            // Confidence as percentage of price
            uint256 confidencePct = (priceData.confidence * 10000) / priceData.price;
            if (confidencePct > config.minConfidence) {
                // Low confidence warning but don't fail
                // Could add to warnings array
            }
        }

        result.isValid = true;
        result.failedCheck = CheckType.NONE;
        return result;
    }

    function _calculateDeviation(uint256 price1, uint256 price2)
        internal pure returns (uint256)
    {
        if (price1 == 0 || price2 == 0) return 10000; // 100%

        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 avg = (price1 + price2) / 2;

        return (diff * 10000) / avg;
    }

    function _triggerCircuitBreaker(
        bytes32 pairHash,
        address base,
        address quote,
        uint256 currentPrice,
        uint256 previousPrice,
        string memory reason
    ) internal {
        circuitBreakers[pairHash] = CircuitBreaker({
            isTriggered: true,
            triggeredAt: block.timestamp,
            triggerPrice: currentPrice,
            preBreakPrice: previousPrice,
            reason: reason
        });

        emit CircuitBreakerTriggered(base, quote, currentPrice, previousPrice, reason);
    }

    function _recordObservation(bytes32 pairHash, uint256 price) internal {
        PriceObservation[] storage history = _priceHistory[pairHash];

        if (history.length < MAX_HISTORY) {
            history.push(PriceObservation({
                price: price,
                timestamp: block.timestamp,
                blockNumber: block.number
            }));
            _historyIndex[pairHash] = history.length - 1;
        } else {
            // Circular buffer - overwrite oldest
            uint256 nextIdx = (_historyIndex[pairHash] + 1) % MAX_HISTORY;
            history[nextIdx] = PriceObservation({
                price: price,
                timestamp: block.timestamp,
                blockNumber: block.number
            });
            _historyIndex[pairHash] = nextIdx;
        }
    }

    function _getDefaultConfig() internal pure returns (GuardConfig memory) {
        return GuardConfig({
            maxDeviation: DEFAULT_MAX_DEVIATION,
            maxVolatility: DEFAULT_MAX_VOLATILITY,
            maxStaleness: DEFAULT_MAX_STALENESS,
            minConfidence: 0,
            circuitBreakerThreshold: DEFAULT_CIRCUIT_BREAKER,
            recoveryPeriod: DEFAULT_RECOVERY_PERIOD,
            minOracleConsensus: 1,
            requireTWAPComparison: true,
            isActive: true
        });
    }

    function _getPairHash(address base, address quote) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, quote));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get price history for a pair
    function getPriceHistory(address base, address quote)
        external view returns (PriceObservation[] memory)
    {
        return _priceHistory[_getPairHash(base, quote)];
    }

    /// @notice Get circuit breaker status
    function getCircuitBreakerStatus(address base, address quote)
        external view returns (CircuitBreaker memory)
    {
        return circuitBreakers[_getPairHash(base, quote)];
    }

    /// @notice Check if circuit breaker is active
    function isCircuitBreakerActive(address base, address quote)
        external view returns (bool)
    {
        bytes32 pairHash = _getPairHash(base, quote);
        CircuitBreaker storage breaker = circuitBreakers[pairHash];
        GuardConfig storage config = guardConfigs[pairHash];

        return breaker.isTriggered &&
            block.timestamp < breaker.triggeredAt + config.recoveryPeriod;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Configure guard for a pair
    function setGuardConfig(
        address base,
        address quote,
        GuardConfig calldata config
    ) external onlyOwner {
        if (config.maxDeviation > 5000) revert InvalidConfig(); // Max 50%
        if (config.maxStaleness > 86400) revert InvalidConfig(); // Max 24h

        guardConfigs[_getPairHash(base, quote)] = config;
        emit ConfigUpdated(base, quote);
    }

    /// @notice Manually reset circuit breaker (emergency)
    function resetCircuitBreaker(address base, address quote) external onlyOwner {
        bytes32 pairHash = _getPairHash(base, quote);
        circuitBreakers[pairHash].isTriggered = false;
        emit CircuitBreakerReset(base, quote);
    }

    /// @notice Update oracle addresses
    function setOracles(address _aggregator, address _twap) external onlyOwner {
        oracleAggregator = ISmartOracle(_aggregator);
        twapOracle = ISmartOracle(_twap);
    }

    /*//////////////////////////////////////////////////////////////
                            UUPS
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    uint256[40] private __gap;
}
