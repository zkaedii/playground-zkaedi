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
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error FeeTooHigh(uint256 fee, uint256 max);
    error InvalidTier();
    error InvalidDiscount();
    error InvalidFeeConfig();

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Fee configuration
    struct FeeConfig {
        uint256 baseFee;         // Base fee in BPS
        uint256 minFee;          // Minimum fee amount (absolute)
        uint256 maxFee;          // Maximum fee amount (absolute), 0 = no cap
        bool flatFee;            // If true, baseFee is absolute amount not BPS
    }

    /// @notice Fee tier based on volume/amount
    struct FeeTier {
        uint256 minAmount;       // Minimum amount for this tier
        uint256 feeBps;          // Fee in basis points for this tier
    }

    /// @notice Volume-based fee discount
    struct VolumeDiscount {
        uint256 volumeThreshold; // Minimum volume for discount
        uint256 discountBps;     // Discount in basis points
    }

    /// @notice Time-based fee (e.g., decay over time)
    struct TimeBasedFee {
        uint256 startTime;
        uint256 endTime;
        uint256 startFeeBps;     // Fee at start
        uint256 endFeeBps;       // Fee at end
    }

    /// @notice Fee distribution to multiple recipients
    struct FeeDistribution {
        address[] recipients;
        uint256[] shares;        // Shares in BPS (should sum to 10000)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC FEE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate fee from basis points
    /// @param amount The amount to calculate fee on
    /// @param feeBps Fee in basis points (1 = 0.01%)
    /// @return fee The calculated fee
    function calculateBpsFee(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return (amount * feeBps) / MAX_BPS;
    }

    /// @notice Calculate fee with config
    function calculateFee(
        uint256 amount,
        FeeConfig memory config
    ) internal pure returns (uint256 fee) {
        if (config.flatFee) {
            fee = config.baseFee;
        } else {
            fee = calculateBpsFee(amount, config.baseFee);
        }

        // Apply min/max bounds
        if (fee < config.minFee) {
            fee = config.minFee;
        }
        if (config.maxFee > 0 && fee > config.maxFee) {
            fee = config.maxFee;
        }
    }

    /// @notice Calculate amount after fee deduction
    function amountAfterFee(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return amount - calculateBpsFee(amount, feeBps);
    }

    /// @notice Calculate amount before fee (given desired output)
    /// @param desiredOutput Amount user wants to receive
    /// @param feeBps Fee in basis points
    /// @return amountIn Required input amount
    function amountBeforeFee(
        uint256 desiredOutput,
        uint256 feeBps
    ) internal pure returns (uint256) {
        // amountIn - (amountIn * feeBps / MAX_BPS) = desiredOutput
        // amountIn * (MAX_BPS - feeBps) / MAX_BPS = desiredOutput
        // amountIn = desiredOutput * MAX_BPS / (MAX_BPS - feeBps)
        return (desiredOutput * MAX_BPS + MAX_BPS - feeBps - 1) / (MAX_BPS - feeBps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIERED FEES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get fee rate for amount based on tiers (highest matching tier)
    /// @dev Tiers should be sorted by minAmount ascending
    function getTieredFee(
        uint256 amount,
        FeeTier[] memory tiers
    ) internal pure returns (uint256 feeBps) {
        if (tiers.length == 0) revert InvalidTier();

        // Default to first tier
        feeBps = tiers[0].feeBps;

        // Find highest qualifying tier
        unchecked {
            for (uint256 i = 1; i < tiers.length; ++i) {
                if (amount >= tiers[i].minAmount) {
                    feeBps = tiers[i].feeBps;
                } else {
                    break; // Tiers should be sorted, so we can break early
                }
            }
        }
    }

    /// @notice Calculate tiered fee amount
    function calculateTieredFee(
        uint256 amount,
        FeeTier[] memory tiers
    ) internal pure returns (uint256) {
        uint256 feeBps = getTieredFee(amount, tiers);
        return calculateBpsFee(amount, feeBps);
    }

    /// @notice Get fee with progressive tiers (different rate for each portion)
    /// @dev Example: 1% on first 1000, 0.5% on 1000-10000, 0.1% on rest
    function calculateProgressiveFee(
        uint256 amount,
        FeeTier[] memory tiers
    ) internal pure returns (uint256 totalFee) {
        if (tiers.length == 0) revert InvalidTier();

        uint256 remaining = amount;
        uint256 prevThreshold;

        unchecked {
            for (uint256 i; i < tiers.length && remaining > 0; ++i) {
                uint256 tierMax = (i + 1 < tiers.length) ?
                    tiers[i + 1].minAmount - prevThreshold :
                    type(uint256).max;

                uint256 amountInTier = remaining > tierMax ? tierMax : remaining;
                totalFee += calculateBpsFee(amountInTier, tiers[i].feeBps);
                remaining -= amountInTier;
                prevThreshold = tiers[i].minAmount;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOLUME DISCOUNTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get discount percentage based on cumulative volume
    /// @dev Discounts should be sorted by volumeThreshold ascending
    function getVolumeDiscount(
        uint256 cumulativeVolume,
        VolumeDiscount[] memory discounts
    ) internal pure returns (uint256 discountBps) {
        unchecked {
            for (uint256 i; i < discounts.length; ++i) {
                if (cumulativeVolume >= discounts[i].volumeThreshold) {
                    discountBps = discounts[i].discountBps;
                }
            }
        }
    }

    /// @notice Apply volume discount to fee
    function applyDiscount(
        uint256 baseFee,
        uint256 discountBps
    ) internal pure returns (uint256) {
        if (discountBps >= MAX_BPS) return 0;
        return baseFee - calculateBpsFee(baseFee, discountBps);
    }

    /// @notice Calculate fee with volume discount
    function calculateFeeWithVolumeDiscount(
        uint256 amount,
        uint256 baseFeeBps,
        uint256 cumulativeVolume,
        VolumeDiscount[] memory discounts
    ) internal pure returns (uint256) {
        uint256 baseFee = calculateBpsFee(amount, baseFeeBps);
        uint256 discountBps = getVolumeDiscount(cumulativeVolume, discounts);
        return applyDiscount(baseFee, discountBps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME-BASED FEES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate fee that decays over time
    function getTimeBasedFee(TimeBasedFee memory config) internal view returns (uint256 feeBps) {
        if (block.timestamp <= config.startTime) {
            return config.startFeeBps;
        }
        if (block.timestamp >= config.endTime) {
            return config.endFeeBps;
        }

        // Linear interpolation
        uint256 elapsed = block.timestamp - config.startTime;
        uint256 duration = config.endTime - config.startTime;

        if (config.startFeeBps > config.endFeeBps) {
            // Decaying fee
            uint256 decrease = config.startFeeBps - config.endFeeBps;
            feeBps = config.startFeeBps - (decrease * elapsed / duration);
        } else {
            // Increasing fee
            uint256 increase = config.endFeeBps - config.startFeeBps;
            feeBps = config.startFeeBps + (increase * elapsed / duration);
        }
    }

    /// @notice Calculate Dutch auction style decaying fee
    function getDutchAuctionFee(
        uint256 startTime,
        uint256 decayDuration,
        uint256 startFeeBps,
        uint256 endFeeBps
    ) internal view returns (uint256) {
        return getTimeBasedFee(TimeBasedFee({
            startTime: startTime,
            endTime: startTime + decayDuration,
            startFeeBps: startFeeBps,
            endFeeBps: endFeeBps
        }));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate fee distribution (shares sum to MAX_BPS)
    function validateDistribution(FeeDistribution memory dist) internal pure returns (bool) {
        if (dist.recipients.length != dist.shares.length) return false;
        if (dist.recipients.length == 0) return false;

        uint256 total;
        unchecked {
            for (uint256 i; i < dist.shares.length; ++i) {
                total += dist.shares[i];
            }
        }
        return total == MAX_BPS;
    }

    /// @notice Calculate fee amounts for each recipient
    function calculateDistribution(
        uint256 totalFee,
        FeeDistribution memory dist
    ) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](dist.recipients.length);
        uint256 distributed;

        unchecked {
            for (uint256 i; i < dist.shares.length - 1; ++i) {
                amounts[i] = (totalFee * dist.shares[i]) / MAX_BPS;
                distributed += amounts[i];
            }
            // Last recipient gets remainder to handle rounding
            amounts[dist.shares.length - 1] = totalFee - distributed;
        }
    }

    /// @notice Simple 2-way split
    function splitFee(
        uint256 totalFee,
        uint256 primaryShareBps
    ) internal pure returns (uint256 primary, uint256 secondary) {
        primary = (totalFee * primaryShareBps) / MAX_BPS;
        secondary = totalFee - primary;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING-BASED DISCOUNTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate discount based on staked amount
    /// @param stakedAmount User's staked amount
    /// @param maxStakeForDiscount Stake amount for max discount
    /// @param maxDiscountBps Maximum discount achievable
    function getStakingDiscount(
        uint256 stakedAmount,
        uint256 maxStakeForDiscount,
        uint256 maxDiscountBps
    ) internal pure returns (uint256 discountBps) {
        if (stakedAmount >= maxStakeForDiscount) {
            return maxDiscountBps;
        }
        return (maxDiscountBps * stakedAmount) / maxStakeForDiscount;
    }

    /// @notice Calculate fee with staking discount
    function calculateFeeWithStakingDiscount(
        uint256 amount,
        uint256 baseFeeBps,
        uint256 stakedAmount,
        uint256 maxStakeForDiscount,
        uint256 maxDiscountBps
    ) internal pure returns (uint256) {
        uint256 baseFee = calculateBpsFee(amount, baseFeeBps);
        uint256 discountBps = getStakingDiscount(stakedAmount, maxStakeForDiscount, maxDiscountBps);
        return applyDiscount(baseFee, discountBps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validate fee is within acceptable range
    function validateFee(uint256 feeBps, uint256 maxFeeBps) internal pure {
        if (feeBps > maxFeeBps) {
            revert FeeTooHigh(feeBps, maxFeeBps);
        }
    }

    /// @notice Validate fee config
    function validateFeeConfig(FeeConfig memory config) internal pure {
        if (!config.flatFee && config.baseFee > MAX_FEE_BPS) {
            revert InvalidFeeConfig();
        }
        if (config.maxFee > 0 && config.minFee > config.maxFee) {
            revert InvalidFeeConfig();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Convert percentage to basis points
    function percentToBps(uint256 percent) internal pure returns (uint256) {
        return percent * 100;
    }

    /// @notice Convert basis points to percentage
    function bpsToPercent(uint256 bps) internal pure returns (uint256) {
        return bps / 100;
    }

    /// @notice Format fee as human readable (returns fee per 1000 units)
    function feePerThousand(uint256 feeBps) internal pure returns (uint256) {
        return (feeBps * 1000) / MAX_BPS;
    }

    /// @notice Check if fee is zero
    function isZeroFee(FeeConfig memory config) internal pure returns (bool) {
        return config.baseFee == 0 && config.minFee == 0;
    }

    /// @notice Create simple BPS fee config
    function createBpsFeeConfig(
        uint256 feeBps
    ) internal pure returns (FeeConfig memory) {
        return FeeConfig({
            baseFee: feeBps,
            minFee: 0,
            maxFee: 0,
            flatFee: false
        });
    }

    /// @notice Create flat fee config
    function createFlatFeeConfig(
        uint256 flatAmount
    ) internal pure returns (FeeConfig memory) {
        return FeeConfig({
            baseFee: flatAmount,
            minFee: 0,
            maxFee: 0,
            flatFee: true
        });
    }
}
