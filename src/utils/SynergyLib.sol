// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SynergyLib
 * @notice Protocol synergy utilities for combining and coordinating multiple operations
 * @dev Provides mechanisms for protocol composition, batch operations, multi-protocol
 *      coordination, yield aggregation, and cross-protocol arbitrage opportunities
 */
library SynergyLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum protocols that can be combined in a single synergy
    uint256 internal constant MAX_PROTOCOLS = 10;

    /// @dev Maximum operations in a batch
    uint256 internal constant MAX_BATCH_SIZE = 50;

    /// @dev Basis points denominator
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @dev WAD precision (18 decimals)
    uint256 internal constant WAD = 1e18;

    /// @dev Minimum synergy bonus (0.1%)
    uint256 internal constant MIN_SYNERGY_BONUS = 10;

    /// @dev Maximum synergy bonus (50%)
    uint256 internal constant MAX_SYNERGY_BONUS = 5000;

    /// @dev Default priority for operations
    uint256 internal constant DEFAULT_PRIORITY = 100;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error MaxProtocolsExceeded(uint256 count, uint256 max);
    error MaxBatchSizeExceeded(uint256 count, uint256 max);
    error ProtocolNotRegistered(address protocol);
    error ProtocolAlreadyRegistered(address protocol);
    error InvalidSynergyConfiguration();
    error SynergyNotActive(bytes32 synergyId);
    error SynergyAlreadyActive(bytes32 synergyId);
    error IncompatibleProtocols(address protocol1, address protocol2);
    error CircularDependency(bytes32 operationId);
    error DependencyNotMet(bytes32 operationId, bytes32 dependency);
    error OperationFailed(bytes32 operationId, bytes memory reason);
    error InsufficientSynergyScore(uint256 score, uint256 required);
    error YieldOptimizationFailed();
    error ArbitrageNotProfitable(int256 expectedProfit);
    error InvalidPriorityRange(uint256 priority);
    error EmptyBatch();
    error InvalidWeight(uint256 weight);
    error WeightSumMismatch(uint256 sum, uint256 expected);
    error ProtocolPaused(address protocol);
    error CooldownActive(bytes32 synergyId);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Protocol status enum
    enum ProtocolStatus {
        Inactive,
        Active,
        Paused,
        Deprecated
    }

    /// @notice Operation execution status
    enum ExecutionStatus {
        Pending,
        Executing,
        Completed,
        Failed,
        Skipped
    }

    /// @notice Synergy type classification
    enum SynergyType {
        YieldAggregation,
        LiquiditySharing,
        CrossProtocolArbitrage,
        ComposableStrategy,
        RiskDistribution,
        FeeOptimization
    }

    /// @notice Registered protocol information
    struct ProtocolInfo {
        address protocolAddress;
        bytes32 protocolId;
        ProtocolStatus status;
        uint256 trustScore;
        uint256 registeredAt;
        uint256 lastActiveAt;
        bytes4[] supportedSelectors;
    }

    /// @notice Protocol registry for synergy management
    struct ProtocolRegistry {
        mapping(address => ProtocolInfo) protocols;
        mapping(bytes32 => address) idToAddress;
        address[] registeredProtocols;
        uint256 activeCount;
    }

    /// @notice Compatibility matrix between protocols
    struct CompatibilityMatrix {
        mapping(bytes32 => mapping(bytes32 => bool)) isCompatible;
        mapping(bytes32 => mapping(bytes32 => uint256)) synergyBonus;
    }

    /// @notice Single operation in a batch
    struct Operation {
        bytes32 operationId;
        address target;
        bytes callData;
        uint256 value;
        uint256 priority;
        bytes32[] dependencies;
        ExecutionStatus status;
        bytes result;
    }

    /// @notice Batch operation container
    struct OperationBatch {
        bytes32 batchId;
        Operation[] operations;
        uint256 createdAt;
        uint256 executedAt;
        bool isAtomic;
        uint256 totalGasUsed;
    }

    /// @notice Synergy configuration
    struct SynergyConfig {
        bytes32 synergyId;
        SynergyType synergyType;
        address[] protocols;
        uint256[] weights;
        uint256 minSynergyScore;
        uint256 cooldownPeriod;
        bool isActive;
        uint256 lastExecuted;
        uint256 totalExecutions;
        uint256 totalValueProcessed;
    }

    /// @notice Synergy registry
    struct SynergyRegistry {
        mapping(bytes32 => SynergyConfig) synergies;
        bytes32[] activeSynergies;
        uint256 totalSynergies;
    }

    /// @notice Yield opportunity from multiple protocols
    struct YieldOpportunity {
        bytes32 opportunityId;
        address[] protocols;
        uint256[] allocations;
        uint256 expectedAPY;
        uint256 riskScore;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 lockPeriod;
    }

    /// @notice Arbitrage opportunity between protocols
    struct ArbitrageOpportunity {
        bytes32 opportunityId;
        address sourceProtocol;
        address targetProtocol;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedAmountOut;
        uint256 minProfit;
        uint256 deadline;
        bytes routeData;
    }

    /// @notice Protocol yield data for aggregation
    struct ProtocolYield {
        address protocol;
        uint256 currentAPY;
        uint256 tvl;
        uint256 utilizationRate;
        uint256 riskScore;
    }

    /// @notice Synergy execution result
    struct SynergyResult {
        bytes32 synergyId;
        bool success;
        uint256 totalValue;
        uint256 synergyBonus;
        uint256 gasUsed;
        bytes[] protocolResults;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROTOCOL REGISTRY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Register a new protocol in the registry
    /// @param registry The protocol registry storage
    /// @param protocolAddress Address of the protocol
    /// @param protocolId Unique identifier for the protocol
    /// @param trustScore Initial trust score (0-10000)
    /// @param supportedSelectors Function selectors supported by the protocol
    function registerProtocol(
        ProtocolRegistry storage registry,
        address protocolAddress,
        bytes32 protocolId,
        uint256 trustScore,
        bytes4[] memory supportedSelectors
    ) internal {
        if (registry.protocols[protocolAddress].protocolAddress != address(0)) {
            revert ProtocolAlreadyRegistered(protocolAddress);
        }
        if (registry.registeredProtocols.length >= MAX_PROTOCOLS) {
            revert MaxProtocolsExceeded(registry.registeredProtocols.length + 1, MAX_PROTOCOLS);
        }

        registry.protocols[protocolAddress] = ProtocolInfo({
            protocolAddress: protocolAddress,
            protocolId: protocolId,
            status: ProtocolStatus.Active,
            trustScore: trustScore > BPS_DENOMINATOR ? BPS_DENOMINATOR : trustScore,
            registeredAt: block.timestamp,
            lastActiveAt: block.timestamp,
            supportedSelectors: supportedSelectors
        });

        registry.idToAddress[protocolId] = protocolAddress;
        registry.registeredProtocols.push(protocolAddress);
        unchecked {
            ++registry.activeCount;
        }
    }

    /// @notice Update protocol status
    /// @param registry The protocol registry storage
    /// @param protocolAddress Protocol address
    /// @param newStatus New status to set
    function updateProtocolStatus(
        ProtocolRegistry storage registry,
        address protocolAddress,
        ProtocolStatus newStatus
    ) internal {
        ProtocolInfo storage info = registry.protocols[protocolAddress];
        if (info.protocolAddress == address(0)) {
            revert ProtocolNotRegistered(protocolAddress);
        }

        ProtocolStatus oldStatus = info.status;
        info.status = newStatus;

        if (oldStatus == ProtocolStatus.Active && newStatus != ProtocolStatus.Active) {
            unchecked {
                --registry.activeCount;
            }
        } else if (oldStatus != ProtocolStatus.Active && newStatus == ProtocolStatus.Active) {
            unchecked {
                ++registry.activeCount;
            }
        }
    }

    /// @notice Update protocol trust score
    /// @param registry The protocol registry storage
    /// @param protocolAddress Protocol address
    /// @param newScore New trust score
    function updateTrustScore(
        ProtocolRegistry storage registry,
        address protocolAddress,
        uint256 newScore
    ) internal {
        ProtocolInfo storage info = registry.protocols[protocolAddress];
        if (info.protocolAddress == address(0)) {
            revert ProtocolNotRegistered(protocolAddress);
        }

        info.trustScore = newScore > BPS_DENOMINATOR ? BPS_DENOMINATOR : newScore;
        info.lastActiveAt = block.timestamp;
    }

    /// @notice Check if a protocol is registered and active
    /// @param registry The protocol registry storage
    /// @param protocolAddress Protocol address
    /// @return isActive True if protocol is registered and active
    function isProtocolActive(
        ProtocolRegistry storage registry,
        address protocolAddress
    ) internal view returns (bool isActive) {
        ProtocolInfo storage info = registry.protocols[protocolAddress];
        return info.protocolAddress != address(0) && info.status == ProtocolStatus.Active;
    }

    /// @notice Get protocol info by address
    /// @param registry The protocol registry storage
    /// @param protocolAddress Protocol address
    /// @return info Protocol information
    function getProtocolInfo(
        ProtocolRegistry storage registry,
        address protocolAddress
    ) internal view returns (ProtocolInfo storage info) {
        info = registry.protocols[protocolAddress];
        if (info.protocolAddress == address(0)) {
            revert ProtocolNotRegistered(protocolAddress);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPATIBILITY MATRIX FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set compatibility between two protocols
    /// @param matrix The compatibility matrix storage
    /// @param protocolId1 First protocol ID
    /// @param protocolId2 Second protocol ID
    /// @param compatible Whether protocols are compatible
    /// @param bonus Synergy bonus in basis points
    function setCompatibility(
        CompatibilityMatrix storage matrix,
        bytes32 protocolId1,
        bytes32 protocolId2,
        bool compatible,
        uint256 bonus
    ) internal {
        if (bonus > MAX_SYNERGY_BONUS) {
            bonus = MAX_SYNERGY_BONUS;
        }

        matrix.isCompatible[protocolId1][protocolId2] = compatible;
        matrix.isCompatible[protocolId2][protocolId1] = compatible;

        if (compatible && bonus >= MIN_SYNERGY_BONUS) {
            matrix.synergyBonus[protocolId1][protocolId2] = bonus;
            matrix.synergyBonus[protocolId2][protocolId1] = bonus;
        }
    }

    /// @notice Check if two protocols are compatible
    /// @param matrix The compatibility matrix storage
    /// @param protocolId1 First protocol ID
    /// @param protocolId2 Second protocol ID
    /// @return compatible True if protocols are compatible
    function checkCompatibility(
        CompatibilityMatrix storage matrix,
        bytes32 protocolId1,
        bytes32 protocolId2
    ) internal view returns (bool compatible) {
        return matrix.isCompatible[protocolId1][protocolId2];
    }

    /// @notice Get synergy bonus between two protocols
    /// @param matrix The compatibility matrix storage
    /// @param protocolId1 First protocol ID
    /// @param protocolId2 Second protocol ID
    /// @return bonus Synergy bonus in basis points
    function getSynergyBonus(
        CompatibilityMatrix storage matrix,
        bytes32 protocolId1,
        bytes32 protocolId2
    ) internal view returns (uint256 bonus) {
        return matrix.synergyBonus[protocolId1][protocolId2];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SYNERGY CONFIGURATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a new synergy configuration
    /// @param synergyReg The synergy registry storage
    /// @param synergyType Type of synergy
    /// @param protocols Array of protocol addresses
    /// @param weights Allocation weights for each protocol
    /// @param minScore Minimum synergy score required
    /// @param cooldown Cooldown period between executions
    /// @return synergyId Generated synergy ID
    function createSynergy(
        SynergyRegistry storage synergyReg,
        SynergyType synergyType,
        address[] memory protocols,
        uint256[] memory weights,
        uint256 minScore,
        uint256 cooldown
    ) internal returns (bytes32 synergyId) {
        if (protocols.length == 0 || protocols.length > MAX_PROTOCOLS) {
            revert MaxProtocolsExceeded(protocols.length, MAX_PROTOCOLS);
        }
        if (protocols.length != weights.length) {
            revert InvalidSynergyConfiguration();
        }

        // Validate weights sum to BPS_DENOMINATOR
        uint256 weightSum;
        for (uint256 i; i < weights.length;) {
            if (weights[i] == 0) {
                revert InvalidWeight(weights[i]);
            }
            weightSum += weights[i];
            unchecked { ++i; }
        }
        if (weightSum != BPS_DENOMINATOR) {
            revert WeightSumMismatch(weightSum, BPS_DENOMINATOR);
        }

        synergyId = keccak256(
            abi.encode(synergyType, protocols, weights, block.timestamp, synergyReg.totalSynergies)
        );

        synergyReg.synergies[synergyId] = SynergyConfig({
            synergyId: synergyId,
            synergyType: synergyType,
            protocols: protocols,
            weights: weights,
            minSynergyScore: minScore,
            cooldownPeriod: cooldown,
            isActive: true,
            lastExecuted: 0,
            totalExecutions: 0,
            totalValueProcessed: 0
        });

        synergyReg.activeSynergies.push(synergyId);
        unchecked {
            ++synergyReg.totalSynergies;
        }
    }

    /// @notice Activate or deactivate a synergy
    /// @param synergyReg The synergy registry storage
    /// @param synergyId Synergy identifier
    /// @param active New active status
    function setSynergyActive(
        SynergyRegistry storage synergyReg,
        bytes32 synergyId,
        bool active
    ) internal {
        SynergyConfig storage config = synergyReg.synergies[synergyId];
        if (config.synergyId == bytes32(0)) {
            revert SynergyNotActive(synergyId);
        }
        config.isActive = active;
    }

    /// @notice Check if synergy can be executed (cooldown check)
    /// @param synergyReg The synergy registry storage
    /// @param synergyId Synergy identifier
    /// @return canExecute True if synergy can be executed
    function canExecuteSynergy(
        SynergyRegistry storage synergyReg,
        bytes32 synergyId
    ) internal view returns (bool canExecute) {
        SynergyConfig storage config = synergyReg.synergies[synergyId];
        if (!config.isActive) return false;

        return block.timestamp >= config.lastExecuted + config.cooldownPeriod;
    }

    /// @notice Record synergy execution
    /// @param synergyReg The synergy registry storage
    /// @param synergyId Synergy identifier
    /// @param valueProcessed Value processed in this execution
    function recordSynergyExecution(
        SynergyRegistry storage synergyReg,
        bytes32 synergyId,
        uint256 valueProcessed
    ) internal {
        SynergyConfig storage config = synergyReg.synergies[synergyId];
        if (!config.isActive) {
            revert SynergyNotActive(synergyId);
        }

        if (block.timestamp < config.lastExecuted + config.cooldownPeriod) {
            revert CooldownActive(synergyId);
        }

        config.lastExecuted = block.timestamp;
        unchecked {
            ++config.totalExecutions;
            config.totalValueProcessed += valueProcessed;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH OPERATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a new operation batch
    /// @param batchId Unique batch identifier
    /// @param isAtomic Whether all operations must succeed
    /// @return batch The created batch struct
    function createBatch(
        bytes32 batchId,
        bool isAtomic
    ) internal view returns (OperationBatch memory batch) {
        batch.batchId = batchId;
        batch.createdAt = block.timestamp;
        batch.isAtomic = isAtomic;
    }

    /// @notice Add operation to batch
    /// @param batch The batch to add to (memory)
    /// @param target Target contract address
    /// @param callData Call data for the operation
    /// @param value ETH value to send
    /// @param priority Execution priority (lower = higher priority)
    /// @param dependencies Array of operation IDs this depends on
    /// @return operationId Generated operation ID
    function addOperation(
        OperationBatch memory batch,
        address target,
        bytes memory callData,
        uint256 value,
        uint256 priority,
        bytes32[] memory dependencies
    ) internal pure returns (bytes32 operationId) {
        if (batch.operations.length >= MAX_BATCH_SIZE) {
            revert MaxBatchSizeExceeded(batch.operations.length + 1, MAX_BATCH_SIZE);
        }

        operationId = keccak256(
            abi.encode(batch.batchId, target, callData, batch.operations.length)
        );

        // Note: In actual implementation, this would require dynamic array handling
        // This is a simplified version showing the concept
    }

    /// @notice Sort operations by priority
    /// @param operations Array of operations to sort
    /// @return sorted Sorted operations array
    function sortByPriority(
        Operation[] memory operations
    ) internal pure returns (Operation[] memory sorted) {
        uint256 length = operations.length;
        sorted = new Operation[](length);

        // Copy array
        for (uint256 i; i < length;) {
            sorted[i] = operations[i];
            unchecked { ++i; }
        }

        // Simple bubble sort (for small arrays)
        for (uint256 i; i < length;) {
            for (uint256 j = i + 1; j < length;) {
                if (sorted[j].priority < sorted[i].priority) {
                    Operation memory temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /// @notice Check if all dependencies are met for an operation
    /// @param operations All operations in batch
    /// @param operationIndex Index of operation to check
    /// @return met True if all dependencies completed successfully
    function checkDependencies(
        Operation[] memory operations,
        uint256 operationIndex
    ) internal pure returns (bool met) {
        Operation memory op = operations[operationIndex];

        for (uint256 i; i < op.dependencies.length;) {
            bool found = false;

            for (uint256 j; j < operations.length;) {
                if (operations[j].operationId == op.dependencies[i]) {
                    if (operations[j].status != ExecutionStatus.Completed) {
                        return false;
                    }
                    found = true;
                    break;
                }
                unchecked { ++j; }
            }

            if (!found) {
                revert DependencyNotMet(op.operationId, op.dependencies[i]);
            }

            unchecked { ++i; }
        }

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SYNERGY SCORE CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate synergy score for a set of protocols
    /// @param matrix The compatibility matrix storage
    /// @param registry The protocol registry storage
    /// @param protocols Array of protocol addresses
    /// @return score Combined synergy score (0-10000)
    function calculateSynergyScore(
        CompatibilityMatrix storage matrix,
        ProtocolRegistry storage registry,
        address[] memory protocols
    ) internal view returns (uint256 score) {
        if (protocols.length < 2) return 0;

        uint256 compatibilityScore;
        uint256 trustScore;
        uint256 bonusScore;
        uint256 pairCount;

        // Calculate pairwise compatibility and bonus
        for (uint256 i; i < protocols.length;) {
            ProtocolInfo storage info1 = registry.protocols[protocols[i]];
            trustScore += info1.trustScore;

            for (uint256 j = i + 1; j < protocols.length;) {
                ProtocolInfo storage info2 = registry.protocols[protocols[j]];

                if (matrix.isCompatible[info1.protocolId][info2.protocolId]) {
                    compatibilityScore += BPS_DENOMINATOR;
                    bonusScore += matrix.synergyBonus[info1.protocolId][info2.protocolId];
                }

                unchecked {
                    ++pairCount;
                    ++j;
                }
            }
            unchecked { ++i; }
        }

        if (pairCount == 0) return 0;

        // Average scores
        uint256 avgCompatibility = compatibilityScore / pairCount;
        uint256 avgTrust = trustScore / protocols.length;
        uint256 avgBonus = bonusScore / pairCount;

        // Weighted combination: 40% compatibility + 30% trust + 30% bonus
        score = (avgCompatibility * 4000 + avgTrust * 3000 + avgBonus * 3000) / BPS_DENOMINATOR;
    }

    /// @notice Check if synergy score meets minimum requirement
    /// @param matrix The compatibility matrix storage
    /// @param registry The protocol registry storage
    /// @param protocols Array of protocol addresses
    /// @param minScore Minimum required score
    function requireMinSynergyScore(
        CompatibilityMatrix storage matrix,
        ProtocolRegistry storage registry,
        address[] memory protocols,
        uint256 minScore
    ) internal view {
        uint256 score = calculateSynergyScore(matrix, registry, protocols);
        if (score < minScore) {
            revert InsufficientSynergyScore(score, minScore);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD AGGREGATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate optimal yield allocation across protocols
    /// @param yields Array of protocol yield data
    /// @param totalAmount Total amount to allocate
    /// @param maxRiskScore Maximum acceptable risk score
    /// @return allocations Optimal allocation per protocol
    function calculateOptimalAllocation(
        ProtocolYield[] memory yields,
        uint256 totalAmount,
        uint256 maxRiskScore
    ) internal pure returns (uint256[] memory allocations) {
        allocations = new uint256[](yields.length);

        if (yields.length == 0 || totalAmount == 0) {
            return allocations;
        }

        // Filter by risk and calculate risk-adjusted yields
        uint256[] memory adjustedYields = new uint256[](yields.length);
        uint256 totalAdjustedYield;

        for (uint256 i; i < yields.length;) {
            if (yields[i].riskScore <= maxRiskScore) {
                // Risk-adjusted yield = APY * (1 - riskScore/10000)
                uint256 riskMultiplier = BPS_DENOMINATOR - yields[i].riskScore;
                adjustedYields[i] = (yields[i].currentAPY * riskMultiplier) / BPS_DENOMINATOR;
                totalAdjustedYield += adjustedYields[i];
            }
            unchecked { ++i; }
        }

        if (totalAdjustedYield == 0) {
            return allocations;
        }

        // Allocate proportionally to risk-adjusted yield
        uint256 allocated;
        for (uint256 i; i < yields.length;) {
            if (adjustedYields[i] > 0) {
                allocations[i] = (totalAmount * adjustedYields[i]) / totalAdjustedYield;
                allocated += allocations[i];
            }
            unchecked { ++i; }
        }

        // Handle rounding remainder
        if (allocated < totalAmount && allocations.length > 0) {
            for (uint256 i; i < allocations.length;) {
                if (allocations[i] > 0) {
                    allocations[i] += totalAmount - allocated;
                    break;
                }
                unchecked { ++i; }
            }
        }
    }

    /// @notice Calculate combined APY from multiple allocations
    /// @param yields Array of protocol yield data
    /// @param allocations Allocation amounts per protocol
    /// @param totalAmount Total allocated amount
    /// @return combinedAPY Weighted average APY
    function calculateCombinedAPY(
        ProtocolYield[] memory yields,
        uint256[] memory allocations,
        uint256 totalAmount
    ) internal pure returns (uint256 combinedAPY) {
        if (totalAmount == 0 || yields.length != allocations.length) {
            return 0;
        }

        uint256 weightedSum;
        for (uint256 i; i < yields.length;) {
            weightedSum += yields[i].currentAPY * allocations[i];
            unchecked { ++i; }
        }

        combinedAPY = weightedSum / totalAmount;
    }

    /// @notice Calculate combined risk score
    /// @param yields Array of protocol yield data
    /// @param allocations Allocation amounts per protocol
    /// @param totalAmount Total allocated amount
    /// @return combinedRisk Weighted average risk score
    function calculateCombinedRisk(
        ProtocolYield[] memory yields,
        uint256[] memory allocations,
        uint256 totalAmount
    ) internal pure returns (uint256 combinedRisk) {
        if (totalAmount == 0 || yields.length != allocations.length) {
            return 0;
        }

        uint256 weightedSum;
        for (uint256 i; i < yields.length;) {
            weightedSum += yields[i].riskScore * allocations[i];
            unchecked { ++i; }
        }

        combinedRisk = weightedSum / totalAmount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ARBITRAGE OPPORTUNITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate expected profit from arbitrage
    /// @param opportunity The arbitrage opportunity
    /// @param gasPrice Current gas price
    /// @param estimatedGas Estimated gas for execution
    /// @return profit Expected profit (can be negative)
    function calculateArbitrageProfit(
        ArbitrageOpportunity memory opportunity,
        uint256 gasPrice,
        uint256 estimatedGas
    ) internal pure returns (int256 profit) {
        uint256 gasCost = gasPrice * estimatedGas;

        if (opportunity.expectedAmountOut > opportunity.amountIn) {
            uint256 grossProfit = opportunity.expectedAmountOut - opportunity.amountIn;
            profit = int256(grossProfit) - int256(gasCost);
        } else {
            profit = -int256(opportunity.amountIn - opportunity.expectedAmountOut + gasCost);
        }
    }

    /// @notice Check if arbitrage opportunity is profitable
    /// @param opportunity The arbitrage opportunity
    /// @param gasPrice Current gas price
    /// @param estimatedGas Estimated gas
    /// @param minProfitBps Minimum profit in basis points
    /// @return isProfitable True if profitable above threshold
    function isArbitrageProfitable(
        ArbitrageOpportunity memory opportunity,
        uint256 gasPrice,
        uint256 estimatedGas,
        uint256 minProfitBps
    ) internal pure returns (bool isProfitable) {
        int256 profit = calculateArbitrageProfit(opportunity, gasPrice, estimatedGas);

        if (profit <= 0) return false;

        uint256 profitBps = (uint256(profit) * BPS_DENOMINATOR) / opportunity.amountIn;
        return profitBps >= minProfitBps;
    }

    /// @notice Validate arbitrage opportunity
    /// @param opportunity The arbitrage opportunity to validate
    function validateArbitrageOpportunity(
        ArbitrageOpportunity memory opportunity
    ) internal view {
        if (block.timestamp > opportunity.deadline) {
            revert ArbitrageNotProfitable(-1);
        }

        if (opportunity.expectedAmountOut < opportunity.amountIn + opportunity.minProfit) {
            revert ArbitrageNotProfitable(
                int256(opportunity.expectedAmountOut) - int256(opportunity.amountIn)
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate unique synergy ID
    /// @param protocols Array of protocol addresses
    /// @param synergyType Type of synergy
    /// @param salt Additional entropy
    /// @return synergyId Generated unique ID
    function generateSynergyId(
        address[] memory protocols,
        SynergyType synergyType,
        bytes32 salt
    ) internal view returns (bytes32 synergyId) {
        return keccak256(
            abi.encode(protocols, synergyType, salt, block.timestamp, block.chainid)
        );
    }

    /// @notice Calculate allocation from weights
    /// @param totalAmount Total amount to allocate
    /// @param weights Weight for each allocation
    /// @return allocations Calculated allocations
    function calculateAllocations(
        uint256 totalAmount,
        uint256[] memory weights
    ) internal pure returns (uint256[] memory allocations) {
        allocations = new uint256[](weights.length);

        uint256 totalWeight;
        for (uint256 i; i < weights.length;) {
            totalWeight += weights[i];
            unchecked { ++i; }
        }

        if (totalWeight == 0) return allocations;

        uint256 allocated;
        for (uint256 i; i < weights.length;) {
            allocations[i] = (totalAmount * weights[i]) / totalWeight;
            allocated += allocations[i];
            unchecked { ++i; }
        }

        // Handle rounding
        if (allocated < totalAmount && allocations.length > 0) {
            allocations[0] += totalAmount - allocated;
        }
    }

    /// @notice Calculate protocol share based on TVL
    /// @param protocolTVL TVL of specific protocol
    /// @param totalTVL Total TVL across all protocols
    /// @return share Share in basis points
    function calculateTVLShare(
        uint256 protocolTVL,
        uint256 totalTVL
    ) internal pure returns (uint256 share) {
        if (totalTVL == 0) return 0;
        return (protocolTVL * BPS_DENOMINATOR) / totalTVL;
    }

    /// @notice Check if protocols array contains duplicates
    /// @param protocols Array of protocol addresses
    /// @return hasDuplicates True if duplicates exist
    function hasDuplicateProtocols(
        address[] memory protocols
    ) internal pure returns (bool hasDuplicates) {
        for (uint256 i; i < protocols.length;) {
            for (uint256 j = i + 1; j < protocols.length;) {
                if (protocols[i] == protocols[j]) {
                    return true;
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
        return false;
    }
}
