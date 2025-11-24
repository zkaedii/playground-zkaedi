// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyGuardLib
 * @notice Gas-optimized reentrancy protection library with advanced patterns
 * @dev Implements single-entry guard, read-only reentrancy detection, and cross-function protection
 */
library ReentrancyGuardLib {
    // ============ ERRORS ============
    error ReentrantCall();
    error ReadOnlyReentrancy();
    error CrossFunctionReentrancy(bytes4 selector);
    error GuardAlreadyInitialized();
    error GuardNotInitialized();
    error InvalidGuardState(uint256 expected, uint256 actual);

    // ============ CONSTANTS ============
    // Using non-zero values to save gas on SSTORE
    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;
    uint256 internal constant READ_ONLY_ENTERED = 3;

    // Bit flags for function-specific guards
    uint256 internal constant GUARD_DEPOSIT = 1 << 0;
    uint256 internal constant GUARD_WITHDRAW = 1 << 1;
    uint256 internal constant GUARD_SWAP = 1 << 2;
    uint256 internal constant GUARD_BORROW = 1 << 3;
    uint256 internal constant GUARD_REPAY = 1 << 4;
    uint256 internal constant GUARD_LIQUIDATE = 1 << 5;
    uint256 internal constant GUARD_FLASH_LOAN = 1 << 6;
    uint256 internal constant GUARD_STAKE = 1 << 7;
    uint256 internal constant GUARD_UNSTAKE = 1 << 8;
    uint256 internal constant GUARD_CLAIM = 1 << 9;
    uint256 internal constant GUARD_BRIDGE = 1 << 10;
    uint256 internal constant GUARD_MINT = 1 << 11;
    uint256 internal constant GUARD_BURN = 1 << 12;

    // ============ TYPES ============
    struct ReentrancyGuard {
        uint256 status;
    }

    struct AdvancedGuard {
        uint256 status;
        uint256 functionGuards; // Bitmap for function-specific guards
        uint256 lastCallBlock;
        bytes4 lastSelector;
    }

    struct CrossContractGuard {
        mapping(address => uint256) contractStatus;
        uint256 globalStatus;
    }

    // ============ EVENTS ============
    event GuardTriggered(address indexed caller, bytes4 indexed selector);
    event CrossContractGuardTriggered(address indexed caller, address indexed target);

    // ============ BASIC REENTRANCY GUARD ============

    /**
     * @notice Initialize the reentrancy guard
     * @param guard The guard storage
     */
    function initialize(ReentrancyGuard storage guard) internal {
        if (guard.status != 0) revert GuardAlreadyInitialized();
        guard.status = NOT_ENTERED;
    }

    /**
     * @notice Enter the guard (call at the start of protected function)
     * @param guard The guard storage
     */
    function enter(ReentrancyGuard storage guard) internal {
        if (guard.status == 0) {
            guard.status = NOT_ENTERED;
        }
        if (guard.status != NOT_ENTERED) {
            revert ReentrantCall();
        }
        guard.status = ENTERED;
    }

    /**
     * @notice Exit the guard (call at the end of protected function)
     * @param guard The guard storage
     */
    function exit(ReentrancyGuard storage guard) internal {
        guard.status = NOT_ENTERED;
    }

    /**
     * @notice Check if currently in a guarded context
     * @param guard The guard storage
     * @return True if currently entered
     */
    function isEntered(ReentrancyGuard storage guard) internal view returns (bool) {
        return guard.status == ENTERED;
    }

    // ============ READ-ONLY REENTRANCY GUARD ============

    /**
     * @notice Enter read-only guard (for view functions that need protection)
     * @param guard The guard storage
     */
    function enterReadOnly(ReentrancyGuard storage guard) internal {
        if (guard.status == 0) {
            guard.status = NOT_ENTERED;
        }
        // Allow read-only calls from non-entered state
        // But prevent if already in a write context
        if (guard.status == ENTERED) {
            revert ReadOnlyReentrancy();
        }
    }

    /**
     * @notice Check for read-only reentrancy in view functions
     * @dev Use this in view functions to detect if called during state modification
     * @param guard The guard storage
     */
    function checkReadOnlyReentrancy(ReentrancyGuard storage guard) internal view {
        if (guard.status == ENTERED) {
            revert ReadOnlyReentrancy();
        }
    }

    // ============ ADVANCED GUARD WITH FUNCTION-SPECIFIC PROTECTION ============

    /**
     * @notice Initialize the advanced guard
     * @param guard The guard storage
     */
    function initializeAdvanced(AdvancedGuard storage guard) internal {
        if (guard.status != 0) revert GuardAlreadyInitialized();
        guard.status = NOT_ENTERED;
    }

    /**
     * @notice Enter with function-specific guard
     * @param guard The guard storage
     * @param functionFlag The function guard flag (e.g., GUARD_DEPOSIT)
     */
    function enterFunction(AdvancedGuard storage guard, uint256 functionFlag) internal {
        if (guard.status == 0) {
            guard.status = NOT_ENTERED;
        }

        // Check global reentrancy
        if (guard.status != NOT_ENTERED) {
            revert ReentrantCall();
        }

        // Check function-specific guard
        if (guard.functionGuards & functionFlag != 0) {
            revert CrossFunctionReentrancy(msg.sig);
        }

        guard.status = ENTERED;
        guard.functionGuards |= functionFlag;
        guard.lastCallBlock = block.number;
        guard.lastSelector = msg.sig;
    }

    /**
     * @notice Exit with function-specific guard
     * @param guard The guard storage
     * @param functionFlag The function guard flag
     */
    function exitFunction(AdvancedGuard storage guard, uint256 functionFlag) internal {
        guard.status = NOT_ENTERED;
        guard.functionGuards &= ~functionFlag;
    }

    /**
     * @notice Check if a specific function guard is active
     * @param guard The guard storage
     * @param functionFlag The function guard flag
     * @return True if the function guard is active
     */
    function isFunctionGuardActive(
        AdvancedGuard storage guard,
        uint256 functionFlag
    ) internal view returns (bool) {
        return guard.functionGuards & functionFlag != 0;
    }

    /**
     * @notice Prevent specific function combinations
     * @param guard The guard storage
     * @param disallowedFlags Bitmap of disallowed function flags
     */
    function checkDisallowedCombination(
        AdvancedGuard storage guard,
        uint256 disallowedFlags
    ) internal view {
        if (guard.functionGuards & disallowedFlags != 0) {
            revert CrossFunctionReentrancy(msg.sig);
        }
    }

    // ============ CROSS-CONTRACT GUARD ============

    /**
     * @notice Enter cross-contract guard
     * @param guard The guard storage
     * @param target The target contract address
     */
    function enterCrossContract(
        CrossContractGuard storage guard,
        address target
    ) internal {
        if (guard.globalStatus == 0) {
            guard.globalStatus = NOT_ENTERED;
        }

        if (guard.globalStatus != NOT_ENTERED) {
            revert ReentrantCall();
        }

        if (guard.contractStatus[target] != 0 && guard.contractStatus[target] != NOT_ENTERED) {
            revert ReentrantCall();
        }

        guard.globalStatus = ENTERED;
        guard.contractStatus[target] = ENTERED;

        emit CrossContractGuardTriggered(msg.sender, target);
    }

    /**
     * @notice Exit cross-contract guard
     * @param guard The guard storage
     * @param target The target contract address
     */
    function exitCrossContract(
        CrossContractGuard storage guard,
        address target
    ) internal {
        guard.globalStatus = NOT_ENTERED;
        guard.contractStatus[target] = NOT_ENTERED;
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Execute a function with reentrancy protection
     * @dev Uses a callback pattern for cleaner code
     * @param guard The guard storage
     * @param callback The function to execute
     * @return result The return data from the callback
     */
    function executeProtected(
        ReentrancyGuard storage guard,
        function() internal returns (bytes memory) callback
    ) internal returns (bytes memory result) {
        enter(guard);
        result = callback();
        exit(guard);
    }

    /**
     * @notice Get guard status for debugging
     * @param guard The guard storage
     * @return status The current status
     * @return statusName Human-readable status name
     */
    function getStatus(
        ReentrancyGuard storage guard
    ) internal view returns (uint256 status, string memory statusName) {
        status = guard.status;
        if (status == NOT_ENTERED || status == 0) {
            statusName = "NOT_ENTERED";
        } else if (status == ENTERED) {
            statusName = "ENTERED";
        } else if (status == READ_ONLY_ENTERED) {
            statusName = "READ_ONLY_ENTERED";
        } else {
            statusName = "UNKNOWN";
        }
    }

    /**
     * @notice Get advanced guard info
     * @param guard The guard storage
     * @return status The current status
     * @return activeGuards Bitmap of active function guards
     * @return lastBlock The last call block
     * @return lastFunc The last function selector
     */
    function getAdvancedStatus(
        AdvancedGuard storage guard
    ) internal view returns (
        uint256 status,
        uint256 activeGuards,
        uint256 lastBlock,
        bytes4 lastFunc
    ) {
        return (
            guard.status,
            guard.functionGuards,
            guard.lastCallBlock,
            guard.lastSelector
        );
    }

    /**
     * @notice Create a combined function guard flag
     * @param flags Array of individual flags to combine
     * @return combined The combined flag
     */
    function combineFlags(uint256[] memory flags) internal pure returns (uint256 combined) {
        for (uint256 i = 0; i < flags.length; i++) {
            combined |= flags[i];
        }
    }

    /**
     * @notice Check if same-block reentrancy (useful for flash loan protection)
     * @param guard The guard storage
     * @return True if called in the same block as previous call
     */
    function isSameBlockCall(AdvancedGuard storage guard) internal view returns (bool) {
        return guard.lastCallBlock == block.number && guard.status == ENTERED;
    }
}
