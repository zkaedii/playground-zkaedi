// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FeeLib
 * @notice Comprehensive fee calculation with tiers, discounts, and caps
 * @dev Provides flexible fee structures for DeFi protocols
 */
library FeeLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant MAX_FEE_BPS = 5_000; // 50% max fee
    uint256 internal constant MAX_DISCOUNT_BPS = 10_000; // 100% max discount

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Basic fee configuration
    struct FeeConfig {
        uint64 baseFee;           // Flat base fee
        uint16 percentageFee;     // Fee in basis points
        uint64 minFee;            // Minimum total fee
        uint64 maxFee;            // Maximum total fee (0 = no max)
        bool active;              // Whether fees are enabled
    }

    /// @notice Tiered fee structure
    struct TieredFee {
        uint128 tier1Threshold;   // Volume threshold for tier 1
        uint128 tier2Threshold;   // Volume threshold for tier 2
        uint128 tier3Threshold;   // Volume threshold for tier 3
        uint16 baseFeeRate;       // Default fee rate (BPS)
        uint16 tier1Rate;         // Tier 1 discount rate
        uint16 tier2Rate;         // Tier 2 discount rate
        uint16 tier3Rate;         // Tier 3 discount rate (lowest)
    }

    /// @notice Fee distribution configuration
    struct FeeDistribution {
        address treasury;         // Treasury address
        address stakers;          // Staker rewards pool
        address referrer;         // Referrer (if any)
        uint16 treasuryShare;     // Treasury share (BPS of total)
        uint16 stakersShare;      // Stakers share (BPS of total)
        uint16 referrerShare;     // Referrer share (BPS of total)
    }

    /// @notice Dynamic fee with time decay
    struct DynamicFee {
        uint16 initialRate;       // Starting fee rate
        uint16 finalRate;         // Ending fee rate
        uint64 startTime;         // When decay starts
        uint64 duration;          // Decay duration
    }

    /// @notice Volume-based discount tracker
    struct VolumeDiscount {
        uint128 volume30d;        // 30-day rolling volume
        uint64 lastUpdateTime;    // Last volume update
        uint16 discountBps;       // Current discount rate
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidFeeRate(uint256 rate);
    error FeeTooHigh(uint256 fee, uint256 maxFee);
    error InvalidDistribution();
    error InvalidTierThresholds();
    error ZeroRecipient();

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC FEE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate fee with config
     * @param amount Transaction amount
     * @param config Fee configuration
     * @return fee Calculated fee
     */
    function calculateFee(
        uint256 amount,
        FeeConfig memory config
    ) internal pure returns (uint256 fee) {
        if (!config.active) return 0;

        // Base fee + percentage
        fee = config.baseFee + (amount * config.percentageFee) / MAX_BPS;

        // Apply min/max caps
        if (fee < config.minFee) fee = config.minFee;
        if (config.maxFee > 0 && fee > config.maxFee) fee = config.maxFee;
    }

    /**
     * @notice Calculate simple percentage fee
     * @param amount Transaction amount
     * @param bps Fee in basis points
     * @return Fee amount
     */
    function percentageFee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (bps > MAX_FEE_BPS) revert InvalidFeeRate(bps);
        return (amount * bps) / MAX_BPS;
    }

    /**
     * @notice Calculate percentage fee with rounding up
     */
    function percentageFeeRoundUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (bps > MAX_FEE_BPS) revert InvalidFeeRate(bps);
        return (amount * bps + MAX_BPS - 1) / MAX_BPS;
    }

    /**
     * @notice Calculate amount after fee deduction
     * @param amount Original amount
     * @param feeBps Fee in basis points
     * @return Amount minus fee
     */
    function amountAfterFee(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return (amount * (MAX_BPS - feeBps)) / MAX_BPS;
    }

    /**
     * @notice Calculate original amount before fee was deducted
     * @param netAmount Amount after fee
     * @param feeBps Fee in basis points
     * @return Original amount
     */
    function amountBeforeFee(uint256 netAmount, uint256 feeBps) internal pure returns (uint256) {
        return (netAmount * MAX_BPS) / (MAX_BPS - feeBps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIERED FEE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get fee rate based on volume tier
     * @param tieredFee Tiered fee configuration
     * @param volume User's volume
     * @return Fee rate in BPS
     */
    function getTierRate(
        TieredFee memory tieredFee,
        uint256 volume
    ) internal pure returns (uint16) {
        if (volume >= tieredFee.tier3Threshold) return tieredFee.tier3Rate;
        if (volume >= tieredFee.tier2Threshold) return tieredFee.tier2Rate;
        if (volume >= tieredFee.tier1Threshold) return tieredFee.tier1Rate;
        return tieredFee.baseFeeRate;
    }

    /**
     * @notice Calculate fee with tiered rates
     */
    function calculateTieredFee(
        uint256 amount,
        TieredFee memory tieredFee,
        uint256 userVolume
    ) internal pure returns (uint256) {
        uint16 rate = getTierRate(tieredFee, userVolume);
        return (amount * rate) / MAX_BPS;
    }

    /**
     * @notice Initialize tiered fee structure
     */
    function initTieredFee(
        TieredFee storage tieredFee,
        uint128 tier1Threshold,
        uint128 tier2Threshold,
        uint128 tier3Threshold,
        uint16 baseFeeRate,
        uint16 tier1Rate,
        uint16 tier2Rate,
        uint16 tier3Rate
    ) internal {
        if (tier1Threshold > tier2Threshold || tier2Threshold > tier3Threshold) {
            revert InvalidTierThresholds();
        }
        if (baseFeeRate > MAX_FEE_BPS) revert InvalidFeeRate(baseFeeRate);

        tieredFee.tier1Threshold = tier1Threshold;
        tieredFee.tier2Threshold = tier2Threshold;
        tieredFee.tier3Threshold = tier3Threshold;
        tieredFee.baseFeeRate = baseFeeRate;
        tieredFee.tier1Rate = tier1Rate;
        tieredFee.tier2Rate = tier2Rate;
        tieredFee.tier3Rate = tier3Rate;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate fee distribution amounts
     * @param totalFee Total fee collected
     * @param dist Distribution configuration
     * @return treasuryAmount Amount for treasury
     * @return stakersAmount Amount for stakers
     * @return referrerAmount Amount for referrer
     */
    function calculateDistribution(
        uint256 totalFee,
        FeeDistribution memory dist
    ) internal pure returns (
        uint256 treasuryAmount,
        uint256 stakersAmount,
        uint256 referrerAmount
    ) {
        // Validate total shares
        uint256 totalShares = dist.treasuryShare + dist.stakersShare + dist.referrerShare;
        if (totalShares > MAX_BPS) revert InvalidDistribution();

        treasuryAmount = (totalFee * dist.treasuryShare) / MAX_BPS;
        stakersAmount = (totalFee * dist.stakersShare) / MAX_BPS;

        // Referrer only gets share if address is set
        if (dist.referrer != address(0)) {
            referrerAmount = (totalFee * dist.referrerShare) / MAX_BPS;
        } else {
            // Add referrer share to treasury if no referrer
            treasuryAmount += (totalFee * dist.referrerShare) / MAX_BPS;
        }
    }

    /**
     * @notice Validate distribution configuration
     */
    function validateDistribution(FeeDistribution memory dist) internal pure {
        uint256 totalShares = dist.treasuryShare + dist.stakersShare + dist.referrerShare;
        if (totalShares > MAX_BPS) revert InvalidDistribution();
        if (dist.treasury == address(0)) revert ZeroRecipient();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DYNAMIC FEES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize dynamic fee with decay
     */
    function initDynamicFee(
        DynamicFee storage fee,
        uint16 initialRate,
        uint16 finalRate,
        uint64 duration
    ) internal {
        if (initialRate > MAX_FEE_BPS) revert InvalidFeeRate(initialRate);
        if (finalRate > MAX_FEE_BPS) revert InvalidFeeRate(finalRate);

        fee.initialRate = initialRate;
        fee.finalRate = finalRate;
        fee.startTime = uint64(block.timestamp);
        fee.duration = duration;
    }

    /**
     * @notice Get current dynamic fee rate
     */
    function getCurrentRate(DynamicFee memory fee) internal view returns (uint16) {
        if (block.timestamp < fee.startTime) return fee.initialRate;
        if (block.timestamp >= fee.startTime + fee.duration) return fee.finalRate;

        // Linear interpolation
        uint256 elapsed = block.timestamp - fee.startTime;
        if (fee.initialRate >= fee.finalRate) {
            uint256 decrease = fee.initialRate - fee.finalRate;
            uint256 currentDecrease = (decrease * elapsed) / fee.duration;
            return uint16(fee.initialRate - currentDecrease);
        } else {
            uint256 increase = fee.finalRate - fee.initialRate;
            uint256 currentIncrease = (increase * elapsed) / fee.duration;
            return uint16(fee.initialRate + currentIncrease);
        }
    }

    /**
     * @notice Calculate dynamic fee
     */
    function calculateDynamicFee(
        uint256 amount,
        DynamicFee memory fee
    ) internal view returns (uint256) {
        uint16 rate = getCurrentRate(fee);
        return (amount * rate) / MAX_BPS;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DISCOUNT CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Apply discount to fee
     * @param fee Original fee
     * @param discountBps Discount in basis points
     * @return Discounted fee
     */
    function applyDiscount(uint256 fee, uint256 discountBps) internal pure returns (uint256) {
        if (discountBps >= MAX_BPS) return 0;
        return (fee * (MAX_BPS - discountBps)) / MAX_BPS;
    }

    /**
     * @notice Calculate volume-based discount
     * @param volume User's trading volume
     * @param thresholds Volume thresholds for each discount level
     * @param discounts Discount rates for each level (in BPS)
     * @return Discount rate in BPS
     */
    function volumeBasedDiscount(
        uint256 volume,
        uint256[] memory thresholds,
        uint256[] memory discounts
    ) internal pure returns (uint256) {
        for (uint256 i = thresholds.length; i > 0;) {
            unchecked { --i; }
            if (volume >= thresholds[i]) {
                return discounts[i];
            }
        }
        return 0;
    }

    /**
     * @notice Calculate staking-based discount
     * @param stakedAmount User's staked amount
     * @param totalStaked Total staked in protocol
     * @param maxDiscountBps Maximum discount possible
     * @return Discount rate in BPS
     */
    function stakingDiscount(
        uint256 stakedAmount,
        uint256 totalStaked,
        uint256 maxDiscountBps
    ) internal pure returns (uint256) {
        if (totalStaked == 0) return 0;

        // Linear discount based on stake share (capped at max)
        uint256 stakeShare = (stakedAmount * MAX_BPS) / totalStaked;
        uint256 discount = (stakeShare * maxDiscountBps) / MAX_BPS;

        return discount > maxDiscountBps ? maxDiscountBps : discount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate fee with cap
     * @param amount Transaction amount
     * @param feeBps Fee in basis points
     * @param maxFee Maximum fee
     * @return Capped fee
     */
    function feeWithCap(
        uint256 amount,
        uint256 feeBps,
        uint256 maxFee
    ) internal pure returns (uint256) {
        uint256 fee = (amount * feeBps) / MAX_BPS;
        return fee > maxFee ? maxFee : fee;
    }

    /**
     * @notice Calculate fee with floor
     * @param amount Transaction amount
     * @param feeBps Fee in basis points
     * @param minFee Minimum fee
     * @return Fee with minimum
     */
    function feeWithFloor(
        uint256 amount,
        uint256 feeBps,
        uint256 minFee
    ) internal pure returns (uint256) {
        uint256 fee = (amount * feeBps) / MAX_BPS;
        return fee < minFee ? minFee : fee;
    }

    /**
     * @notice Split amount into principal and fee
     * @param totalAmount Total amount including fee
     * @param feeBps Fee rate in BPS
     * @return principal Amount minus fee
     * @return fee Fee amount
     */
    function splitFee(
        uint256 totalAmount,
        uint256 feeBps
    ) internal pure returns (uint256 principal, uint256 fee) {
        fee = (totalAmount * feeBps) / MAX_BPS;
        principal = totalAmount - fee;
    }

    /**
     * @notice Validate fee rate is within acceptable range
     */
    function validateFeeRate(uint256 feeBps, uint256 maxAllowed) internal pure {
        if (feeBps > maxAllowed) revert InvalidFeeRate(feeBps);
    }
}
