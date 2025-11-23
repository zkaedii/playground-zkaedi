// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title CrossChainConstants
 * @notice Shared constants, errors, and utilities for cross-chain infrastructure
 * @dev Provides standardized values across all cross-chain contracts
 */
library CrossChainConstants {
    /*//////////////////////////////////////////////////////////////
                            CHAIN IDS
    //////////////////////////////////////////////////////////////*/

    // Mainnet chains
    uint256 internal constant ETHEREUM = 1;
    uint256 internal constant OPTIMISM = 10;
    uint256 internal constant BSC = 56;
    uint256 internal constant POLYGON = 137;
    uint256 internal constant FANTOM = 250;
    uint256 internal constant ARBITRUM = 42161;
    uint256 internal constant AVALANCHE = 43114;
    uint256 internal constant BASE = 8453;

    // Testnet chains
    uint256 internal constant GOERLI = 5;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant MUMBAI = 80001;

    /*//////////////////////////////////////////////////////////////
                            TIME CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant MIN_DELAY = 1 minutes;
    uint256 internal constant DEFAULT_DELAY = 1 hours;
    uint256 internal constant MAX_DELAY = 7 days;

    uint256 internal constant MIN_EXPIRY = 1 days;
    uint256 internal constant DEFAULT_EXPIRY = 30 days;
    uint256 internal constant MAX_EXPIRY = 365 days;

    uint256 internal constant DEFAULT_TIMEOUT = 24 hours;
    uint256 internal constant MAX_TIMEOUT = 7 days;

    /*//////////////////////////////////////////////////////////////
                            FEE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant BPS_DENOMINATOR = 10000;
    uint256 internal constant MAX_FEE_BPS = 1000; // 10%
    uint256 internal constant DEFAULT_FEE_BPS = 50; // 0.5%

    uint256 internal constant MAX_SLIPPAGE_BPS = 500; // 5%
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 50; // 0.5%

    /*//////////////////////////////////////////////////////////////
                            PROTOCOL IDS
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant PROTOCOL_CCIP = 0;
    uint8 internal constant PROTOCOL_LAYERZERO = 1;
    uint8 internal constant PROTOCOL_WORMHOLE = 2;
    uint8 internal constant PROTOCOL_AXELAR = 3;
    uint8 internal constant PROTOCOL_HYPERLANE = 4;

    /*//////////////////////////////////////////////////////////////
                            GAS LIMITS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant MIN_GAS_LIMIT = 100_000;
    uint256 internal constant DEFAULT_GAS_LIMIT = 200_000;
    uint256 internal constant MAX_GAS_LIMIT = 3_000_000;

    /*//////////////////////////////////////////////////////////////
                            RETRY CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant DEFAULT_MAX_RETRIES = 5;
    uint8 internal constant MAX_RETRIES_LIMIT = 10;
    uint256 internal constant MIN_RETRY_DELAY = 30 seconds;
    uint256 internal constant DEFAULT_RETRY_DELAY = 60 seconds;
    uint256 internal constant MAX_RETRY_DELAY = 1 hours;

    /*//////////////////////////////////////////////////////////////
                            ORACLE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant DEFAULT_STALENESS = 3600; // 1 hour
    uint256 internal constant MAX_STALENESS = 86400; // 24 hours
    uint256 internal constant MAX_DEVIATION_BPS = 500; // 5%
    uint8 internal constant MAX_ORACLES_PER_PAIR = 5;

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate basis points
    function bps(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
        return (amount * basisPoints) / BPS_DENOMINATOR;
    }

    /// @notice Check if value is within BPS range
    function isValidBPS(uint256 value) internal pure returns (bool) {
        return value <= BPS_DENOMINATOR;
    }

    /// @notice Convert address to bytes32
    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @notice Convert bytes32 to address
    function bytes32ToAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    /// @notice Generate unique message ID
    function generateMessageId(
        uint256 sourceChain,
        uint256 destChain,
        address sender,
        uint256 nonce
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            sourceChain,
            destChain,
            sender,
            nonce,
            block.timestamp
        ));
    }

    /// @notice Generate pair hash for token pairs
    function getPairHash(address base, address quote) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, quote));
    }
}

/**
 * @title CrossChainErrors
 * @notice Shared custom errors for cross-chain infrastructure
 */
library CrossChainErrors {
    // Authorization errors
    error Unauthorized();
    error NotOwner();
    error NotGuardian();
    error NotProcessor();
    error NotExecutor();

    // State errors
    error Paused();
    error NotPaused();
    error AlreadyInitialized();
    error NotInitialized();

    // Validation errors
    error ZeroAddress();
    error ZeroAmount();
    error InvalidAmount();
    error InvalidAddress();
    error InvalidChainId();
    error InvalidProtocol();
    error InvalidFee();
    error InvalidSlippage();
    error InvalidTimeout();

    // Operation errors
    error TransferFailed();
    error ExecutionFailed();
    error RetryFailed();
    error BridgeFailed();

    // Limit errors
    error ExceedsMaxFee();
    error ExceedsMaxSlippage();
    error ExceedsMaxRetries();
    error ExceedsMaxDelay();
    error BelowMinAmount();

    // State machine errors
    error InvalidState();
    error AlreadyProcessed();
    error NotClaimable();
    error Expired();
    error NotExpired();

    // Oracle errors
    error StalePrice();
    error InvalidPrice();
    error NoPriceFeed();
    error PriceDeviationTooHigh();

    // Circuit breaker errors
    error CircuitBreakerActive();
    error CooldownActive();
}

/**
 * @title CrossChainEvents
 * @notice Shared events for cross-chain infrastructure
 */
library CrossChainEvents {
    event MessageSent(
        bytes32 indexed messageId,
        uint256 indexed destChain,
        address sender,
        uint8 protocol
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint256 indexed sourceChain,
        address recipient,
        uint8 protocol
    );

    event MessageProcessed(
        bytes32 indexed messageId,
        bool success,
        bytes result
    );

    event MessageFailed(
        bytes32 indexed messageId,
        bytes reason
    );

    event RefundCreated(
        bytes32 indexed refundId,
        address indexed recipient,
        uint256 amount
    );

    event RefundClaimed(
        bytes32 indexed refundId,
        address indexed recipient,
        uint256 amount
    );

    event ProtocolConfigured(
        uint8 indexed protocol,
        address endpoint,
        bool isActive
    );

    event EmergencyAction(
        bytes32 indexed actionId,
        address executor,
        string action
    );
}
