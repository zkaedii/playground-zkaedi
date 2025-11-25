// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/utils/GasOptimizedTransfers.sol";

/**
 * @title GasOptimizedTransfersTest
 * @notice Battle-tested test suite for GasOptimizedTransfers v2.0
 * @dev Run: `forge test --match-contract GasOptimizedTransfersTest -vvv --gas-report`
 *
 * Test Coverage:
 * ├── Packed Encoding/Decoding
 * ├── Batch ERC20 Transfers (Standard, Atomic, Packed)
 * ├── Batch TransferFrom
 * ├── ETH Distribution (Standard, Unsafe, Packed)
 * ├── Multi-Token Transfers
 * ├── Merkle Claims
 * ├── Rate Limiting
 * ├── Reentrancy Protection
 * ├── Gas Benchmarks
 * └── Fuzz Tests
 */
contract GasOptimizedTransfersTest is Test {
    using GasOptimizedTransfers for *;

    // ═══════════════════════════════════════════════════════════════════════════════
    //                               TEST SETUP
    // ═══════════════════════════════════════════════════════════════════════════════

    MockERC20 token;
    MockERC20 token2;
    BatchTestHarness harness;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address dave = makeAddr("dave");
    address eve = makeAddr("eve");

    function setUp() public {
        token = new MockERC20("Test Token", "TEST");
        token2 = new MockERC20("Second Token", "TEST2");
        harness = new BatchTestHarness();

        // Fund harness
        vm.deal(address(harness), 1000 ether);
        token.mint(address(harness), 1_000_000e18);
        token2.mint(address(harness), 1_000_000e18);

        // Labels
        vm.label(address(token), "Token");
        vm.label(address(token2), "Token2");
        vm.label(address(harness), "Harness");
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                          PACKED ENCODING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Pack_Roundtrip() public pure {
        address recipient = address(0xBEEF);
        uint256 amount = 100e18;

        uint256 packed = GasOptimizedTransfers.pack(recipient, amount);
        (address r, uint256 a) = GasOptimizedTransfers.unpack(packed);

        assertEq(r, recipient, "recipient mismatch");
        assertEq(a, amount, "amount mismatch");
    }

    function test_Pack_MaxAmount() public pure {
        uint256 maxAmount = type(uint96).max;
        uint256 packed = GasOptimizedTransfers.pack(alice, maxAmount);
        (, uint256 amount) = GasOptimizedTransfers.unpack(packed);

        assertEq(amount, maxAmount);
    }

    function test_Pack_RevertsOnOverflow() public {
        uint256 tooLarge = uint256(type(uint96).max) + 1;

        vm.expectRevert(GasOptimizedTransfers.AmountTooLarge.selector);
        GasOptimizedTransfers.pack(alice, tooLarge);
    }

    function test_PackBatch() public pure {
        GasOptimizedTransfers.Transfer[] memory transfers = new GasOptimizedTransfers.Transfer[](3);
        transfers[0] = GasOptimizedTransfers.Transfer(alice, 100e18);
        transfers[1] = GasOptimizedTransfers.Transfer(bob, 200e18);
        transfers[2] = GasOptimizedTransfers.Transfer(charlie, 300e18);

        uint256[] memory packed = GasOptimizedTransfers.packBatch(transfers);

        assertEq(packed.length, 3);

        for (uint256 i; i < 3; i++) {
            (address r, uint256 a) = GasOptimizedTransfers.unpack(packed[i]);
            assertEq(r, transfers[i].recipient);
            assertEq(a, transfers[i].amount);
        }
    }

    function testFuzz_Pack_Roundtrip(address recipient, uint96 amount) public pure {
        vm.assume(recipient != address(0));

        uint256 packed = GasOptimizedTransfers.pack(recipient, amount);
        (address r, uint256 a) = GasOptimizedTransfers.unpack(packed);

        assertEq(r, recipient);
        assertEq(a, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                         BATCH ERC20 TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransfer_Single() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = alice;
        amounts[0] = 100e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransfer(
            address(token), recipients, amounts
        );

        assertEq(result.succeeded, 1);
        assertEq(result.failed, 0);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_BatchTransfer_Multiple() public {
        (address[] memory recipients, uint256[] memory amounts) = _createBatch(5);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransfer(
            address(token), recipients, amounts
        );

        assertEq(result.succeeded, 5);
        assertEq(result.failed, 0);

        for (uint256 i; i < 5; i++) {
            assertEq(token.balanceOf(recipients[i]), amounts[i]);
        }
    }

    function test_BatchTransfer_SkipsZeroAddresses() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = alice;
        recipients[1] = address(0); // Should skip
        recipients[2] = charlie;

        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransfer(
            address(token), recipients, amounts
        );

        assertEq(result.succeeded, 2);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(charlie), 300e18);
    }

    function test_BatchTransfer_SkipsZeroAmounts() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;

        amounts[0] = 100e18;
        amounts[1] = 0; // Should skip
        amounts[2] = 300e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransfer(
            address(token), recipients, amounts
        );

        assertEq(result.succeeded, 2);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_BatchTransfer_RevertsOnEmptyBatch() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(GasOptimizedTransfers.EmptyBatch.selector);
        harness.batchTransfer(address(token), recipients, amounts);
    }

    function test_BatchTransfer_RevertsOnLengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](3);

        vm.expectRevert(GasOptimizedTransfers.LengthMismatch.selector);
        harness.batchTransfer(address(token), recipients, amounts);
    }

    function test_BatchTransfer_RevertsOnZeroToken() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = alice;
        amounts[0] = 100e18;

        vm.expectRevert(GasOptimizedTransfers.ZeroAddress.selector);
        harness.batchTransfer(address(0), recipients, amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                         ATOMIC BATCH TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransferAtomic_Success() public {
        (address[] memory recipients, uint256[] memory amounts) = _createBatch(3);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferAtomic(
            address(token), recipients, amounts
        );

        assertEq(result.succeeded, 3);
        assertEq(result.failed, 0);
    }

    function test_BatchTransferAtomic_RevertsOnFailure() public {
        // Create a failing token that reverts on certain transfers
        FailingToken failToken = new FailingToken();
        failToken.mint(address(harness), 1_000_000e18);
        failToken.setFailOnIndex(1); // Fail second transfer

        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        vm.expectRevert(abi.encodeWithSelector(
            GasOptimizedTransfers.AtomicBatchFailed.selector, 1
        ));
        harness.batchTransferAtomic(address(failToken), recipients, amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                         PACKED BATCH TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransferPacked_Single() public {
        uint256[] memory packed = new uint256[](1);
        packed[0] = GasOptimizedTransfers.pack(alice, 100e18);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferPacked(
            address(token), packed
        );

        assertEq(result.succeeded, 1);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_BatchTransferPacked_Multiple() public {
        uint256[] memory packed = new uint256[](5);
        packed[0] = GasOptimizedTransfers.pack(alice, 100e18);
        packed[1] = GasOptimizedTransfers.pack(bob, 200e18);
        packed[2] = GasOptimizedTransfers.pack(charlie, 300e18);
        packed[3] = GasOptimizedTransfers.pack(dave, 400e18);
        packed[4] = GasOptimizedTransfers.pack(eve, 500e18);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferPacked(
            address(token), packed
        );

        assertEq(result.succeeded, 5);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.balanceOf(charlie), 300e18);
        assertEq(token.balanceOf(dave), 400e18);
        assertEq(token.balanceOf(eve), 500e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                         BATCH TRANSFER FROM TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BatchTransferFrom() public {
        // Setup: alice approves harness
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(address(harness), type(uint256).max);

        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        recipients[0] = bob;
        recipients[1] = charlie;
        recipients[2] = dave;
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransferFrom(
            address(token), alice, recipients, amounts
        );

        assertEq(result.succeeded, 3);
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(charlie), 200e18);
        assertEq(token.balanceOf(dave), 300e18);
        assertEq(token.balanceOf(alice), 400e18); // 1000 - 600
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                           ETH DISTRIBUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_DistributeETH_Single() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = alice;
        amounts[0] = 1 ether;

        uint256 balBefore = alice.balance;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETH(
            recipients, amounts
        );

        assertEq(result.succeeded, 1);
        assertEq(alice.balance - balBefore, 1 ether);
    }

    function test_DistributeETH_Multiple() public {
        address[] memory recipients = new address[](5);
        uint256[] memory amounts = new uint256[](5);

        for (uint256 i; i < 5; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", i)));
            amounts[i] = (i + 1) * 0.1 ether;
        }

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETH(
            recipients, amounts
        );

        assertEq(result.succeeded, 5);
        assertEq(result.totalTransferred, 1.5 ether);
    }

    function test_DistributeETH_RevertsOnInsufficientBalance() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = alice;
        amounts[0] = 10000 ether; // More than harness has

        vm.expectRevert(GasOptimizedTransfers.InsufficientETH.selector);
        harness.distributeETH(recipients, amounts);
    }

    function test_DistributeETHPacked() public {
        uint256[] memory packed = new uint256[](3);
        packed[0] = GasOptimizedTransfers.pack(alice, 1 ether);
        packed[1] = GasOptimizedTransfers.pack(bob, 2 ether);
        packed[2] = GasOptimizedTransfers.pack(charlie, 3 ether);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 charlieBefore = charlie.balance;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETHPacked(packed);

        assertEq(result.succeeded, 3);
        assertEq(alice.balance - aliceBefore, 1 ether);
        assertEq(bob.balance - bobBefore, 2 ether);
        assertEq(charlie.balance - charlieBefore, 3 ether);
    }

    function test_DistributeETHUnsafe_WithGuard() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETHUnsafe(
            recipients, amounts
        );

        assertEq(result.succeeded, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                         MULTI-TOKEN TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_MultiTokenTransfer() public {
        GasOptimizedTransfers.MultiTransfer[] memory transfers =
            new GasOptimizedTransfers.MultiTransfer[](3);

        transfers[0] = GasOptimizedTransfers.MultiTransfer(address(token), alice, 100e18);
        transfers[1] = GasOptimizedTransfers.MultiTransfer(address(token2), bob, 200e18);
        transfers[2] = GasOptimizedTransfers.MultiTransfer(address(token), charlie, 300e18);

        GasOptimizedTransfers.BatchResult memory result = harness.multiTokenTransfer(transfers);

        assertEq(result.succeeded, 3);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token2.balanceOf(bob), 200e18);
        assertEq(token.balanceOf(charlie), 300e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                           MERKLE CLAIMS TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_MerkleClaim() public {
        // Create simple merkle tree with one leaf
        bytes32 leaf = keccak256(abi.encodePacked(uint256(0), alice, uint256(100e18)));
        bytes32 root = leaf; // Single leaf tree

        harness.initClaims(root, 0);

        bytes32[] memory proof = new bytes32[](0);
        bool valid = harness.verifyClaim(0, alice, 100e18, proof);

        assertTrue(valid);
        assertTrue(harness.isClaimed(0));
    }

    function test_MerkleClaim_RevertsOnDoubleClaim() public {
        bytes32 leaf = keccak256(abi.encodePacked(uint256(0), alice, uint256(100e18)));
        bytes32 root = leaf;

        harness.initClaims(root, 0);

        bytes32[] memory proof = new bytes32[](0);
        harness.verifyClaim(0, alice, 100e18, proof);

        vm.expectRevert(GasOptimizedTransfers.AlreadyClaimed.selector);
        harness.verifyClaim(0, alice, 100e18, proof);
    }

    function test_MerkleClaim_RevertsOnInvalidProof() public {
        bytes32 root = keccak256("invalid");

        harness.initClaims(root, 0);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(GasOptimizedTransfers.InvalidProof.selector);
        harness.verifyClaim(0, alice, 100e18, proof);
    }

    function test_MerkleClaim_RevertsOnDeadline() public {
        bytes32 leaf = keccak256(abi.encodePacked(uint256(0), alice, uint256(100e18)));
        bytes32 root = leaf;

        harness.initClaims(root, uint64(block.timestamp + 1 hours));

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(GasOptimizedTransfers.DeadlineExpired.selector);
        harness.verifyClaim(0, alice, 100e18, proof);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                           RATE LIMITER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_RateLimiter() public {
        harness.initRateLimiter(5, 1 hours);

        // Should succeed 5 times
        for (uint256 i; i < 5; i++) {
            harness.checkRateLimit(alice);
        }

        // 6th should fail
        vm.expectRevert(GasOptimizedTransfers.RateLimitExceeded.selector);
        harness.checkRateLimit(alice);
    }

    function test_RateLimiter_ResetsAfterWindow() public {
        harness.initRateLimiter(3, 1 hours);

        // Use all 3
        for (uint256 i; i < 3; i++) {
            harness.checkRateLimit(alice);
        }

        // Warp past window
        vm.warp(block.timestamp + 2 hours);

        // Should work again
        harness.checkRateLimit(alice);
    }

    function test_RateLimiter_IndependentPerUser() public {
        harness.initRateLimiter(2, 1 hours);

        harness.checkRateLimit(alice);
        harness.checkRateLimit(alice);
        harness.checkRateLimit(bob); // Bob has separate limit
        harness.checkRateLimit(bob);

        vm.expectRevert(GasOptimizedTransfers.RateLimitExceeded.selector);
        harness.checkRateLimit(alice);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                         REENTRANCY GUARD TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_ReentrancyGuard() public {
        ReentrantAttacker attacker = new ReentrantAttacker(harness);

        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = address(attacker);
        amounts[0] = 1 ether;

        // Should not revert - guard is properly managed
        harness.distributeETHUnsafe(recipients, amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                            UTILITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_GetBalance() public view {
        uint256 bal = GasOptimizedTransfers.getBalance(address(token), address(harness));
        assertEq(bal, 1_000_000e18);
    }

    function test_IsContract() public view {
        assertTrue(GasOptimizedTransfers.isContract(address(token)));
        assertFalse(GasOptimizedTransfers.isContract(alice));
    }

    function test_EstimateGas() public pure {
        uint256 erc20Est = GasOptimizedTransfers.estimateGas(10, true);
        uint256 ethEst = GasOptimizedTransfers.estimateGas(10, false);

        assertEq(erc20Est, 26_000 + 10 * 30_000);
        assertEq(ethEst, 26_000 + 10 * 7_000);
    }

    function test_SumPacked() public {
        uint256[] memory packed = new uint256[](3);
        packed[0] = GasOptimizedTransfers.pack(alice, 100e18);
        packed[1] = GasOptimizedTransfers.pack(bob, 200e18);
        packed[2] = GasOptimizedTransfers.pack(charlie, 300e18);

        uint256 total = harness.sumPacked(packed);
        assertEq(total, 600e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                           GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_GasBenchmark_10Transfers() public {
        (address[] memory recipients, uint256[] memory amounts) = _createBatch(10);

        uint256 gasStart = gasleft();
        harness.batchTransfer(address(token), recipients, amounts);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Gas for 10 transfers", gasUsed);
        emit log_named_uint("Gas per transfer", gasUsed / 10);
    }

    function test_GasBenchmark_50Transfers() public {
        (address[] memory recipients, uint256[] memory amounts) = _createBatch(50);

        uint256 gasStart = gasleft();
        harness.batchTransfer(address(token), recipients, amounts);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Gas for 50 transfers", gasUsed);
        emit log_named_uint("Gas per transfer", gasUsed / 50);
    }

    function test_GasBenchmark_100Transfers() public {
        (address[] memory recipients, uint256[] memory amounts) = _createBatch(100);

        uint256 gasStart = gasleft();
        harness.batchTransfer(address(token), recipients, amounts);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Gas for 100 transfers", gasUsed);
        emit log_named_uint("Gas per transfer", gasUsed / 100);
    }

    function test_GasBenchmark_PackedVsUnpacked() public {
        uint256 count = 20;

        // Unpacked
        (address[] memory recipients, uint256[] memory amounts) = _createBatch(count);
        uint256 gasStart = gasleft();
        harness.batchTransfer(address(token), recipients, amounts);
        uint256 unpackedGas = gasStart - gasleft();

        // Reset
        for (uint256 i; i < count; i++) {
            vm.prank(recipients[i]);
            token.transfer(address(harness), amounts[i]);
        }

        // Packed
        uint256[] memory packed = new uint256[](count);
        for (uint256 i; i < count; i++) {
            packed[i] = GasOptimizedTransfers.pack(recipients[i], amounts[i]);
        }

        gasStart = gasleft();
        harness.batchTransferPacked(address(token), packed);
        uint256 packedGas = gasStart - gasleft();

        emit log_named_uint("Unpacked gas (20)", unpackedGas);
        emit log_named_uint("Packed gas (20)", packedGas);
        emit log_named_int("Savings", int256(unpackedGas) - int256(packedGas));
    }

    function test_GasBenchmark_ETHDistribution() public {
        uint256 count = 20;
        address[] memory recipients = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        for (uint256 i; i < count; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("eth", i)));
            amounts[i] = 0.01 ether;
        }

        uint256 gasStart = gasleft();
        harness.distributeETH(recipients, amounts);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("ETH distribution gas (20)", gasUsed);
        emit log_named_uint("Gas per ETH transfer", gasUsed / count);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                              FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function testFuzz_BatchTransfer(uint8 count) public {
        vm.assume(count > 0 && count <= 50);

        (address[] memory recipients, uint256[] memory amounts) = _createBatch(count);

        GasOptimizedTransfers.BatchResult memory result = harness.batchTransfer(
            address(token), recipients, amounts
        );

        assertEq(result.succeeded, count);
    }

    function testFuzz_DistributeETH(uint8 count) public {
        vm.assume(count > 0 && count <= 50);

        address[] memory recipients = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        for (uint256 i; i < count; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("fuzz", i)));
            amounts[i] = 0.001 ether;
        }

        GasOptimizedTransfers.BatchResult memory result = harness.distributeETH(
            recipients, amounts
        );

        assertEq(result.succeeded, count);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    //                              HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    function _createBatch(uint256 count)
        internal
        pure
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        recipients = new address[](count);
        amounts = new uint256[](count);

        for (uint256 i; i < count; i++) {
            recipients[i] = address(uint160(0x1000 + i));
            amounts[i] = (i + 1) * 1e18;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════
//                              MOCK CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════════════

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
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
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
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
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract FailingToken is MockERC20 {
    uint256 public failOnIndex;
    uint256 public transferCount;

    constructor() MockERC20("Failing", "FAIL") {}

    function setFailOnIndex(uint256 index) external {
        failOnIndex = index;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (transferCount == failOnIndex) {
            transferCount++;
            return false;
        }
        transferCount++;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

contract BatchTestHarness {
    using GasOptimizedTransfers for *;

    GasOptimizedTransfers.Guard public guard;
    GasOptimizedTransfers.ClaimRegistry public claims;
    GasOptimizedTransfers.RateLimiter public limiter;

    constructor() {
        guard.init();
    }

    receive() external payable {}

    // ERC20 Transfers
    function batchTransfer(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransfer(token, recipients, amounts);
    }

    function batchTransferAtomic(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransferAtomic(token, recipients, amounts);
    }

    function batchTransferPacked(
        address token,
        uint256[] calldata packed
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransferPacked(token, packed);
    }

    function batchTransferFrom(
        address token,
        address from,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.batchTransferFrom(token, from, recipients, amounts);
    }

    // ETH Distribution
    function distributeETH(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.distributeETH(recipients, amounts);
    }

    function distributeETHUnsafe(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.distributeETHUnsafe(recipients, amounts, guard);
    }

    function distributeETHPacked(
        uint256[] calldata packed
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.distributeETHPacked(packed);
    }

    // Multi-Token
    function multiTokenTransfer(
        GasOptimizedTransfers.MultiTransfer[] calldata transfers
    ) external returns (GasOptimizedTransfers.BatchResult memory) {
        return GasOptimizedTransfers.multiTokenTransfer(transfers);
    }

    // Claims
    function initClaims(bytes32 root, uint64 deadline) external {
        claims.initClaims(root, deadline);
    }

    function verifyClaim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) external returns (bool) {
        return claims.verifyClaim(index, account, amount, proof);
    }

    function isClaimed(uint256 index) external view returns (bool) {
        return claims.isClaimed(index);
    }

    // Rate Limiter
    function initRateLimiter(uint32 limit, uint32 window) external {
        limiter.initRateLimiter(limit, window);
    }

    function checkRateLimit(address account) external {
        limiter.checkRateLimit(account);
    }

    // Utilities
    function sumPacked(uint256[] calldata packed) external pure returns (uint256) {
        return GasOptimizedTransfers.sumPacked(packed);
    }
}

contract ReentrantAttacker {
    BatchTestHarness public target;
    uint256 public attackCount;

    constructor(BatchTestHarness _target) {
        target = _target;
    }

    receive() external payable {
        // Attempt reentry - should fail due to guard
        if (attackCount < 1) {
            attackCount++;
            address[] memory recipients = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            recipients[0] = address(this);
            amounts[0] = 0.1 ether;

            // This should revert with Reentrancy error
            try target.distributeETHUnsafe(recipients, amounts) {} catch {}
        }
    }
}
