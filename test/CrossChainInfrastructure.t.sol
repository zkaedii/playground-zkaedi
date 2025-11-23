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
                    MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

contract MockChainlinkFeed {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(int256 price_, uint8 decimals_) {
        _price = price_;
        _decimals = decimals_;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function setPrice(int256 price_) external {
        _price = price_;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    function setStale() external {
        _updatedAt = block.timestamp - 2 hours;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function getRoundData(uint80) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
}

contract MockCCIPRouter {
    uint256 private _fee = 0.01 ether;
    uint256 private _messageCount;

    event MessageSent(uint64 destinationChainSelector, bytes32 messageId);

    function ccipSend(
        uint64 destinationChainSelector,
        ICCIPRouter.EVM2AnyMessage calldata
    ) external payable returns (bytes32 messageId) {
        require(msg.value >= _fee, "Insufficient fee");
        messageId = keccak256(abi.encodePacked(destinationChainSelector, _messageCount++));
        emit MessageSent(destinationChainSelector, messageId);
    }

    function getFee(uint64, ICCIPRouter.EVM2AnyMessage calldata) external view returns (uint256) {
        return _fee;
    }

    function setFee(uint256 fee_) external {
        _fee = fee_;
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getSupportedTokens(uint64) external pure returns (address[] memory) {
        return new address[](0);
    }
}

contract MockLZEndpoint {
    uint256 private _fee = 0.005 ether;
    uint64 private _nonce;

    event MessageSent(uint32 dstEid, bytes32 guid);

    function send(
        ILayerZeroEndpoint.MessagingParams calldata params,
        address
    ) external payable returns (ILayerZeroEndpoint.MessagingReceipt memory receipt) {
        require(msg.value >= _fee, "Insufficient fee");

        bytes32 guid = keccak256(abi.encodePacked(params.dstEid, _nonce++));

        receipt = ILayerZeroEndpoint.MessagingReceipt({
            guid: guid,
            nonce: _nonce,
            fee: ILayerZeroEndpoint.MessagingFee({
                nativeFee: _fee,
                lzTokenFee: 0
            })
        });

        emit MessageSent(params.dstEid, guid);
    }

    function quote(
        ILayerZeroEndpoint.MessagingParams calldata,
        address
    ) external view returns (ILayerZeroEndpoint.MessagingFee memory) {
        return ILayerZeroEndpoint.MessagingFee({
            nativeFee: _fee,
            lzTokenFee: 0
        });
    }

    function setDelegate(address) external {}

    function nextNonce(address, uint32, bytes32) external view returns (uint64) {
        return _nonce + 1;
    }
}

/*//////////////////////////////////////////////////////////////
                    ORACLE TESTS
//////////////////////////////////////////////////////////////*/

contract SmartOracleAggregatorTest is Test {
    SmartOracleAggregator public oracle;
    MockChainlinkFeed public ethFeed;
    MockChainlinkFeed public btcFeed;

    address public weth = address(0x1);
    address public wbtc = address(0x2);
    address public usdc = address(0x3);

    address public owner = address(this);

    function setUp() public {
        // Deploy oracle
        oracle = new SmartOracleAggregator();
        oracle.initialize(address(0), address(0));

        // Deploy mock feeds
        ethFeed = new MockChainlinkFeed(2000e8, 8); // $2000
        btcFeed = new MockChainlinkFeed(40000e8, 8); // $40000
    }

    function test_RegisterOracle() public {
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(ethFeed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });

        oracle.registerOracle(weth, usdc, config);

        IOracleRegistry.OracleConfig[] memory configs = oracle.getOracles(weth, usdc);
        assertEq(configs.length, 1);
        assertEq(configs[0].oracle, address(ethFeed));
    }

    function test_GetPrice() public {
        // Register oracle
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(ethFeed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });

        oracle.registerOracle(weth, usdc, config);

        // Get price
        ISmartOracle.PriceData memory data = oracle.getPrice(weth, usdc);

        assertEq(data.price, 2000e8);
        assertEq(data.decimals, 8);
        assertEq(uint8(data.source), uint8(ISmartOracle.OracleType.CHAINLINK));
    }

    function test_GetPrice_Fallback() public {
        // Register primary (will be stale)
        MockChainlinkFeed staleFeed = new MockChainlinkFeed(1900e8, 8);
        staleFeed.setStale();

        IOracleRegistry.OracleConfig memory primaryConfig = IOracleRegistry.OracleConfig({
            oracle: address(staleFeed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });

        IOracleRegistry.OracleConfig memory fallbackConfig = IOracleRegistry.OracleConfig({
            oracle: address(ethFeed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 2,
            isActive: true
        });

        oracle.registerOracle(weth, usdc, primaryConfig);
        oracle.registerOracle(weth, usdc, fallbackConfig);

        // Should use fallback
        ISmartOracle.PriceData memory data = oracle.getPrice(weth, usdc);
        assertEq(data.price, 2000e8);
    }

    function test_HasPriceFeed() public {
        assertFalse(oracle.hasPriceFeed(weth, usdc));

        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(ethFeed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });

        oracle.registerOracle(weth, usdc, config);

        assertTrue(oracle.hasPriceFeed(weth, usdc));
    }

    function test_RecordTWAPObservation() public {
        oracle.recordTWAPObservation(weth, usdc, 2000e18);

        vm.warp(block.timestamp + 5 minutes);
        oracle.recordTWAPObservation(weth, usdc, 2010e18);

        vm.warp(block.timestamp + 5 minutes);
        oracle.recordTWAPObservation(weth, usdc, 2020e18);

        // Register TWAP oracle
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(0),
            oracleType: ISmartOracle.OracleType.TWAP,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });

        oracle.registerOracle(weth, usdc, config);

        uint256 twap = oracle.getTWAP(weth, usdc, 10 minutes);
        assertTrue(twap > 0);
    }

    function testFuzz_RegisterMultipleOracles(uint8 count) public {
        vm.assume(count > 0 && count <= 5);

        for (uint8 i = 0; i < count; i++) {
            MockChainlinkFeed feed = new MockChainlinkFeed(int256(2000e8 + i * 100e8), 8);

            IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
                oracle: address(feed),
                oracleType: ISmartOracle.OracleType.CHAINLINK,
                heartbeat: 3600,
                priority: i + 1,
                isActive: true
            });

            oracle.registerOracle(weth, usdc, config);
        }

        IOracleRegistry.OracleConfig[] memory configs = oracle.getOracles(weth, usdc);
        assertEq(configs.length, count);
    }
}

/*//////////////////////////////////////////////////////////////
                    ORACLE GUARD TESTS
//////////////////////////////////////////////////////////////*/

contract OracleGuardTest is Test {
    OracleGuard public guard;
    SmartOracleAggregator public oracle;
    SmartOracleAggregator public twapOracle;
    MockChainlinkFeed public feed;

    address public weth = address(0x1);
    address public usdc = address(0x2);

    function setUp() public {
        oracle = new SmartOracleAggregator();
        oracle.initialize(address(0), address(0));

        twapOracle = new SmartOracleAggregator();
        twapOracle.initialize(address(0), address(0));

        guard = new OracleGuard();
        guard.initialize(address(oracle), address(twapOracle));

        feed = new MockChainlinkFeed(2000e8, 8);

        // Register oracle
        IOracleRegistry.OracleConfig memory config = IOracleRegistry.OracleConfig({
            oracle: address(feed),
            oracleType: ISmartOracle.OracleType.CHAINLINK,
            heartbeat: 3600,
            priority: 1,
            isActive: true
        });

        oracle.registerOracle(weth, usdc, config);
    }

    function test_ValidatePrice() public {
        OracleGuard.PriceCheckResult memory result = guard.validatePrice(weth, usdc);

        assertTrue(result.isValid);
        assertEq(result.price, 2000e8);
        assertEq(uint8(result.failedCheck), uint8(OracleGuard.CheckType.NONE));
    }

    function test_ValidatePrice_Stale() public {
        feed.setStale();

        OracleGuard.PriceCheckResult memory result = guard.validatePrice(weth, usdc);

        assertFalse(result.isValid);
        assertEq(uint8(result.failedCheck), uint8(OracleGuard.CheckType.STALENESS));
    }

    function test_CircuitBreaker() public {
        // Configure guard with low threshold
        OracleGuard.GuardConfig memory config = OracleGuard.GuardConfig({
            maxDeviation: 300,
            maxVolatility: 100, // 1% per block
            maxStaleness: 3600,
            minConfidence: 0,
            circuitBreakerThreshold: 500, // 5%
            recoveryPeriod: 1 hours,
            minOracleConsensus: 1,
            requireTWAPComparison: false,
            isActive: true
        });

        guard.setGuardConfig(weth, usdc, config);

        // First price
        guard.validatePrice(weth, usdc);

        // Large price change
        feed.setPrice(2500e8); // 25% increase

        OracleGuard.PriceCheckResult memory result = guard.validatePrice(weth, usdc);

        // Should trigger circuit breaker
        assertTrue(guard.isCircuitBreakerActive(weth, usdc));
    }

    function test_GetPriceHistory() public {
        guard.validatePrice(weth, usdc);

        feed.setPrice(2010e8);
        vm.roll(block.number + 1);
        guard.validatePrice(weth, usdc);

        feed.setPrice(2020e8);
        vm.roll(block.number + 1);
        guard.validatePrice(weth, usdc);

        OracleGuard.PriceObservation[] memory history = guard.getPriceHistory(weth, usdc);
        assertEq(history.length, 3);
    }
}

/*//////////////////////////////////////////////////////////////
                    REFUND MANAGER TESTS
//////////////////////////////////////////////////////////////*/

contract RefundManagerTest is Test {
    RefundManager public refundManager;
    MockERC20 public token;

    address public treasury = address(0x100);
    address public user = address(0x200);
    address public processor = address(0x300);

    function setUp() public {
        refundManager = new RefundManager();
        refundManager.initialize(treasury);

        token = new MockERC20("Test Token", "TEST");

        // Set processor
        refundManager.setProcessor(processor, true);

        // Fund refund manager
        token.mint(address(refundManager), 1000e18);
        vm.deal(address(refundManager), 100 ether);
    }

    function test_CreateRefund() public {
        bytes32 txId = keccak256("tx1");

        vm.prank(processor);
        bytes32 refundId = refundManager.createRefund(
            txId,
            user,
            address(token),
            100e18,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            bytes32(0)
        );

        RefundManager.RefundRequest memory refund = refundManager.getRefund(refundId);

        assertEq(refund.recipient, user);
        assertEq(refund.token, address(token));
        assertTrue(refund.amount < 100e18); // Fee deducted
        assertEq(uint8(refund.status), uint8(RefundManager.RefundStatus.PENDING));
    }

    function test_ClaimRefund() public {
        bytes32 txId = keccak256("tx1");

        // Create refund with no delay
        RefundManager.RefundConfig memory config = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 50,
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(token), config);

        vm.prank(processor);
        bytes32 refundId = refundManager.createRefund(
            txId,
            user,
            address(token),
            100e18,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            bytes32(0)
        );

        uint256 balanceBefore = token.balanceOf(user);

        vm.prank(user);
        refundManager.claimRefund(refundId);

        uint256 balanceAfter = token.balanceOf(user);
        assertTrue(balanceAfter > balanceBefore);

        RefundManager.RefundRequest memory refund = refundManager.getRefund(refundId);
        assertEq(uint8(refund.status), uint8(RefundManager.RefundStatus.CLAIMED));
    }

    function test_ClaimRefund_ETH() public {
        bytes32 txId = keccak256("tx2");

        RefundManager.RefundConfig memory config = RefundManager.RefundConfig({
            claimDelay: 0,
            expiryPeriod: 30 days,
            minRefundAmount: 0,
            feePercentage: 50,
            requireProof: false,
            autoProcess: false
        });
        refundManager.setTokenConfig(address(0), config);

        vm.prank(processor);
        bytes32 refundId = refundManager.createRefund(
            txId,
            user,
            address(0), // ETH
            1 ether,
            RefundManager.RefundReason.BRIDGE_FAILURE,
            bytes32(0)
        );

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        refundManager.claimRefund(refundId);

        assertTrue(user.balance > balanceBefore);
    }

    function test_DisputeRefund() public {
        bytes32 txId = keccak256("tx3");

        vm.prank(processor);
        bytes32 refundId = refundManager.createRefund(
            txId,
            user,
            address(token),
            100e18,
            RefundManager.RefundReason.SLIPPAGE_EXCEEDED,
            bytes32(0)
        );

        vm.prank(user);
        refundManager.disputeRefund(refundId, "Wrong amount");

        RefundManager.RefundRequest memory refund = refundManager.getRefund(refundId);
        assertEq(uint8(refund.status), uint8(RefundManager.RefundStatus.DISPUTED));
    }

    function test_ResolveDispute() public {
        bytes32 txId = keccak256("tx4");

        vm.prank(processor);
        bytes32 refundId = refundManager.createRefund(
            txId,
            user,
            address(token),
            100e18,
            RefundManager.RefundReason.TRANSACTION_FAILED,
            bytes32(0)
        );

        vm.prank(user);
        refundManager.disputeRefund(refundId, "Dispute reason");

        refundManager.setResolver(address(this), true);
        refundManager.resolveDispute(refundId, true, 95e18);

        RefundManager.RefundRequest memory refund = refundManager.getRefund(refundId);
        assertEq(uint8(refund.status), uint8(RefundManager.RefundStatus.CLAIMABLE));
        assertEq(refund.amount, 95e18);
    }

    function test_GetPendingRefunds() public {
        // Create multiple refunds
        for (uint i = 0; i < 5; i++) {
            bytes32 txId = keccak256(abi.encodePacked("tx", i));

            vm.prank(processor);
            refundManager.createRefund(
                txId,
                user,
                address(token),
                10e18,
                RefundManager.RefundReason.TRANSACTION_FAILED,
                bytes32(0)
            );
        }

        (bytes32[] memory pending, uint256 total) = refundManager.getPendingRefunds(user);

        assertEq(pending.length, 5);
        assertTrue(total > 0);
    }
}

/*//////////////////////////////////////////////////////////////
                    EMERGENCY MANAGER TESTS
//////////////////////////////////////////////////////////////*/

contract EmergencyManagerTest is Test {
    EmergencyManager public emergency;

    address public guardian1 = address(0x100);
    address public guardian2 = address(0x200);

    function setUp() public {
        emergency = new EmergencyManager();
        emergency.initialize();

        emergency.addGuardian(guardian1);
        emergency.addGuardian(guardian2);
    }

    function test_TriggerCircuitBreaker() public {
        vm.prank(guardian1);
        emergency.triggerCircuitBreaker(
            EmergencyManager.CircuitBreakerType.PROTOCOL,
            keccak256("uniswap"),
            "High slippage detected",
            1 hours
        );

        assertTrue(emergency.isCircuitBreakerActive(
            EmergencyManager.CircuitBreakerType.PROTOCOL,
            keccak256("uniswap")
        ));
    }

    function test_SetEmergencyLevel() public {
        vm.prank(guardian1);
        emergency.setEmergencyLevel(EmergencyManager.EmergencyLevel.HIGH);

        assertEq(uint8(emergency.emergencyLevel()), uint8(EmergencyManager.EmergencyLevel.HIGH));
        assertTrue(emergency.paused());
    }

    function test_ProposeAndExecuteEmergencyAction() public {
        // Propose action
        vm.prank(guardian1);
        bytes32 actionId = emergency.proposeEmergencyAction(
            address(this),
            abi.encodeWithSignature("mockAction()"),
            0
        );

        // Approve from second guardian
        vm.prank(guardian2);
        emergency.approveEmergencyAction(actionId);

        // Wait for timelock
        vm.warp(block.timestamp + 2 hours);

        // Execute
        vm.prank(guardian1);
        emergency.executeEmergencyAction(actionId);

        (,,,,,,bool executed) = emergency.getEmergencyAction(actionId);
        assertTrue(executed);
    }

    function test_EmergencyAction_BypassTimelock() public {
        // Set critical level
        vm.prank(guardian1);
        emergency.setEmergencyLevel(EmergencyManager.EmergencyLevel.CRITICAL);

        // In critical, timelock is bypassed
        vm.prank(guardian1);
        bytes32 actionId = emergency.proposeEmergencyAction(
            address(this),
            abi.encodeWithSignature("mockAction()"),
            0
        );

        // No timelock wait needed in CRITICAL
        vm.prank(guardian1);
        emergency.executeEmergencyAction(actionId);

        (,,,,,,bool executed) = emergency.getEmergencyAction(actionId);
        assertTrue(executed);
    }

    function test_FallbackRouting() public {
        address primary = address(0x1);
        address fallback_ = address(0x2);

        emergency.setFallbackRoute(primary, fallback_);

        // Initially use primary
        assertEq(emergency.getActiveAddress(primary), primary);

        // Activate fallback
        vm.prank(guardian1);
        emergency.activateFallback(primary);

        assertEq(emergency.getActiveAddress(primary), fallback_);
    }

    function mockAction() external pure returns (bool) {
        return true;
    }
}

/*//////////////////////////////////////////////////////////////
                    RETRY MANAGER TESTS
//////////////////////////////////////////////////////////////*/

contract RetryManagerTest is Test {
    RetryManager public retryManager;
    MockERC20 public token;

    address public executor = address(0x100);
    address public handler = address(0x200);
    address public sender = address(0x300);

    function setUp() public {
        retryManager = new RetryManager();
        retryManager.initialize(handler);

        retryManager.setExecutor(executor, true);

        token = new MockERC20("Test", "TEST");
        token.mint(address(retryManager), 1000e18);
    }

    function test_QueueForRetry() public {
        bytes32 messageId = keccak256("msg1");
        bytes32 txId = keccak256("tx1");

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(executor);
        retryManager.queueForRetry(
            messageId,
            txId,
            sender,
            1, // source chain
            42161, // dest chain
            abi.encode("test payload"),
            abi.encode("error"),
            tokens,
            amounts
        );

        assertEq(retryManager.getQueueLength(), 1);

        RetryManager.RetryMetrics memory metrics = retryManager.getMetrics();
        assertEq(metrics.totalMessages, 1);
        assertEq(metrics.pendingRetries, 1);
    }

    function test_GetPendingRetries() public {
        // Queue multiple messages
        for (uint i = 0; i < 5; i++) {
            bytes32 messageId = keccak256(abi.encodePacked("msg", i));
            bytes32 txId = keccak256(abi.encodePacked("tx", i));

            address[] memory tokens = new address[](0);
            uint256[] memory amounts = new uint256[](0);

            vm.prank(executor);
            retryManager.queueForRetry(
                messageId,
                txId,
                sender,
                1,
                42161,
                abi.encode("payload"),
                abi.encode("error"),
                tokens,
                amounts
            );
        }

        // Fast forward past initial delay
        vm.warp(block.timestamp + 2 minutes);

        (bytes32[] memory pending, uint256 count) = retryManager.getPendingRetries(10);
        assertEq(count, 5);
    }

    function test_DeadLetterMessage() public {
        bytes32 messageId = keccak256("msg1");
        bytes32 txId = keccak256("tx1");

        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(executor);
        retryManager.queueForRetry(
            messageId,
            txId,
            sender,
            1,
            42161,
            abi.encode("payload"),
            abi.encode("error"),
            tokens,
            amounts
        );

        vm.prank(executor);
        retryManager.deadLetterMessage(messageId, "Manual intervention required");

        RetryManager.RetryMetrics memory metrics = retryManager.getMetrics();
        assertEq(metrics.deadLettered, 1);
    }
}

/*//////////////////////////////////////////////////////////////
                    FEE MANAGER TESTS
//////////////////////////////////////////////////////////////*/

contract FeeManagerTest is Test {
    FeeManager public feeManager;

    address public treasury = address(0x100);

    function setUp() public {
        feeManager = new FeeManager();
        feeManager.initialize(treasury, address(0));

        // Set chain gas config
        FeeManager.ChainGasConfig memory gasConfig = FeeManager.ChainGasConfig({
            gasPrice: 50 gwei,
            gasPriceUpdatedAt: block.timestamp,
            l1DataFee: 0,
            priorityFee: 2 gwei,
            baseFeeMultiplier: 12000 // 1.2x
        });

        feeManager.setChainGasConfig(42161, gasConfig);
    }

    function test_GetFeeQuote() public {
        FeeManager.FeeQuote memory quote = feeManager.getFeeQuote(
            42161, // Arbitrum
            200000, // gas limit
            1 ether, // value
            0 // CCIP
        );

        assertTrue(quote.totalFee > 0);
        assertTrue(quote.gasFee > 0);
        assertTrue(quote.validUntil > block.timestamp);
    }

    function test_EstimateGasFee() public {
        uint256 gasFee = feeManager.estimateGasFee(42161, 200000);

        // 200000 * (50 gwei + 2 gwei) * 1.2
        uint256 expected = 200000 * 52 gwei * 12000 / 10000;
        assertEq(gasFee, expected);
    }

    function test_CollectFees() public payable {
        FeeManager.FeeQuote memory quote = feeManager.getFeeQuote(
            42161,
            200000,
            1 ether,
            0
        );

        bytes32 txId = keccak256("tx1");

        vm.deal(address(this), 1 ether);
        feeManager.collectFees{value: quote.totalFee + 0.01 ether}(
            txId,
            address(this),
            1 ether,
            42161,
            200000,
            0
        );

        // Check pending refund for excess
        assertTrue(feeManager.pendingRefunds(txId) > 0);
    }

    function test_UpdateGasPrice() public {
        address gasOracle = address(0x500);
        feeManager.setGasOracle(gasOracle);

        vm.prank(gasOracle);
        feeManager.updateGasPrice(42161, 100 gwei, 5 gwei, 0);

        (uint256 gasPrice,,,,,) = feeManager.chainGasConfigs(42161);
        assertEq(gasPrice, 100 gwei);
    }
}

/*//////////////////////////////////////////////////////////////
                    RESPONSE HANDLER TESTS
//////////////////////////////////////////////////////////////*/

contract ResponseHandlerTest is Test {
    ResponseHandler public handler;

    address public responder = address(0x100);
    address public callbackContract = address(0x200);

    function setUp() public {
        handler = new ResponseHandler();
        handler.initialize();

        handler.setAuthorizedResponder(responder, true);
    }

    function test_RegisterCallback() public {
        bytes32 requestId = keccak256("req1");

        handler.registerCallback(
            requestId,
            callbackContract,
            bytes4(keccak256("onResponse(bytes32,bytes)")),
            1 hours,
            ""
        );

        (bool registered,,,) = handler.getCallbackStatus(requestId);
        assertTrue(registered);
    }

    function test_HandleResponse() public {
        bytes32 requestId = keccak256("req1");

        handler.registerCallback(
            requestId,
            address(this),
            bytes4(keccak256("onResponse(bytes32,bytes)")),
            1 hours,
            ""
        );

        vm.prank(responder);
        ResponseHandler.CallbackResult memory result = handler.handleSuccessResponse(
            requestId,
            abi.encode("success data"),
            42161
        );

        assertTrue(handler.hasResponse(requestId));
    }

    function test_IsExpired() public {
        bytes32 requestId = keccak256("req1");

        handler.registerCallback(
            requestId,
            callbackContract,
            bytes4(keccak256("onResponse(bytes32,bytes)")),
            1 hours,
            ""
        );

        assertFalse(handler.isExpired(requestId));

        vm.warp(block.timestamp + 2 hours);

        assertTrue(handler.isExpired(requestId));
    }

    function onResponse(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }
}
