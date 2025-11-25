// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IntelligentReentrancyAnalytics
 * @notice Intelligent reentrancy circuit with comprehensive analytics and monitoring
 * @dev Provides detailed metrics, trend analysis, and automated reporting
 *
 * Key Features:
 * - Real-time transaction analytics
 * - Historical trend analysis
 * - Anomaly scoring
 * - Automated reporting
 * - Security metrics dashboard
 */
library IntelligentReentrancyAnalytics {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error AnalyticsAnomalyThresholdExceeded(uint256 score);
    error AnalyticsTrendViolation(bytes32 trendType);
    error AnalyticsRateLimitExceeded();
    error AnalyticsInvalidTimeRange();
    error AnalyticsDataNotAvailable();
    error AnalyticsQuotaExceeded();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    // Time periods
    uint64 internal constant PERIOD_MINUTE = 60;
    uint64 internal constant PERIOD_HOUR = 3600;
    uint64 internal constant PERIOD_DAY = 86400;
    uint64 internal constant PERIOD_WEEK = 604800;

    // Metric types
    uint8 internal constant METRIC_CALLS = 0;
    uint8 internal constant METRIC_GAS = 1;
    uint8 internal constant METRIC_VALUE = 2;
    uint8 internal constant METRIC_FAILURES = 3;
    uint8 internal constant METRIC_BLOCKS = 4;
    uint8 internal constant METRIC_UNIQUE_CALLERS = 5;
    uint8 internal constant METRIC_AVG_DEPTH = 6;
    uint8 internal constant METRIC_ANOMALIES = 7;

    uint8 internal constant MAX_METRICS = 8;

    // Trend directions
    uint8 internal constant TREND_STABLE = 0;
    uint8 internal constant TREND_INCREASING = 1;
    uint8 internal constant TREND_DECREASING = 2;
    uint8 internal constant TREND_VOLATILE = 3;
    uint8 internal constant TREND_SPIKE = 4;

    // Report types
    uint8 internal constant REPORT_SUMMARY = 0;
    uint8 internal constant REPORT_DETAILED = 1;
    uint8 internal constant REPORT_ALERT = 2;
    uint8 internal constant REPORT_AUDIT = 3;

    // Data retention
    uint16 internal constant MAX_HOURLY_BUCKETS = 168;  // 1 week
    uint16 internal constant MAX_DAILY_BUCKETS = 365;   // 1 year

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Single data point
    struct DataPoint {
        uint256 value;
        uint64 timestamp;
        uint64 blockNumber;
    }

    /// @notice Time-series bucket
    struct TimeBucket {
        uint256 sum;
        uint256 count;
        uint256 min;
        uint256 max;
        uint64 startTime;
        uint64 endTime;
    }

    /// @notice Metric storage
    struct MetricData {
        uint256 current;
        uint256 total;
        uint256 peak;
        uint64 peakTimestamp;
        uint256 average;
        uint256 sampleCount;
    }

    /// @notice Analytics dashboard
    struct AnalyticsDashboard {
        MetricData[8] metrics;
        uint64 lastUpdated;
        uint64 startTime;
        uint256 totalTransactions;
        uint256 totalBlocked;
        uint256 totalAnomalies;
        uint8 healthScore;
    }

    /// @notice Trend analysis
    struct TrendAnalysis {
        uint8 direction;
        int256 changePercent;  // Basis points (can be negative)
        uint256 volatility;
        uint64 periodStart;
        uint64 periodEnd;
        uint256 dataPoints;
    }

    /// @notice Anomaly detection
    struct AnomalyDetector {
        uint256 baselineValue;
        uint256 standardDeviation;
        uint256 threshold;  // Multiplier of std dev
        uint256 anomalyCount;
        uint64 lastAnomaly;
        bytes32 lastAnomalyType;
    }

    /// @notice Security report
    struct SecurityReport {
        uint8 reportType;
        uint64 generatedAt;
        uint256 periodStart;
        uint256 periodEnd;
        uint256 totalCalls;
        uint256 blockedCalls;
        uint256 anomalies;
        uint256 riskScore;
        bytes32 reportHash;
    }

    /// @notice Caller analytics
    struct CallerAnalytics {
        uint256 totalCalls;
        uint256 totalValue;
        uint256 avgGasUsed;
        uint64 firstSeen;
        uint64 lastSeen;
        uint8 riskLevel;
        uint256 anomalyScore;
    }

    /// @notice Rate tracking
    struct RateTracker {
        uint256 callsThisMinute;
        uint256 callsThisHour;
        uint256 callsThisDay;
        uint64 minuteStart;
        uint64 hourStart;
        uint64 dayStart;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event MetricRecorded(uint8 indexed metricType, uint256 value, uint64 timestamp);
    event AnomalyDetected(bytes32 indexed anomalyType, uint256 score, uint256 threshold);
    event TrendChanged(uint8 indexed metricType, uint8 newDirection, int256 changePercent);
    event ReportGenerated(uint8 indexed reportType, bytes32 reportHash, uint64 timestamp);
    event HealthScoreUpdated(uint8 oldScore, uint8 newScore);
    event RateLimitTriggered(address indexed caller, uint256 rate, uint256 limit);
    event BaselineUpdated(uint8 indexed metricType, uint256 newBaseline);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize analytics dashboard
     * @param dashboard The dashboard storage
     */
    function initializeDashboard(AnalyticsDashboard storage dashboard) internal {
        dashboard.startTime = uint64(block.timestamp);
        dashboard.lastUpdated = uint64(block.timestamp);
        dashboard.healthScore = 100;

        // Initialize all metrics
        for (uint8 i = 0; i < MAX_METRICS; i++) {
            dashboard.metrics[i].min = type(uint256).max;
        }
    }

    /**
     * @notice Initialize anomaly detector
     * @param detector The detector storage
     * @param baseline Initial baseline value
     * @param threshold Anomaly threshold (multiplier of std dev)
     */
    function initializeAnomalyDetector(
        AnomalyDetector storage detector,
        uint256 baseline,
        uint256 threshold
    ) internal {
        detector.baselineValue = baseline;
        detector.threshold = threshold > 0 ? threshold : 3; // Default 3 std deviations
    }

    /**
     * @notice Initialize rate tracker
     * @param tracker The tracker storage
     */
    function initializeRateTracker(RateTracker storage tracker) internal {
        uint64 now_ = uint64(block.timestamp);
        tracker.minuteStart = now_;
        tracker.hourStart = now_;
        tracker.dayStart = now_;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // METRIC RECORDING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record a metric value
     * @param dashboard The dashboard storage
     * @param metricType Type of metric
     * @param value Value to record
     */
    function recordMetric(
        AnalyticsDashboard storage dashboard,
        uint8 metricType,
        uint256 value
    ) internal {
        if (metricType >= MAX_METRICS) return;

        MetricData storage metric = dashboard.metrics[metricType];

        // Update current
        metric.current = value;
        metric.total += value;
        metric.sampleCount++;

        // Update average
        metric.average = metric.total / metric.sampleCount;

        // Update peak
        if (value > metric.peak) {
            metric.peak = value;
            metric.peakTimestamp = uint64(block.timestamp);
        }

        // Update min (stored in a separate way since MetricData doesn't have min)
        dashboard.lastUpdated = uint64(block.timestamp);

        emit MetricRecorded(metricType, value, uint64(block.timestamp));
    }

    /**
     * @notice Record multiple metrics at once
     * @param dashboard The dashboard storage
     * @param calls Number of calls
     * @param gasUsed Gas used
     * @param value Value transferred
     * @param failed Whether it failed
     */
    function recordTransaction(
        AnalyticsDashboard storage dashboard,
        uint256 calls,
        uint256 gasUsed,
        uint256 value,
        bool failed
    ) internal {
        dashboard.totalTransactions++;

        recordMetric(dashboard, METRIC_CALLS, calls);
        recordMetric(dashboard, METRIC_GAS, gasUsed);
        recordMetric(dashboard, METRIC_VALUE, value);

        if (failed) {
            recordMetric(dashboard, METRIC_FAILURES, 1);
        }
    }

    /**
     * @notice Record blocked attempt
     * @param dashboard The dashboard storage
     */
    function recordBlocked(AnalyticsDashboard storage dashboard) internal {
        dashboard.totalBlocked++;
        recordMetric(dashboard, METRIC_BLOCKS, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ANOMALY DETECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check value against anomaly detector
     * @param detector The detector storage
     * @param value Value to check
     * @return isAnomaly True if anomaly detected
     * @return score Anomaly score
     */
    function checkAnomaly(
        AnomalyDetector storage detector,
        uint256 value
    ) internal returns (bool isAnomaly, uint256 score) {
        if (detector.baselineValue == 0) {
            return (false, 0);
        }

        uint256 deviation;
        if (value > detector.baselineValue) {
            deviation = value - detector.baselineValue;
        } else {
            deviation = detector.baselineValue - value;
        }

        // Calculate how many std deviations away
        if (detector.standardDeviation > 0) {
            score = (deviation * 100) / detector.standardDeviation;
        } else {
            score = (deviation * 100) / detector.baselineValue;
        }

        isAnomaly = score >= (detector.threshold * 100);

        if (isAnomaly) {
            detector.anomalyCount++;
            detector.lastAnomaly = uint64(block.timestamp);
            detector.lastAnomalyType = keccak256(abi.encodePacked(value, block.timestamp));

            emit AnomalyDetected(detector.lastAnomalyType, score, detector.threshold * 100);
        }

        return (isAnomaly, score);
    }

    /**
     * @notice Update baseline from recent data
     * @param detector The detector storage
     * @param newBaseline New baseline value
     * @param newStdDev New standard deviation
     */
    function updateBaseline(
        AnomalyDetector storage detector,
        uint256 newBaseline,
        uint256 newStdDev
    ) internal {
        detector.baselineValue = newBaseline;
        detector.standardDeviation = newStdDev;

        emit BaselineUpdated(0, newBaseline); // 0 = general baseline
    }

    /**
     * @notice Enforce anomaly threshold
     * @param detector The detector storage
     * @param dashboard The dashboard storage
     * @param value Value to check
     */
    function enforceAnomaly(
        AnomalyDetector storage detector,
        AnalyticsDashboard storage dashboard,
        uint256 value
    ) internal {
        (bool isAnomaly, uint256 score) = checkAnomaly(detector, value);

        if (isAnomaly) {
            dashboard.totalAnomalies++;
            recordMetric(dashboard, METRIC_ANOMALIES, 1);
            revert AnalyticsAnomalyThresholdExceeded(score);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TREND ANALYSIS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Analyze trend for a metric
     * @param dashboard The dashboard storage
     * @param metricType Metric to analyze
     * @param periodLength Period in seconds
     * @return analysis Trend analysis result
     */
    function analyzeTrend(
        AnalyticsDashboard storage dashboard,
        uint8 metricType,
        uint64 periodLength
    ) internal view returns (TrendAnalysis memory analysis) {
        if (metricType >= MAX_METRICS) {
            return analysis;
        }

        MetricData storage metric = dashboard.metrics[metricType];

        analysis.periodStart = uint64(block.timestamp) - periodLength;
        analysis.periodEnd = uint64(block.timestamp);
        analysis.dataPoints = metric.sampleCount;

        // Calculate change percent
        if (metric.average > 0 && metric.sampleCount > 1) {
            if (metric.current > metric.average) {
                analysis.changePercent = int256(((metric.current - metric.average) * 10000) / metric.average);
            } else {
                analysis.changePercent = -int256(((metric.average - metric.current) * 10000) / metric.average);
            }
        }

        // Determine direction
        if (analysis.changePercent > 1000) { // > 10%
            analysis.direction = TREND_INCREASING;
        } else if (analysis.changePercent < -1000) { // < -10%
            analysis.direction = TREND_DECREASING;
        } else {
            analysis.direction = TREND_STABLE;
        }

        // Calculate volatility
        if (metric.peak > 0 && metric.average > 0) {
            analysis.volatility = ((metric.peak - metric.average) * 10000) / metric.average;
        }

        // Check for spike
        if (metric.current > metric.average * 3) {
            analysis.direction = TREND_SPIKE;
        }

        return analysis;
    }

    /**
     * @notice Check if trend violates threshold
     * @param dashboard The dashboard storage
     * @param metricType Metric to check
     * @param maxChangePercent Maximum allowed change (basis points)
     */
    function enforceTrend(
        AnalyticsDashboard storage dashboard,
        uint8 metricType,
        int256 maxChangePercent
    ) internal {
        TrendAnalysis memory trend = analyzeTrend(dashboard, metricType, PERIOD_HOUR);

        if (trend.direction == TREND_SPIKE) {
            revert AnalyticsTrendViolation(keccak256("SPIKE"));
        }

        if (trend.changePercent > maxChangePercent || trend.changePercent < -maxChangePercent) {
            revert AnalyticsTrendViolation(keccak256("EXCESSIVE_CHANGE"));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RATE LIMITING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Track and enforce rate limits
     * @param tracker The tracker storage
     * @param minuteLimit Max calls per minute
     * @param hourLimit Max calls per hour
     * @param dayLimit Max calls per day
     */
    function enforceRateLimit(
        RateTracker storage tracker,
        uint256 minuteLimit,
        uint256 hourLimit,
        uint256 dayLimit
    ) internal {
        uint64 now_ = uint64(block.timestamp);

        // Reset counters if period elapsed
        if (now_ >= tracker.minuteStart + PERIOD_MINUTE) {
            tracker.callsThisMinute = 0;
            tracker.minuteStart = now_;
        }
        if (now_ >= tracker.hourStart + PERIOD_HOUR) {
            tracker.callsThisHour = 0;
            tracker.hourStart = now_;
        }
        if (now_ >= tracker.dayStart + PERIOD_DAY) {
            tracker.callsThisDay = 0;
            tracker.dayStart = now_;
        }

        // Increment counters
        tracker.callsThisMinute++;
        tracker.callsThisHour++;
        tracker.callsThisDay++;

        // Check limits
        if (tracker.callsThisMinute > minuteLimit) {
            emit RateLimitTriggered(msg.sender, tracker.callsThisMinute, minuteLimit);
            revert AnalyticsRateLimitExceeded();
        }
        if (tracker.callsThisHour > hourLimit) {
            emit RateLimitTriggered(msg.sender, tracker.callsThisHour, hourLimit);
            revert AnalyticsRateLimitExceeded();
        }
        if (tracker.callsThisDay > dayLimit) {
            emit RateLimitTriggered(msg.sender, tracker.callsThisDay, dayLimit);
            revert AnalyticsRateLimitExceeded();
        }
    }

    /**
     * @notice Get current rates
     * @param tracker The tracker storage
     */
    function getRates(RateTracker storage tracker) internal view returns (
        uint256 perMinute,
        uint256 perHour,
        uint256 perDay
    ) {
        return (tracker.callsThisMinute, tracker.callsThisHour, tracker.callsThisDay);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REPORTING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Generate security report
     * @param dashboard The dashboard storage
     * @param reportType Type of report
     * @param periodStart Report period start
     * @param periodEnd Report period end
     * @return report Generated report
     */
    function generateReport(
        AnalyticsDashboard storage dashboard,
        uint8 reportType,
        uint256 periodStart,
        uint256 periodEnd
    ) internal returns (SecurityReport memory report) {
        report.reportType = reportType;
        report.generatedAt = uint64(block.timestamp);
        report.periodStart = periodStart;
        report.periodEnd = periodEnd;

        report.totalCalls = dashboard.totalTransactions;
        report.blockedCalls = dashboard.totalBlocked;
        report.anomalies = dashboard.totalAnomalies;

        // Calculate risk score
        if (dashboard.totalTransactions > 0) {
            uint256 blockedRatio = (dashboard.totalBlocked * 10000) / dashboard.totalTransactions;
            uint256 anomalyRatio = (dashboard.totalAnomalies * 10000) / dashboard.totalTransactions;

            report.riskScore = blockedRatio + (anomalyRatio * 2);
            if (report.riskScore > 10000) {
                report.riskScore = 10000;
            }
        }

        // Generate report hash
        report.reportHash = keccak256(abi.encodePacked(
            reportType,
            report.generatedAt,
            periodStart,
            periodEnd,
            report.totalCalls,
            report.blockedCalls,
            report.anomalies,
            report.riskScore
        ));

        emit ReportGenerated(reportType, report.reportHash, uint64(block.timestamp));

        return report;
    }

    /**
     * @notice Update health score
     * @param dashboard The dashboard storage
     */
    function updateHealthScore(AnalyticsDashboard storage dashboard) internal {
        uint8 oldScore = dashboard.healthScore;
        uint8 newScore = 100;

        // Deduct for blocked calls
        if (dashboard.totalTransactions > 0) {
            uint256 blockedPercent = (dashboard.totalBlocked * 100) / dashboard.totalTransactions;
            if (blockedPercent > 50) {
                newScore -= 30;
            } else if (blockedPercent > 20) {
                newScore -= 15;
            } else if (blockedPercent > 5) {
                newScore -= 5;
            }
        }

        // Deduct for anomalies
        if (dashboard.totalAnomalies > 100) {
            newScore -= 20;
        } else if (dashboard.totalAnomalies > 50) {
            newScore -= 10;
        } else if (dashboard.totalAnomalies > 10) {
            newScore -= 5;
        }

        // Deduct for high failure rate
        MetricData storage failures = dashboard.metrics[METRIC_FAILURES];
        if (failures.sampleCount > 0 && dashboard.totalTransactions > 0) {
            uint256 failureRate = (failures.total * 100) / dashboard.totalTransactions;
            if (failureRate > 20) {
                newScore -= 20;
            } else if (failureRate > 10) {
                newScore -= 10;
            }
        }

        dashboard.healthScore = newScore;

        if (oldScore != newScore) {
            emit HealthScoreUpdated(oldScore, newScore);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLER ANALYTICS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update caller analytics
     * @param analytics The caller analytics storage
     * @param value Transaction value
     * @param gasUsed Gas used
     */
    function updateCallerAnalytics(
        CallerAnalytics storage analytics,
        uint256 value,
        uint256 gasUsed
    ) internal {
        if (analytics.firstSeen == 0) {
            analytics.firstSeen = uint64(block.timestamp);
        }

        analytics.lastSeen = uint64(block.timestamp);
        analytics.totalCalls++;
        analytics.totalValue += value;

        // Update average gas
        analytics.avgGasUsed = ((analytics.avgGasUsed * (analytics.totalCalls - 1)) + gasUsed) / analytics.totalCalls;
    }

    /**
     * @notice Calculate caller risk level
     * @param analytics The caller analytics storage
     * @return riskLevel Risk level (0-4)
     */
    function calculateCallerRisk(CallerAnalytics storage analytics) internal returns (uint8 riskLevel) {
        riskLevel = 0;

        // High call volume = higher risk
        if (analytics.totalCalls > 1000) {
            riskLevel++;
        }
        if (analytics.totalCalls > 10000) {
            riskLevel++;
        }

        // High value = higher risk
        if (analytics.totalValue > 100 ether) {
            riskLevel++;
        }

        // Recent anomalies = higher risk
        if (analytics.anomalyScore > 500) {
            riskLevel++;
        }

        analytics.riskLevel = riskLevel;
        return riskLevel;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get dashboard summary
     * @param dashboard The dashboard storage
     */
    function getDashboardSummary(AnalyticsDashboard storage dashboard) internal view returns (
        uint256 totalTx,
        uint256 blocked,
        uint256 anomalies,
        uint8 health
    ) {
        return (
            dashboard.totalTransactions,
            dashboard.totalBlocked,
            dashboard.totalAnomalies,
            dashboard.healthScore
        );
    }

    /**
     * @notice Get metric data
     * @param dashboard The dashboard storage
     * @param metricType Metric type
     */
    function getMetric(
        AnalyticsDashboard storage dashboard,
        uint8 metricType
    ) internal view returns (
        uint256 current,
        uint256 average,
        uint256 peak,
        uint256 total
    ) {
        if (metricType >= MAX_METRICS) {
            return (0, 0, 0, 0);
        }

        MetricData storage metric = dashboard.metrics[metricType];
        return (metric.current, metric.average, metric.peak, metric.total);
    }

    /**
     * @notice Get caller summary
     * @param analytics The caller analytics
     */
    function getCallerSummary(CallerAnalytics storage analytics) internal view returns (
        uint256 calls,
        uint256 value,
        uint8 risk,
        uint64 tenure
    ) {
        uint64 tenureDays = analytics.firstSeen > 0
            ? (uint64(block.timestamp) - analytics.firstSeen) / PERIOD_DAY
            : 0;

        return (
            analytics.totalCalls,
            analytics.totalValue,
            analytics.riskLevel,
            tenureDays
        );
    }

    /**
     * @notice Get metric name
     * @param metricType Metric type
     * @return name Metric name
     */
    function getMetricName(uint8 metricType) internal pure returns (string memory name) {
        if (metricType == METRIC_CALLS) return "CALLS";
        if (metricType == METRIC_GAS) return "GAS";
        if (metricType == METRIC_VALUE) return "VALUE";
        if (metricType == METRIC_FAILURES) return "FAILURES";
        if (metricType == METRIC_BLOCKS) return "BLOCKS";
        if (metricType == METRIC_UNIQUE_CALLERS) return "UNIQUE_CALLERS";
        if (metricType == METRIC_AVG_DEPTH) return "AVG_DEPTH";
        if (metricType == METRIC_ANOMALIES) return "ANOMALIES";
        return "UNKNOWN";
    }
}
