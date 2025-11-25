// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IntelligentReentrancyAdaptive
 * @notice Intelligent reentrancy circuit with adaptive thresholds and learning
 * @dev Implements self-adjusting protection based on historical attack patterns
 *
 * Key Features:
 * - Dynamic threshold adjustment
 * - Learning from blocked attempts
 * - Gas-based anomaly detection
 * - Time-decay risk scoring
 * - Adaptive cooldown periods
 */
library IntelligentReentrancyAdaptive {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error AdaptiveThresholdExceeded(uint256 current, uint256 threshold);
    error AdaptiveCooldownActive(uint64 remaining);
    error AdaptiveGasAnomalyDetected();
    error AdaptiveRiskScoreTooHigh(uint256 score);
    error AdaptiveLearningLocked();
    error AdaptiveInvalidConfiguration();
    error AdaptiveCircuitOpen();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    // Initial thresholds
    uint256 internal constant INITIAL_CALL_THRESHOLD = 5;
    uint256 internal constant INITIAL_GAS_THRESHOLD = 500000;
    uint256 internal constant INITIAL_VALUE_THRESHOLD = 10 ether;

    // Adjustment factors (basis points)
    uint256 internal constant INCREASE_FACTOR = 500;   // 5% increase
    uint256 internal constant DECREASE_FACTOR = 200;   // 2% decrease
    uint256 internal constant DECAY_FACTOR = 100;      // 1% decay per period

    // Time constants
    uint64 internal constant MIN_COOLDOWN = 60;        // 1 minute
    uint64 internal constant MAX_COOLDOWN = 86400;     // 24 hours
    uint64 internal constant DECAY_PERIOD = 3600;      // 1 hour
    uint64 internal constant LEARNING_WINDOW = 604800; // 1 week

    // Risk score bounds
    uint256 internal constant MIN_RISK_SCORE = 0;
    uint256 internal constant MAX_RISK_SCORE = 10000;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Adaptive thresholds
    struct AdaptiveThresholds {
        uint256 callThreshold;
        uint256 gasThreshold;
        uint256 valueThreshold;
        uint64 lastAdjustment;
        uint256 adjustmentCount;
    }

    /// @notice Learning state
    struct LearningState {
        uint256 totalAttempts;
        uint256 blockedAttempts;
        uint256 successfulBlocks;
        uint256 falsePositives;
        uint64 learningStarted;
        bool learningActive;
    }

    /// @notice Risk score with decay
    struct DecayingRiskScore {
        uint256 baseScore;
        uint64 lastUpdate;
        uint256 peakScore;
        uint64 peakTimestamp;
    }

    /// @notice Cooldown state
    struct AdaptiveCooldown {
        uint64 cooldownEnd;
        uint64 baseCooldown;
        uint64 currentCooldown;
        uint8 consecutiveViolations;
    }

    /// @notice Operation metrics
    struct OperationMetrics {
        uint256 callCount;
        uint256 totalGasUsed;
        uint256 totalValue;
        uint64 windowStart;
        uint64 windowDuration;
    }

    /// @notice Circuit state
    struct AdaptiveCircuit {
        bool isOpen;
        uint64 openedAt;
        uint256 openReason;
        uint8 halfOpenAttempts;
        uint8 maxHalfOpenAttempts;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event ThresholdAdjusted(string thresholdType, uint256 oldValue, uint256 newValue);
    event RiskScoreUpdated(address indexed subject, uint256 newScore, uint256 decayedFrom);
    event CooldownActivated(address indexed subject, uint64 duration);
    event LearningUpdated(uint256 blocked, uint256 falsePositives, uint256 accuracy);
    event CircuitStateChanged(bool isOpen, uint256 reason);
    event AnomalyLearned(bytes32 indexed patternHash, uint256 severity);
    event AdaptiveMetricsRecorded(uint256 calls, uint256 gas, uint256 value);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize adaptive thresholds
     * @param thresholds The thresholds storage
     */
    function initializeThresholds(AdaptiveThresholds storage thresholds) internal {
        thresholds.callThreshold = INITIAL_CALL_THRESHOLD;
        thresholds.gasThreshold = INITIAL_GAS_THRESHOLD;
        thresholds.valueThreshold = INITIAL_VALUE_THRESHOLD;
        thresholds.lastAdjustment = uint64(block.timestamp);
    }

    /**
     * @notice Initialize with custom thresholds
     * @param thresholds The thresholds storage
     * @param callThreshold Custom call threshold
     * @param gasThreshold Custom gas threshold
     * @param valueThreshold Custom value threshold
     */
    function initializeCustomThresholds(
        AdaptiveThresholds storage thresholds,
        uint256 callThreshold,
        uint256 gasThreshold,
        uint256 valueThreshold
    ) internal {
        if (callThreshold == 0 || gasThreshold == 0) {
            revert AdaptiveInvalidConfiguration();
        }

        thresholds.callThreshold = callThreshold;
        thresholds.gasThreshold = gasThreshold;
        thresholds.valueThreshold = valueThreshold;
        thresholds.lastAdjustment = uint64(block.timestamp);
    }

    /**
     * @notice Initialize learning state
     * @param state The learning state storage
     */
    function initializeLearning(LearningState storage state) internal {
        state.learningStarted = uint64(block.timestamp);
        state.learningActive = true;
    }

    /**
     * @notice Initialize adaptive circuit
     * @param circuit The circuit storage
     * @param maxHalfOpen Maximum half-open attempts
     */
    function initializeCircuit(AdaptiveCircuit storage circuit, uint8 maxHalfOpen) internal {
        circuit.maxHalfOpenAttempts = maxHalfOpen > 0 ? maxHalfOpen : 3;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // THRESHOLD MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check and enforce call threshold
     * @param thresholds The thresholds
     * @param metrics Operation metrics
     */
    function enforceCallThreshold(
        AdaptiveThresholds storage thresholds,
        OperationMetrics storage metrics
    ) internal view {
        _resetMetricsIfNeeded(metrics);

        if (metrics.callCount >= thresholds.callThreshold) {
            revert AdaptiveThresholdExceeded(metrics.callCount, thresholds.callThreshold);
        }
    }

    /**
     * @notice Check and enforce gas threshold
     * @param thresholds The thresholds
     * @param gasUsed Gas used in current operation
     */
    function enforceGasThreshold(
        AdaptiveThresholds storage thresholds,
        uint256 gasUsed
    ) internal view {
        if (gasUsed > thresholds.gasThreshold) {
            revert AdaptiveGasAnomalyDetected();
        }
    }

    /**
     * @notice Check and enforce value threshold
     * @param thresholds The thresholds
     * @param value Value in current operation
     */
    function enforceValueThreshold(
        AdaptiveThresholds storage thresholds,
        uint256 value
    ) internal view {
        if (value > thresholds.valueThreshold) {
            revert AdaptiveThresholdExceeded(value, thresholds.valueThreshold);
        }
    }

    /**
     * @notice Increase thresholds after successful period
     * @param thresholds The thresholds storage
     */
    function increaseThresholds(AdaptiveThresholds storage thresholds) internal {
        uint256 oldCall = thresholds.callThreshold;
        uint256 oldGas = thresholds.gasThreshold;
        uint256 oldValue = thresholds.valueThreshold;

        thresholds.callThreshold = (oldCall * (10000 + INCREASE_FACTOR)) / 10000;
        thresholds.gasThreshold = (oldGas * (10000 + INCREASE_FACTOR)) / 10000;
        thresholds.valueThreshold = (oldValue * (10000 + INCREASE_FACTOR)) / 10000;
        thresholds.lastAdjustment = uint64(block.timestamp);
        thresholds.adjustmentCount++;

        emit ThresholdAdjusted("call", oldCall, thresholds.callThreshold);
        emit ThresholdAdjusted("gas", oldGas, thresholds.gasThreshold);
        emit ThresholdAdjusted("value", oldValue, thresholds.valueThreshold);
    }

    /**
     * @notice Decrease thresholds after attack detection
     * @param thresholds The thresholds storage
     */
    function decreaseThresholds(AdaptiveThresholds storage thresholds) internal {
        uint256 oldCall = thresholds.callThreshold;
        uint256 oldGas = thresholds.gasThreshold;
        uint256 oldValue = thresholds.valueThreshold;

        // Don't go below initial values
        uint256 newCall = (oldCall * (10000 - DECREASE_FACTOR)) / 10000;
        thresholds.callThreshold = newCall > 1 ? newCall : 1;

        uint256 newGas = (oldGas * (10000 - DECREASE_FACTOR)) / 10000;
        thresholds.gasThreshold = newGas > 100000 ? newGas : 100000;

        uint256 newValue = (oldValue * (10000 - DECREASE_FACTOR)) / 10000;
        thresholds.valueThreshold = newValue > 0.1 ether ? newValue : 0.1 ether;

        thresholds.lastAdjustment = uint64(block.timestamp);
        thresholds.adjustmentCount++;

        emit ThresholdAdjusted("call", oldCall, thresholds.callThreshold);
        emit ThresholdAdjusted("gas", oldGas, thresholds.gasThreshold);
        emit ThresholdAdjusted("value", oldValue, thresholds.valueThreshold);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RISK SCORING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update risk score with decay
     * @param riskScore The risk score storage
     * @param addition Amount to add to score
     */
    function updateRiskScore(DecayingRiskScore storage riskScore, uint256 addition) internal {
        uint256 currentScore = getDecayedScore(riskScore);
        uint256 newScore = currentScore + addition;

        if (newScore > MAX_RISK_SCORE) {
            newScore = MAX_RISK_SCORE;
        }

        uint256 oldBase = riskScore.baseScore;
        riskScore.baseScore = newScore;
        riskScore.lastUpdate = uint64(block.timestamp);

        if (newScore > riskScore.peakScore) {
            riskScore.peakScore = newScore;
            riskScore.peakTimestamp = uint64(block.timestamp);
        }

        emit RiskScoreUpdated(msg.sender, newScore, oldBase);
    }

    /**
     * @notice Get current decayed risk score
     * @param riskScore The risk score storage
     * @return Current score after decay
     */
    function getDecayedScore(DecayingRiskScore storage riskScore) internal view returns (uint256) {
        if (riskScore.lastUpdate == 0) return 0;

        uint64 elapsed = uint64(block.timestamp) - riskScore.lastUpdate;
        uint256 decayPeriods = elapsed / DECAY_PERIOD;

        if (decayPeriods == 0) return riskScore.baseScore;

        uint256 score = riskScore.baseScore;
        for (uint256 i = 0; i < decayPeriods && score > 0; i++) {
            score = (score * (10000 - DECAY_FACTOR)) / 10000;
        }

        return score;
    }

    /**
     * @notice Check if risk score exceeds threshold
     * @param riskScore The risk score storage
     * @param threshold Risk threshold
     */
    function enforceRiskScore(
        DecayingRiskScore storage riskScore,
        uint256 threshold
    ) internal view {
        uint256 current = getDecayedScore(riskScore);
        if (current >= threshold) {
            revert AdaptiveRiskScoreTooHigh(current);
        }
    }

    /**
     * @notice Reset risk score
     * @param riskScore The risk score storage
     */
    function resetRiskScore(DecayingRiskScore storage riskScore) internal {
        riskScore.baseScore = 0;
        riskScore.lastUpdate = uint64(block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COOLDOWN MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Activate cooldown
     * @param cooldown The cooldown storage
     */
    function activateCooldown(AdaptiveCooldown storage cooldown) internal {
        cooldown.consecutiveViolations++;

        // Exponential backoff
        uint64 duration = cooldown.baseCooldown > 0
            ? cooldown.baseCooldown
            : MIN_COOLDOWN;

        duration = duration * (1 << cooldown.consecutiveViolations);
        if (duration > MAX_COOLDOWN) {
            duration = MAX_COOLDOWN;
        }

        cooldown.currentCooldown = duration;
        cooldown.cooldownEnd = uint64(block.timestamp) + duration;

        emit CooldownActivated(msg.sender, duration);
    }

    /**
     * @notice Check if cooldown is active
     * @param cooldown The cooldown storage
     */
    function enforceCooldown(AdaptiveCooldown storage cooldown) internal view {
        if (block.timestamp < cooldown.cooldownEnd) {
            revert AdaptiveCooldownActive(cooldown.cooldownEnd - uint64(block.timestamp));
        }
    }

    /**
     * @notice Check cooldown status
     * @param cooldown The cooldown storage
     * @return isActive Whether cooldown is active
     * @return remaining Seconds remaining
     */
    function getCooldownStatus(AdaptiveCooldown storage cooldown) internal view returns (
        bool isActive,
        uint64 remaining
    ) {
        if (block.timestamp >= cooldown.cooldownEnd) {
            return (false, 0);
        }
        return (true, cooldown.cooldownEnd - uint64(block.timestamp));
    }

    /**
     * @notice Reset cooldown on good behavior
     * @param cooldown The cooldown storage
     */
    function resetCooldown(AdaptiveCooldown storage cooldown) internal {
        cooldown.consecutiveViolations = 0;
        cooldown.currentCooldown = cooldown.baseCooldown;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // METRICS TRACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record operation metrics
     * @param metrics The metrics storage
     * @param gasUsed Gas used
     * @param value Value transferred
     */
    function recordMetrics(
        OperationMetrics storage metrics,
        uint256 gasUsed,
        uint256 value
    ) internal {
        _resetMetricsIfNeeded(metrics);

        metrics.callCount++;
        metrics.totalGasUsed += gasUsed;
        metrics.totalValue += value;

        emit AdaptiveMetricsRecorded(metrics.callCount, metrics.totalGasUsed, metrics.totalValue);
    }

    /**
     * @notice Get current metrics
     * @param metrics The metrics storage
     */
    function getMetrics(OperationMetrics storage metrics) internal view returns (
        uint256 calls,
        uint256 gas,
        uint256 value,
        uint64 windowRemaining
    ) {
        uint64 elapsed = uint64(block.timestamp) - metrics.windowStart;
        uint64 remaining = elapsed < metrics.windowDuration
            ? metrics.windowDuration - elapsed
            : 0;

        return (metrics.callCount, metrics.totalGasUsed, metrics.totalValue, remaining);
    }

    /**
     * @notice Set metrics window duration
     * @param metrics The metrics storage
     * @param duration Window duration in seconds
     */
    function setMetricsWindow(OperationMetrics storage metrics, uint64 duration) internal {
        metrics.windowDuration = duration;
        metrics.windowStart = uint64(block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LEARNING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record blocked attempt for learning
     * @param state The learning state
     * @param wasActualAttack Whether this was confirmed as attack
     */
    function recordBlockedAttempt(LearningState storage state, bool wasActualAttack) internal {
        if (!state.learningActive) return;

        state.totalAttempts++;
        state.blockedAttempts++;

        if (wasActualAttack) {
            state.successfulBlocks++;
        } else {
            state.falsePositives++;
        }

        uint256 accuracy = state.blockedAttempts > 0
            ? (state.successfulBlocks * 10000) / state.blockedAttempts
            : 0;

        emit LearningUpdated(state.blockedAttempts, state.falsePositives, accuracy);
    }

    /**
     * @notice Get learning accuracy
     * @param state The learning state
     * @return accuracy Accuracy in basis points
     */
    function getLearningAccuracy(LearningState storage state) internal view returns (uint256 accuracy) {
        if (state.blockedAttempts == 0) return 10000;
        return (state.successfulBlocks * 10000) / state.blockedAttempts;
    }

    /**
     * @notice Check if should adjust based on learning
     * @param state The learning state
     * @return shouldIncrease True if should increase thresholds
     * @return shouldDecrease True if should decrease thresholds
     */
    function shouldAdjustFromLearning(LearningState storage state) internal view returns (
        bool shouldIncrease,
        bool shouldDecrease
    ) {
        uint256 accuracy = getLearningAccuracy(state);

        // If accuracy > 95%, can be more permissive
        if (accuracy > 9500 && state.totalAttempts > 100) {
            return (true, false);
        }

        // If accuracy < 80%, need to be stricter
        if (accuracy < 8000 && state.totalAttempts > 50) {
            return (false, true);
        }

        return (false, false);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CIRCUIT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Open circuit (trip)
     * @param circuit The circuit storage
     * @param reason Reason code for opening
     */
    function openCircuit(AdaptiveCircuit storage circuit, uint256 reason) internal {
        circuit.isOpen = true;
        circuit.openedAt = uint64(block.timestamp);
        circuit.openReason = reason;
        circuit.halfOpenAttempts = 0;

        emit CircuitStateChanged(true, reason);
    }

    /**
     * @notice Check circuit state
     * @param circuit The circuit storage
     */
    function enforceCircuit(AdaptiveCircuit storage circuit) internal view {
        if (circuit.isOpen) {
            revert AdaptiveCircuitOpen();
        }
    }

    /**
     * @notice Attempt half-open test
     * @param circuit The circuit storage
     * @return True if test is allowed
     */
    function attemptHalfOpen(AdaptiveCircuit storage circuit) internal returns (bool) {
        if (!circuit.isOpen) return true;

        if (circuit.halfOpenAttempts >= circuit.maxHalfOpenAttempts) {
            return false;
        }

        circuit.halfOpenAttempts++;
        return true;
    }

    /**
     * @notice Close circuit on successful half-open test
     * @param circuit The circuit storage
     */
    function closeCircuit(AdaptiveCircuit storage circuit) internal {
        circuit.isOpen = false;
        circuit.openReason = 0;
        circuit.halfOpenAttempts = 0;

        emit CircuitStateChanged(false, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current thresholds
     * @param thresholds The thresholds storage
     */
    function getThresholds(AdaptiveThresholds storage thresholds) internal view returns (
        uint256 call,
        uint256 gas,
        uint256 value,
        uint256 adjustments
    ) {
        return (
            thresholds.callThreshold,
            thresholds.gasThreshold,
            thresholds.valueThreshold,
            thresholds.adjustmentCount
        );
    }

    /**
     * @notice Get circuit status
     * @param circuit The circuit storage
     */
    function getCircuitStatus(AdaptiveCircuit storage circuit) internal view returns (
        bool isOpen_,
        uint64 openedAt_,
        uint256 reason,
        uint8 halfOpenAttempts_
    ) {
        return (
            circuit.isOpen,
            circuit.openedAt,
            circuit.openReason,
            circuit.halfOpenAttempts
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _resetMetricsIfNeeded(OperationMetrics storage metrics) private view {
        if (metrics.windowStart == 0 ||
            block.timestamp >= metrics.windowStart + metrics.windowDuration) {
            // Note: In view context, we can only check, not reset
            // Reset should be done in a separate non-view function
        }
    }
}
