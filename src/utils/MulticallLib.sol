// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MulticallLib
 * @notice Gas-efficient multicall library for batching multiple operations
 * @dev Implements various multicall patterns including deadline support and value forwarding
 */
library MulticallLib {
    // ============ ERRORS ============
    error CallFailed(uint256 index, bytes reason);
    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error InsufficientValue(uint256 required, uint256 provided);
    error InvalidCallData();
    error TooManyCalls(uint256 count, uint256 maximum);
    error EmptyCallArray();
    error ValueMismatch(uint256 expected, uint256 actual);
    error PartialFailure(uint256 successCount, uint256 totalCount);
    error StaticCallMutation();

    // ============ CONSTANTS ============
    uint256 internal constant MAX_CALLS = 100;
    uint256 internal constant MAX_CALL_GAS = 5_000_000;

    // ============ TYPES ============
    struct Call {
        address target;
        bytes callData;
        uint256 value;
    }

    struct CallWithGas {
        address target;
        bytes callData;
        uint256 value;
        uint256 gasLimit;
    }

    struct Result {
        bool success;
        bytes returnData;
        uint256 gasUsed;
    }

    struct BatchConfig {
        bool allowPartialFailure;
        bool refundUnusedValue;
        uint256 deadline;
        uint256 maxGasPerCall;
    }

    // ============ EVENTS ============
    event MulticallExecuted(uint256 indexed callCount, uint256 successCount, uint256 totalGasUsed);
    event CallResult(uint256 indexed index, bool success, bytes returnData);
    event ValueRefunded(address indexed recipient, uint256 amount);

    // ============ BASIC MULTICALL ============

    /**
     * @notice Execute multiple calls in a single transaction
     * @param calls Array of call data to execute on this contract
     * @return results Array of return data from each call
     */
    function multicall(
        bytes[] memory calls
    ) internal returns (bytes[] memory results) {
        if (calls.length == 0) revert EmptyCallArray();
        if (calls.length > MAX_CALLS) revert TooManyCalls(calls.length, MAX_CALLS);

        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);

            if (!success) {
                revert CallFailed(i, result);
            }

            results[i] = result;
        }
    }

    /**
     * @notice Execute multiple calls with deadline check
     * @param calls Array of call data
     * @param deadline The deadline timestamp
     * @return results Array of return data
     */
    function multicallWithDeadline(
        bytes[] memory calls,
        uint256 deadline
    ) internal returns (bytes[] memory results) {
        if (block.timestamp > deadline) {
            revert DeadlineExpired(deadline, block.timestamp);
        }
        return multicall(calls);
    }

    /**
     * @notice Execute multiple calls allowing partial failures
     * @param calls Array of call data
     * @return results Array of Result structs with success status
     */
    function tryMulticall(
        bytes[] memory calls
    ) internal returns (Result[] memory results) {
        if (calls.length == 0) revert EmptyCallArray();
        if (calls.length > MAX_CALLS) revert TooManyCalls(calls.length, MAX_CALLS);

        results = new Result[](calls.length);
        uint256 successCount = 0;
        uint256 totalGasUsed = 0;

        for (uint256 i = 0; i < calls.length; i++) {
            uint256 gasBefore = gasleft();

            (bool success, bytes memory returnData) = address(this).delegatecall(calls[i]);

            uint256 gasUsed = gasBefore - gasleft();
            totalGasUsed += gasUsed;

            results[i] = Result({
                success: success,
                returnData: returnData,
                gasUsed: gasUsed
            });

            if (success) successCount++;

            emit CallResult(i, success, returnData);
        }

        emit MulticallExecuted(calls.length, successCount, totalGasUsed);
    }

    // ============ EXTERNAL CALLS ============

    /**
     * @notice Execute multiple external calls
     * @param calls Array of Call structs with target, callData, and value
     * @return results Array of return data
     */
    function multicallExternal(
        Call[] memory calls
    ) internal returns (bytes[] memory results) {
        if (calls.length == 0) revert EmptyCallArray();
        if (calls.length > MAX_CALLS) revert TooManyCalls(calls.length, MAX_CALLS);

        uint256 totalValue = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
        }

        if (address(this).balance < totalValue) {
            revert InsufficientValue(totalValue, address(this).balance);
        }

        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.call{value: calls[i].value}(
                calls[i].callData
            );

            if (!success) {
                revert CallFailed(i, result);
            }

            results[i] = result;
        }
    }

    /**
     * @notice Execute multiple external calls with gas limits
     * @param calls Array of CallWithGas structs
     * @return results Array of Result structs
     */
    function multicallExternalWithGas(
        CallWithGas[] memory calls
    ) internal returns (Result[] memory results) {
        if (calls.length == 0) revert EmptyCallArray();
        if (calls.length > MAX_CALLS) revert TooManyCalls(calls.length, MAX_CALLS);

        results = new Result[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            uint256 gasLimit = calls[i].gasLimit > 0 ? calls[i].gasLimit : MAX_CALL_GAS;
            uint256 gasBefore = gasleft();

            (bool success, bytes memory returnData) = calls[i].target.call{
                value: calls[i].value,
                gas: gasLimit
            }(calls[i].callData);

            results[i] = Result({
                success: success,
                returnData: returnData,
                gasUsed: gasBefore - gasleft()
            });
        }
    }

    /**
     * @notice Execute multiple static calls (read-only)
     * @param calls Array of Call structs (value is ignored)
     * @return results Array of return data
     */
    function multicallStatic(
        Call[] memory calls
    ) internal view returns (bytes[] memory results) {
        if (calls.length == 0) revert EmptyCallArray();
        if (calls.length > MAX_CALLS) revert TooManyCalls(calls.length, MAX_CALLS);

        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.staticcall(calls[i].callData);

            if (!success) {
                revert CallFailed(i, result);
            }

            results[i] = result;
        }
    }

    // ============ BATCH OPERATIONS ============

    /**
     * @notice Execute batch with configuration
     * @param calls Array of Call structs
     * @param config Batch configuration
     * @return results Array of Result structs
     */
    function batchExecute(
        Call[] memory calls,
        BatchConfig memory config
    ) internal returns (Result[] memory results) {
        if (calls.length == 0) revert EmptyCallArray();
        if (calls.length > MAX_CALLS) revert TooManyCalls(calls.length, MAX_CALLS);

        if (config.deadline != 0 && block.timestamp > config.deadline) {
            revert DeadlineExpired(config.deadline, block.timestamp);
        }

        uint256 initialBalance = address(this).balance;
        results = new Result[](calls.length);
        uint256 successCount = 0;

        for (uint256 i = 0; i < calls.length; i++) {
            uint256 gasLimit = config.maxGasPerCall > 0 ? config.maxGasPerCall : MAX_CALL_GAS;
            uint256 gasBefore = gasleft();

            (bool success, bytes memory returnData) = calls[i].target.call{
                value: calls[i].value,
                gas: gasLimit
            }(calls[i].callData);

            results[i] = Result({
                success: success,
                returnData: returnData,
                gasUsed: gasBefore - gasleft()
            });

            if (success) {
                successCount++;
            } else if (!config.allowPartialFailure) {
                revert CallFailed(i, returnData);
            }
        }

        if (config.refundUnusedValue) {
            uint256 remainingBalance = address(this).balance;
            if (remainingBalance > initialBalance) {
                uint256 refund = remainingBalance - initialBalance;
                (bool refundSuccess, ) = msg.sender.call{value: refund}("");
                if (refundSuccess) {
                    emit ValueRefunded(msg.sender, refund);
                }
            }
        }

        emit MulticallExecuted(calls.length, successCount, 0);
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Encode a function call
     * @param selector The function selector
     * @param params The encoded parameters
     * @return The encoded call data
     */
    function encodeCall(
        bytes4 selector,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(selector, params);
    }

    /**
     * @notice Decode return data as a specific type
     * @param data The return data to decode
     * @return The decoded uint256 value
     */
    function decodeUint256(bytes memory data) internal pure returns (uint256) {
        if (data.length < 32) revert InvalidCallData();
        return abi.decode(data, (uint256));
    }

    /**
     * @notice Decode return data as address
     * @param data The return data to decode
     * @return The decoded address
     */
    function decodeAddress(bytes memory data) internal pure returns (address) {
        if (data.length < 32) revert InvalidCallData();
        return abi.decode(data, (address));
    }

    /**
     * @notice Decode return data as bool
     * @param data The return data to decode
     * @return The decoded bool
     */
    function decodeBool(bytes memory data) internal pure returns (bool) {
        if (data.length < 32) revert InvalidCallData();
        return abi.decode(data, (bool));
    }

    /**
     * @notice Calculate total value needed for calls
     * @param calls Array of Call structs
     * @return total The total value
     */
    function calculateTotalValue(Call[] memory calls) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < calls.length; i++) {
            total += calls[i].value;
        }
    }

    /**
     * @notice Create a Call struct
     * @param target The target address
     * @param callData The call data
     * @param value The ETH value
     * @return The Call struct
     */
    function createCall(
        address target,
        bytes memory callData,
        uint256 value
    ) internal pure returns (Call memory) {
        return Call({
            target: target,
            callData: callData,
            value: value
        });
    }

    /**
     * @notice Aggregate results from multiple calls
     * @param results Array of Result structs
     * @return successCount Number of successful calls
     * @return failureCount Number of failed calls
     * @return totalGasUsed Total gas used
     */
    function aggregateResults(
        Result[] memory results
    ) internal pure returns (
        uint256 successCount,
        uint256 failureCount,
        uint256 totalGasUsed
    ) {
        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].success) {
                successCount++;
            } else {
                failureCount++;
            }
            totalGasUsed += results[i].gasUsed;
        }
    }

    /**
     * @notice Extract error message from failed call
     * @param returnData The return data from the failed call
     * @return The error message string
     */
    function extractErrorMessage(bytes memory returnData) internal pure returns (string memory) {
        // Check for standard Error(string) selector
        if (returnData.length >= 4) {
            bytes4 selector;
            assembly {
                selector := mload(add(returnData, 32))
            }

            // Error(string) selector
            if (selector == 0x08c379a0 && returnData.length >= 68) {
                assembly {
                    returnData := add(returnData, 4)
                }
                return abi.decode(returnData, (string));
            }
        }

        return "Unknown error";
    }
}
