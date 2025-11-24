// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title TokenomicsLib
/// @notice Advanced tokenomics library with bonding curves, vesting, and dynamic supply mechanics
/// @dev Implements multiple bonding curve types and sophisticated supply management
/// @author playground-zkaedi
library TokenomicsLib {
    // ============ Custom Errors ============
    error InvalidSupply();
    error InvalidReserve();
    error InvalidSlope();
    error InsufficientLiquidity();
    error InsufficientTokens();
    error SlippageExceeded(uint256 expected, uint256 actual);
    error CurveNotInitialized();
    error InvalidCurveType();
    error InvalidExponent();
    error OverflowProtection();
    error VestingNotStarted();
    error VestingAlreadyStarted();
    error NothingToVest();
    error InvalidVestingSchedule();
    error CliffNotReached();

    // ============ Constants ============
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant BPS = 10000;
    uint256 internal constant MAX_EXPONENT = 5;

    // Taylor series coefficients for exp approximation (scaled by 1e18)
    uint256 internal constant E = 2718281828459045235; // e ≈ 2.718...

    // ============ Enums ============
    enum CurveType {
        Linear,           // y = mx + b
        Polynomial,       // y = a * x^n + b
        Exponential,      // y = a * e^(bx)
        Logarithmic,      // y = a * ln(x + 1) + b
        Sigmoid,          // y = L / (1 + e^(-k(x-x0)))
        Bancor            // Bancor formula with reserve ratio
    }

    // ============ Structs ============

    /// @notice Configuration for a bonding curve
    struct BondingCurve {
        CurveType curveType;
        uint256 slope;              // Primary coefficient (a)
        uint256 intercept;          // Secondary coefficient (b)
        uint256 exponent;           // For polynomial curves
        uint256 reserveRatio;       // For Bancor (in BPS)
        uint256 currentSupply;      // Current token supply on curve
        uint256 reserveBalance;     // ETH/token reserve balance
        bool initialized;
    }

    /// @notice Parameters for price calculation
    struct PriceParams {
        uint256 supply;
        uint256 amount;
        uint256 reserveBalance;
        uint256 reserveRatio;
    }

    /// @notice Vesting schedule configuration
    struct VestingSchedule {
        uint256 totalAmount;        // Total tokens to vest
        uint256 startTime;          // Vesting start timestamp
        uint256 cliffDuration;      // Cliff period in seconds
        uint256 vestingDuration;    // Total vesting period
        uint256 releasedAmount;     // Amount already released
        uint256 revokedTime;        // If revoked, timestamp (0 = not revoked)
        bool revocable;             // Can be revoked by admin
        bool initialized;
    }

    /// @notice Dynamic supply configuration
    struct DynamicSupply {
        uint256 baseSupply;         // Initial supply
        uint256 currentSupply;      // Current circulating supply
        uint256 maxSupply;          // Hard cap
        uint256 minSupply;          // Floor (for deflationary)
        uint256 targetInflation;    // Target annual inflation (in BPS)
        uint256 lastRebaseTime;     // Last supply adjustment
        uint256 rebaseInterval;     // Time between rebases
        uint256 dampingFactor;      // Rate limiting (in BPS)
        bool initialized;
    }

    /// @notice Emission schedule for token distribution
    struct EmissionSchedule {
        uint256 initialRate;        // Initial tokens per second
        uint256 decayRate;          // Decay percentage per epoch (in BPS)
        uint256 epochDuration;      // Duration of each epoch
        uint256 startTime;          // Schedule start time
        uint256 minRate;            // Minimum emission rate floor
        uint256 totalEmitted;       // Total tokens emitted
        bool initialized;
    }

    // ============ Bonding Curve Functions ============

    /// @notice Initialize a linear bonding curve
    /// @param curve The curve storage reference
    /// @param slope Price increase per token
    /// @param intercept Starting price
    function initializeLinear(
        BondingCurve storage curve,
        uint256 slope,
        uint256 intercept
    ) internal {
        curve.curveType = CurveType.Linear;
        curve.slope = slope;
        curve.intercept = intercept;
        curve.initialized = true;
    }

    /// @notice Initialize a polynomial bonding curve
    /// @param curve The curve storage reference
    /// @param coefficient The 'a' coefficient
    /// @param exponent The power (1-5)
    /// @param intercept Base price
    function initializePolynomial(
        BondingCurve storage curve,
        uint256 coefficient,
        uint256 exponent,
        uint256 intercept
    ) internal {
        if (exponent == 0 || exponent > MAX_EXPONENT) revert InvalidExponent();

        curve.curveType = CurveType.Polynomial;
        curve.slope = coefficient;
        curve.exponent = exponent;
        curve.intercept = intercept;
        curve.initialized = true;
    }

    /// @notice Initialize a Bancor-style curve
    /// @param curve The curve storage reference
    /// @param reserveRatio Reserve ratio in BPS (e.g., 5000 = 50%)
    /// @param initialSupply Initial token supply
    /// @param initialReserve Initial reserve balance
    function initializeBancor(
        BondingCurve storage curve,
        uint256 reserveRatio,
        uint256 initialSupply,
        uint256 initialReserve
    ) internal {
        if (reserveRatio == 0 || reserveRatio > BPS) revert InvalidSlope();
        if (initialSupply == 0) revert InvalidSupply();

        curve.curveType = CurveType.Bancor;
        curve.reserveRatio = reserveRatio;
        curve.currentSupply = initialSupply;
        curve.reserveBalance = initialReserve;
        curve.initialized = true;
    }

    /// @notice Initialize exponential curve
    function initializeExponential(
        BondingCurve storage curve,
        uint256 base,
        uint256 growthRate
    ) internal {
        curve.curveType = CurveType.Exponential;
        curve.slope = base;
        curve.intercept = growthRate;
        curve.initialized = true;
    }

    /// @notice Initialize sigmoid curve (S-curve)
    function initializeSigmoid(
        BondingCurve storage curve,
        uint256 maxPrice,
        uint256 steepness,
        uint256 midpoint
    ) internal {
        curve.curveType = CurveType.Sigmoid;
        curve.slope = maxPrice;
        curve.intercept = steepness;
        curve.exponent = midpoint;
        curve.initialized = true;
    }

    // ============ Price Calculations ============

    /// @notice Get current spot price
    /// @param curve The bonding curve
    /// @return price Current price per token
    function getSpotPrice(BondingCurve storage curve) internal view returns (uint256 price) {
        _checkCurveInitialized(curve);
        return _calculatePrice(curve, curve.currentSupply);
    }

    /// @notice Calculate price at a given supply level
    function getPriceAtSupply(
        BondingCurve storage curve,
        uint256 supply
    ) internal view returns (uint256) {
        _checkCurveInitialized(curve);
        return _calculatePrice(curve, supply);
    }

    /// @notice Calculate cost to buy tokens
    /// @param curve The bonding curve
    /// @param amount Number of tokens to buy
    /// @return cost Total cost in reserve currency
    function calculateBuyCost(
        BondingCurve storage curve,
        uint256 amount
    ) internal view returns (uint256 cost) {
        _checkCurveInitialized(curve);

        if (curve.curveType == CurveType.Bancor) {
            return _bancorBuyCost(curve, amount);
        }

        // Integrate price curve from current supply to supply + amount
        return _integratePrice(curve, curve.currentSupply, curve.currentSupply + amount);
    }

    /// @notice Calculate return from selling tokens
    /// @param curve The bonding curve
    /// @param amount Number of tokens to sell
    /// @return returnAmount Amount of reserve currency returned
    function calculateSellReturn(
        BondingCurve storage curve,
        uint256 amount
    ) internal view returns (uint256 returnAmount) {
        _checkCurveInitialized(curve);

        if (amount > curve.currentSupply) revert InsufficientTokens();

        if (curve.curveType == CurveType.Bancor) {
            return _bancorSellReturn(curve, amount);
        }

        return _integratePrice(curve, curve.currentSupply - amount, curve.currentSupply);
    }

    /// @notice Execute a buy on the curve (updates state)
    function executeBuy(
        BondingCurve storage curve,
        uint256 reserveAmount,
        uint256 minTokens
    ) internal returns (uint256 tokensOut) {
        _checkCurveInitialized(curve);

        if (curve.curveType == CurveType.Bancor) {
            tokensOut = _bancorPurchaseReturn(curve, reserveAmount);
        } else {
            // Binary search for tokens purchasable with reserveAmount
            tokensOut = _calculateTokensForReserve(curve, reserveAmount);
        }

        if (tokensOut < minTokens) revert SlippageExceeded(minTokens, tokensOut);

        curve.currentSupply += tokensOut;
        curve.reserveBalance += reserveAmount;

        return tokensOut;
    }

    /// @notice Execute a sell on the curve (updates state)
    function executeSell(
        BondingCurve storage curve,
        uint256 tokenAmount,
        uint256 minReserve
    ) internal returns (uint256 reserveOut) {
        _checkCurveInitialized(curve);

        if (tokenAmount > curve.currentSupply) revert InsufficientTokens();

        reserveOut = calculateSellReturn(curve, tokenAmount);

        if (reserveOut < minReserve) revert SlippageExceeded(minReserve, reserveOut);
        if (reserveOut > curve.reserveBalance) revert InsufficientLiquidity();

        curve.currentSupply -= tokenAmount;
        curve.reserveBalance -= reserveOut;

        return reserveOut;
    }

    // ============ Vesting Functions ============

    /// @notice Create a vesting schedule
    function createVestingSchedule(
        VestingSchedule storage schedule,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) internal {
        if (totalAmount == 0) revert InvalidVestingSchedule();
        if (vestingDuration == 0) revert InvalidVestingSchedule();
        if (cliffDuration > vestingDuration) revert InvalidVestingSchedule();
        if (startTime == 0) startTime = block.timestamp;

        schedule.totalAmount = totalAmount;
        schedule.startTime = startTime;
        schedule.cliffDuration = cliffDuration;
        schedule.vestingDuration = vestingDuration;
        schedule.releasedAmount = 0;
        schedule.revocable = revocable;
        schedule.revokedTime = 0;
        schedule.initialized = true;
    }

    /// @notice Calculate vested amount at current time
    function vestedAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        return vestedAmountAt(schedule, block.timestamp);
    }

    /// @notice Calculate vested amount at a specific time
    function vestedAmountAt(
        VestingSchedule storage schedule,
        uint256 timestamp
    ) internal view returns (uint256) {
        if (!schedule.initialized) return 0;
        if (timestamp < schedule.startTime) return 0;

        // Check cliff
        uint256 cliffEnd = schedule.startTime + schedule.cliffDuration;
        if (timestamp < cliffEnd) return 0;

        // Handle revocation
        uint256 effectiveTime = schedule.revokedTime > 0
            ? _min(timestamp, schedule.revokedTime)
            : timestamp;

        uint256 vestingEnd = schedule.startTime + schedule.vestingDuration;

        if (effectiveTime >= vestingEnd) {
            return schedule.totalAmount;
        }

        // Linear vesting
        uint256 elapsed = effectiveTime - schedule.startTime;
        return (schedule.totalAmount * elapsed) / schedule.vestingDuration;
    }

    /// @notice Calculate releasable amount
    function releasableAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        return vestedAmount(schedule) - schedule.releasedAmount;
    }

    /// @notice Release vested tokens
    function release(VestingSchedule storage schedule) internal returns (uint256 amount) {
        amount = releasableAmount(schedule);
        if (amount == 0) revert NothingToVest();

        schedule.releasedAmount += amount;
        return amount;
    }

    /// @notice Revoke vesting schedule
    function revoke(VestingSchedule storage schedule) internal returns (uint256 unvested) {
        if (!schedule.revocable) revert InvalidVestingSchedule();
        if (schedule.revokedTime > 0) revert VestingAlreadyStarted();

        schedule.revokedTime = block.timestamp;
        unvested = schedule.totalAmount - vestedAmount(schedule);
        return unvested;
    }

    /// @notice Get vesting progress as percentage (in BPS)
    function getVestingProgress(VestingSchedule storage schedule) internal view returns (uint256) {
        if (!schedule.initialized || schedule.totalAmount == 0) return 0;
        return (vestedAmount(schedule) * BPS) / schedule.totalAmount;
    }

    // ============ Dynamic Supply Functions ============

    /// @notice Initialize dynamic supply management
    function initializeDynamicSupply(
        DynamicSupply storage ds,
        uint256 baseSupply,
        uint256 maxSupply,
        uint256 minSupply,
        uint256 targetInflation,
        uint256 rebaseInterval
    ) internal {
        if (baseSupply == 0) revert InvalidSupply();
        if (maxSupply < baseSupply) revert InvalidSupply();
        if (minSupply > baseSupply) revert InvalidSupply();

        ds.baseSupply = baseSupply;
        ds.currentSupply = baseSupply;
        ds.maxSupply = maxSupply;
        ds.minSupply = minSupply;
        ds.targetInflation = targetInflation;
        ds.rebaseInterval = rebaseInterval;
        ds.lastRebaseTime = block.timestamp;
        ds.dampingFactor = 5000; // 50% damping by default
        ds.initialized = true;
    }

    /// @notice Calculate rebase adjustment
    function calculateRebase(
        DynamicSupply storage ds,
        uint256 currentPrice,
        uint256 targetPrice
    ) internal view returns (int256 adjustment) {
        if (!ds.initialized) return 0;
        if (block.timestamp < ds.lastRebaseTime + ds.rebaseInterval) return 0;

        // Price deviation from target
        int256 deviation;
        if (currentPrice > targetPrice) {
            deviation = int256(((currentPrice - targetPrice) * BPS) / targetPrice);
        } else {
            deviation = -int256(((targetPrice - currentPrice) * BPS) / targetPrice);
        }

        // Apply damping factor
        adjustment = (deviation * int256(ds.dampingFactor)) / int256(BPS);

        // Calculate supply change
        int256 supplyChange = (int256(ds.currentSupply) * adjustment) / int256(BPS);

        return supplyChange;
    }

    /// @notice Execute rebase
    function executeRebase(
        DynamicSupply storage ds,
        int256 adjustment
    ) internal returns (uint256 newSupply) {
        if (!ds.initialized) revert InvalidSupply();

        if (adjustment > 0) {
            newSupply = ds.currentSupply + uint256(adjustment);
            if (newSupply > ds.maxSupply) newSupply = ds.maxSupply;
        } else {
            uint256 decrease = uint256(-adjustment);
            if (decrease > ds.currentSupply - ds.minSupply) {
                newSupply = ds.minSupply;
            } else {
                newSupply = ds.currentSupply - decrease;
            }
        }

        ds.currentSupply = newSupply;
        ds.lastRebaseTime = block.timestamp;

        return newSupply;
    }

    /// @notice Calculate inflation/deflation rate
    function getCurrentInflationRate(DynamicSupply storage ds) internal view returns (int256) {
        if (!ds.initialized || ds.baseSupply == 0) return 0;

        if (ds.currentSupply >= ds.baseSupply) {
            return int256(((ds.currentSupply - ds.baseSupply) * BPS) / ds.baseSupply);
        } else {
            return -int256(((ds.baseSupply - ds.currentSupply) * BPS) / ds.baseSupply);
        }
    }

    // ============ Emission Schedule Functions ============

    /// @notice Initialize emission schedule
    function initializeEmission(
        EmissionSchedule storage schedule,
        uint256 initialRate,
        uint256 decayRate,
        uint256 epochDuration,
        uint256 minRate
    ) internal {
        if (initialRate == 0) revert InvalidSupply();
        if (decayRate > BPS) revert InvalidSlope();
        if (epochDuration == 0) revert InvalidVestingSchedule();

        schedule.initialRate = initialRate;
        schedule.decayRate = decayRate;
        schedule.epochDuration = epochDuration;
        schedule.startTime = block.timestamp;
        schedule.minRate = minRate;
        schedule.totalEmitted = 0;
        schedule.initialized = true;
    }

    /// @notice Get current emission rate
    function getCurrentEmissionRate(
        EmissionSchedule storage schedule
    ) internal view returns (uint256) {
        if (!schedule.initialized) return 0;

        uint256 elapsed = block.timestamp - schedule.startTime;
        uint256 epochs = elapsed / schedule.epochDuration;

        uint256 rate = schedule.initialRate;

        // Apply decay for each epoch
        for (uint256 i = 0; i < epochs && rate > schedule.minRate; i++) {
            rate = (rate * (BPS - schedule.decayRate)) / BPS;
        }

        return rate < schedule.minRate ? schedule.minRate : rate;
    }

    /// @notice Calculate pending emissions
    function calculatePendingEmissions(
        EmissionSchedule storage schedule,
        uint256 lastClaim
    ) internal view returns (uint256) {
        if (!schedule.initialized) return 0;
        if (lastClaim < schedule.startTime) lastClaim = schedule.startTime;

        uint256 currentTime = block.timestamp;
        if (currentTime <= lastClaim) return 0;

        // Simplified: use average rate over period
        uint256 startRate = _getRateAtTime(schedule, lastClaim);
        uint256 endRate = _getRateAtTime(schedule, currentTime);
        uint256 avgRate = (startRate + endRate) / 2;

        return avgRate * (currentTime - lastClaim);
    }

    /// @notice Claim emissions
    function claimEmissions(
        EmissionSchedule storage schedule,
        uint256 lastClaim
    ) internal returns (uint256 emissions) {
        emissions = calculatePendingEmissions(schedule, lastClaim);
        schedule.totalEmitted += emissions;
        return emissions;
    }

    // ============ Internal Price Functions ============

    function _checkCurveInitialized(BondingCurve storage curve) private view {
        if (!curve.initialized) revert CurveNotInitialized();
    }

    function _calculatePrice(
        BondingCurve storage curve,
        uint256 supply
    ) private view returns (uint256) {
        if (curve.curveType == CurveType.Linear) {
            // y = mx + b
            return (curve.slope * supply) / PRECISION + curve.intercept;
        } else if (curve.curveType == CurveType.Polynomial) {
            // y = a * x^n + b
            uint256 powered = _pow(supply, curve.exponent);
            return (curve.slope * powered) / PRECISION + curve.intercept;
        } else if (curve.curveType == CurveType.Exponential) {
            // y = a * e^(bx)
            uint256 exponent = (curve.intercept * supply) / PRECISION;
            return (curve.slope * _exp(exponent)) / PRECISION;
        } else if (curve.curveType == CurveType.Sigmoid) {
            // y = L / (1 + e^(-k(x-x0)))
            return _calculateSigmoid(curve.slope, curve.intercept, curve.exponent, supply);
        } else if (curve.curveType == CurveType.Bancor) {
            // Price = Reserve / (Supply * ReserveRatio)
            if (curve.currentSupply == 0) return curve.intercept;
            return (curve.reserveBalance * BPS * PRECISION) /
                   (curve.currentSupply * curve.reserveRatio);
        }

        return 0;
    }

    function _integratePrice(
        BondingCurve storage curve,
        uint256 fromSupply,
        uint256 toSupply
    ) private view returns (uint256) {
        if (curve.curveType == CurveType.Linear) {
            // ∫(mx + b)dx = (m/2)x² + bx
            uint256 upperArea = (curve.slope * toSupply * toSupply) / (2 * PRECISION) +
                               curve.intercept * toSupply;
            uint256 lowerArea = (curve.slope * fromSupply * fromSupply) / (2 * PRECISION) +
                               curve.intercept * fromSupply;
            return upperArea - lowerArea;
        } else if (curve.curveType == CurveType.Polynomial) {
            // ∫(ax^n + b)dx = a/(n+1) * x^(n+1) + bx
            uint256 n1 = curve.exponent + 1;
            uint256 upperArea = (curve.slope * _pow(toSupply, n1)) / (n1 * PRECISION) +
                               curve.intercept * toSupply;
            uint256 lowerArea = (curve.slope * _pow(fromSupply, n1)) / (n1 * PRECISION) +
                               curve.intercept * fromSupply;
            return upperArea - lowerArea;
        }

        // For other curves, use numerical integration (Simpson's rule)
        return _numericalIntegrate(curve, fromSupply, toSupply, 100);
    }

    function _numericalIntegrate(
        BondingCurve storage curve,
        uint256 from,
        uint256 to,
        uint256 steps
    ) private view returns (uint256) {
        if (from >= to) return 0;

        uint256 h = (to - from) / steps;
        uint256 sum = _calculatePrice(curve, from) + _calculatePrice(curve, to);

        for (uint256 i = 1; i < steps; i++) {
            uint256 x = from + i * h;
            uint256 coeff = (i % 2 == 0) ? 2 : 4;
            sum += coeff * _calculatePrice(curve, x);
        }

        return (sum * h) / 3;
    }

    function _calculateTokensForReserve(
        BondingCurve storage curve,
        uint256 reserveAmount
    ) private view returns (uint256) {
        // Binary search
        uint256 low = 0;
        uint256 high = reserveAmount * PRECISION / curve.intercept; // Upper bound estimate

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            uint256 cost = _integratePrice(curve, curve.currentSupply, curve.currentSupply + mid);

            if (cost <= reserveAmount) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    // ============ Bancor Formula Functions ============

    function _bancorBuyCost(
        BondingCurve storage curve,
        uint256 tokenAmount
    ) private view returns (uint256) {
        // Cost = Reserve * ((1 + tokens/supply)^(1/RR) - 1)
        // Simplified approximation for gas efficiency
        uint256 supplyRatio = (tokenAmount * PRECISION) / curve.currentSupply;
        uint256 exp = (PRECISION * BPS) / curve.reserveRatio;
        uint256 factor = _pow(PRECISION + supplyRatio, exp / PRECISION);
        return (curve.reserveBalance * (factor - PRECISION)) / PRECISION;
    }

    function _bancorSellReturn(
        BondingCurve storage curve,
        uint256 tokenAmount
    ) private view returns (uint256) {
        // Return = Reserve * (1 - (1 - tokens/supply)^(1/RR))
        uint256 supplyRatio = (tokenAmount * PRECISION) / curve.currentSupply;
        if (supplyRatio >= PRECISION) return curve.reserveBalance;

        uint256 exp = (PRECISION * BPS) / curve.reserveRatio;
        uint256 factor = _pow(PRECISION - supplyRatio, exp / PRECISION);
        return (curve.reserveBalance * (PRECISION - factor)) / PRECISION;
    }

    function _bancorPurchaseReturn(
        BondingCurve storage curve,
        uint256 reserveAmount
    ) private view returns (uint256) {
        // Tokens = Supply * ((1 + deposit/reserve)^RR - 1)
        uint256 reserveRatio = (reserveAmount * PRECISION) / curve.reserveBalance;
        uint256 exp = curve.reserveRatio;
        uint256 factor = _pow(PRECISION + reserveRatio, exp * PRECISION / BPS / PRECISION);
        return (curve.currentSupply * (factor - PRECISION)) / PRECISION;
    }

    // ============ Math Helpers ============

    function _pow(uint256 base, uint256 exp) private pure returns (uint256) {
        if (exp == 0) return PRECISION;
        if (exp == 1) return base;

        uint256 result = PRECISION;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) / PRECISION;
            }
            base = (base * base) / PRECISION;
            exp /= 2;
        }
        return result;
    }

    function _exp(uint256 x) private pure returns (uint256) {
        // Taylor series approximation: e^x ≈ 1 + x + x²/2! + x³/3! + ...
        if (x == 0) return PRECISION;
        if (x > 20 * PRECISION) revert OverflowProtection();

        uint256 sum = PRECISION;
        uint256 term = PRECISION;

        for (uint256 i = 1; i <= 12; i++) {
            term = (term * x) / (i * PRECISION);
            sum += term;
            if (term < 1) break;
        }

        return sum;
    }

    function _calculateSigmoid(
        uint256 maxValue,
        uint256 steepness,
        uint256 midpoint,
        uint256 x
    ) private pure returns (uint256) {
        // y = L / (1 + e^(-k(x-x0)))
        int256 exponent;
        if (x >= midpoint) {
            exponent = -int256((steepness * (x - midpoint)) / PRECISION);
        } else {
            exponent = int256((steepness * (midpoint - x)) / PRECISION);
        }

        uint256 expValue = exponent >= 0 ? _exp(uint256(exponent)) : PRECISION * PRECISION / _exp(uint256(-exponent));
        return (maxValue * PRECISION) / (PRECISION + expValue);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _getRateAtTime(
        EmissionSchedule storage schedule,
        uint256 timestamp
    ) private view returns (uint256) {
        if (timestamp < schedule.startTime) return schedule.initialRate;

        uint256 elapsed = timestamp - schedule.startTime;
        uint256 epochs = elapsed / schedule.epochDuration;

        uint256 rate = schedule.initialRate;
        for (uint256 i = 0; i < epochs && rate > schedule.minRate; i++) {
            rate = (rate * (BPS - schedule.decayRate)) / BPS;
        }

        return rate < schedule.minRate ? schedule.minRate : rate;
    }
}
