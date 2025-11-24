// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/utils/ValidatorsLib.sol";
import "../src/utils/HardenedSecurityLib.sol";
import "../src/utils/StakingLib.sol";
import "../src/utils/RewardLib.sol";
import "../src/utils/RefundersLib.sol";
import "../src/utils/SolversLib.sol";
import "../src/utils/ReturnersLib.sol";
import "../src/utils/SynergyLib.sol";

/**
 * @title LibraryTests
 * @notice Comprehensive test suite for all utility libraries
 */
contract LibraryTests is Test {
    using ValidatorsLib for *;
    using HardenedSecurityLib for *;
    using StakingLib for StakingLib.StakingPool;
    using RewardLib for *;
    using RefundersLib for RefundersLib.RefundRegistry;
    using SolversLib for *;
    using ReturnersLib for *;
    using SynergyLib for *;

    // Test accounts
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATORS LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ValidatorsLib_requireNonZeroAddress() public pure {
        ValidatorsLib.requireNonZeroAddress(address(0x1));
    }

    function test_ValidatorsLib_requireNonZeroAddress_reverts() public {
        vm.expectRevert(ValidatorsLib.ZeroAddress.selector);
        ValidatorsLib.requireNonZeroAddress(address(0));
    }

    function test_ValidatorsLib_requireNonZeroAmount() public pure {
        ValidatorsLib.requireNonZeroAmount(100);
    }

    function test_ValidatorsLib_requireNonZeroAmount_reverts() public {
        vm.expectRevert(ValidatorsLib.ZeroAmount.selector);
        ValidatorsLib.requireNonZeroAmount(0);
    }

    function test_ValidatorsLib_requireValidDeadline() public view {
        ValidatorsLib.requireValidDeadline(block.timestamp + 1 hours);
    }

    function test_ValidatorsLib_requireValidDeadline_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidatorsLib.DeadlineExpired.selector,
                block.timestamp - 1,
                block.timestamp
            )
        );
        ValidatorsLib.requireValidDeadline(block.timestamp - 1);
    }

    function test_ValidatorsLib_requireAmountInRange() public pure {
        ValidatorsLib.requireAmountInRange(50, 10, 100);
    }

    function test_ValidatorsLib_requireAmountInRange_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidatorsLib.ValueOutOfRange.selector,
                150,
                10,
                100
            )
        );
        ValidatorsLib.requireAmountInRange(150, 10, 100);
    }

    function test_ValidatorsLib_requireValidBps() public pure {
        ValidatorsLib.requireValidBps(5000); // 50%
    }

    function test_ValidatorsLib_requireValidBps_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(ValidatorsLib.InvalidPercentage.selector, 15000)
        );
        ValidatorsLib.requireValidBps(15000); // 150% - invalid
    }

    function test_ValidatorsLib_requireDifferentAddresses() public pure {
        ValidatorsLib.requireDifferentAddresses(address(0x1), address(0x2));
    }

    function test_ValidatorsLib_requireDifferentAddresses_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(ValidatorsLib.SameAddress.selector, address(0x1))
        );
        ValidatorsLib.requireDifferentAddresses(address(0x1), address(0x1));
    }

    function test_ValidatorsLib_verifyMerkleProof() public pure {
        // Create a simple merkle tree
        bytes32 leaf1 = keccak256(abi.encodePacked(address(0x1), uint256(100)));
        bytes32 leaf2 = keccak256(abi.encodePacked(address(0x2), uint256(200)));
        bytes32 root = leaf1 < leaf2
            ? keccak256(abi.encodePacked(leaf1, leaf2))
            : keccak256(abi.encodePacked(leaf2, leaf1));

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        bool valid = ValidatorsLib.verifyMerkleProof(proof, root, leaf1);
        assertTrue(valid);
    }

    function test_ValidatorsLib_validateSlippage() public pure {
        // 1% slippage tolerance, actual is within range
        ValidatorsLib.validateSlippage(1000, 995, 100); // 1% tolerance
    }

    function test_ValidatorsLib_validateSlippage_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidatorsLib.SlippageExceeded.selector,
                1000,
                900,
                100
            )
        );
        ValidatorsLib.validateSlippage(1000, 900, 100); // 10% slippage exceeds 1% tolerance
    }

    function test_ValidatorsLib_sortTokens() public pure {
        address tokenA = address(0x2);
        address tokenB = address(0x1);

        (address token0, address token1) = ValidatorsLib.sortTokens(tokenA, tokenB);

        assertEq(token0, address(0x1));
        assertEq(token1, address(0x2));
    }

    function test_ValidatorsLib_isETH() public pure {
        assertTrue(ValidatorsLib.isETH(address(0)));
        assertTrue(ValidatorsLib.isETH(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        assertFalse(ValidatorsLib.isETH(address(0x1)));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HARDENED SECURITY LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    HardenedSecurityLib.RateLimiter rateLimiter;
    HardenedSecurityLib.CooldownTracker cooldownTracker;
    HardenedSecurityLib.EmergencyState emergencyState;
    HardenedSecurityLib.NonceManager nonceManager;
    HardenedSecurityLib.ManipulationGuard manipulationGuard;

    function test_HardenedSecurityLib_rateLimiter() public {
        rateLimiter.initRateLimiter(10, 1 hours);

        // Should succeed for first 10 operations
        for (uint256 i = 0; i < 10; i++) {
            rateLimiter.consumeRateLimit(alice);
        }

        // 11th should fail
        vm.expectRevert(HardenedSecurityLib.RateLimitExceeded.selector);
        rateLimiter.consumeRateLimit(alice);
    }

    function test_HardenedSecurityLib_rateLimiter_resetsAfterWindow() public {
        rateLimiter.initRateLimiter(5, 1 hours);

        // Use all 5
        for (uint256 i = 0; i < 5; i++) {
            rateLimiter.consumeRateLimit(alice);
        }

        // Fast forward past window
        vm.warp(block.timestamp + 2 hours);

        // Should work again
        rateLimiter.consumeRateLimit(alice);
    }

    function test_HardenedSecurityLib_cooldownTracker() public {
        cooldownTracker.initCooldown(1 hours);

        // First use should work
        cooldownTracker.enforceCooldown(alice);

        // Immediate second use should fail
        vm.expectRevert();
        cooldownTracker.enforceCooldown(alice);

        // After cooldown, should work
        vm.warp(block.timestamp + 2 hours);
        cooldownTracker.enforceCooldown(alice);
    }

    function test_HardenedSecurityLib_emergencyState() public {
        // Initially not in emergency
        assertFalse(emergencyState.isEmergencyActive());

        // Activate emergency
        emergencyState.activateEmergencyMode(keccak256("TEST_REASON"));
        assertTrue(emergencyState.isEmergencyActive());

        // Deactivate
        emergencyState.deactivateEmergencyMode();
        assertFalse(emergencyState.isEmergencyActive());
    }

    function test_HardenedSecurityLib_nonceManager() public {
        // Initial nonce should be 0
        assertEq(nonceManager.getCurrentNonce(alice), 0);

        // Consume sequential nonce
        nonceManager.consumeNonceSequential(alice, 0);
        assertEq(nonceManager.getCurrentNonce(alice), 1);

        // Wrong nonce should fail
        vm.expectRevert();
        nonceManager.consumeNonceSequential(alice, 0);
    }

    function test_HardenedSecurityLib_manipulationGuard() public {
        manipulationGuard.initManipulationGuard(500); // 5% threshold

        // Small change should pass
        assertFalse(manipulationGuard.detectManipulation(1000, 1040)); // 4%

        // Large change should detect manipulation
        assertTrue(manipulationGuard.detectManipulation(1000, 1100)); // 10%
    }

    function test_HardenedSecurityLib_domainSeparator() public view {
        bytes32 domain = HardenedSecurityLib.buildDomainSeparator("TestApp", "1");
        assertTrue(domain != bytes32(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    StakingLib.StakingPool stakingPool;

    function test_StakingLib_initializePool() public {
        stakingPool.initializePool(
            address(0x100), // staking token
            address(0x200), // reward token
            1e18, // 1 token per second
            type(uint256).max
        );

        assertEq(stakingPool.config.stakingToken, address(0x100));
        assertEq(stakingPool.config.rewardToken, address(0x200));
        assertTrue(stakingPool.config.status == StakingLib.PoolStatus.Active);
    }

    function test_StakingLib_stake() public {
        stakingPool.initializePool(address(0x100), address(0x200), 1e18, type(uint256).max);

        uint256 shares = stakingPool.stake(alice, 1000e18);

        assertEq(shares, 1000e18); // First staker gets 1:1 shares
        assertEq(stakingPool.config.totalStaked, 1000e18);
        assertEq(stakingPool.config.totalShares, 1000e18);
    }

    function test_StakingLib_stakeWithLock() public {
        stakingPool.initializePool(address(0x100), address(0x200), 1e18, type(uint256).max);

        StakingLib.LockSchedule memory schedule = StakingLib.LockSchedule({
            baseMultiplier: 1e18,
            maxMultiplier: 4e18,
            minLockDuration: 7 days,
            maxLockDuration: 4 * 365 days
        });

        uint256 shares = stakingPool.stakeWithLock(alice, 1000e18, 365 days, schedule);

        StakingLib.StakePosition storage position = stakingPool.stakes[alice];
        assertTrue(position.lockEndTime > block.timestamp);
        assertTrue(position.boostMultiplier > 1e18); // Should have boost
    }

    function test_StakingLib_pendingRewards() public {
        stakingPool.initializePool(address(0x100), address(0x200), 1e18, type(uint256).max);
        stakingPool.stake(alice, 1000e18);

        // Fast forward 100 seconds
        vm.warp(block.timestamp + 100);

        uint256 pending = stakingPool.pendingRewards(alice);
        assertEq(pending, 100e18); // 100 seconds * 1 token/sec
    }

    function test_StakingLib_delegation() public {
        stakingPool.initializePool(address(0x100), address(0x200), 1e18, type(uint256).max);
        stakingPool.config.allowDelegation = true;

        stakingPool.stake(alice, 1000e18);

        stakingPool.delegate(alice, bob);

        assertEq(stakingPool.delegations[alice], bob);
        assertEq(stakingPool.delegatedPower[bob], 1000e18);
    }

    function test_StakingLib_calculateAPR() public pure {
        // 1 token/sec reward, 1000 tokens staked
        uint256 apr = StakingLib.calculateAPR(1e18, 1000e18);

        // APR should be ~31.5576 (seconds in a year / 1000)
        assertTrue(apr > 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARD LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    RewardLib.TieredRewards tieredRewards;
    RewardLib.EpochRewards epochRewards;
    RewardLib.MultiplierConfig multiplierConfig;
    RewardLib.UserMultiplier userMultiplier;

    function test_RewardLib_tieredRewards() public {
        tieredRewards.addTier(0, 10000, 0); // Base tier: 1x
        tieredRewards.addTier(1000e18, 15000, 100e18); // Silver: 1.5x + 100 bonus
        tieredRewards.addTier(10000e18, 20000, 500e18); // Gold: 2x + 500 bonus

        // User with 500 tokens should be in base tier
        uint256 tier = tieredRewards.determineTier(500e18);
        assertEq(tier, 0);

        // User with 5000 tokens should be in silver tier
        tier = tieredRewards.determineTier(5000e18);
        assertEq(tier, 1);

        // User with 15000 tokens should be in gold tier
        tier = tieredRewards.determineTier(15000e18);
        assertEq(tier, 2);
    }

    function test_RewardLib_epochRewards() public {
        epochRewards.initializeEpochRewards(7 days, 10000e18);

        assertEq(epochRewards.epochDuration, 7 days);
        assertEq(epochRewards.rewardsPerEpoch, 10000e18);
    }

    function test_RewardLib_multiplierDecay() public {
        multiplierConfig.initializeMultiplier(
            1e18,  // base: 1x
            10e18, // max: 10x
            1e17,  // boost per unit: 0.1x
            1e18 / 365 days // decay rate
        );

        // Apply boost
        userMultiplier.applyBoost(multiplierConfig, 10); // 10 units = 1x boost

        assertEq(userMultiplier.currentMultiplier, 2e18); // 1x + 1x boost = 2x

        // Fast forward and check decay
        vm.warp(block.timestamp + 180 days);

        uint256 currentMult = userMultiplier.calculateMultiplier(multiplierConfig);
        assertTrue(currentMult < 2e18); // Should have decayed
        assertTrue(currentMult >= 1e18); // But not below base
    }

    function test_RewardLib_vesting() public {
        RewardLib.VestingConfig memory config = RewardLib.VestingConfig({
            cliffDuration: 30 days,
            vestingDuration: 365 days,
            slicePeriod: 1 days,
            revocable: true
        });

        RewardLib.VestingSchedule memory schedule = RewardLib.createVestingSchedule(
            1000e18,
            config
        );

        assertEq(schedule.totalAmount, 1000e18);
        assertEq(schedule.cliffDuration, 30 days);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFUNDERS LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    RefundersLib.RefundRegistry refundRegistry;

    function test_RefundersLib_createAndClaimRefund() public {
        refundRegistry.initializePool(address(0)); // ETH pool

        bytes32 refundId = refundRegistry.createRefund(
            alice,
            address(0),
            1e18,
            RefundersLib.RefundType.FailedTransaction,
            keccak256("TEST"),
            30 days
        );

        assertTrue(refundId != bytes32(0));

        // Approve refund
        refundRegistry.approveRefund(refundId);

        // Check claimability
        assertTrue(refundRegistry.isRefundClaimable(refundId));

        // Claim refund
        (address recipient, address token, uint256 amount) = refundRegistry.claimRefund(refundId);

        assertEq(recipient, alice);
        assertEq(token, address(0));
        assertEq(amount, 1e18);
    }

    function test_RefundersLib_gasTracking() public view {
        RefundersLib.GasTracker memory tracker = RefundersLib.startGasTracking(alice);

        assertTrue(tracker.startGas > 0);
        assertEq(tracker.refundRecipient, alice);
        assertTrue(tracker.shouldRefund);
    }

    function test_RefundersLib_merkleProof() public {
        bytes32 merkleRoot = keccak256(abi.encodePacked(alice, uint256(100e18)));

        refundRegistry.setMerkleRoot(
            merkleRoot,
            block.timestamp,
            block.timestamp + 30 days
        );

        assertTrue(refundRegistry.isMerkleClaimActive());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SOLVERS LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SolversLib_calculateSwapOutput() public pure {
        // Pool with 1000 token0, 1000 token1
        uint256 amountOut = SolversLib.calculateSwapOutput(
            100e18, // amount in
            1000e18, // reserve in
            1000e18, // reserve out
            30 // 0.3% fee
        );

        // Should get less than 100 due to fee and price impact
        assertTrue(amountOut < 100e18);
        assertTrue(amountOut > 90e18);
    }

    function test_SolversLib_calculatePriceImpact() public pure {
        uint256 impact = SolversLib.calculatePriceImpact(
            100e18, // amount
            1000e18 // reserve
        );

        // 10% of pool = ~10% impact
        assertEq(impact, 1000); // 10% in basis points
    }

    function test_SolversLib_sqrt() public pure {
        assertEq(SolversLib.sqrt(100), 10);
        assertEq(SolversLib.sqrt(144), 12);
        assertEq(SolversLib.sqrt(1e18), 1e9);
    }

    function test_SolversLib_calculateImpermanentLoss() public pure {
        // Price doubles (2x)
        uint256 loss = SolversLib.calculateImpermanentLoss(2e18);

        // IL at 2x should be ~5.7%
        assertTrue(loss > 500); // > 5%
        assertTrue(loss < 600); // < 6%
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RETURNERS LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ReturnersLib_encodeDecodeUint() public pure {
        uint256 value = 12345;
        bytes memory encoded = ReturnersLib.encodeUint256(value);
        uint256 decoded = ReturnersLib.decodeUint256(encoded);

        assertEq(decoded, value);
    }

    function test_ReturnersLib_encodeDecodeAddress() public pure {
        address value = address(0x1234);
        bytes memory encoded = ReturnersLib.encodeAddress(value);
        address decoded = ReturnersLib.decodeAddress(encoded);

        assertEq(decoded, value);
    }

    function test_ReturnersLib_parseRevertReason() public pure {
        // Create a revert reason
        bytes memory revertData = abi.encodeWithSignature("Error(string)", "Test error");

        string memory reason = ReturnersLib.parseRevertReason(revertData);
        assertEq(reason, "Test error");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SYNERGY LIB TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    SynergyLib.ProtocolRegistry protocolRegistry;

    function test_SynergyLib_registerProtocol() public {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("swap(address,uint256)"));
        selectors[1] = bytes4(keccak256("addLiquidity(uint256,uint256)"));

        bytes32 protocolId = protocolRegistry.registerProtocol(
            address(0x100),
            keccak256("TestDEX"),
            8000, // 80% trust score
            selectors
        );

        assertTrue(protocolId != bytes32(0));

        SynergyLib.Protocol storage protocol = protocolRegistry.getProtocol(protocolId);
        assertEq(protocol.protocolAddress, address(0x100));
        assertEq(protocol.trustScore, 8000);
    }

    function test_SynergyLib_updateTrustScore() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("test()"));

        bytes32 protocolId = protocolRegistry.registerProtocol(
            address(0x100),
            keccak256("Test"),
            5000,
            selectors
        );

        protocolRegistry.updateTrustScore(protocolId, 9000);

        SynergyLib.Protocol storage protocol = protocolRegistry.getProtocol(protocolId);
        assertEq(protocol.trustScore, 9000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ValidatorsLib_requireAmountInRange(
        uint256 value,
        uint256 min,
        uint256 max
    ) public pure {
        vm.assume(min <= max);
        vm.assume(value >= min && value <= max);

        ValidatorsLib.requireAmountInRange(value, min, max);
    }

    function testFuzz_SolversLib_sqrt(uint256 x) public pure {
        vm.assume(x < type(uint128).max);

        uint256 result = SolversLib.sqrt(x);

        // result^2 <= x < (result+1)^2
        assertTrue(result * result <= x);
        if (result < type(uint128).max) {
            assertTrue((result + 1) * (result + 1) > x);
        }
    }

    function testFuzz_StakingLib_calculateAPR(uint256 rewardRate, uint256 totalStaked) public pure {
        vm.assume(totalStaked > 0);
        vm.assume(rewardRate < type(uint128).max);
        vm.assume(totalStaked < type(uint128).max);

        uint256 apr = StakingLib.calculateAPR(rewardRate, totalStaked);

        // APR should be proportional to reward rate and inversely proportional to stake
        if (rewardRate > 0) {
            assertTrue(apr > 0);
        }
    }
}
