// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IntelligentReentrancyPredictor
 * @notice Intelligent reentrancy circuit using pattern detection and prediction
 * @dev Implements behavioral analysis to detect and prevent reentrancy attacks
 *
 * Key Features:
 * - Call pattern analysis
 * - Anomaly detection based on historical behavior
 * - Risk scoring for incoming calls
 * - Attack signature detection
 * - Predictive blocking
 */
library IntelligentReentrancyPredictor {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error PredictorHighRiskCall(uint256 riskScore);
    error PredictorAnomalyDetected(bytes32 anomalyType);
    error PredictorKnownAttackPattern();
    error PredictorCallDepthExceeded();
    error PredictorSuspiciousOrigin(address origin);
    error PredictorRateLimitExceeded();
    error PredictorBlockedCaller(address caller);
    error PredictorInvalidPattern();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    // Risk thresholds (out of 1000)
    uint256 internal constant RISK_LOW = 100;
    uint256 internal constant RISK_MEDIUM = 400;
    uint256 internal constant RISK_HIGH = 700;
    uint256 internal constant RISK_CRITICAL = 900;

    // Pattern detection
    uint8 internal constant MAX_CALL_DEPTH = 10;
    uint8 internal constant PATTERN_WINDOW = 10;

    // Anomaly types
    bytes32 internal constant ANOMALY_RAPID_CALLS = keccak256("RAPID_CALLS");
    bytes32 internal constant ANOMALY_DEEP_NESTING = keccak256("DEEP_NESTING");
    bytes32 internal constant ANOMALY_CIRCULAR_CALL = keccak256("CIRCULAR_CALL");
    bytes32 internal constant ANOMALY_VALUE_EXTRACTION = keccak256("VALUE_EXTRACTION");
    bytes32 internal constant ANOMALY_STATE_MANIPULATION = keccak256("STATE_MANIPULATION");

    // Time windows
    uint64 internal constant RAPID_CALL_WINDOW = 10; // 10 seconds
    uint64 internal constant RATE_LIMIT_WINDOW = 60; // 1 minute

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Call context for analysis
    struct CallContext {
        address caller;
        address origin;
        bytes4 selector;
        uint256 value;
        uint256 gasLimit;
        uint64 timestamp;
        uint64 blockNumber;
        uint8 depth;
    }

    /// @notice Caller behavior profile
    struct CallerProfile {
        uint64 firstSeen;
        uint64 lastSeen;
        uint256 totalCalls;
        uint256 totalValue;
        uint256 successfulCalls;
        uint256 failedCalls;
        uint256 riskScore;
        bool blocked;
    }

    /// @notice Call pattern tracker
    struct PatternTracker {
        bytes4[10] recentSelectors;
        uint64[10] recentTimestamps;
        uint8 patternIndex;
        uint8 currentDepth;
        bytes32 lastPatternHash;
    }

    /// @notice Attack signature database
    struct AttackSignatures {
        mapping(bytes32 => bool) knownPatterns;
        mapping(address => bool) knownAttackers;
        uint256 signatureCount;
    }

    /// @notice Risk assessment result
    struct RiskAssessment {
        uint256 score;
        bytes32[] factors;
        bool shouldBlock;
        string recommendation;
    }

    /// @notice Predictor state
    struct PredictorState {
        uint256 totalAnalyzed;
        uint256 totalBlocked;
        uint256 falsePositives;
        uint64 lastCalibration;
        uint256 sensitivity; // 1-100
        bool active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event RiskAssessed(address indexed caller, uint256 riskScore, bool blocked);
    event AnomalyDetected(address indexed caller, bytes32 indexed anomalyType);
    event AttackPatternMatched(address indexed caller, bytes32 indexed patternHash);
    event CallerBlocked(address indexed caller, uint256 riskScore);
    event CallerUnblocked(address indexed caller);
    event PredictorCalibrated(uint256 sensitivity, uint64 timestamp);
    event PatternRecorded(bytes32 indexed patternHash, address caller);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize predictor state
     * @param state The predictor state storage
     * @param sensitivity Initial sensitivity (1-100)
     */
    function initialize(PredictorState storage state, uint256 sensitivity) internal {
        state.sensitivity = sensitivity > 0 && sensitivity <= 100 ? sensitivity : 50;
        state.active = true;
        state.lastCalibration = uint64(block.timestamp);
    }

    /**
     * @notice Initialize caller profile
     * @param profile The caller profile storage
     */
    function initializeProfile(CallerProfile storage profile) internal {
        profile.firstSeen = uint64(block.timestamp);
        profile.lastSeen = uint64(block.timestamp);
    }

    /**
     * @notice Initialize pattern tracker
     * @param tracker The pattern tracker storage
     */
    function initializeTracker(PatternTracker storage tracker) internal {
        tracker.patternIndex = 0;
        tracker.currentDepth = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RISK ASSESSMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Assess risk of incoming call
     * @param state The predictor state
     * @param profile Caller's profile
     * @param tracker Pattern tracker
     * @param context Current call context
     * @return assessment Risk assessment result
     */
    function assessRisk(
        PredictorState storage state,
        CallerProfile storage profile,
        PatternTracker storage tracker,
        CallContext memory context
    ) internal returns (RiskAssessment memory assessment) {
        if (!state.active) {
            return RiskAssessment(0, new bytes32[](0), false, "Predictor inactive");
        }

        state.totalAnalyzed++;

        uint256 score = 0;
        bytes32[] memory factors = new bytes32[](5);
        uint8 factorCount = 0;

        // Factor 1: Call depth analysis
        if (context.depth > 3) {
            score += (context.depth - 3) * 100;
            factors[factorCount++] = ANOMALY_DEEP_NESTING;
        }

        // Factor 2: Rapid call detection
        if (_isRapidCall(profile, context.timestamp)) {
            score += 200;
            factors[factorCount++] = ANOMALY_RAPID_CALLS;
        }

        // Factor 3: Value extraction pattern
        if (_isValueExtraction(profile, context.value)) {
            score += 300;
            factors[factorCount++] = ANOMALY_VALUE_EXTRACTION;
        }

        // Factor 4: Circular call detection
        if (_isCircularPattern(tracker, context.selector)) {
            score += 400;
            factors[factorCount++] = ANOMALY_CIRCULAR_CALL;
        }

        // Factor 5: Historical risk
        score += profile.riskScore / 10;

        // Apply sensitivity
        score = (score * state.sensitivity) / 100;

        // Determine if should block
        bool shouldBlock = score >= RISK_HIGH || profile.blocked;

        if (shouldBlock) {
            state.totalBlocked++;
        }

        // Resize factors array
        bytes32[] memory actualFactors = new bytes32[](factorCount);
        for (uint8 i = 0; i < factorCount; i++) {
            actualFactors[i] = factors[i];
        }

        assessment = RiskAssessment({
            score: score,
            factors: actualFactors,
            shouldBlock: shouldBlock,
            recommendation: _getRecommendation(score)
        });

        emit RiskAssessed(context.caller, score, shouldBlock);

        return assessment;
    }

    /**
     * @notice Quick risk check without full assessment
     * @param profile Caller's profile
     * @param depth Current call depth
     * @return True if call should be allowed
     */
    function quickCheck(
        CallerProfile storage profile,
        uint8 depth
    ) internal view returns (bool) {
        if (profile.blocked) return false;
        if (depth > MAX_CALL_DEPTH) return false;
        if (profile.riskScore >= RISK_CRITICAL) return false;
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PATTERN DETECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record call pattern
     * @param tracker The pattern tracker
     * @param selector Function selector
     */
    function recordPattern(PatternTracker storage tracker, bytes4 selector) internal {
        uint8 idx = tracker.patternIndex;

        tracker.recentSelectors[idx] = selector;
        tracker.recentTimestamps[idx] = uint64(block.timestamp);
        tracker.patternIndex = (idx + 1) % PATTERN_WINDOW;

        // Calculate pattern hash
        bytes32 patternHash = _calculatePatternHash(tracker);
        tracker.lastPatternHash = patternHash;

        emit PatternRecorded(patternHash, msg.sender);
    }

    /**
     * @notice Increase call depth
     * @param tracker The pattern tracker
     */
    function increaseDepth(PatternTracker storage tracker) internal {
        tracker.currentDepth++;
    }

    /**
     * @notice Decrease call depth
     * @param tracker The pattern tracker
     */
    function decreaseDepth(PatternTracker storage tracker) internal {
        if (tracker.currentDepth > 0) {
            tracker.currentDepth--;
        }
    }

    /**
     * @notice Get current depth
     * @param tracker The pattern tracker
     * @return Current call depth
     */
    function getDepth(PatternTracker storage tracker) internal view returns (uint8) {
        return tracker.currentDepth;
    }

    /**
     * @notice Check for known attack pattern
     * @param signatures Attack signature database
     * @param patternHash Pattern to check
     * @return True if known attack pattern
     */
    function isKnownAttack(
        AttackSignatures storage signatures,
        bytes32 patternHash
    ) internal view returns (bool) {
        return signatures.knownPatterns[patternHash];
    }

    /**
     * @notice Add attack signature
     * @param signatures Attack signature database
     * @param patternHash Pattern hash to add
     */
    function addAttackSignature(
        AttackSignatures storage signatures,
        bytes32 patternHash
    ) internal {
        if (!signatures.knownPatterns[patternHash]) {
            signatures.knownPatterns[patternHash] = true;
            signatures.signatureCount++;
        }
    }

    /**
     * @notice Mark address as known attacker
     * @param signatures Attack signature database
     * @param attacker Address to mark
     */
    function markAttacker(
        AttackSignatures storage signatures,
        address attacker
    ) internal {
        signatures.knownAttackers[attacker] = true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLER PROFILE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update caller profile after call
     * @param profile Caller's profile
     * @param success Whether call succeeded
     * @param value Value transferred
     */
    function updateProfile(
        CallerProfile storage profile,
        bool success,
        uint256 value
    ) internal {
        profile.lastSeen = uint64(block.timestamp);
        profile.totalCalls++;
        profile.totalValue += value;

        if (success) {
            profile.successfulCalls++;
            // Decrease risk on success (slowly)
            if (profile.riskScore > 0) {
                profile.riskScore = profile.riskScore * 99 / 100;
            }
        } else {
            profile.failedCalls++;
            // Increase risk on failure
            profile.riskScore += 10;
        }
    }

    /**
     * @notice Block a caller
     * @param profile Caller's profile
     * @param reason Blocking reason
     */
    function blockCaller(CallerProfile storage profile, uint256 reason) internal {
        profile.blocked = true;
        profile.riskScore = RISK_CRITICAL;
        emit CallerBlocked(msg.sender, reason);
    }

    /**
     * @notice Unblock a caller
     * @param profile Caller's profile
     */
    function unblockCaller(CallerProfile storage profile) internal {
        profile.blocked = false;
        profile.riskScore = RISK_MEDIUM; // Reset to medium, not zero
        emit CallerUnblocked(msg.sender);
    }

    /**
     * @notice Get caller risk level
     * @param profile Caller's profile
     * @return level Risk level string
     */
    function getRiskLevel(CallerProfile storage profile) internal view returns (string memory level) {
        if (profile.blocked) return "BLOCKED";
        if (profile.riskScore >= RISK_CRITICAL) return "CRITICAL";
        if (profile.riskScore >= RISK_HIGH) return "HIGH";
        if (profile.riskScore >= RISK_MEDIUM) return "MEDIUM";
        return "LOW";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ANOMALY DETECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Detect anomalies in call context
     * @param profile Caller's profile
     * @param tracker Pattern tracker
     * @param context Call context
     * @return anomalyType Type of anomaly detected (or zero if none)
     */
    function detectAnomalies(
        CallerProfile storage profile,
        PatternTracker storage tracker,
        CallContext memory context
    ) internal returns (bytes32 anomalyType) {
        // Check for rapid calls
        if (_isRapidCall(profile, context.timestamp)) {
            emit AnomalyDetected(context.caller, ANOMALY_RAPID_CALLS);
            return ANOMALY_RAPID_CALLS;
        }

        // Check for deep nesting
        if (context.depth > MAX_CALL_DEPTH) {
            emit AnomalyDetected(context.caller, ANOMALY_DEEP_NESTING);
            return ANOMALY_DEEP_NESTING;
        }

        // Check for circular patterns
        if (_isCircularPattern(tracker, context.selector)) {
            emit AnomalyDetected(context.caller, ANOMALY_CIRCULAR_CALL);
            return ANOMALY_CIRCULAR_CALL;
        }

        // Check for value extraction
        if (_isValueExtraction(profile, context.value)) {
            emit AnomalyDetected(context.caller, ANOMALY_VALUE_EXTRACTION);
            return ANOMALY_VALUE_EXTRACTION;
        }

        return bytes32(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALIBRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calibrate predictor sensitivity
     * @param state The predictor state
     * @param newSensitivity New sensitivity value (1-100)
     */
    function calibrate(PredictorState storage state, uint256 newSensitivity) internal {
        require(newSensitivity > 0 && newSensitivity <= 100, "Invalid sensitivity");

        state.sensitivity = newSensitivity;
        state.lastCalibration = uint64(block.timestamp);

        emit PredictorCalibrated(newSensitivity, uint64(block.timestamp));
    }

    /**
     * @notice Record false positive for calibration
     * @param state The predictor state
     */
    function recordFalsePositive(PredictorState storage state) internal {
        state.falsePositives++;

        // Auto-calibrate if too many false positives
        if (state.falsePositives > state.totalBlocked / 10 && state.sensitivity > 10) {
            state.sensitivity -= 5;
            emit PredictorCalibrated(state.sensitivity, uint64(block.timestamp));
        }
    }

    /**
     * @notice Enable/disable predictor
     * @param state The predictor state
     * @param active Whether to activate
     */
    function setActive(PredictorState storage state, bool active) internal {
        state.active = active;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get predictor statistics
     * @param state The predictor state
     */
    function getStats(PredictorState storage state) internal view returns (
        uint256 analyzed,
        uint256 blocked,
        uint256 falsePos,
        uint256 sensitivity_
    ) {
        return (
            state.totalAnalyzed,
            state.totalBlocked,
            state.falsePositives,
            state.sensitivity
        );
    }

    /**
     * @notice Get caller profile summary
     * @param profile Caller's profile
     */
    function getProfileSummary(CallerProfile storage profile) internal view returns (
        uint256 calls,
        uint256 riskScore_,
        bool blocked_,
        uint64 firstSeen_
    ) {
        return (
            profile.totalCalls,
            profile.riskScore,
            profile.blocked,
            profile.firstSeen
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _isRapidCall(CallerProfile storage profile, uint64 timestamp) private view returns (bool) {
        return timestamp - profile.lastSeen < RAPID_CALL_WINDOW;
    }

    function _isValueExtraction(CallerProfile storage profile, uint256 value) private view returns (bool) {
        if (profile.totalValue == 0) return false;
        // Flag if trying to extract more than 50% of total value seen
        return value > profile.totalValue / 2;
    }

    function _isCircularPattern(PatternTracker storage tracker, bytes4 selector) private view returns (bool) {
        // Check if same selector appears multiple times recently
        uint8 count = 0;
        for (uint8 i = 0; i < PATTERN_WINDOW; i++) {
            if (tracker.recentSelectors[i] == selector) {
                count++;
                if (count >= 3) return true;
            }
        }
        return false;
    }

    function _calculatePatternHash(PatternTracker storage tracker) private view returns (bytes32) {
        return keccak256(abi.encodePacked(
            tracker.recentSelectors,
            tracker.currentDepth
        ));
    }

    function _getRecommendation(uint256 score) private pure returns (string memory) {
        if (score >= RISK_CRITICAL) return "BLOCK: Critical risk detected";
        if (score >= RISK_HIGH) return "BLOCK: High risk pattern";
        if (score >= RISK_MEDIUM) return "MONITOR: Elevated risk";
        if (score >= RISK_LOW) return "ALLOW: Low risk";
        return "ALLOW: Minimal risk";
    }
}
