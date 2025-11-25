# Security Fixes Test Plan

**Date:** 2025-11-25
**Branch:** `claude/document-audit-findings-01MxNAa9tEG4Uy1A3KJzp7dT`
**Purpose:** Verify all 13 security fixes work correctly

---

## 🎯 Test Execution Command

```bash
forge test --gas-report -vvv
```

For specific test files:
```bash
forge test --match-path test/GasOptimizedTransfersTest.t.sol -vvv
forge test --match-path test/LibraryTests.t.sol -vvv
forge test --match-path test/IntegrationTests.t.sol -vvv
```

---

## ✅ CRITICAL Priority Tests

### 1. ReentrancyGuardLib Bitwise Operations (CRITICAL)

**File:** `src/utils/ReentrancyGuardLib.sol`
**Lines Fixed:** 157, 187, 199

**Test Cases:**

```solidity
// Test 1: Verify function-specific guards work correctly
function testFunctionGuardsPreventsReentrancy() public {
    // Setup contract with AdvancedGuard
    // Set functionFlag for function A
    // Try to re-enter function A from within function A
    // Should revert with CrossFunctionReentrancy
}

// Test 2: Verify isFunctionGuardActive returns correct value
function testIsFunctionGuardActiveReturnsTrue() public {
    // Set guard for functionFlag = 0x01
    // Call isFunctionGuardActive(0x01)
    // Should return true
}

// Test 3: Verify disallowed combination checks work
function testDisallowedCombinationPreventsAccess() public {
    // Set active guards: 0x01 | 0x02 = 0x03
    // Try function with disallowedFlags = 0x04
    // Should succeed
    // Try function with disallowedFlags = 0x02
    // Should revert
}

// Test 4: Bitwise operation edge cases
function testBitwiseOperationsEdgeCases() public {
    // Test with functionFlag = 0 (should handle gracefully)
    // Test with functionFlag = type(uint256).max
    // Test multiple flags set simultaneously
}
```

**Expected Result:** All function-specific reentrancy guards must work correctly.

**Priority:** 🔴 CRITICAL - Test FIRST

---

### 2. Assembly Overflow in Batch Transfers (HIGH)

**File:** `src/utils/GasOptimizedTransfers.sol`
**Functions:** `batchTransfer()`, `batchTransferFrom()`, `batchTransferPacked()`

**Test Cases:**

```solidity
// Test 1: Overflow with two large amounts
function testBatchTransferOverflowReverts() public {
    address[] memory recipients = new address[](2);
    uint256[] memory amounts = new uint256[](2);

    recipients[0] = address(0x1);
    recipients[1] = address(0x2);
    amounts[0] = type(uint256).max / 2 + 1;
    amounts[1] = type(uint256).max / 2 + 1;

    // Should revert due to totalAmount overflow in Solidity calculation
    vm.expectRevert();
    GasOptimizedTransfers.batchTransfer(token, recipients, amounts, guard);
}

// Test 2: Maximum safe batch transfer
function testBatchTransferMaxSafeAmount() public {
    address[] memory recipients = new address[](2);
    uint256[] memory amounts = new uint256[](2);

    recipients[0] = address(0x1);
    recipients[1] = address(0x2);
    amounts[0] = type(uint256).max / 2;
    amounts[1] = type(uint256).max / 2;

    // Should succeed - no overflow
    GasOptimizedTransfers.batchTransfer(token, recipients, amounts, guard);
}

// Test 3: batchTransferFrom overflow
function testBatchTransferFromOverflow() public {
    // Same as above but for batchTransferFrom
    // Should revert on overflow
}

// Test 4: batchTransferPacked overflow
function testBatchTransferPackedOverflow() public {
    uint256[] memory packed = new uint256[](2);
    // Pack (address, amount) where amounts overflow
    packed[0] = packAddressAmount(address(0x1), type(uint256).max / 2 + 1);
    packed[1] = packAddressAmount(address(0x2), type(uint256).max / 2 + 1);

    vm.expectRevert();
    GasOptimizedTransfers.batchTransferPacked(token, packed);
}
```

**Expected Result:** All overflow attempts must revert.

**Priority:** 🔴 HIGH

---

### 3. Assembly Overflow in ETH Distribution (HIGH)

**File:** `src/utils/GasOptimizedTransfers.sol`
**Functions:** `distributeETH()`, `distributeETHUnsafe()`, `distributeETHPacked()`

**Test Cases:**

```solidity
// Test 1: ETH distribution with overflow amounts
function testDistributeETHOverflowReverts() public {
    address[] memory recipients = new address[](2);
    uint256[] memory amounts = new uint256[](2);

    recipients[0] = address(0x1);
    recipients[1] = address(0x2);
    amounts[0] = type(uint256).max - 100;
    amounts[1] = 200;

    // First phase: totalRequired calculated in Solidity (should overflow)
    vm.expectRevert();
    GasOptimizedTransfers.distributeETH(recipients, amounts);
}

// Test 2: distributeETHUnsafe with overflow
function testDistributeETHUnsafeOverflow() public {
    // Test assembly overflow check in totalSent accumulation
    // Setup recipients that would cause overflow in assembly
    // NEW FIX: Should revert with assembly overflow check
}

// Test 3: distributeETHPacked with overflow
function testDistributeETHPackedOverflow() public {
    uint256[] memory packed = new uint256[](2);
    packed[0] = packAddressAmount(address(0x1), type(uint256).max - 50);
    packed[1] = packAddressAmount(address(0x2), 100);

    vm.expectRevert();
    GasOptimizedTransfers.distributeETHPacked(packed);
}

// Test 4: Verify totalSent assembly overflow check
function testTotalSentAssemblyOverflowCheck() public {
    // Create scenario where totalSent would overflow in assembly
    // Ensure revert occurs at the assembly level
    // This tests lines 663-666, 731-734, 790-793
}
```

**Expected Result:** All overflow checks (both Solidity and assembly) must work.

**Priority:** 🔴 HIGH

---

### 4. Gas Underflow in distributeETHUnsafe (HIGH)

**File:** `src/utils/GasOptimizedTransfers.sol:722-726`

**Test Cases:**

```solidity
// Test 1: Low gas scenario (< 10000 gas remaining)
function testDistributeETHUnsafeLowGas() public {
    address[] memory recipients = new address[](1);
    uint256[] memory amounts = new uint256[](1);

    recipients[0] = address(0x1);
    amounts[0] = 0.1 ether;

    // Set gas limit to ensure low gas during call
    // Should NOT underflow to type(uint256).max
    // Should forward available gas safely
    uint256 gasLimit = 15000;
    (bool success,) = address(this).call{gas: gasLimit}(
        abi.encodeCall(this.distributeETHUnsafe, (recipients, amounts, guard))
    );

    // Should succeed without underflow
    assertTrue(success);
}

// Test 2: Gas exactly at GAS_RESERVE (10000)
function testDistributeETHUnsafeAtReserve() public {
    // Test with exactly GAS_RESERVE gas remaining
    // Should forward 0 gas (or minimal gas)
    // Should NOT underflow
}

// Test 3: Gas below GAS_RESERVE
function testDistributeETHUnsafeBelowReserve() public {
    // Test with < GAS_RESERVE gas
    // NEW FIX: Should forward all available gas (no underflow)
    // OLD BUG: Would have underflowed to uint256.max
}
```

**Expected Result:** No gas underflow, safe handling of low gas scenarios.

**Priority:** 🔴 HIGH

---

### 5. Missing Return Data Size Check (HIGH)

**File:** `src/utils/GasOptimizedTransfers.sol:597-602`

**Test Cases:**

```solidity
// Test 1: Malicious token returns < 32 bytes
function testBatchTransferPackedInvalidReturnSize() public {
    // Deploy malicious token that returns only 16 bytes
    MaliciousToken malicious = new MaliciousToken(16); // returns 16 bytes

    uint256[] memory packed = new uint256[](1);
    packed[0] = packAddressAmount(address(0x1), 100);

    // NEW FIX: Should detect size < 0x20 and mark as failed
    BatchResult memory result = GasOptimizedTransfers.batchTransferPacked(
        address(malicious),
        packed
    );

    // Transfer should be marked as failed
    assertEq(result.failed, 1);
    assertEq(result.succeeded, 0);
}

// Test 2: Token returns exactly 32 bytes with false
function testBatchTransferPackedValidSizeReturnsFalse() public {
    // Token returns 32 bytes = false (0)
    // Should correctly detect false return
}

// Test 3: Token returns no data (0 bytes)
function testBatchTransferPackedNoReturnData() public {
    // Some tokens return nothing on success
    // Should succeed (empty returndatasize is valid)
}

// Test 4: Compare with other batch functions
function testAllBatchFunctionsHandleReturnDataConsistently() public {
    // Verify batchTransfer, batchTransferFrom, and batchTransferPacked
    // all handle return data size checks consistently
}
```

**Expected Result:** Invalid return data size must be detected and handled.

**Priority:** 🔴 HIGH

---

### 6. Broken Self-Approval in CrossChainDEXRouter (HIGH)

**File:** `src/dex/CrossChainDEXRouter.sol:301-311`

**Test Cases:**

```solidity
// Test 1: Cross-chain swap with source-chain swap
function testCrossChainSwapWithSourceSwap() public {
    // Setup: Token A on source chain, need to swap to bridge token B
    CrossChainSwapParams memory params = CrossChainSwapParams({
        tokenIn: address(tokenA),
        tokenOut: address(tokenC), // on destination chain
        amountIn: 1000e18,
        minAmountOut: 900e18,
        recipient: user,
        srcChainId: 1,
        dstChainId: 42161,
        swapData: abi.encode(address(bridgeTokenB), 950e18) // swap to bridge token
    });

    // NEW FIX: Should use internal _executeSwapRoute
    // OLD BUG: Used this.swap() with self-approval (broken)

    bytes32 txId = router.initiateCrossChainSwap(params);

    // Verify swap executed correctly
    // Verify bridge token received by router
    assertGt(bridgeTokenB.balanceOf(address(router)), 0);
}

// Test 2: Cross-chain swap without source-chain swap
function testCrossChainSwapNoSourceSwap() public {
    // If swapData is empty, should skip source swap
    // Should work without any swap
}

// Test 3: Verify no self-approval
function testNoSelfApprovalOccurs() public {
    // Track approval events
    // Ensure no approval from router to router
}

// Test 4: Verify internal execution path
function testInternalExecutionPath() public {
    // Verify _executeSwapRoute is called
    // Verify tokens stay in contract throughout
}
```

**Expected Result:** Cross-chain swaps with source swaps must work without self-approval.

**Priority:** 🔴 HIGH

---

### 7. Intent Cancellation Griefing (HIGH)

**File:** `src/intents/IntentSettlement.sol:403-406`

**Test Cases:**

```solidity
// Test 1: Cannot cancel unseen intent
function testCannotCancelUnseenIntent() public {
    bytes32 intentId = keccak256("fake_intent");

    // Attacker tries to cancel never-seen intent
    vm.prank(attacker);
    vm.expectRevert(IntentSettlement.Unauthorized.selector);
    settlement.cancelIntent(intentId);

    // NEW FIX: Should revert (maker not stored)
    // OLD BUG: Would have allowed attacker to claim ownership
}

// Test 2: Can cancel seen intent
function testCanCancelSeenIntent() public {
    // Submit intent (stores maker)
    Intent memory intent = createTestIntent();
    settlement.submitIntent(intent, signature);

    bytes32 intentId = settlement.getIntentHash(intent);

    // Maker can now cancel
    vm.prank(intent.maker);
    settlement.cancelIntent(intentId);

    // Verify cancelled
    (FillStatus status,,,) = settlement.fills(intentId);
    assertEq(uint8(status), uint8(FillStatus.CANCELLED));
}

// Test 3: Cannot cancel other's intent
function testCannotCancelOthersIntent() public {
    Intent memory intent = createTestIntent();
    settlement.submitIntent(intent, signature);

    bytes32 intentId = settlement.getIntentHash(intent);

    // Attacker tries to cancel
    vm.prank(attacker);
    vm.expectRevert(IntentSettlement.Unauthorized.selector);
    settlement.cancelIntent(intentId);
}

// Test 4: Use cancelIntentWithProof for unseen
function testCancelIntentWithProofForUnseen() public {
    // Create intent but don't submit
    Intent memory intent = createTestIntent();
    bytes memory signature = signIntent(makerPrivateKey, intent);

    // Cancel with proof (should work for unseen)
    settlement.cancelIntentWithProof(intent, signature);

    bytes32 intentId = settlement.getIntentHash(intent);
    (FillStatus status,,,) = settlement.fills(intentId);
    assertEq(uint8(status), uint8(FillStatus.CANCELLED));
}
```

**Expected Result:** Griefing attack must be prevented, only makers can cancel.

**Priority:** 🔴 HIGH

---

## ✅ MEDIUM Priority Tests

### 8. Weight Validation in MathUtils (MEDIUM)

**File:** `src/utils/MathUtils.sol:391`

**Test Cases:**

```solidity
// Test 1: Invalid weight (weightA > totalWeight)
function testWeightedAvgInvalidWeight() public {
    uint256 a = 100;
    uint256 b = 200;
    uint256 weightA = 150;
    uint256 totalWeight = 100;

    vm.expectRevert(MathUtils.InvalidInput.selector);
    MathUtils.weightedAvg(a, b, weightA, totalWeight);
}

// Test 2: Valid edge case (weightA == totalWeight)
function testWeightedAvgMaxWeight() public {
    uint256 result = MathUtils.weightedAvg(100, 200, 100, 100);
    assertEq(result, 100); // Should return 'a'
}

// Test 3: Zero weight
function testWeightedAvgZeroWeight() public {
    uint256 result = MathUtils.weightedAvg(100, 200, 0, 100);
    assertEq(result, 200); // Should return 'b'
}

// Test 4: Integration with oracle price aggregation
function testOraclePriceAggregationWithInvalidWeights() public {
    // Test oracle using weightedAvg with invalid weights
    // Should revert at MathUtils level
}
```

**Expected Result:** Invalid weights must be rejected.

**Priority:** 🟡 MEDIUM

---

### 9. Dutch Auction Parameter Validation (MEDIUM)

**File:** `src/intents/IntentSettlement.sol:544`

**Test Cases:**

```solidity
// Test 1: Invalid Dutch auction (startAmountOut < minAmountOut)
function testDutchAuctionInvalidParameters() public {
    Intent memory intent = Intent({
        intentType: IntentType.DUTCH,
        maker: maker,
        tokenIn: address(tokenA),
        tokenOut: address(tokenB),
        amountIn: 1000e18,
        minAmountOut: 2000e18,
        startAmountOut: 1500e18, // INVALID: < minAmountOut
        deadline: block.timestamp + 1 hours,
        nonce: 1
    });

    bytes memory signature = signIntent(makerPrivateKey, intent);

    vm.expectRevert(IntentSettlement.InvalidIntent.selector);
    settlement.submitIntent(intent, signature);
}

// Test 2: Valid Dutch auction
function testDutchAuctionValidParameters() public {
    Intent memory intent = Intent({
        intentType: IntentType.DUTCH,
        startAmountOut: 2000e18,  // Valid: > minAmountOut
        minAmountOut: 1500e18,
        // ... other params
    });

    // Should succeed
    settlement.submitIntent(intent, signature);
}

// Test 3: Dutch auction price decay
function testDutchAuctionPriceDecay() public {
    // Submit valid Dutch auction
    // Fast forward time
    // Verify price decays correctly without underflow
}

// Test 4: Edge case (startAmountOut == minAmountOut)
function testDutchAuctionNoDecay() public {
    // When start == min, no decay occurs
    // Should be valid
}
```

**Expected Result:** Invalid auction parameters must be rejected.

**Priority:** 🟡 MEDIUM

---

### 10. Pyth Exponent Validation (MEDIUM)

**File:** `src/oracles/SmartOracleAggregator.sol:335-344`

**Test Cases:**

```solidity
// Test 1: Positive exponent too large (> 77)
function testPythExponentOverflow() public {
    IPythPriceFeed.Price memory price = IPythPriceFeed.Price({
        price: 100,
        expo: 78, // Too large! 10^78 > uint256.max
        publishTime: block.timestamp
    });

    // Mock Pyth to return this price
    vm.mockCall(
        pythOracle,
        abi.encodeWithSelector(IPythPriceFeed.getPriceNoOlderThan.selector),
        abi.encode(price)
    );

    vm.expectRevert(SmartOracleAggregator.InvalidPrice.selector);
    oracle.getPrice(baseToken, quoteToken);
}

// Test 2: Negative exponent too large (< -255)
function testPythExponentTruncation() public {
    IPythPriceFeed.Price memory price = IPythPriceFeed.Price({
        price: 100,
        expo: -300, // abs(-300) = 300 > 255 (uint8 max)
        publishTime: block.timestamp
    });

    vm.mockCall(pythOracle, ...);

    vm.expectRevert(SmartOracleAggregator.InvalidPrice.selector);
    oracle.getPrice(baseToken, quoteToken);
}

// Test 3: Valid positive exponent
function testPythValidPositiveExponent() public {
    // expo = 18 (common for ETH prices)
    // Should succeed
}

// Test 4: Valid negative exponent
function testPythValidNegativeExponent() public {
    // expo = -8 (common for USD prices)
    // Should succeed
}

// Test 5: Edge cases
function testPythExponentEdgeCases() public {
    // Test expo = 0
    // Test expo = 77 (max valid positive)
    // Test expo = -255 (max valid negative)
}
```

**Expected Result:** Invalid exponents must be rejected, valid ones accepted.

**Priority:** 🟡 MEDIUM

---

### 11. Hop Length Limit (MEDIUM)

**File:** `src/dex/CrossChainDEXRouter.sol:225`

**Test Cases:**

```solidity
// Test 1: Exceeds MAX_HOPS (> 5)
function testMultiHopSwapExceedsLimit() public {
    // Create 6-hop swap path
    SwapRoute[] memory hops = new SwapRoute[](6);
    for (uint i = 0; i < 6; i++) {
        hops[i] = SwapRoute({
            tokenIn: address(tokens[i]),
            tokenOut: address(tokens[i+1]),
            dex: DEXType.UNISWAP_V2,
            amountIn: 1000e18,
            extraData: ""
        });
    }

    MultiHopSwap memory params = MultiHopSwap({
        hops: hops,
        minAmountOut: 900e18,
        deadline: block.timestamp + 1 hours
    });

    vm.expectRevert(CrossChainDEXRouter.InvalidRoute.selector);
    router.multiHopSwap(params, user);
}

// Test 2: Exactly MAX_HOPS (5)
function testMultiHopSwapAtLimit() public {
    // Create 5-hop swap (should succeed)
    SwapRoute[] memory hops = new SwapRoute[](5);
    // ... setup

    // Should succeed
    router.multiHopSwap(params, user);
}

// Test 3: Single hop
function testSingleHopSwap() public {
    // 1 hop should always work
}

// Test 4: Gas consumption comparison
function testHopGasConsumption() public {
    // Verify 5 hops doesn't exceed reasonable gas limits
    // Measure gas for 1, 2, 3, 4, 5 hops
}
```

**Expected Result:** > 5 hops must be rejected, ≤ 5 must succeed.

**Priority:** 🟡 MEDIUM

---

### 12. Empty Routes Array Validation (MEDIUM)

**File:** `src/dex/CrossChainDEXRouter.sol:207,308`

**Test Cases:**

```solidity
// Test 1: _getOptimalQuote returns empty routes
function testSwapWithEmptyRoutes() public {
    // Mock _getOptimalQuote to return empty routes array
    // This simulates no liquidity found

    vm.mockCall(
        address(router),
        abi.encodeWithSelector(router._getOptimalQuote.selector),
        abi.encode(SwapQuote({
            amountOut: 0,
            routes: new SwapRoute[](0) // EMPTY!
        }))
    );

    vm.expectRevert(CrossChainDEXRouter.InvalidRoute.selector);
    router.swap(tokenIn, tokenOut, 1000e18, 900e18, user, deadline);
}

// Test 2: Cross-chain swap with empty routes
function testCrossChainSwapEmptyRoutes() public {
    // Mock _getOptimalQuote in initiateCrossChainSwap
    // Should revert before accessing routes[0]

    vm.expectRevert(CrossChainDEXRouter.InvalidRoute.selector);
    router.initiateCrossChainSwap(params);
}

// Test 3: Valid routes array
function testSwapWithValidRoutes() public {
    // Normal case: routes has at least 1 element
    // Should succeed
}
```

**Expected Result:** Empty routes must be rejected before array access.

**Priority:** 🟡 MEDIUM

---

## 🔧 Integration Tests

### Test 1: End-to-End Cross-Chain Swap
```solidity
function testE2ECrossChainSwapWithAllFixes() public {
    // Test combines multiple fixes:
    // - Routes array validation (MEDIUM-008)
    // - Self-approval fix (HIGH-005)
    // - Hop length limit (MEDIUM-007)

    // Execute complete cross-chain swap flow
    // Verify all validations work correctly
}
```

### Test 2: Batch Operations Under Stress
```solidity
function testBatchOperationsStressTest() public {
    // Test combines:
    // - Overflow protection (HIGH-001)
    // - Return data size check (HIGH-004)
    // - Gas handling (HIGH-002)

    // Execute large batches near limits
    // Verify all protections activate correctly
}
```

### Test 3: Oracle Price Aggregation
```solidity
function testOraclePriceAggregationWithAllValidations() public {
    // Test combines:
    // - Weight validation (MEDIUM-002)
    // - Pyth exponent validation (MEDIUM-003)

    // Aggregate prices from multiple sources
    // Verify all validations work
}
```

### Test 4: Intent Settlement Flow
```solidity
function testIntentSettlementFullFlow() public {
    // Test combines:
    // - Cancellation griefing fix (HIGH-006)
    // - Dutch auction validation (MEDIUM-004)

    // Test complete intent lifecycle
    // Verify all protections work
}
```

---

## 📊 Expected Test Results

### Success Criteria

**All tests must pass with:**
- ✅ No reverts in valid scenarios
- ✅ Correct reverts in invalid scenarios
- ✅ Gas usage within reasonable limits
- ✅ No memory corruption
- ✅ No underflow/overflow in protected code

### Failure Investigation

If any test fails:
1. Check if new validation is too strict
2. Verify test setup is correct
3. Review fix implementation
4. Check for edge cases not considered

---

## 🚀 Running the Tests

### Full Test Suite
```bash
# Run all tests with verbose output
forge test -vvv

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage
```

### Specific Test Categories
```bash
# Test only HIGH priority fixes
forge test --match-test "testHIGH" -vvv

# Test only MEDIUM priority fixes
forge test --match-test "testMEDIUM" -vvv

# Test specific contract
forge test --match-path test/GasOptimizedTransfersTest.t.sol -vvv
```

### Debug Failing Tests
```bash
# Run specific test with max verbosity
forge test --match-test testBatchTransferOverflowReverts -vvvv

# Show trace for specific test
forge test --match-test testBatchTransferOverflowReverts --debug
```

---

## 📝 Test Coverage Goals

Target coverage for modified files:
- **src/utils/GasOptimizedTransfers.sol**: > 95%
- **src/utils/ReentrancyGuardLib.sol**: > 95%
- **src/dex/CrossChainDEXRouter.sol**: > 90%
- **src/intents/IntentSettlement.sol**: > 90%
- **src/oracles/SmartOracleAggregator.sol**: > 85%
- **src/utils/MathUtils.sol**: > 95%

---

## ✅ Sign-Off Checklist

After testing:
- [ ] All CRITICAL tests pass
- [ ] All HIGH tests pass
- [ ] All MEDIUM tests pass
- [ ] Integration tests pass
- [ ] Coverage meets targets
- [ ] Gas usage is reasonable
- [ ] No regressions in existing tests
- [ ] Edge cases handled correctly

---

**End of Test Plan**
