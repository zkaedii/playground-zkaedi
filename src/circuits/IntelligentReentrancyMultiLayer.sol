// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IntelligentReentrancyMultiLayer
 * @notice Intelligent reentrancy circuit implementing defense-in-depth strategy
 * @dev Combines multiple protection layers with coordinated response
 *
 * Key Features:
 * - Multiple independent protection layers
 * - Coordinated threat response
 * - Fallback chain protection
 * - Layer health monitoring
 * - Cascading alert system
 */
library IntelligentReentrancyMultiLayer {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error MultiLayerAllLayersFailed();
    error MultiLayerLayerDisabled(uint8 layer);
    error MultiLayerInsufficientLayers();
    error MultiLayerCoordinatedBlock();
    error MultiLayerQuorumNotReached();
    error MultiLayerInvalidLayerConfig();
    error MultiLayerCascadeTriggered();
    error MultiLayerHealthCheckFailed(uint8 layer);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    // Layer identifiers
    uint8 internal constant LAYER_BASIC_GUARD = 0;
    uint8 internal constant LAYER_FUNCTION_GUARD = 1;
    uint8 internal constant LAYER_CALL_DEPTH = 2;
    uint8 internal constant LAYER_GAS_MONITOR = 3;
    uint8 internal constant LAYER_VALUE_MONITOR = 4;
    uint8 internal constant LAYER_PATTERN_DETECTOR = 5;
    uint8 internal constant LAYER_RATE_LIMITER = 6;
    uint8 internal constant LAYER_CIRCUIT_BREAKER = 7;

    uint8 internal constant MAX_LAYERS = 8;

    // Layer status
    uint8 internal constant STATUS_ACTIVE = 1;
    uint8 internal constant STATUS_TRIGGERED = 2;
    uint8 internal constant STATUS_DISABLED = 3;
    uint8 internal constant STATUS_MAINTENANCE = 4;

    // Alert levels
    uint8 internal constant ALERT_NONE = 0;
    uint8 internal constant ALERT_LOW = 1;
    uint8 internal constant ALERT_MEDIUM = 2;
    uint8 internal constant ALERT_HIGH = 3;
    uint8 internal constant ALERT_CRITICAL = 4;

    // Quorum requirements
    uint8 internal constant MIN_LAYERS_FOR_QUORUM = 3;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Individual layer state
    struct Layer {
        uint8 status;
        uint8 alertLevel;
        uint64 lastTriggered;
        uint64 lastHealthCheck;
        uint256 triggerCount;
        uint256 blockCount;
        bool enabled;
    }

    /// @notice Multi-layer coordinator
    struct LayerCoordinator {
        uint8 activeLayerCount;
        uint8 triggeredLayerCount;
        uint8 requiredQuorum;
        uint8 currentAlertLevel;
        uint64 lastCoordinatedAction;
        bool cascadeActive;
    }

    /// @notice Layer health metrics
    struct LayerHealth {
        uint256 successfulChecks;
        uint256 failedChecks;
        uint64 uptime;
        uint64 lastFailure;
        uint256 avgResponseTime;
    }

    /// @notice Coordinated response
    struct CoordinatedResponse {
        uint8[] respondingLayers;
        uint8 consensusLevel;
        bytes32 threatHash;
        uint64 timestamp;
        bool actionTaken;
    }

    /// @notice Defense configuration
    struct DefenseConfig {
        uint8 minActiveLayers;
        uint8 quorumForBlock;
        uint8 cascadeThreshold;
        uint64 healthCheckInterval;
        bool allowPartialProtection;
    }

    /// @notice Layer check result
    struct LayerCheckResult {
        uint8 layerId;
        bool passed;
        uint8 alertLevel;
        bytes32 reason;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event LayerTriggered(uint8 indexed layerId, uint8 alertLevel, bytes32 reason);
    event LayerStatusChanged(uint8 indexed layerId, uint8 oldStatus, uint8 newStatus);
    event CoordinatedResponseInitiated(bytes32 indexed threatHash, uint8 respondingLayers);
    event QuorumReached(uint8 layersAgreeing, uint8 required);
    event CascadeActivated(uint8 triggeringLayer, uint8 affectedLayers);
    event AlertLevelChanged(uint8 oldLevel, uint8 newLevel);
    event LayerHealthUpdated(uint8 indexed layerId, bool healthy);
    event DefenseConfigUpdated(uint8 minLayers, uint8 quorum);

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize all layers
     * @param layers Array of layer storage
     * @param coordinator The coordinator storage
     */
    function initializeAllLayers(
        Layer[8] storage layers,
        LayerCoordinator storage coordinator
    ) internal {
        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            layers[i].status = STATUS_ACTIVE;
            layers[i].enabled = true;
            layers[i].lastHealthCheck = uint64(block.timestamp);
        }

        coordinator.activeLayerCount = MAX_LAYERS;
        coordinator.requiredQuorum = MIN_LAYERS_FOR_QUORUM;
    }

    /**
     * @notice Initialize specific layers
     * @param layers Array of layer storage
     * @param coordinator The coordinator storage
     * @param enabledLayers Bitmap of layers to enable
     */
    function initializeSelectLayers(
        Layer[8] storage layers,
        LayerCoordinator storage coordinator,
        uint8 enabledLayers
    ) internal {
        uint8 activeCount = 0;

        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            bool enabled = (enabledLayers & (1 << i)) != 0;
            layers[i].enabled = enabled;
            layers[i].status = enabled ? STATUS_ACTIVE : STATUS_DISABLED;
            layers[i].lastHealthCheck = uint64(block.timestamp);

            if (enabled) {
                activeCount++;
            }
        }

        coordinator.activeLayerCount = activeCount;
        coordinator.requiredQuorum = activeCount >= 3 ? 3 : activeCount;
    }

    /**
     * @notice Initialize defense configuration
     * @param config The config storage
     * @param minLayers Minimum active layers
     * @param quorum Required quorum for blocking
     * @param cascadeThreshold Layers to trigger cascade
     */
    function initializeConfig(
        DefenseConfig storage config,
        uint8 minLayers,
        uint8 quorum,
        uint8 cascadeThreshold
    ) internal {
        config.minActiveLayers = minLayers;
        config.quorumForBlock = quorum;
        config.cascadeThreshold = cascadeThreshold;
        config.healthCheckInterval = 3600; // 1 hour
        config.allowPartialProtection = true;

        emit DefenseConfigUpdated(minLayers, quorum);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER CHECKS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Run check on specific layer
     * @param layer The layer storage
     * @param layerId Layer identifier
     * @param checkData Data for the check
     * @return result Check result
     */
    function checkLayer(
        Layer storage layer,
        uint8 layerId,
        bytes memory checkData
    ) internal returns (LayerCheckResult memory result) {
        result.layerId = layerId;

        if (!layer.enabled || layer.status == STATUS_DISABLED) {
            result.passed = true; // Disabled layers pass by default
            result.alertLevel = ALERT_NONE;
            return result;
        }

        // Perform layer-specific check
        (bool passed, uint8 alertLevel, bytes32 reason) = _executeLayerCheck(layerId, checkData);

        result.passed = passed;
        result.alertLevel = alertLevel;
        result.reason = reason;

        if (!passed) {
            layer.triggerCount++;
            layer.lastTriggered = uint64(block.timestamp);
            layer.alertLevel = alertLevel;

            if (alertLevel >= ALERT_HIGH) {
                layer.status = STATUS_TRIGGERED;
            }

            emit LayerTriggered(layerId, alertLevel, reason);
        }

        return result;
    }

    /**
     * @notice Run all enabled layer checks
     * @param layers Array of layer storage
     * @param coordinator The coordinator storage
     * @param checkData Data for the checks
     * @return results Array of results
     * @return shouldBlock Whether to block based on results
     */
    function checkAllLayers(
        Layer[8] storage layers,
        LayerCoordinator storage coordinator,
        bytes memory checkData
    ) internal returns (LayerCheckResult[] memory results, bool shouldBlock) {
        results = new LayerCheckResult[](MAX_LAYERS);
        uint8 failedCount = 0;
        uint8 maxAlertLevel = ALERT_NONE;

        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            results[i] = checkLayer(layers[i], i, checkData);

            if (!results[i].passed) {
                failedCount++;
                if (results[i].alertLevel > maxAlertLevel) {
                    maxAlertLevel = results[i].alertLevel;
                }
            }
        }

        coordinator.triggeredLayerCount = failedCount;

        // Update alert level
        if (maxAlertLevel != coordinator.currentAlertLevel) {
            emit AlertLevelChanged(coordinator.currentAlertLevel, maxAlertLevel);
            coordinator.currentAlertLevel = maxAlertLevel;
        }

        // Determine if should block based on quorum
        shouldBlock = failedCount >= coordinator.requiredQuorum;

        if (shouldBlock) {
            emit QuorumReached(failedCount, coordinator.requiredQuorum);
        }

        return (results, shouldBlock);
    }

    /**
     * @notice Quick multi-layer check
     * @param layers Array of layer storage
     * @param coordinator The coordinator
     * @return allowed True if all critical layers pass
     */
    function quickCheck(
        Layer[8] storage layers,
        LayerCoordinator storage coordinator
    ) internal view returns (bool allowed) {
        if (coordinator.cascadeActive) {
            return false;
        }

        uint8 failedCritical = 0;

        // Check only critical layers (0-3)
        for (uint8 i = 0; i < 4; i++) {
            if (layers[i].enabled && layers[i].status == STATUS_TRIGGERED) {
                failedCritical++;
            }
        }

        return failedCritical < coordinator.requiredQuorum;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COORDINATED RESPONSE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initiate coordinated response
     * @param response The response storage
     * @param coordinator The coordinator
     * @param threatHash Hash identifying the threat
     * @param triggeringLayers Bitmap of layers that triggered
     */
    function initiateCoordinatedResponse(
        CoordinatedResponse storage response,
        LayerCoordinator storage coordinator,
        bytes32 threatHash,
        uint8 triggeringLayers
    ) internal {
        uint8 count = 0;
        uint8[] memory responding = new uint8[](MAX_LAYERS);

        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            if ((triggeringLayers & (1 << i)) != 0) {
                responding[count] = i;
                count++;
            }
        }

        // Resize array
        response.respondingLayers = new uint8[](count);
        for (uint8 i = 0; i < count; i++) {
            response.respondingLayers[i] = responding[i];
        }

        response.threatHash = threatHash;
        response.timestamp = uint64(block.timestamp);
        response.consensusLevel = count;

        coordinator.lastCoordinatedAction = uint64(block.timestamp);

        emit CoordinatedResponseInitiated(threatHash, count);
    }

    /**
     * @notice Execute coordinated block
     * @param coordinator The coordinator
     * @param config The defense config
     * @param triggeredCount Number of triggered layers
     */
    function executeCoordinatedBlock(
        LayerCoordinator storage coordinator,
        DefenseConfig storage config,
        uint8 triggeredCount
    ) internal {
        if (triggeredCount < config.quorumForBlock) {
            revert MultiLayerQuorumNotReached();
        }

        coordinator.lastCoordinatedAction = uint64(block.timestamp);

        // Check for cascade
        if (triggeredCount >= config.cascadeThreshold) {
            coordinator.cascadeActive = true;
            emit CascadeActivated(triggeredCount, coordinator.activeLayerCount);
        }

        revert MultiLayerCoordinatedBlock();
    }

    /**
     * @notice Clear coordinated response
     * @param response The response storage
     * @param coordinator The coordinator
     */
    function clearResponse(
        CoordinatedResponse storage response,
        LayerCoordinator storage coordinator
    ) internal {
        response.threatHash = bytes32(0);
        response.consensusLevel = 0;
        response.actionTaken = false;
        delete response.respondingLayers;

        coordinator.triggeredLayerCount = 0;
        coordinator.cascadeActive = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LAYER MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Enable a layer
     * @param layer The layer storage
     * @param coordinator The coordinator
     * @param layerId Layer identifier
     */
    function enableLayer(
        Layer storage layer,
        LayerCoordinator storage coordinator,
        uint8 layerId
    ) internal {
        if (layer.enabled) return;

        uint8 oldStatus = layer.status;
        layer.enabled = true;
        layer.status = STATUS_ACTIVE;
        coordinator.activeLayerCount++;

        emit LayerStatusChanged(layerId, oldStatus, STATUS_ACTIVE);
    }

    /**
     * @notice Disable a layer
     * @param layer The layer storage
     * @param coordinator The coordinator
     * @param layerId Layer identifier
     */
    function disableLayer(
        Layer storage layer,
        LayerCoordinator storage coordinator,
        uint8 layerId
    ) internal {
        if (!layer.enabled) return;

        uint8 oldStatus = layer.status;
        layer.enabled = false;
        layer.status = STATUS_DISABLED;
        coordinator.activeLayerCount--;

        emit LayerStatusChanged(layerId, oldStatus, STATUS_DISABLED);
    }

    /**
     * @notice Reset a triggered layer
     * @param layer The layer storage
     * @param layerId Layer identifier
     */
    function resetLayer(Layer storage layer, uint8 layerId) internal {
        if (!layer.enabled) return;

        uint8 oldStatus = layer.status;
        layer.status = STATUS_ACTIVE;
        layer.alertLevel = ALERT_NONE;

        emit LayerStatusChanged(layerId, oldStatus, STATUS_ACTIVE);
    }

    /**
     * @notice Put layer in maintenance mode
     * @param layer The layer storage
     * @param layerId Layer identifier
     */
    function setLayerMaintenance(Layer storage layer, uint8 layerId) internal {
        uint8 oldStatus = layer.status;
        layer.status = STATUS_MAINTENANCE;

        emit LayerStatusChanged(layerId, oldStatus, STATUS_MAINTENANCE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HEALTH MONITORING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Perform health check on layer
     * @param layer The layer storage
     * @param health The health storage
     * @param layerId Layer identifier
     * @return healthy True if layer is healthy
     */
    function healthCheck(
        Layer storage layer,
        LayerHealth storage health,
        uint8 layerId
    ) internal returns (bool healthy) {
        if (!layer.enabled) {
            return true;
        }

        layer.lastHealthCheck = uint64(block.timestamp);

        // Check layer status
        healthy = layer.status == STATUS_ACTIVE || layer.status == STATUS_MAINTENANCE;

        if (healthy) {
            health.successfulChecks++;
            health.uptime = uint64(block.timestamp);
        } else {
            health.failedChecks++;
            health.lastFailure = uint64(block.timestamp);
        }

        emit LayerHealthUpdated(layerId, healthy);

        return healthy;
    }

    /**
     * @notice Check all layers health
     * @param layers Array of layer storage
     * @param healths Array of health storage
     * @return healthyCount Number of healthy layers
     */
    function healthCheckAll(
        Layer[8] storage layers,
        LayerHealth[8] storage healths
    ) internal returns (uint8 healthyCount) {
        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            if (healthCheck(layers[i], healths[i], i)) {
                healthyCount++;
            }
        }
    }

    /**
     * @notice Get layer health score
     * @param health The health storage
     * @return score Health score (0-100)
     */
    function getHealthScore(LayerHealth storage health) internal view returns (uint8 score) {
        uint256 total = health.successfulChecks + health.failedChecks;
        if (total == 0) return 100;

        return uint8((health.successfulChecks * 100) / total);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CASCADE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Trigger cascade from layer
     * @param layers Array of layer storage
     * @param coordinator The coordinator
     * @param triggeringLayerId Layer triggering cascade
     */
    function triggerCascade(
        Layer[8] storage layers,
        LayerCoordinator storage coordinator,
        uint8 triggeringLayerId
    ) internal {
        coordinator.cascadeActive = true;

        // Set all layers to triggered
        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            if (layers[i].enabled && layers[i].status == STATUS_ACTIVE) {
                layers[i].status = STATUS_TRIGGERED;
                layers[i].alertLevel = ALERT_CRITICAL;
            }
        }

        emit CascadeActivated(triggeringLayerId, coordinator.activeLayerCount);

        revert MultiLayerCascadeTriggered();
    }

    /**
     * @notice Reset cascade
     * @param layers Array of layer storage
     * @param coordinator The coordinator
     */
    function resetCascade(
        Layer[8] storage layers,
        LayerCoordinator storage coordinator
    ) internal {
        coordinator.cascadeActive = false;
        coordinator.triggeredLayerCount = 0;
        coordinator.currentAlertLevel = ALERT_NONE;

        for (uint8 i = 0; i < MAX_LAYERS; i++) {
            if (layers[i].enabled) {
                layers[i].status = STATUS_ACTIVE;
                layers[i].alertLevel = ALERT_NONE;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get layer status
     * @param layer The layer storage
     * @param layerId Layer identifier
     */
    function getLayerStatus(Layer storage layer, uint8 layerId) internal view returns (
        uint8 status,
        uint8 alertLevel,
        uint256 triggers,
        bool enabled
    ) {
        return (
            layer.status,
            layer.alertLevel,
            layer.triggerCount,
            layer.enabled
        );
    }

    /**
     * @notice Get coordinator status
     * @param coordinator The coordinator storage
     */
    function getCoordinatorStatus(LayerCoordinator storage coordinator) internal view returns (
        uint8 activeLayers,
        uint8 triggeredLayers,
        uint8 alertLevel,
        bool cascadeActive_
    ) {
        return (
            coordinator.activeLayerCount,
            coordinator.triggeredLayerCount,
            coordinator.currentAlertLevel,
            coordinator.cascadeActive
        );
    }

    /**
     * @notice Get layer name
     * @param layerId Layer identifier
     * @return name Layer name string
     */
    function getLayerName(uint8 layerId) internal pure returns (string memory name) {
        if (layerId == LAYER_BASIC_GUARD) return "BASIC_GUARD";
        if (layerId == LAYER_FUNCTION_GUARD) return "FUNCTION_GUARD";
        if (layerId == LAYER_CALL_DEPTH) return "CALL_DEPTH";
        if (layerId == LAYER_GAS_MONITOR) return "GAS_MONITOR";
        if (layerId == LAYER_VALUE_MONITOR) return "VALUE_MONITOR";
        if (layerId == LAYER_PATTERN_DETECTOR) return "PATTERN_DETECTOR";
        if (layerId == LAYER_RATE_LIMITER) return "RATE_LIMITER";
        if (layerId == LAYER_CIRCUIT_BREAKER) return "CIRCUIT_BREAKER";
        return "UNKNOWN";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Execute layer-specific check logic
     */
    function _executeLayerCheck(
        uint8 layerId,
        bytes memory checkData
    ) private pure returns (bool passed, uint8 alertLevel, bytes32 reason) {
        // This is a placeholder - in real implementation, each layer would have specific check logic
        // For now, we just decode and check basic conditions
        if (checkData.length == 0) {
            return (true, ALERT_NONE, bytes32(0));
        }

        // Layer-specific logic would go here
        // For demonstration, all layers pass with no alert
        return (true, ALERT_NONE, bytes32(0));
    }
}
