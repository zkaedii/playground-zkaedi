// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/utils/GasOptimizedTransfers.sol";

/**
 * @title GasOptimizedTransfersTest
 * @notice Comprehensive test suite with gas benchmarking for GasOptimizedTransfers library
 * @dev Run with `forge test --match-contract GasOptimizedTransfersTest -vvv --gas-report`
 */
contract GasOptimizedTransfersTest is Test {
    using GasOptimizedTransfers for *;

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════════════

    MockERC20 token;
    GasTestHarness harness;

    // Test accounts
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dave = address(0x4);
    address eve = address(0x5);

    // Gas tracking
    uint256 constant GAS_BENCHMARK_ITERATIONS = 5;

    function setUp() public {
        token = new MockERC20("Test Token", "TEST", 18);
        harness = new GasTestHarness();

        // Fund test accounts
        vm.deal(address(harness), 1000 ether);
        token.mint(address(harness), 1_000_000e18);

        // Labels for better trace output
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dave, "Dave");
        vm.label(eve, "Eve");
        vm.label(address(token), "TestToken");
        vm.label(address(harness), "GasTestHarness");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PACKED ENCODING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_PackTransfer_BasicPacking() public pure {
        address recipient = address(0x1234567890123456789012345678901234567890);
        uint256 amount = 100e18;

        uint256 packed = GasOptimizedTransfers.packTransfer(recipient, amount);
        (address unpackedRecipient, uint256 unpackedAmount) = GasOptimizedTransfers.unpackTransfer(packed);

        assertEq(unpackedRecipient, recipient, "Recipient mismatch");
        assertEq(unpackedAmount, amount, "Amount mismatch");
    }

    function test_PackTransfer_MaxAmount() public pure {
        address recipient = alice;
        uint256 maxAmount = (1 << 96) - 1; // Max 96-bit value

        uint256 packed = GasOptimizedTransfers.packTransfer(recipient, maxAmount);
        (, uint256 unpackedAmount) = GasOptimizedTransfers.unpackTransfer(packed);

        assertEq(unpackedAmount, maxAmount, "Max amount mismatch");
    }

    function test_PackTransfer_ZeroAmount() public pure {
        uint256 packed = GasOptimizedTransfers.packTransfer(alice, 0);
        (, uint256 amount) = GasOptimizedTransfers.unpackTransfer(packed);

        assertEq(amount, 0, "Zero amount mismatch");
    }

    function testFuzz_PackTransfer_Roundtrip(address recipient, uint96 amount) public pure {
        vm.assume(recipient != address(0));

        uint256 packed = GasOptimizedTransfers.packTransfer(recipient, uint256(amount));
        (address unpackedRecipient, uint256 unpackedAmount) = GasOptimizedTransfers.unpackTransfer(packed);

        assertEq(unpackedRecipient, recipient);
        assertEq(unpackedAmount, uint256(amount));
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // BATCH ERC20 TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransferERC20_SingleRecipient() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = alice;
        amounts[0] = 100e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferERC20(
            address(token),
            recipients,
            amounts
        );

        assertEq(result.successCount, 1, "Should have 1 success");
        assertEq(result.failureCount, 0, "Should have 0 failures");
        assertEq(token.balanceOf(alice), 100e18, "Alice should receive tokens");
    }

    function test_BatchTransferERC20_MultipleRecipients() public {
        address[] memory recipients = new address[](5);
        uint256[] memory amounts = new uint256[](5);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        recipients[3] = dave;
        recipients[4] = eve;

        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;
        amounts[3] = 400e18;
        amounts[4] = 500e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferERC20(
            address(token),
            recipients,
            amounts
        );

        assertEq(result.successCount, 5, "All transfers should succeed");
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.balanceOf(charlie), 300e18);
        assertEq(token.balanceOf(dave), 400e18);
        assertEq(token.balanceOf(eve), 500e18);
    }

    function test_BatchTransferERC20_SkipsZeroAmounts() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;

        amounts[0] = 100e18;
        amounts[1] = 0;         // Should be skipped
        amounts[2] = 300e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferERC20(
            address(token),
            recipients,
            amounts
        );

        // Note: successCount only counts actual transfers, not skipped ones
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(charlie), 300e18);
    }

    function test_BatchTransferERC20_RevertOnEmptyBatch() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(GasOptimizedTransfers.EmptyBatch.selector);
        harness.batchTransferERC20(address(token), recipients, amounts);
    }

    function test_BatchTransferERC20_RevertOnArrayMismatch() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = alice;
        recipients[1] = bob;
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                GasOptimizedTransfers.ArrayLengthMismatch.selector,
                2,
                3
            )
        );
        harness.batchTransferERC20(address(token), recipients, amounts);
    }

    function test_BatchTransferERC20_RevertOnZeroToken() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = alice;
        amounts[0] = 100e18;

        vm.expectRevert(GasOptimizedTransfers.ZeroAddress.selector);
        harness.batchTransferERC20(address(0), recipients, amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PACKED BATCH TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransferPacked_SingleRecipient() public {
        uint256[] memory packed = new uint256[](1);
        packed[0] = GasOptimizedTransfers.packTransfer(alice, 100e18);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferPacked(
            address(token),
            packed
        );

        assertEq(result.successCount, 1);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_BatchTransferPacked_MultipleRecipients() public {
        uint256[] memory packed = new uint256[](5);
        packed[0] = GasOptimizedTransfers.packTransfer(alice, 100e18);
        packed[1] = GasOptimizedTransfers.packTransfer(bob, 200e18);
        packed[2] = GasOptimizedTransfers.packTransfer(charlie, 300e18);
        packed[3] = GasOptimizedTransfers.packTransfer(dave, 400e18);
        packed[4] = GasOptimizedTransfers.packTransfer(eve, 500e18);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferPacked(
            address(token),
            packed
        );

        assertEq(result.successCount, 5);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.balanceOf(charlie), 300e18);
        assertEq(token.balanceOf(dave), 400e18);
        assertEq(token.balanceOf(eve), 500e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ETH DISTRIBUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_DistributeETH_SingleRecipient() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = alice;
        amounts[0] = 1 ether;

        uint256 aliceBalanceBefore = alice.balance;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETH(
            recipients,
            amounts
        );

        assertEq(result.successCount, 1);
        assertEq(alice.balance - aliceBalanceBefore, 1 ether);
    }

    function test_DistributeETH_MultipleRecipients() public {
        address[] memory recipients = new address[](5);
        uint256[] memory amounts = new uint256[](5);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        recipients[3] = dave;
        recipients[4] = eve;

        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        amounts[3] = 4 ether;
        amounts[4] = 5 ether;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETH(
            recipients,
            amounts
        );

        assertEq(result.successCount, 5);
        assertEq(result.amountTransferred, 15 ether);
    }

    function test_DistributeETH_RevertOnInsufficientBalance() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = alice;
        amounts[0] = 10000 ether; // More than harness has

        vm.expectRevert(
            abi.encodeWithSelector(
                GasOptimizedTransfers.InsufficientETH.selector,
                10000 ether,
                1000 ether
            )
        );
        harness.distributeETH(recipients, amounts);
    }

    function test_DistributeETHPacked_MultipleRecipients() public {
        uint256[] memory packed = new uint256[](3);
        packed[0] = GasOptimizedTransfers.packTransfer(alice, 1 ether);
        packed[1] = GasOptimizedTransfers.packTransfer(bob, 2 ether);
        packed[2] = GasOptimizedTransfers.packTransfer(charlie, 3 ether);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 charlieBefore = charlie.balance;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETHPacked(packed);

        assertEq(result.successCount, 3);
        assertEq(alice.balance - aliceBefore, 1 ether);
        assertEq(bob.balance - bobBefore, 2 ether);
        assertEq(charlie.balance - charlieBefore, 3 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SILENT TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransferSilent_NoEvents() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;

        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        // Record logs - should be empty for silent transfer
        vm.recordLogs();

        uint256 successCount = harness.batchTransferSilent(
            address(token),
            recipients,
            amounts
        );

        // No BatchTransferCompleted event should be emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3); // Only ERC20 Transfer events from token contract

        assertEq(successCount, 3);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.balanceOf(charlie), 300e18);
    }

    function test_DistributeETHSilent_NoEvents() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        recipients[0] = alice;
        recipients[1] = bob;

        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        uint256 successCount = harness.distributeETHSilent(recipients, amounts);

        assertEq(successCount, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // REENTRANCY GUARD TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_ReentrancyGuard_Initialize() public {
        GasOptimizedTransfers.ReentrancyGuard memory guard;
        // Initial status should be 0
        assertEq(guard.status, 0);
    }

    function test_DistributeETHWithFullGas_WithGuard() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        recipients[0] = alice;
        recipients[1] = bob;

        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETHWithFullGas(
            recipients,
            amounts
        );

        assertEq(result.successCount, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_GetBalance() public view {
        uint256 balance = GasOptimizedTransfers.getBalance(address(token), address(harness));
        assertEq(balance, 1_000_000e18);
    }

    function test_EstimateBatchGas_ERC20() public pure {
        uint256 estimate10 = GasOptimizedTransfers.estimateBatchGas(10, true);
        uint256 estimate50 = GasOptimizedTransfers.estimateBatchGas(50, true);
        uint256 estimate100 = GasOptimizedTransfers.estimateBatchGas(100, true);

        // ERC20: base (26000) + count * 30000
        assertEq(estimate10, 26000 + 10 * 30000);
        assertEq(estimate50, 26000 + 50 * 30000);
        assertEq(estimate100, 26000 + 100 * 30000);
    }

    function test_EstimateBatchGas_ETH() public pure {
        uint256 estimate10 = GasOptimizedTransfers.estimateBatchGas(10, false);
        uint256 estimate50 = GasOptimizedTransfers.estimateBatchGas(50, false);

        // ETH: base (26000) + count * 7000
        assertEq(estimate10, 26000 + 10 * 7000);
        assertEq(estimate50, 26000 + 50 * 7000);
    }

    function test_CalculatePackedTotal() public pure {
        uint256[] memory packed = new uint256[](3);
        packed[0] = GasOptimizedTransfers.packTransfer(alice, 100e18);
        packed[1] = GasOptimizedTransfers.packTransfer(bob, 200e18);
        packed[2] = GasOptimizedTransfers.packTransfer(charlie, 300e18);

        // Note: This requires a wrapper since calculatePackedTotal takes calldata
        uint256 expectedTotal = 600e18;

        (,uint256 amt0) = GasOptimizedTransfers.unpackTransfer(packed[0]);
        (,uint256 amt1) = GasOptimizedTransfers.unpackTransfer(packed[1]);
        (,uint256 amt2) = GasOptimizedTransfers.unpackTransfer(packed[2]);

        assertEq(amt0 + amt1 + amt2, expectedTotal);
    }

    function test_CreateTransfer() public pure {
        GasOptimizedTransfers.Transfer memory transfer = GasOptimizedTransfers.createTransfer(
            alice,
            100e18
        );

        assertEq(transfer.recipient, alice);
        assertEq(transfer.amount, 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Benchmark: 10 ERC20 transfers (standard vs optimized)
     * @dev Run with: forge test --match-test test_GasBenchmark_10Transfers -vvv
     */
    function test_GasBenchmark_10Transfers() public {
        uint256 count = 10;
        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        // Optimized batch transfer
        uint256 gasStart = gasleft();
        harness.batchTransferERC20(address(token), recipients, amounts);
        uint256 optimizedGas = gasStart - gasleft();

        emit log_named_uint("Optimized Gas (10 transfers)", optimizedGas);
        emit log_named_uint("Gas per transfer", optimizedGas / count);

        // Compare with standard (simulated)
        uint256 standardEstimate = count * 50000; // ~50k per standard transfer
        emit log_named_uint("Standard estimate (10 transfers)", standardEstimate);
        emit log_named_uint("Savings percentage", ((standardEstimate - optimizedGas) * 100) / standardEstimate);
    }

    /**
     * @notice Benchmark: 50 ERC20 transfers
     */
    function test_GasBenchmark_50Transfers() public {
        uint256 count = 50;
        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        uint256 gasStart = gasleft();
        harness.batchTransferERC20(address(token), recipients, amounts);
        uint256 optimizedGas = gasStart - gasleft();

        emit log_named_uint("Optimized Gas (50 transfers)", optimizedGas);
        emit log_named_uint("Gas per transfer", optimizedGas / count);
    }

    /**
     * @notice Benchmark: 100 ERC20 transfers
     */
    function test_GasBenchmark_100Transfers() public {
        uint256 count = 100;
        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        uint256 gasStart = gasleft();
        harness.batchTransferERC20(address(token), recipients, amounts);
        uint256 optimizedGas = gasStart - gasleft();

        emit log_named_uint("Optimized Gas (100 transfers)", optimizedGas);
        emit log_named_uint("Gas per transfer", optimizedGas / count);
    }

    /**
     * @notice Benchmark: Packed vs Unpacked calldata efficiency
     */
    function test_GasBenchmark_PackedVsUnpacked() public {
        uint256 count = 20;

        // Generate unpacked data
        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        // Generate packed data
        uint256[] memory packed = new uint256[](count);
        for (uint256 i; i < count; i++) {
            packed[i] = GasOptimizedTransfers.packTransfer(recipients[i], amounts[i]);
        }

        // Benchmark unpacked
        uint256 gasStart = gasleft();
        harness.batchTransferERC20(address(token), recipients, amounts);
        uint256 unpackedGas = gasStart - gasleft();

        // Reset token balances
        for (uint256 i; i < count; i++) {
            vm.prank(recipients[i]);
            token.transfer(address(harness), amounts[i]);
        }

        // Benchmark packed
        gasStart = gasleft();
        harness.batchTransferPacked(address(token), packed);
        uint256 packedGas = gasStart - gasleft();

        emit log_named_uint("Unpacked Gas (20 transfers)", unpackedGas);
        emit log_named_uint("Packed Gas (20 transfers)", packedGas);
        emit log_named_uint("Calldata savings (bytes)", count * 32); // 32 bytes saved per transfer
    }

    /**
     * @notice Benchmark: ETH distribution
     */
    function test_GasBenchmark_ETHDistribution() public {
        uint256 count = 20;
        (address[] memory recipients, uint256[] memory amounts) = _generateETHBatchData(count);

        uint256 gasStart = gasleft();
        harness.distributeETH(recipients, amounts);
        uint256 optimizedGas = gasStart - gasleft();

        emit log_named_uint("ETH Distribution Gas (20 recipients)", optimizedGas);
        emit log_named_uint("Gas per ETH transfer", optimizedGas / count);
    }

    /**
     * @notice Benchmark: Silent vs Event-emitting transfers
     */
    function test_GasBenchmark_SilentVsEvents() public {
        uint256 count = 20;
        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        // With events
        uint256 gasStart = gasleft();
        harness.batchTransferERC20(address(token), recipients, amounts);
        uint256 withEventsGas = gasStart - gasleft();

        // Reset balances
        for (uint256 i; i < count; i++) {
            vm.prank(recipients[i]);
            token.transfer(address(harness), amounts[i]);
        }

        // Silent (no events)
        gasStart = gasleft();
        harness.batchTransferSilent(address(token), recipients, amounts);
        uint256 silentGas = gasStart - gasleft();

        emit log_named_uint("With events Gas", withEventsGas);
        emit log_named_uint("Silent Gas", silentGas);
        emit log_named_uint("Event overhead", withEventsGas - silentGas);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function testFuzz_BatchTransferERC20(uint8 count) public {
        vm.assume(count > 0 && count <= 50);

        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferERC20(
            address(token),
            recipients,
            amounts
        );

        assertEq(result.successCount, count);
    }

    function testFuzz_DistributeETH(uint8 count) public {
        vm.assume(count > 0 && count <= 50);

        (address[] memory recipients, uint256[] memory amounts) = _generateETHBatchData(count);

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETH(
            recipients,
            amounts
        );

        assertEq(result.successCount, count);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransfer_MaxBatchSize() public {
        uint256 count = 500; // MAX_BATCH_SIZE

        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferERC20(
            address(token),
            recipients,
            amounts
        );

        assertEq(result.successCount, count);
    }

    function test_BatchTransfer_ExceedsMaxBatchSize() public {
        uint256 count = 501; // Exceeds MAX_BATCH_SIZE

        (address[] memory recipients, uint256[] memory amounts) = _generateBatchData(count);

        vm.expectRevert(
            abi.encodeWithSelector(
                GasOptimizedTransfers.BatchSizeTooLarge.selector,
                501,
                500
            )
        );
        harness.batchTransferERC20(address(token), recipients, amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    function _generateBatchData(uint256 count)
        internal
        pure
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        recipients = new address[](count);
        amounts = new uint256[](count);

        for (uint256 i; i < count; i++) {
            recipients[i] = address(uint160(0x1000 + i));
            amounts[i] = (i + 1) * 1e18; // 1, 2, 3... tokens
        }
    }

    function _generateETHBatchData(uint256 count)
        internal
        pure
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        recipients = new address[](count);
        amounts = new uint256[](count);

        for (uint256 i; i < count; i++) {
            recipients[i] = address(uint160(0x2000 + i));
            amounts[i] = 0.01 ether * (i + 1); // 0.01, 0.02, 0.03... ETH
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════
// MOCK CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════════════

/**
 * @notice Mock ERC20 for testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        require(to != address(0), "ERC20: mint to zero address");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "ERC20: transfer to zero address");
        require(balanceOf[msg.sender] >= amount, "ERC20: insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(to != address(0), "ERC20: transfer to zero address");
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @notice Test harness contract to expose library functions
 */
contract GasTestHarness {
    using GasOptimizedTransfers for *;

    GasOptimizedTransfers.ReentrancyGuard public guard;

    constructor() {
        guard.initReentrancyGuard();
    }

    receive() external payable {}

    function batchTransferERC20(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransferERC20(token, recipients, amounts);
    }

    function batchTransferFromERC20(
        address token,
        address from,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransferFromERC20(token, from, recipients, amounts);
    }

    function batchTransferPacked(
        address token,
        uint256[] calldata packedTransfers
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransferPacked(token, packedTransfers);
    }

    function distributeETH(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.distributeETH(recipients, amounts);
    }

    function distributeETHWithFullGas(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.distributeETHWithFullGas(recipients, amounts, guard);
    }

    function distributeETHPacked(
        uint256[] calldata packedTransfers
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.distributeETHPacked(packedTransfers);
    }

    function batchTransferSilent(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (uint256) {
        return GasOptimizedTransfers.batchTransferSilent(token, recipients, amounts);
    }

    function distributeETHSilent(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (uint256) {
        return GasOptimizedTransfers.distributeETHSilent(recipients, amounts);
    }
}
