// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/oracles/SmartOracleAggregator.sol";
import "../src/oracles/OracleGuard.sol";
import "../src/dex/CrossChainDEXRouter.sol";
import "../src/dex/adapters/DEXAdapters.sol";
import "../src/intents/IntentSettlement.sol";
import "../src/crosschain/receivers/CrossChainReceiverHub.sol";
import "../src/crosschain/recovery/RefundManager.sol";
import "../src/crosschain/handlers/MessageCatcher.sol";
import "../src/crosschain/broadcast/RadioBroadcaster.sol";
import "../src/crosschain/callbacks/ResponseHandler.sol";
import "../src/crosschain/emergency/EmergencyManager.sol";
import "../src/crosschain/fees/FeeManager.sol";
import "../src/crosschain/retry/RetryManager.sol";

/*//////////////////////////////////////////////////////////////
                    INTEGRATION TEST MOCKS
//////////////////////////////////////////////////////////////*/

contract MockToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockPriceFeed {
    int256 public price;
    uint8 public feedDecimals;
    uint256 public updatedAt;
    uint80 public roundId = 1;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        feedDecimals = _decimals;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
        roundId++;
    }

    function decimals() external view returns (uint8) {
        return feedDecimals;
    }

    function latestRoundData() external view returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (roundId, price, updatedAt, updatedAt, roundId);
    }

    function getRoundData(uint80) external view returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (roundId, price, updatedAt, updatedAt, roundId);
    }

    function description() external pure returns (string memory) {
        return "Mock Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

contract MockRetryHandler {
    bool public shouldSucceed = true;
    uint256 public callCount;

    function setShouldSucceed(bool _succeed) external {
        shouldSucceed = _succeed;
    }

    function retryMessage(
        bytes32,
        bytes calldata,
        address[] calldata,
        uint256[] calldata
    ) external payable returns (bool) {
        callCount++;
        return shouldSucceed;
    }
}

contract MockCallbackReceiver {
    bytes32 public lastRequestId;
    bytes public lastData;
    bool public wasSuccessful;
    uint256 public callCount;

    function onResponse(bytes32 requestId, bytes calldata data) external returns (bool) {
        lastRequestId = requestId;
        lastData = data;
        wasSuccessful = true;
        callCount++;
        return true;
    }

    function onCrossChainResponse(
        bytes32 requestId,
        bool success,
        bytes calldata data
    ) external {
        lastRequestId = requestId;
        lastData = data;
        wasSuccessful = success;
        callCount++;
    }
}

/*//////////////////////////////////////////////////////////////
                FULL SYSTEM INTEGRATION TESTS
//////////////////////////////////////////////////////////////*/

contract FullSystemIntegrationTest is Test {
    // Core contracts
    SmartOracleAggregator public oracle;
    OracleGuard public oracleGuard;
    FeeManager public feeManager;
    RefundManager public refundManager;
    RetryManager public retryManager;
    EmergencyManager public emergencyManager;
    ResponseHandler public responseHandler;

    // Mock contracts
    MockToken public weth;
    MockToken public usdc;
    MockPriceFeed public ethFeed;
    MockRetryHandler public retryHandler;
    MockCallbackReceiver public callbackReceiver;

    // Test accounts
    address public admin = address(this);
    address public user = address(0x1000);
    address public solver = address(0x2000);
    address public guardian = address(0x3000);
    address public treasury = address(0x4000);

    function setUp() public {
        // Deploy tokens
        weth = new MockToken("Wrapped ETH", "WETH");
        usdc = new MockToken("USD Coin", "USDC");

        // Deploy price feed
        ethFeed = new MockPriceFeed(2000e8, 8);

        // Deploy core contracts
        oracle = new SmartOracleAggregator();
        oracle.initialize(address(0), address(0));

        oracleGuard = new OracleGuard();
        oracleGuard.initialize(address(oracle), address(oracle));

        feeManager = new FeeManager();
        feeManager.initialize(treasury, address(0));

        refundManager = new RefundManager();
        refundManager.initialize(treasury);

        retryHandler = new MockRetryHandler();
        retryManager = new RetryManager();
        retryManager.initialize(address(retryHandler));

        emergencyManager = new EmergencyManager();
        emergencyManager.initialize();

        responseHandler = new ResponseHandler();
        responseHandler.initialize();

        callbackReceiver = new MockCallbackReceiver();

        // Setup oracle
        IOracleRegistry.OracleConfig memory oracleConfig = IOracleRegistry.OracleConfig({
            oracle: address(ethFeed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });
        oracle.registerOracle(address(weth), address(usdc), oracleConfig);

        // Setup fee manager
        FeeManager.ChainGasConfig memory gasConfig = FeeManager.ChainGasConfig({
            gasPrice: 50 gwei,
            gasPriceUpdatedAt: block.timestamp,
            l1DataFee: 0,
            priorityFee: 2 gwei,
            baseFeeMultiplier: 12000
        });
        feeManager.setChainGasConfig(42161, gasConfig);

        // Setup permissions
        refundManager.setProcessor(address(this), true);
        retryManager.setExecutor(address(this), true);
        emergencyManager.addGuardian(guardian);
        responseHandler.setAuthorizedResponder(address(this), true);

        // Fund accounts
        vm.deal(user, 100 ether);
        weth.mint(user, 100e18);
        usdc.mint(address(refundManager), 100000e6);
    }

    /*//////////////////////////////////////////////////////////////
                    ORACLE + GUARD INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_Integration_OracleWithGuard() public {
        // Validate price through guard
        OracleGuard.PriceCheckResult memory result = oracleGuard.validatePrice(
            address(weth),
            address(usdc)
        );

        assertTrue(result.isValid);
        assertEq(result.price, 2000e8);

        // Record history through validation
        vm.roll(block.number + 1);
        ethFeed.setPrice(2010e8);
        oracleGuard.validatePrice(address(weth), address(usdc));

        vm.roll(block.number + 1);
        ethFeed.setPrice(2020e8);
        oracleGuard.validatePrice(address(weth), address(usdc));

        // Check history
        OracleGuard.PriceObservation[] memory history = oracleGuard.getPriceHistory(
            address(weth),
            address(usdc)
        );
        assertEq(history.length, 3);
    }

    function test_Integration_OracleCircuitBreaker() public {
        // Configure low threshold
        OracleGuard.GuardConfig memory config = OracleGuard.GuardConfig({
            maxDeviation: 300,
            maxVolatility: 50,
            maxStaleness: 3600,
            minConfidence: 0,
            circuitBreakerThreshold: 500,
            recoveryPeriod: 1 hours,
            minOracleConsensus: 1,
            requireTWAPComparison: false,
            isActive: true
        });
        oracleGuard.setGuardConfig(address(weth), address(usdc), config);

        // Initial price
        oracleGuard.validatePrice(address(weth), address(usdc));

        // Large price spike
        ethFeed.setPrice(3000e8); // 50% increase

        OracleGuard.PriceCheckResult memory result = oracleGuard.validatePrice(
            address(weth),
            address(usdc)
        );

        // Circuit breaker should be active
        assertTrue(oracleGuard.isCircuitBreakerActive(address(weth), address(usdc)));
    }

    /*//////////////////////////////////////////////////////////////
                    FEE + REFUND INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_Integration_FeeCollectionAndRefund() public {
        bytes32 txId = keccak256("cross-chain-tx-1");

        // Get fee quote
        FeeManager.FeeQuote memory quote = feeManager.getFeeQuote(
            42161,
            200000,
            1 ether,
            0
        );

        // Collect fees with excess
        uint256 excessAmount = 0.05 ether;
        vm.deal(address(this), quote.totalFee + excessAmount);

        feeManager.collectFees{value: quote.totalFee + excessAmount}(
            txId,
            address(this),
            1 ether,
            42161,
            200000,
            0
        );

        // Check pending refund
        assertEq(feeManager.pendingRefunds(txId), excessAmount);

        // Refund excess
        uint256 balanceBefore = address(this).balance;
        feeManager.refundExcess(txId, address(this));
        assertEq(address(this).balance, balanceBefore + excessAmount);
    }

    function test_Integration_RefundWithDispute() public {
        bytes32 txId = keccak256("failed-tx");

        // Configure no delay for testing
        RefundManager.RefundConfig memory config = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 100,
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(usdc), config);

        // Create refund
        bytes32 refundId = refundManager.createRefund(
            txId,
            user,
            address(usdc),
            1000e6,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            bytes32(0)
        );

        // User disputes
        vm.prank(user);
        refundManager.disputeRefund(refundId, "Amount should be higher");

        // Verify disputed status
        RefundManager.RefundRequest memory refund = refundManager.getRefund(refundId);
        assertEq(uint8(refund.status), uint8(RefundManager.RefundStatus.DISPUTED));

        // Resolve dispute
        refundManager.setResolver(address(this), true);
        refundManager.resolveDispute(refundId, true, 1100e6); // Higher amount

        // Claim after resolution
        uint256 balanceBefore = usdc.balanceOf(user);
        vm.prank(user);
        refundManager.claimRefund(refundId);

        assertEq(usdc.balanceOf(user), balanceBefore + 1100e6);
    }

    /*//////////////////////////////////////////////////////////////
                    RETRY + CALLBACK INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_Integration_RetryWithCallback() public {
        bytes32 messageId = keccak256("cross-chain-msg");
        bytes32 txId = keccak256("original-tx");

        // Register callback for when message succeeds
        responseHandler.registerCallback(
            messageId,
            address(callbackReceiver),
            bytes4(keccak256("onCrossChainResponse(bytes32,bool,bytes)")),
            1 hours,
            ""
        );

        // Queue for retry
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        retryManager.queueForRetry(
            messageId,
            txId,
            user,
            1,
            42161,
            abi.encode("swap", address(weth), address(usdc)),
            abi.encode("INSUFFICIENT_OUTPUT"),
            tokens,
            amounts
        );

        // Verify queued
        assertEq(retryManager.getQueueLength(), 1);

        // Fast forward past delay
        vm.warp(block.timestamp + 2 minutes);

        // Execute retry
        retryHandler.setShouldSucceed(true);
        bool success = retryManager.executeRetry(messageId);

        assertTrue(success);

        // Trigger callback
        responseHandler.handleSuccessResponse(
            messageId,
            abi.encode("swap completed"),
            42161
        );

        // Verify callback received
        assertTrue(responseHandler.hasResponse(messageId));
    }

    function test_Integration_RetryExponentialBackoff() public {
        bytes32 messageId = keccak256("retry-msg");
        bytes32 txId = keccak256("tx");

        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        retryManager.queueForRetry(
            messageId,
            txId,
            user,
            1,
            42161,
            abi.encode("payload"),
            abi.encode("error"),
            tokens,
            amounts
        );

        // Make retries fail
        retryHandler.setShouldSucceed(false);

        // First retry after initial delay (60s)
        vm.warp(block.timestamp + 61);
        retryManager.executeRetry(messageId);

        // Check next retry is scheduled with backoff (120s)
        (,,,,,,,,,uint256 nextRetryAt,,,,,) = retryManager.failedMessages(messageId);
        assertTrue(nextRetryAt > block.timestamp + 100); // At least 2x initial delay
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY + SYSTEM INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_Integration_EmergencyShutdown() public {
        // Trigger emergency level
        vm.prank(guardian);
        emergencyManager.setEmergencyLevel(EmergencyManager.EmergencyLevel.HIGH);

        assertTrue(emergencyManager.paused());

        // Trigger circuit breaker
        vm.prank(guardian);
        emergencyManager.triggerCircuitBreaker(
            EmergencyManager.CircuitBreakerType.GLOBAL,
            bytes32(0),
            "System compromise detected",
            24 hours
        );

        assertTrue(emergencyManager.isCircuitBreakerActive(
            EmergencyManager.CircuitBreakerType.GLOBAL,
            bytes32(0)
        ));
    }

    function test_Integration_EmergencyRecovery() public {
        // Send tokens to emergency manager for recovery
        weth.mint(address(emergencyManager), 10e18);

        // Set medium emergency level
        vm.prank(guardian);
        emergencyManager.setEmergencyLevel(EmergencyManager.EmergencyLevel.MEDIUM);

        // Recover tokens
        uint256 balanceBefore = weth.balanceOf(treasury);

        vm.prank(guardian);
        emergencyManager.recoverTokens(address(weth), treasury, 10e18);

        assertEq(weth.balanceOf(treasury), balanceBefore + 10e18);
    }

    /*//////////////////////////////////////////////////////////////
                    END-TO-END FLOW TEST
    //////////////////////////////////////////////////////////////*/

    function test_Integration_FullCrossChainFlow() public {
        bytes32 txId = keccak256("e2e-tx");
        bytes32 messageId = keccak256(abi.encodePacked(txId, block.timestamp));

        // 1. Get price from oracle
        ISmartOracle.PriceData memory priceData = oracle.getPrice(
            address(weth),
            address(usdc)
        );
        assertEq(priceData.price, 2000e8);

        // 2. Validate through guard
        OracleGuard.PriceCheckResult memory validation = oracleGuard.validatePrice(
            address(weth),
            address(usdc)
        );
        assertTrue(validation.isValid);

        // 3. Get and collect fees
        FeeManager.FeeQuote memory quote = feeManager.getFeeQuote(
            42161, 200000, 1 ether, 0
        );

        vm.deal(address(this), quote.totalFee);
        feeManager.collectFees{value: quote.totalFee}(
            txId, address(this), 1 ether, 42161, 200000, 0
        );

        // 4. Register callback for cross-chain response
        responseHandler.registerCallback(
            messageId,
            address(callbackReceiver),
            bytes4(keccak256("onCrossChainResponse(bytes32,bool,bytes)")),
            1 hours,
            ""
        );

        // 5. Simulate message failure and queue for retry
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        weth.mint(address(retryManager), 1e18);

        retryManager.queueForRetry(
            messageId, txId, user, 1, 42161,
            abi.encode("swap", 1e18),
            abi.encode("TIMEOUT"),
            tokens, amounts
        );

        // 6. Fast forward and retry
        vm.warp(block.timestamp + 2 minutes);
        retryHandler.setShouldSucceed(true);

        bool success = retryManager.executeRetry(messageId);
        assertTrue(success);

        // 7. Handle success response
        responseHandler.handleSuccessResponse(
            messageId,
            abi.encode("swap completed", 1900e6),
            42161
        );

        // Verify full flow completed
        assertTrue(responseHandler.hasResponse(messageId));

        RetryManager.RetryMetrics memory metrics = retryManager.getMetrics();
        assertEq(metrics.successfulRetries, 1);
    }

    function test_Integration_FailureWithRefund() public {
        bytes32 txId = keccak256("failed-swap");
        bytes32 messageId = keccak256(abi.encodePacked(txId, "msg"));

        // Setup
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000e6;

        // Queue retry
        retryManager.queueForRetry(
            messageId, txId, user, 1, 42161,
            abi.encode("swap failed"),
            abi.encode("SLIPPAGE_TOO_HIGH"),
            tokens, amounts
        );

        // Make all retries fail
        retryHandler.setShouldSucceed(false);

        // Exhaust retries (5 by default)
        for (uint i = 0; i < 6; i++) {
            vm.warp(block.timestamp + 2 hours);
            try retryManager.executeRetry(messageId) {} catch {}
        }

        // Message should be dead-lettered
        RetryManager.RetryMetrics memory metrics = retryManager.getMetrics();
        assertEq(metrics.deadLettered, 1);

        // Create refund for user
        RefundManager.RefundConfig memory config = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 0,
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(usdc), config);

        bytes32 refundId = refundManager.createRefund(
            txId, user, address(usdc), 1000e6,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            messageId
        );

        // User claims refund
        uint256 balanceBefore = usdc.balanceOf(user);
        vm.prank(user);
        refundManager.claimRefund(refundId);

        assertEq(usdc.balanceOf(user), balanceBefore + 1000e6);
    }

    receive() external payable {}
}

/*//////////////////////////////////////////////////////////////
                STRESS & EDGE CASE TESTS
//////////////////////////////////////////////////////////////*/

contract StressAndEdgeCaseTest is Test {
    SmartOracleAggregator public oracle;
    OracleGuard public oracleGuard;
    RetryManager public retryManager;
    RefundManager public refundManager;
    MockRetryHandler public retryHandler;
    MockToken public token;
    MockPriceFeed public feed;

    address public executor = address(0x100);
    address public processor = address(0x200);
    address public treasury = address(0x300);

    function setUp() public {
        oracle = new SmartOracleAggregator();
        oracle.initialize(address(0), address(0));

        oracleGuard = new OracleGuard();
        oracleGuard.initialize(address(oracle), address(oracle));

        retryHandler = new MockRetryHandler();
        retryManager = new RetryManager();
        retryManager.initialize(address(retryHandler));
        retryManager.setExecutor(executor, true);

        refundManager = new RefundManager();
        refundManager.initialize(treasury);
        refundManager.setProcessor(processor, true);

        token = new MockToken("Test", "TEST");
        token.mint(address(refundManager), 1000000e18);

        feed = new MockPriceFeed(2000e8, 8);
    }

    function test_Stress_HighVolumeRetries() public {
        // Queue 100 messages
        for (uint i = 0; i < 100; i++) {
            bytes32 messageId = keccak256(abi.encodePacked("msg", i));
            bytes32 txId = keccak256(abi.encodePacked("tx", i));

            address[] memory tokens = new address[](0);
            uint256[] memory amounts = new uint256[](0);

            vm.prank(executor);
            retryManager.queueForRetry(
                messageId, txId, address(uint160(i + 1000)),
                1, 42161, abi.encode(i), abi.encode("error"),
                tokens, amounts
            );
        }

        assertEq(retryManager.getQueueLength(), 100);

        // Fast forward
        vm.warp(block.timestamp + 2 minutes);

        // Execute batch
        retryHandler.setShouldSucceed(true);
        vm.prank(executor);
        retryManager.executeRetries(50);

        RetryManager.RetryMetrics memory metrics = retryManager.getMetrics();
        assertEq(metrics.successfulRetries, 50);
    }

    function test_Stress_HighVolumeRefunds() public {
        RefundManager.RefundConfig memory config = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 0,
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(token), config);

        bytes32[] memory refundIds = new bytes32[](50);

        // Create 50 refunds
        for (uint i = 0; i < 50; i++) {
            bytes32 txId = keccak256(abi.encodePacked("tx", i));
            address recipient = address(uint160(i + 1000));

            vm.prank(processor);
            refundIds[i] = refundManager.createRefund(
                txId, recipient, address(token), 100e18,
                RefundManager.RefundReason.TRANSACTION_FAILED,
                bytes32(0)
            );
        }

        // Claim all
        for (uint i = 0; i < 50; i++) {
            address recipient = address(uint160(i + 1000));
            vm.prank(recipient);
            refundManager.claimRefund(refundIds[i]);

            assertEq(token.balanceOf(recipient), 100e18);
        }
    }

    function test_Edge_OraclePriceAtBoundary() public {
        // Register oracle
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(feed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });
        oracle.registerOracle(address(0x1), address(0x2), config);

        // Set price to max int256
        feed.setPrice(type(int256).max / 2);

        ISmartOracle.PriceData memory data = oracle.getPrice(address(0x1), address(0x2));
        assertEq(data.price, type(int256).max / 2);

        // Set price to 1 wei
        feed.setPrice(1);
        data = oracle.getPrice(address(0x1), address(0x2));
        assertEq(data.price, 1);
    }

    function test_Edge_RetryWithMaxValues() public {
        bytes32 messageId = keccak256("max-msg");
        bytes32 txId = keccak256("max-tx");

        address[] memory tokens = new address[](10);
        uint256[] memory amounts = new uint256[](10);

        for (uint i = 0; i < 10; i++) {
            tokens[i] = address(uint160(i + 1));
            amounts[i] = type(uint128).max;
        }

        vm.prank(executor);
        retryManager.queueForRetry(
            messageId, txId, address(0x1000),
            type(uint256).max, type(uint256).max,
            new bytes(1000), // Large payload
            new bytes(500),
            tokens, amounts
        );

        (bytes32 storedMsgId,,,,,,,,,,,,,address[] memory storedTokens,) =
            retryManager.failedMessages(messageId);

        assertEq(storedMsgId, messageId);
        assertEq(storedTokens.length, 10);
    }

    function test_Edge_RapidPriceUpdates() public {
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(feed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });
        oracle.registerOracle(address(0x1), address(0x2), config);

        // Rapid updates
        for (uint i = 0; i < 20; i++) {
            feed.setPrice(int256(2000e8 + i * 10e8));
            vm.roll(block.number + 1);
            oracleGuard.validatePrice(address(0x1), address(0x2));
        }

        OracleGuard.PriceObservation[] memory history = oracleGuard.getPriceHistory(
            address(0x1), address(0x2)
        );

        // Should have accumulated history
        assertTrue(history.length > 0);
    }

    function testFuzz_RefundAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100000e18);

        RefundManager.RefundConfig memory config = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 100, // 1%
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(token), config);

        bytes32 txId = keccak256(abi.encodePacked("fuzz", amount));
        address recipient = address(0x5000);

        vm.prank(processor);
        bytes32 refundId = refundManager.createRefund(
            txId, recipient, address(token), amount,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            bytes32(0)
        );

        RefundManager.RefundRequest memory refund = refundManager.getRefund(refundId);

        // Fee should be 1%
        uint256 expectedFee = (amount * 100) / 10000;
        assertEq(refund.amount, amount - expectedFee);
    }

    function testFuzz_OraclePrices(int256 price) public {
        vm.assume(price > 0 && price < type(int128).max);

        feed.setPrice(price);

        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(feed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });
        oracle.registerOracle(address(0x1), address(0x2), config);

        ISmartOracle.PriceData memory data = oracle.getPrice(address(0x1), address(0x2));
        assertEq(data.price, price);
    }
}

/*//////////////////////////////////////////////////////////////
                    GAS BENCHMARK TESTS
//////////////////////////////////////////////////////////////*/

contract GasBenchmarkTest is Test {
    SmartOracleAggregator public oracle;
    RetryManager public retryManager;
    RefundManager public refundManager;
    FeeManager public feeManager;

    MockToken public token;
    MockPriceFeed public feed;
    MockRetryHandler public retryHandler;

    function setUp() public {
        oracle = new SmartOracleAggregator();
        oracle.initialize(address(0), address(0));

        retryHandler = new MockRetryHandler();
        retryManager = new RetryManager();
        retryManager.initialize(address(retryHandler));
        retryManager.setExecutor(address(this), true);

        refundManager = new RefundManager();
        refundManager.initialize(address(0x100));
        refundManager.setProcessor(address(this), true);

        feeManager = new FeeManager();
        feeManager.initialize(address(0x100), address(0));

        token = new MockToken("Test", "TEST");
        token.mint(address(refundManager), 1000000e18);

        feed = new MockPriceFeed(2000e8, 8);

        // Setup
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(feed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });
        oracle.registerOracle(address(0x1), address(0x2), config);

        FeeManager.ChainGasConfig memory gasConfig = FeeManager.ChainGasConfig({
            gasPrice: 50 gwei,
            gasPriceUpdatedAt: block.timestamp,
            l1DataFee: 0,
            priorityFee: 2 gwei,
            baseFeeMultiplier: 12000
        });
        feeManager.setChainGasConfig(42161, gasConfig);

        RefundManager.RefundConfig memory refundConfig = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 0,
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(token), refundConfig);
    }

    function test_Gas_OracleGetPrice() public {
        uint256 gasBefore = gasleft();
        oracle.getPrice(address(0x1), address(0x2));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Oracle getPrice gas:", gasUsed);
        assertTrue(gasUsed < 50000, "getPrice too expensive");
    }

    function test_Gas_QueueForRetry() public {
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        uint256 gasBefore = gasleft();
        retryManager.queueForRetry(
            keccak256("msg"), keccak256("tx"),
            address(0x1000), 1, 42161,
            abi.encode("payload"), abi.encode("error"),
            tokens, amounts
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Queue for retry gas:", gasUsed);
        assertTrue(gasUsed < 200000, "queueForRetry too expensive");
    }

    function test_Gas_CreateRefund() public {
        uint256 gasBefore = gasleft();
        refundManager.createRefund(
            keccak256("tx"), address(0x1000),
            address(token), 100e18,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            bytes32(0)
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Create refund gas:", gasUsed);
        assertTrue(gasUsed < 150000, "createRefund too expensive");
    }

    function test_Gas_GetFeeQuote() public view {
        uint256 gasBefore = gasleft();
        feeManager.getFeeQuote(42161, 200000, 1 ether, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Get fee quote gas:", gasUsed);
        assertTrue(gasUsed < 30000, "getFeeQuote too expensive");
    }

    function test_Gas_ExecuteRetry() public {
        // Setup
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        bytes32 messageId = keccak256("msg");

        retryManager.queueForRetry(
            messageId, keccak256("tx"),
            address(0x1000), 1, 42161,
            abi.encode("payload"), abi.encode("error"),
            tokens, amounts
        );

        vm.warp(block.timestamp + 2 minutes);
        retryHandler.setShouldSucceed(true);

        uint256 gasBefore = gasleft();
        retryManager.executeRetry(messageId);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Execute retry gas:", gasUsed);
        assertTrue(gasUsed < 100000, "executeRetry too expensive");
    }
}
