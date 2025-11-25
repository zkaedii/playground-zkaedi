// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/utils/AdvancedRandomizerLib.sol";

/**
 * @title AdvancedRandomizerLibTest
 * @notice Comprehensive battle tests for the chaos engine randomizer
 * @dev Tests cover: initialization, generation, edge cases, overflow protection,
 *      distribution quality, determinism, and all mathematical components
 */
contract AdvancedRandomizerLibTest is Test {
    using AdvancedRandomizerLib for AdvancedRandomizerLib.ChaosEngine;

    uint256 constant WAD = 1e18;
    uint256 constant TEST_SEED = 0x123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0;

    // ═══════════════════════════════════════════════════════════════════════════
    //                         INITIALIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_initializeChaosEngine_DefaultParameters() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        assertEq(engine.activeOscillators, 8, "Should have 8 oscillators");
        assertEq(engine.activeDecayTerms, 4, "Should have 4 decay terms");
        assertGt(engine.complexity, 0, "Complexity should be > 0");
        assertLe(engine.complexity, 100, "Complexity should be <= 100");
        assertGt(engine.parallelism, 0, "Parallelism should be > 0");
        assertGt(engine.luckFactor, 0, "Luck factor should be > 0");
        assertLe(engine.luckFactor, 777, "Luck factor should be <= 777");
    }

    function test_initializeChaosEngine_DifferentSeeds() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine1 =
            AdvancedRandomizerLib.initializeChaosEngine(1);
        AdvancedRandomizerLib.ChaosEngine memory engine2 =
            AdvancedRandomizerLib.initializeChaosEngine(2);

        // Different seeds should produce different configurations
        assertTrue(
            engine1.oscillators[0].amplitudeBase != engine2.oscillators[0].amplitudeBase ||
            engine1.oscillators[0].phase != engine2.oscillators[0].phase,
            "Different seeds should produce different configs"
        );
    }

    function test_initializeChaosEngineCustom_ValidOscillatorCount() public pure {
        for (uint256 i = 1; i <= 16; i++) {
            AdvancedRandomizerLib.ChaosEngine memory engine =
                AdvancedRandomizerLib.initializeChaosEngineCustom(TEST_SEED, i);
            assertEq(engine.activeOscillators, i, "Should match requested oscillator count");
        }
    }

    function test_initializeChaosEngineCustom_RevertZeroOscillators() public {
        vm.expectRevert(AdvancedRandomizerLib.InvalidOscillatorCount.selector);
        AdvancedRandomizerLib.initializeChaosEngineCustom(TEST_SEED, 0);
    }

    function test_initializeChaosEngineCustom_RevertTooManyOscillators() public {
        vm.expectRevert(AdvancedRandomizerLib.InvalidOscillatorCount.selector);
        AdvancedRandomizerLib.initializeChaosEngineCustom(TEST_SEED, 17);
    }

    function testFuzz_initializeChaosEngine_AnySeed(uint256 seed) public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(seed);

        // Should always have valid configuration
        assertGt(engine.activeOscillators, 0);
        assertLe(engine.activeOscillators, 16);
        assertGt(engine.complexity, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CORE GENERATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_generate_ProducesOutput() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random = AdvancedRandomizerLib.generate(engine, TEST_SEED, WAD);
        assertGt(random, 0, "Should produce non-zero output");
    }

    function test_generate_DifferentTimes() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random1 = AdvancedRandomizerLib.generate(engine, TEST_SEED, WAD);
        uint256 random2 = AdvancedRandomizerLib.generate(engine, TEST_SEED, 2 * WAD);
        uint256 random3 = AdvancedRandomizerLib.generate(engine, TEST_SEED, 3 * WAD);

        assertTrue(random1 != random2, "Different times should produce different outputs");
        assertTrue(random2 != random3, "Different times should produce different outputs");
        assertTrue(random1 != random3, "Different times should produce different outputs");
    }

    function test_generate_DifferentSeeds() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random1 = AdvancedRandomizerLib.generate(engine, 1, WAD);
        uint256 random2 = AdvancedRandomizerLib.generate(engine, 2, WAD);

        assertTrue(random1 != random2, "Different seeds should produce different outputs");
    }

    function test_generate_Deterministic() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine1 =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);
        AdvancedRandomizerLib.ChaosEngine memory engine2 =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        for (uint256 i = 0; i < 10; i++) {
            uint256 random1 = AdvancedRandomizerLib.generate(engine1, i, i * WAD);
            uint256 random2 = AdvancedRandomizerLib.generate(engine2, i, i * WAD);
            assertEq(random1, random2, "Same inputs should produce same outputs");
        }
    }

    function testFuzz_generate_NeverReverts(uint256 seed, uint256 t) public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(seed);

        // Should not revert for any input
        AdvancedRandomizerLib.generate(engine, seed, t);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         RANGE GENERATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_generateInRange_WithinBounds() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        for (uint256 i = 0; i < 100; i++) {
            uint256 random = AdvancedRandomizerLib.generateInRange(
                engine, i, WAD, 10, 100
            );
            assertGe(random, 10, "Should be >= min");
            assertLe(random, 100, "Should be <= max");
        }
    }

    function test_generateInRange_MinEqualsMax() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random = AdvancedRandomizerLib.generateInRange(
            engine, TEST_SEED, WAD, 42, 42
        );
        assertEq(random, 42, "Should return exact value when min == max");
    }

    function test_generateInRange_RevertInvalidRange() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        vm.expectRevert(AdvancedRandomizerLib.InvalidRange.selector);
        AdvancedRandomizerLib.generateInRange(engine, TEST_SEED, WAD, 100, 10);
    }

    function test_generateInRange_LargeRange() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random = AdvancedRandomizerLib.generateInRange(
            engine, TEST_SEED, WAD, 0, type(uint256).max - 1
        );
        assertLe(random, type(uint256).max - 1);
    }

    function testFuzz_generateInRange_AlwaysInBounds(
        uint256 seed,
        uint256 t,
        uint256 min,
        uint256 max
    ) public pure {
        vm.assume(min <= max);
        vm.assume(max < type(uint256).max); // Prevent overflow in range calculation

        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(seed);

        uint256 random = AdvancedRandomizerLib.generateInRange(engine, seed, t, min, max);
        assertGe(random, min);
        assertLe(random, max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BOOLEAN GENERATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_generateBool_50Percent() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 trueCount = 0;
        uint256 iterations = 1000;

        for (uint256 i = 0; i < iterations; i++) {
            if (AdvancedRandomizerLib.generateBool(engine, i, i * WAD, 5000)) {
                trueCount++;
            }
        }

        // Should be roughly 50% (within 10% tolerance)
        assertGt(trueCount, iterations * 40 / 100, "True count too low");
        assertLt(trueCount, iterations * 60 / 100, "True count too high");
    }

    function test_generateBool_ZeroProbability() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        for (uint256 i = 0; i < 100; i++) {
            bool result = AdvancedRandomizerLib.generateBool(engine, i, WAD, 0);
            assertFalse(result, "0% probability should always be false");
        }
    }

    function test_generateBool_FullProbability() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        for (uint256 i = 0; i < 100; i++) {
            bool result = AdvancedRandomizerLib.generateBool(engine, i, WAD, 10000);
            assertTrue(result, "100% probability should always be true");
        }
    }

    function test_generateBool_ExcessProbabilityClamped() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Should not revert with > 10000 BPS
        for (uint256 i = 0; i < 10; i++) {
            bool result = AdvancedRandomizerLib.generateBool(engine, i, WAD, 15000);
            assertTrue(result, "Should clamp to 100%");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BATCH GENERATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_generateBatch_CorrectCount() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory values = AdvancedRandomizerLib.generateBatch(engine, TEST_SEED, 50);
        assertEq(values.length, 50, "Should generate requested count");
    }

    function test_generateBatch_UniqueValues() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory values = AdvancedRandomizerLib.generateBatch(engine, TEST_SEED, 100);

        // Check that most values are unique (allowing some collisions)
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < values.length; i++) {
            bool isUnique = true;
            for (uint256 j = 0; j < i; j++) {
                if (values[i] == values[j]) {
                    isUnique = false;
                    break;
                }
            }
            if (isUnique) uniqueCount++;
        }

        assertGt(uniqueCount, 90, "Should have mostly unique values");
    }

    function test_generateBatch_RevertZeroCount() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        vm.expectRevert(AdvancedRandomizerLib.BatchSizeTooLarge.selector);
        AdvancedRandomizerLib.generateBatch(engine, TEST_SEED, 0);
    }

    function test_generateBatch_RevertTooLarge() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        vm.expectRevert(AdvancedRandomizerLib.BatchSizeTooLarge.selector);
        AdvancedRandomizerLib.generateBatch(engine, TEST_SEED, 257);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         WEIGHTED SELECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_weightedSelect_RespectsWeights() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 100; // ~33%
        weights[1] = 100; // ~33%
        weights[2] = 100; // ~33%

        uint256[3] memory counts;
        uint256 iterations = 1000;

        for (uint256 i = 0; i < iterations; i++) {
            uint256 selected = AdvancedRandomizerLib.weightedSelect(engine, i, weights);
            assertLt(selected, 3, "Selected index should be valid");
            counts[selected]++;
        }

        // Each should be roughly 33% (within 15% tolerance)
        for (uint256 i = 0; i < 3; i++) {
            assertGt(counts[i], iterations * 20 / 100, "Distribution too skewed");
            assertLt(counts[i], iterations * 47 / 100, "Distribution too skewed");
        }
    }

    function test_weightedSelect_HeavilySkewed() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 900; // 90%
        weights[1] = 50;  // 5%
        weights[2] = 50;  // 5%

        uint256 count0 = 0;
        uint256 iterations = 1000;

        for (uint256 i = 0; i < iterations; i++) {
            if (AdvancedRandomizerLib.weightedSelect(engine, i, weights) == 0) {
                count0++;
            }
        }

        // Should select index 0 most of the time
        assertGt(count0, iterations * 80 / 100, "Heavy weight should be selected often");
    }

    function test_weightedSelect_RevertEmptyWeights() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory weights = new uint256[](0);

        vm.expectRevert(AdvancedRandomizerLib.InvalidParameter.selector);
        AdvancedRandomizerLib.weightedSelect(engine, TEST_SEED, weights);
    }

    function test_weightedSelect_RevertZeroWeights() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 0;
        weights[1] = 0;
        weights[2] = 0;

        vm.expectRevert(AdvancedRandomizerLib.ZeroWeights.selector);
        AdvancedRandomizerLib.weightedSelect(engine, TEST_SEED, weights);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SHUFFLE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_shuffle_CorrectLength() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory shuffled = AdvancedRandomizerLib.shuffle(engine, TEST_SEED, 50);
        assertEq(shuffled.length, 50, "Should have correct length");
    }

    function test_shuffle_ContainsAllIndices() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 length = 20;
        uint256[] memory shuffled = AdvancedRandomizerLib.shuffle(engine, TEST_SEED, length);

        // Check that each index 0 to length-1 appears exactly once
        bool[] memory found = new bool[](length);
        for (uint256 i = 0; i < length; i++) {
            assertLt(shuffled[i], length, "Index should be in range");
            assertFalse(found[shuffled[i]], "Each index should appear once");
            found[shuffled[i]] = true;
        }
    }

    function test_shuffle_ActuallyShuffles() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 length = 20;
        uint256[] memory shuffled = AdvancedRandomizerLib.shuffle(engine, TEST_SEED, length);

        // Count how many are in their original position
        uint256 inPlace = 0;
        for (uint256 i = 0; i < length; i++) {
            if (shuffled[i] == i) inPlace++;
        }

        // Should not have too many in original position (statistically very unlikely)
        assertLt(inPlace, length / 2, "Should actually shuffle");
    }

    function test_shuffle_Deterministic() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory shuffled1 = AdvancedRandomizerLib.shuffle(engine, 42, 20);
        uint256[] memory shuffled2 = AdvancedRandomizerLib.shuffle(engine, 42, 20);

        for (uint256 i = 0; i < 20; i++) {
            assertEq(shuffled1[i], shuffled2[i], "Same seed should produce same shuffle");
        }
    }

    function test_shuffle_RevertZeroLength() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        vm.expectRevert(AdvancedRandomizerLib.BatchSizeTooLarge.selector);
        AdvancedRandomizerLib.shuffle(engine, TEST_SEED, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SELECT UNIQUE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_selectUnique_CorrectCount() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory selected = AdvancedRandomizerLib.selectUnique(engine, TEST_SEED, 100, 10);
        assertEq(selected.length, 10, "Should select correct count");
    }

    function test_selectUnique_AllUnique() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 n = 50;
        uint256 k = 20;
        uint256[] memory selected = AdvancedRandomizerLib.selectUnique(engine, TEST_SEED, n, k);

        for (uint256 i = 0; i < k; i++) {
            assertLt(selected[i], n, "Should be valid index");
            for (uint256 j = i + 1; j < k; j++) {
                assertTrue(selected[i] != selected[j], "All should be unique");
            }
        }
    }

    function test_selectUnique_ZeroK() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory selected = AdvancedRandomizerLib.selectUnique(engine, TEST_SEED, 100, 0);
        assertEq(selected.length, 0, "Should return empty array");
    }

    function test_selectUnique_RevertKGreaterThanN() public {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        vm.expectRevert(AdvancedRandomizerLib.InvalidParameter.selector);
        AdvancedRandomizerLib.selectUnique(engine, TEST_SEED, 10, 20);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         COMPUTE H TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_computeH_ProducesOutput() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        int256 h = AdvancedRandomizerLib.computeH(engine, WAD);
        // Should produce some value (not necessarily non-zero)
        assertTrue(h != type(int256).max && h != type(int256).min, "Should produce valid output");
    }

    function test_computeH_VariesWithTime() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        int256 h1 = AdvancedRandomizerLib.computeH(engine, WAD);
        int256 h2 = AdvancedRandomizerLib.computeH(engine, 2 * WAD);
        int256 h3 = AdvancedRandomizerLib.computeH(engine, 3 * WAD);

        assertTrue(h1 != h2 || h2 != h3, "Should vary with time");
    }

    function testFuzz_computeH_NeverReverts(uint256 seed, uint256 t) public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(seed);

        // Should not revert for any input
        AdvancedRandomizerLib.computeH(engine, t);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ZKAEDI SIGNATURE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_computeZkaediSignature_ValidOutput() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        AdvancedRandomizerLib.ZkaediSignature memory sig =
            AdvancedRandomizerLib.computeZkaediSignature(engine, TEST_SEED);

        // Base value: 649 + 4*complexity + 3*parallelism
        assertGe(sig.baseValue, 649 + 4 + 3, "Base value too low");
        assertGt(sig.phiPower, 0, "Phi power should be non-zero");
        assertGt(sig.luckyMultiplier, 0, "Lucky multiplier should be non-zero");
        assertTrue(sig.finalSignature != bytes32(0), "Signature should be non-zero");
    }

    function test_computeZkaediSignature_Deterministic() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        AdvancedRandomizerLib.ZkaediSignature memory sig1 =
            AdvancedRandomizerLib.computeZkaediSignature(engine, TEST_SEED);
        AdvancedRandomizerLib.ZkaediSignature memory sig2 =
            AdvancedRandomizerLib.computeZkaediSignature(engine, TEST_SEED);

        assertEq(sig1.baseValue, sig2.baseValue);
        assertEq(sig1.phiPower, sig2.phiPower);
        assertEq(sig1.finalSignature, sig2.finalSignature);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         PARTIAL DERIVATIVES TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_computePartialDerivatives_CorrectArraySizes() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        AdvancedRandomizerLib.PartialDerivatives memory derivs =
            AdvancedRandomizerLib.computePartialDerivatives(engine, WAD);

        assertEq(derivs.dH_dPhi.length, engine.activeOscillators);
        assertEq(derivs.dH_dD.length, engine.activeDecayTerms);
    }

    function testFuzz_computePartialDerivatives_NeverReverts(uint256 seed, uint256 t) public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(seed);

        AdvancedRandomizerLib.computePartialDerivatives(engine, t);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SOFTPLUS DERIVATIVES TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_computeSoftplusDerivatives_ValidOutput() public pure {
        AdvancedRandomizerLib.SoftplusParams memory params = AdvancedRandomizerLib.SoftplusParams({
            a: int256(WAD / 10),
            b: int256(WAD),
            x0: 0,
            integralSteps: 32
        });

        (int256 dA, int256 dB, int256 dX0) =
            AdvancedRandomizerLib.computeSoftplusDerivatives(params, int256(WAD));

        // dB should be sigmoid(s) which is in [0, WAD]
        assertGe(dB, 0, "dB should be >= 0");
        assertLe(dB, int256(WAD), "dB should be <= WAD");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         HISTORY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_updateHistory_IncrementsCount() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        assertEq(engine.historyCount, 0, "Should start with empty history");

        engine = AdvancedRandomizerLib.updateHistory(engine, int256(WAD));
        assertEq(engine.historyCount, 1, "Should increment count");

        engine = AdvancedRandomizerLib.updateHistory(engine, int256(2 * WAD));
        assertEq(engine.historyCount, 2, "Should increment count again");
    }

    function test_updateHistory_WrapsAround() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Fill beyond max history
        for (uint256 i = 0; i < 300; i++) {
            engine = AdvancedRandomizerLib.updateHistory(engine, int256(i));
        }

        // Count should be capped at MAX_HISTORY
        assertEq(engine.historyCount, 256, "Should cap at MAX_HISTORY");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CHAOS ANALYSIS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_estimateLyapunovExponent_ProducesOutput() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        int256 lyapunov = AdvancedRandomizerLib.estimateLyapunovExponent(engine, TEST_SEED, 10);
        // Just verify it doesn't revert and produces some output
        assertTrue(lyapunov != type(int256).max, "Should produce valid output");
    }

    function test_estimateLyapunovExponent_ZeroIterations() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        int256 lyapunov = AdvancedRandomizerLib.estimateLyapunovExponent(engine, TEST_SEED, 0);
        assertEq(lyapunov, 0, "Zero iterations should return 0");
    }

    function test_getEntropy_NonZero() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 entropy = AdvancedRandomizerLib.getEntropy(engine);
        assertGt(entropy, 0, "Entropy should be non-zero");
    }

    function test_getEntropy_DifferentForDifferentEngines() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine1 =
            AdvancedRandomizerLib.initializeChaosEngine(1);
        AdvancedRandomizerLib.ChaosEngine memory engine2 =
            AdvancedRandomizerLib.initializeChaosEngine(2);

        uint256 entropy1 = AdvancedRandomizerLib.getEntropy(engine1);
        uint256 entropy2 = AdvancedRandomizerLib.getEntropy(engine2);

        assertTrue(entropy1 != entropy2, "Different engines should have different entropy");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         QUALITY ANALYSIS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_analyzeQuality_WithSamples() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256[] memory samples = AdvancedRandomizerLib.generateBatch(engine, TEST_SEED, 100);
        AdvancedRandomizerLib.QualityMetrics memory metrics =
            AdvancedRandomizerLib.analyzeQuality(samples);

        assertGt(metrics.entropy, 0, "Should have non-zero entropy");
        assertGt(metrics.runsCount, 0, "Should have some runs");
    }

    function test_analyzeQuality_EmptySamples() public pure {
        uint256[] memory samples = new uint256[](0);
        AdvancedRandomizerLib.QualityMetrics memory metrics =
            AdvancedRandomizerLib.analyzeQuality(samples);

        assertEq(metrics.entropy, 0, "Empty samples should have zero entropy");
    }

    function test_verifyDeterminism_Passes() public pure {
        bool isDeterministic = AdvancedRandomizerLib.verifyDeterminism(TEST_SEED, WAD, 10);
        assertTrue(isDeterministic, "Should be deterministic");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_generate_ZeroTime() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random = AdvancedRandomizerLib.generate(engine, TEST_SEED, 0);
        assertGt(random, 0, "Should produce output even at t=0");
    }

    function test_generate_MaxTime() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 random = AdvancedRandomizerLib.generate(engine, TEST_SEED, type(uint256).max);
        // Should not revert and should produce some output
        assertGt(random, 0, "Should handle max time");
    }

    function test_generate_ZeroSeed() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(0);

        uint256 random = AdvancedRandomizerLib.generate(engine, 0, WAD);
        assertGt(random, 0, "Should handle zero seed");
    }

    function test_generate_MaxSeed() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(type(uint256).max);

        uint256 random = AdvancedRandomizerLib.generate(engine, type(uint256).max, WAD);
        assertGt(random, 0, "Should handle max seed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         DISTRIBUTION QUALITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_distribution_Uniformity() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Generate many samples in range 0-9
        uint256[10] memory buckets;
        uint256 iterations = 1000;

        for (uint256 i = 0; i < iterations; i++) {
            uint256 value = AdvancedRandomizerLib.generateInRange(engine, i, i * WAD, 0, 9);
            buckets[value]++;
        }

        // Each bucket should have roughly 100 (10%)
        // Allow 50% tolerance
        for (uint256 i = 0; i < 10; i++) {
            assertGt(buckets[i], 50, "Bucket too empty");
            assertLt(buckets[i], 150, "Bucket too full");
        }
    }

    function test_distribution_HighBitsUsed() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Check that high bits are used (not just low bits)
        uint256 highBitCount = 0;
        uint256 iterations = 100;

        for (uint256 i = 0; i < iterations; i++) {
            uint256 random = AdvancedRandomizerLib.generate(engine, i, i * WAD);
            if (random > type(uint128).max) highBitCount++;
        }

        // Roughly half should have high bit set
        assertGt(highBitCount, 30, "High bits not used enough");
        assertLt(highBitCount, 70, "High bits used too much");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         GAS BENCHMARK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_gas_initializeChaosEngine() public view {
        uint256 gasBefore = gasleft();
        AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for initializeChaosEngine:", gasUsed);
        assertLt(gasUsed, 500000, "Initialization should be reasonably efficient");
    }

    function test_gas_generate() public view {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 gasBefore = gasleft();
        AdvancedRandomizerLib.generate(engine, TEST_SEED, WAD);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for generate:", gasUsed);
        assertLt(gasUsed, 200000, "Generation should be reasonably efficient");
    }

    function test_gas_generateBatch() public view {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        uint256 gasBefore = gasleft();
        AdvancedRandomizerLib.generateBatch(engine, TEST_SEED, 10);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for generateBatch(10):", gasUsed);
        assertLt(gasUsed, 2000000, "Batch generation should be reasonably efficient");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         COMPREHENSIVE STRESS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_stress_ManyGenerations() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Generate many values without reverting
        for (uint256 i = 0; i < 500; i++) {
            AdvancedRandomizerLib.generate(engine, i, i * WAD);
        }
    }

    function test_stress_ManyEngines() public pure {
        // Create many engines without reverting
        for (uint256 i = 0; i < 50; i++) {
            AdvancedRandomizerLib.ChaosEngine memory engine =
                AdvancedRandomizerLib.initializeChaosEngine(i);
            AdvancedRandomizerLib.generate(engine, i, WAD);
        }
    }

    function test_stress_RapidHistoryUpdates() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Many rapid history updates
        for (uint256 i = 0; i < 500; i++) {
            int256 h = AdvancedRandomizerLib.computeH(engine, i * WAD);
            engine = AdvancedRandomizerLib.updateHistory(engine, h);
        }

        // Should still work after many updates
        uint256 random = AdvancedRandomizerLib.generate(engine, TEST_SEED, WAD);
        assertGt(random, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ADDITIONAL EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_generateInRange_FullRange() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Test full uint256 range (previously would overflow)
        uint256 random = AdvancedRandomizerLib.generateInRange(
            engine, TEST_SEED, WAD, 0, type(uint256).max
        );
        // Should not revert and should produce output
        assertTrue(random >= 0, "Should handle full range");
    }

    function test_generateInRange_NearMaxRange() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Test near-max range
        uint256 random = AdvancedRandomizerLib.generateInRange(
            engine, TEST_SEED, WAD, 1, type(uint256).max
        );
        assertGe(random, 1, "Should be >= min");
    }

    function test_generateInRange_RejectionSamplingBounded() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Small range that would cause many rejections
        // The bounded loop should prevent infinite gas consumption
        for (uint256 i = 0; i < 100; i++) {
            uint256 random = AdvancedRandomizerLib.generateInRange(
                engine, i, i * WAD, 0, 2
            );
            assertLe(random, 2, "Should be in range");
        }
    }

    function test_weightedSelect_LargeWeights() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Test with large but non-overflowing weights
        uint256[] memory weights = new uint256[](3);
        weights[0] = type(uint256).max / 4;
        weights[1] = type(uint256).max / 4;
        weights[2] = type(uint256).max / 4;

        uint256 selected = AdvancedRandomizerLib.weightedSelect(engine, TEST_SEED, weights);
        assertLt(selected, 3, "Should select valid index");
    }

    function test_selectUnique_SmallKLargeN() public pure {
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // Test optimized path: small k relative to n
        uint256[] memory selected = AdvancedRandomizerLib.selectUnique(engine, TEST_SEED, 100, 5);
        assertEq(selected.length, 5, "Should select 5 items");

        // Verify all are unique and valid
        for (uint256 i = 0; i < 5; i++) {
            assertLt(selected[i], 100, "Should be valid index");
            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(selected[i] != selected[j], "Should be unique");
            }
        }
    }

    function test_analyzeQuality_RunsTestCorrect() public pure {
        // Create a sample with known runs pattern
        uint256[] memory samples = new uint256[](10);
        // Pattern: 1, 3, 2, 4, 3, 5, 4, 6, 5, 7
        // Runs: ↑, ↓, ↑, ↓, ↑, ↓, ↑, ↓, ↑
        // This should give us many runs (direction changes)
        samples[0] = 1;
        samples[1] = 3;
        samples[2] = 2;
        samples[3] = 4;
        samples[4] = 3;
        samples[5] = 5;
        samples[6] = 4;
        samples[7] = 6;
        samples[8] = 5;
        samples[9] = 7;

        AdvancedRandomizerLib.QualityMetrics memory metrics =
            AdvancedRandomizerLib.analyzeQuality(samples);

        // Should detect multiple runs (alternating up/down pattern)
        assertGt(metrics.runsCount, 5, "Should detect multiple runs");
    }

    function test_analyzeQuality_MonotonicSequence() public pure {
        // Create a strictly increasing sequence - should have only 1 run
        uint256[] memory samples = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            samples[i] = i;
        }

        AdvancedRandomizerLib.QualityMetrics memory metrics =
            AdvancedRandomizerLib.analyzeQuality(samples);

        // Monotonic sequence should have exactly 1 run
        assertEq(metrics.runsCount, 1, "Monotonic should have 1 run");
    }

    function test_powSafe_OperatorPrecedence() public pure {
        // Verify that the operator precedence fix works correctly
        // This tests that (exp & 1) == 1 is evaluated correctly

        // Test with known values
        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(TEST_SEED);

        // The Zkaedi signature uses _powSafe internally
        AdvancedRandomizerLib.ZkaediSignature memory sig =
            AdvancedRandomizerLib.computeZkaediSignature(engine, TEST_SEED);

        // phiPower should be PHI^n where n is active oscillators (8)
        // PHI ≈ 1.618, so PHI^8 ≈ 46.98
        assertGt(sig.phiPower, 40 * WAD, "Phi power should be > 40");
        assertLt(sig.phiPower, 60 * WAD, "Phi power should be < 60");
    }

    function testFuzz_generateInRange_NeverOverflows(
        uint256 seed,
        uint256 t,
        uint256 min,
        uint256 max
    ) public pure {
        vm.assume(min <= max);

        AdvancedRandomizerLib.ChaosEngine memory engine =
            AdvancedRandomizerLib.initializeChaosEngine(seed);

        // Should never revert even with max values
        uint256 result = AdvancedRandomizerLib.generateInRange(engine, seed, t, min, max);
        assertGe(result, min);
        assertLe(result, max);
    }
}
