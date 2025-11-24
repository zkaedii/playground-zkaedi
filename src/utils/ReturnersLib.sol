// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReturnersLib
 * @notice Utilities for handling returns, callbacks, and result processing
 * @dev Provides mechanisms for callback management, return value encoding/decoding,
 *      async result handling, and multi-call result aggregation
 */
library ReturnersLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Maximum callbacks in a single batch
    uint256 internal constant MAX_CALLBACKS = 50;

    /// @dev Maximum return data size (64KB)
    uint256 internal constant MAX_RETURN_SIZE = 65536;

    /// @dev Callback expiration period (1 hour)
    uint256 internal constant CALLBACK_EXPIRY = 1 hours;

    /// @dev Success return code
    bytes4 internal constant SUCCESS_SELECTOR = bytes4(keccak256("Success()"));

    /// @dev Standard ERC-1155 callback selectors
    bytes4 internal constant ERC1155_RECEIVED = 0xf23a6e61;
    bytes4 internal constant ERC1155_BATCH_RECEIVED = 0xbc197c81;

    /// @dev Standard ERC-721 callback selector
    bytes4 internal constant ERC721_RECEIVED = 0x150b7a02;

    /// @dev Flash loan callback selector
    bytes4 internal constant FLASH_CALLBACK = 0x23e30c8b;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error CallbackNotRegistered(bytes32 callbackId);
    error CallbackAlreadyRegistered(bytes32 callbackId);
    error CallbackExpired(bytes32 callbackId, uint256 expiry);
    error CallbackAlreadyExecuted(bytes32 callbackId);
    error InvalidCallbackSelector(bytes4 selector);
    error InvalidReturnData(uint256 length);
    error ReturnDataTooLarge(uint256 size, uint256 max);
    error UnauthorizedCallback(address caller, address expected);
    error CallFailed(address target, bytes reason);
    error BatchCallFailed(uint256 index, bytes reason);
    error InvalidResultIndex(uint256 index, uint256 length);
    error ResultNotAvailable(bytes32 resultId);
    error ResultAlreadySet(bytes32 resultId);
    error DecodingFailed(string reason);
    error InvalidAggregationType();
    error EmptyResults();
    error MismatchedArrayLengths(uint256 length1, uint256 length2);

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Callback status enum
    enum CallbackStatus {
        Pending,
        Executed,
        Failed,
        Expired,
        Cancelled
    }

    /// @notice Return type classification
    enum ReturnType {
        None,
        Bool,
        Uint256,
        Int256,
        Address,
        Bytes32,
        Bytes,
        String,
        Tuple,
        Array
    }

    /// @notice Aggregation method for multi-results
    enum AggregationType {
        First,
        Last,
        Sum,
        Average,
        Min,
        Max,
        Median,
        All
    }

    /// @notice Registered callback information
    struct CallbackInfo {
        bytes32 callbackId;
        address caller;
        address target;
        bytes4 selector;
        bytes data;
        uint256 registeredAt;
        uint256 expiresAt;
        CallbackStatus status;
        bytes returnData;
    }

    /// @notice Callback registry storage
    struct CallbackRegistry {
        mapping(bytes32 => CallbackInfo) callbacks;
        mapping(address => bytes32[]) callerCallbacks;
        mapping(bytes4 => bool) allowedSelectors;
        uint256 totalCallbacks;
        uint256 executedCallbacks;
    }

    /// @notice Single call result
    struct CallResult {
        bool success;
        bytes returnData;
        uint256 gasUsed;
        uint256 timestamp;
    }

    /// @notice Batch call results
    struct BatchResult {
        bytes32 batchId;
        CallResult[] results;
        uint256 successCount;
        uint256 failureCount;
        uint256 totalGasUsed;
    }

    /// @notice Async result storage
    struct AsyncResult {
        bytes32 resultId;
        bool isSet;
        bool success;
        bytes data;
        uint256 setAt;
        address setter;
    }

    /// @notice Async result registry
    struct AsyncRegistry {
        mapping(bytes32 => AsyncResult) results;
        mapping(address => bytes32[]) pendingResults;
        uint256 totalResults;
    }

    /// @notice Decoded return value
    struct DecodedReturn {
        ReturnType returnType;
        uint256 uintValue;
        int256 intValue;
        address addressValue;
        bytes32 bytes32Value;
        bytes bytesValue;
        bool boolValue;
    }

    /// @notice Multi-call configuration
    struct MultiCallConfig {
        bool allowPartialSuccess;
        bool stopOnFirstFailure;
        uint256 gasLimit;
        uint256 timeout;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLBACK REGISTRATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Register a callback for later execution
    /// @param registry The callback registry storage
    /// @param target Target contract for callback
    /// @param selector Function selector
    /// @param data Callback data
    /// @param expiry Expiration timestamp
    /// @return callbackId Generated callback ID
    function registerCallback(
        CallbackRegistry storage registry,
        address target,
        bytes4 selector,
        bytes memory data,
        uint256 expiry
    ) internal returns (bytes32 callbackId) {
        callbackId = keccak256(
            abi.encode(msg.sender, target, selector, data, block.timestamp, registry.totalCallbacks)
        );

        if (registry.callbacks[callbackId].callbackId != bytes32(0)) {
            revert CallbackAlreadyRegistered(callbackId);
        }

        registry.callbacks[callbackId] = CallbackInfo({
            callbackId: callbackId,
            caller: msg.sender,
            target: target,
            selector: selector,
            data: data,
            registeredAt: block.timestamp,
            expiresAt: expiry > 0 ? expiry : block.timestamp + CALLBACK_EXPIRY,
            status: CallbackStatus.Pending,
            returnData: ""
        });

        registry.callerCallbacks[msg.sender].push(callbackId);
        unchecked {
            ++registry.totalCallbacks;
        }
    }

    /// @notice Allow a specific callback selector
    /// @param registry The callback registry storage
    /// @param selector Selector to allow
    function allowSelector(CallbackRegistry storage registry, bytes4 selector) internal {
        registry.allowedSelectors[selector] = true;
    }

    /// @notice Disallow a callback selector
    /// @param registry The callback registry storage
    /// @param selector Selector to disallow
    function disallowSelector(CallbackRegistry storage registry, bytes4 selector) internal {
        registry.allowedSelectors[selector] = false;
    }

    /// @notice Check if selector is allowed
    /// @param registry The callback registry storage
    /// @param selector Selector to check
    /// @return allowed True if selector is allowed
    function isSelectorAllowed(
        CallbackRegistry storage registry,
        bytes4 selector
    ) internal view returns (bool allowed) {
        return registry.allowedSelectors[selector];
    }

    /// @notice Execute a registered callback
    /// @param registry The callback registry storage
    /// @param callbackId Callback to execute
    /// @return success Whether execution succeeded
    /// @return returnData Return data from callback
    function executeCallback(
        CallbackRegistry storage registry,
        bytes32 callbackId
    ) internal returns (bool success, bytes memory returnData) {
        CallbackInfo storage callback = registry.callbacks[callbackId];

        if (callback.callbackId == bytes32(0)) {
            revert CallbackNotRegistered(callbackId);
        }

        if (callback.status != CallbackStatus.Pending) {
            revert CallbackAlreadyExecuted(callbackId);
        }

        if (block.timestamp > callback.expiresAt) {
            callback.status = CallbackStatus.Expired;
            revert CallbackExpired(callbackId, callback.expiresAt);
        }

        // Execute callback
        bytes memory callData = abi.encodePacked(callback.selector, callback.data);
        (success, returnData) = callback.target.call(callData);

        callback.returnData = returnData;
        callback.status = success ? CallbackStatus.Executed : CallbackStatus.Failed;

        if (success) {
            unchecked {
                ++registry.executedCallbacks;
            }
        }
    }

    /// @notice Cancel a pending callback
    /// @param registry The callback registry storage
    /// @param callbackId Callback to cancel
    function cancelCallback(CallbackRegistry storage registry, bytes32 callbackId) internal {
        CallbackInfo storage callback = registry.callbacks[callbackId];

        if (callback.callbackId == bytes32(0)) {
            revert CallbackNotRegistered(callbackId);
        }

        if (callback.caller != msg.sender) {
            revert UnauthorizedCallback(msg.sender, callback.caller);
        }

        if (callback.status != CallbackStatus.Pending) {
            revert CallbackAlreadyExecuted(callbackId);
        }

        callback.status = CallbackStatus.Cancelled;
    }

    /// @notice Get callback info
    /// @param registry The callback registry storage
    /// @param callbackId Callback ID
    /// @return info Callback information
    function getCallback(
        CallbackRegistry storage registry,
        bytes32 callbackId
    ) internal view returns (CallbackInfo storage info) {
        info = registry.callbacks[callbackId];
        if (info.callbackId == bytes32(0)) {
            revert CallbackNotRegistered(callbackId);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RETURN DATA ENCODING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Encode multiple return values into bytes
    /// @param values Array of uint256 values
    /// @return encoded Encoded bytes
    function encodeUintArray(uint256[] memory values) internal pure returns (bytes memory encoded) {
        return abi.encode(values);
    }

    /// @notice Encode address array
    /// @param addresses Array of addresses
    /// @return encoded Encoded bytes
    function encodeAddressArray(address[] memory addresses) internal pure returns (bytes memory encoded) {
        return abi.encode(addresses);
    }

    /// @notice Encode mixed return values
    /// @param success Success flag
    /// @param value Uint value
    /// @param data Bytes data
    /// @return encoded Encoded bytes
    function encodeMixedReturn(
        bool success,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes memory encoded) {
        return abi.encode(success, value, data);
    }

    /// @notice Encode error with message
    /// @param errorSelector Error selector
    /// @param message Error message
    /// @return encoded Encoded error
    function encodeError(
        bytes4 errorSelector,
        string memory message
    ) internal pure returns (bytes memory encoded) {
        return abi.encodeWithSelector(errorSelector, message);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RETURN DATA DECODING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Decode return data to bool
    /// @param data Raw return data
    /// @return value Decoded bool value
    function decodeBool(bytes memory data) internal pure returns (bool value) {
        if (data.length == 0) return false;
        if (data.length < 32) {
            revert DecodingFailed("Invalid bool encoding");
        }
        return abi.decode(data, (bool));
    }

    /// @notice Decode return data to uint256
    /// @param data Raw return data
    /// @return value Decoded uint256 value
    function decodeUint256(bytes memory data) internal pure returns (uint256 value) {
        if (data.length < 32) {
            revert DecodingFailed("Invalid uint256 encoding");
        }
        return abi.decode(data, (uint256));
    }

    /// @notice Decode return data to address
    /// @param data Raw return data
    /// @return value Decoded address
    function decodeAddress(bytes memory data) internal pure returns (address value) {
        if (data.length < 32) {
            revert DecodingFailed("Invalid address encoding");
        }
        return abi.decode(data, (address));
    }

    /// @notice Decode return data to bytes32
    /// @param data Raw return data
    /// @return value Decoded bytes32
    function decodeBytes32(bytes memory data) internal pure returns (bytes32 value) {
        if (data.length < 32) {
            revert DecodingFailed("Invalid bytes32 encoding");
        }
        return abi.decode(data, (bytes32));
    }

    /// @notice Decode return data to uint256 array
    /// @param data Raw return data
    /// @return values Decoded array
    function decodeUint256Array(bytes memory data) internal pure returns (uint256[] memory values) {
        if (data.length < 64) {
            revert DecodingFailed("Invalid array encoding");
        }
        return abi.decode(data, (uint256[]));
    }

    /// @notice Decode return data to address array
    /// @param data Raw return data
    /// @return values Decoded array
    function decodeAddressArray(bytes memory data) internal pure returns (address[] memory values) {
        if (data.length < 64) {
            revert DecodingFailed("Invalid array encoding");
        }
        return abi.decode(data, (address[]));
    }

    /// @notice Decode mixed return (bool, uint256, bytes)
    /// @param data Raw return data
    /// @return success Success flag
    /// @return value Uint value
    /// @return extraData Bytes data
    function decodeMixedReturn(bytes memory data) internal pure returns (
        bool success,
        uint256 value,
        bytes memory extraData
    ) {
        if (data.length < 96) {
            revert DecodingFailed("Invalid mixed encoding");
        }
        return abi.decode(data, (bool, uint256, bytes));
    }

    /// @notice Try to decode and classify return type
    /// @param data Raw return data
    /// @return decoded Decoded return value structure
    function tryDecode(bytes memory data) internal pure returns (DecodedReturn memory decoded) {
        if (data.length == 0) {
            decoded.returnType = ReturnType.None;
            return decoded;
        }

        if (data.length == 32) {
            // Could be bool, uint256, address, or bytes32
            uint256 rawValue = abi.decode(data, (uint256));

            // Check if it looks like a bool
            if (rawValue == 0 || rawValue == 1) {
                decoded.returnType = ReturnType.Bool;
                decoded.boolValue = rawValue == 1;
            }
            // Check if it looks like an address (high bits are zero)
            else if (rawValue <= type(uint160).max) {
                decoded.returnType = ReturnType.Address;
                decoded.addressValue = address(uint160(rawValue));
            }
            // Otherwise treat as uint256
            else {
                decoded.returnType = ReturnType.Uint256;
                decoded.uintValue = rawValue;
            }

            decoded.bytes32Value = bytes32(rawValue);
        } else {
            decoded.returnType = ReturnType.Bytes;
            decoded.bytesValue = data;
        }
    }

    /// @notice Extract revert reason from failed call data
    /// @param data Revert data
    /// @return reason Extracted reason string
    function extractRevertReason(bytes memory data) internal pure returns (string memory reason) {
        if (data.length < 68) {
            return "Unknown error";
        }

        // Check for Error(string) selector: 0x08c379a0
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }

        if (selector == 0x08c379a0) {
            assembly {
                // Skip selector (4 bytes) and offset (32 bytes)
                data := add(data, 36)
            }
            return abi.decode(data, (string));
        }

        return "Custom error";
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH CALL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Execute multiple calls and collect results
    /// @param targets Target addresses
    /// @param callDatas Call data for each target
    /// @param config Multi-call configuration
    /// @return result Batch result
    function batchCall(
        address[] memory targets,
        bytes[] memory callDatas,
        MultiCallConfig memory config
    ) internal returns (BatchResult memory result) {
        if (targets.length != callDatas.length) {
            revert MismatchedArrayLengths(targets.length, callDatas.length);
        }

        result.batchId = keccak256(abi.encode(targets, block.timestamp));
        result.results = new CallResult[](targets.length);

        for (uint256 i; i < targets.length;) {
            uint256 gasBefore = gasleft();

            (bool success, bytes memory returnData) = config.gasLimit > 0
                ? targets[i].call{gas: config.gasLimit}(callDatas[i])
                : targets[i].call(callDatas[i]);

            uint256 gasUsed = gasBefore - gasleft();

            result.results[i] = CallResult({
                success: success,
                returnData: returnData,
                gasUsed: gasUsed,
                timestamp: block.timestamp
            });

            result.totalGasUsed += gasUsed;

            if (success) {
                unchecked { ++result.successCount; }
            } else {
                unchecked { ++result.failureCount; }

                if (config.stopOnFirstFailure) {
                    break;
                }

                if (!config.allowPartialSuccess) {
                    revert BatchCallFailed(i, returnData);
                }
            }

            unchecked { ++i; }
        }
    }

    /// @notice Execute calls with static call (no state changes)
    /// @param targets Target addresses
    /// @param callDatas Call data for each target
    /// @return results Array of call results
    function batchStaticCall(
        address[] memory targets,
        bytes[] memory callDatas
    ) internal view returns (CallResult[] memory results) {
        if (targets.length != callDatas.length) {
            revert MismatchedArrayLengths(targets.length, callDatas.length);
        }

        results = new CallResult[](targets.length);

        for (uint256 i; i < targets.length;) {
            uint256 gasBefore = gasleft();

            (bool success, bytes memory returnData) = targets[i].staticcall(callDatas[i]);

            results[i] = CallResult({
                success: success,
                returnData: returnData,
                gasUsed: gasBefore - gasleft(),
                timestamp: block.timestamp
            });

            unchecked { ++i; }
        }
    }

    /// @notice Get specific result from batch
    /// @param result Batch result
    /// @param index Result index
    /// @return callResult Individual call result
    function getResult(
        BatchResult memory result,
        uint256 index
    ) internal pure returns (CallResult memory callResult) {
        if (index >= result.results.length) {
            revert InvalidResultIndex(index, result.results.length);
        }
        return result.results[index];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ASYNC RESULT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Register an async result placeholder
    /// @param registry Async registry storage
    /// @param resultId Unique result identifier
    function registerAsyncResult(
        AsyncRegistry storage registry,
        bytes32 resultId
    ) internal {
        if (registry.results[resultId].isSet) {
            revert ResultAlreadySet(resultId);
        }

        registry.results[resultId] = AsyncResult({
            resultId: resultId,
            isSet: false,
            success: false,
            data: "",
            setAt: 0,
            setter: address(0)
        });

        registry.pendingResults[msg.sender].push(resultId);
        unchecked {
            ++registry.totalResults;
        }
    }

    /// @notice Set async result
    /// @param registry Async registry storage
    /// @param resultId Result identifier
    /// @param success Success flag
    /// @param data Result data
    function setAsyncResult(
        AsyncRegistry storage registry,
        bytes32 resultId,
        bool success,
        bytes memory data
    ) internal {
        AsyncResult storage result = registry.results[resultId];

        if (result.isSet) {
            revert ResultAlreadySet(resultId);
        }

        result.isSet = true;
        result.success = success;
        result.data = data;
        result.setAt = block.timestamp;
        result.setter = msg.sender;
    }

    /// @notice Get async result
    /// @param registry Async registry storage
    /// @param resultId Result identifier
    /// @return result The async result
    function getAsyncResult(
        AsyncRegistry storage registry,
        bytes32 resultId
    ) internal view returns (AsyncResult storage result) {
        result = registry.results[resultId];
        if (result.resultId == bytes32(0)) {
            revert ResultNotAvailable(resultId);
        }
    }

    /// @notice Check if async result is available
    /// @param registry Async registry storage
    /// @param resultId Result identifier
    /// @return available True if result is set
    function isResultAvailable(
        AsyncRegistry storage registry,
        bytes32 resultId
    ) internal view returns (bool available) {
        return registry.results[resultId].isSet;
    }

    /// @notice Wait for multiple results (check availability)
    /// @param registry Async registry storage
    /// @param resultIds Array of result identifiers
    /// @return allAvailable True if all results are available
    /// @return availableCount Number of available results
    function checkMultipleResults(
        AsyncRegistry storage registry,
        bytes32[] memory resultIds
    ) internal view returns (bool allAvailable, uint256 availableCount) {
        allAvailable = true;

        for (uint256 i; i < resultIds.length;) {
            if (registry.results[resultIds[i]].isSet) {
                unchecked { ++availableCount; }
            } else {
                allAvailable = false;
            }
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RESULT AGGREGATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Aggregate uint256 results
    /// @param results Array of call results (must decode to uint256)
    /// @param aggregationType How to aggregate
    /// @return aggregated Aggregated value
    function aggregateUintResults(
        CallResult[] memory results,
        AggregationType aggregationType
    ) internal pure returns (uint256 aggregated) {
        if (results.length == 0) {
            revert EmptyResults();
        }

        if (aggregationType == AggregationType.First) {
            for (uint256 i; i < results.length;) {
                if (results[i].success && results[i].returnData.length >= 32) {
                    return decodeUint256(results[i].returnData);
                }
                unchecked { ++i; }
            }
            revert EmptyResults();
        }

        if (aggregationType == AggregationType.Last) {
            for (uint256 i = results.length; i > 0;) {
                unchecked { --i; }
                if (results[i].success && results[i].returnData.length >= 32) {
                    return decodeUint256(results[i].returnData);
                }
            }
            revert EmptyResults();
        }

        // Collect valid values
        uint256[] memory values = new uint256[](results.length);
        uint256 validCount;

        for (uint256 i; i < results.length;) {
            if (results[i].success && results[i].returnData.length >= 32) {
                values[validCount] = decodeUint256(results[i].returnData);
                unchecked { ++validCount; }
            }
            unchecked { ++i; }
        }

        if (validCount == 0) {
            revert EmptyResults();
        }

        if (aggregationType == AggregationType.Sum) {
            for (uint256 i; i < validCount;) {
                aggregated += values[i];
                unchecked { ++i; }
            }
        } else if (aggregationType == AggregationType.Average) {
            for (uint256 i; i < validCount;) {
                aggregated += values[i];
                unchecked { ++i; }
            }
            aggregated = aggregated / validCount;
        } else if (aggregationType == AggregationType.Min) {
            aggregated = type(uint256).max;
            for (uint256 i; i < validCount;) {
                if (values[i] < aggregated) {
                    aggregated = values[i];
                }
                unchecked { ++i; }
            }
        } else if (aggregationType == AggregationType.Max) {
            for (uint256 i; i < validCount;) {
                if (values[i] > aggregated) {
                    aggregated = values[i];
                }
                unchecked { ++i; }
            }
        } else if (aggregationType == AggregationType.Median) {
            // Sort values (simple bubble sort for small arrays)
            for (uint256 i; i < validCount;) {
                for (uint256 j = i + 1; j < validCount;) {
                    if (values[j] < values[i]) {
                        uint256 temp = values[i];
                        values[i] = values[j];
                        values[j] = temp;
                    }
                    unchecked { ++j; }
                }
                unchecked { ++i; }
            }

            if (validCount % 2 == 0) {
                aggregated = (values[validCount / 2 - 1] + values[validCount / 2]) / 2;
            } else {
                aggregated = values[validCount / 2];
            }
        } else {
            revert InvalidAggregationType();
        }
    }

    /// @notice Collect all successful results
    /// @param results Array of call results
    /// @return successfulData Array of successful return data
    function collectSuccessfulResults(
        CallResult[] memory results
    ) internal pure returns (bytes[] memory successfulData) {
        // Count successful
        uint256 successCount;
        for (uint256 i; i < results.length;) {
            if (results[i].success) {
                unchecked { ++successCount; }
            }
            unchecked { ++i; }
        }

        // Collect
        successfulData = new bytes[](successCount);
        uint256 idx;

        for (uint256 i; i < results.length;) {
            if (results[i].success) {
                successfulData[idx] = results[i].returnData;
                unchecked { ++idx; }
            }
            unchecked { ++i; }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLBACK RECEIVER HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Standard ERC721 receiver response
    /// @return selector The ERC721 receiver selector
    function onERC721Received() internal pure returns (bytes4 selector) {
        return ERC721_RECEIVED;
    }

    /// @notice Standard ERC1155 receiver response
    /// @return selector The ERC1155 receiver selector
    function onERC1155Received() internal pure returns (bytes4 selector) {
        return ERC1155_RECEIVED;
    }

    /// @notice Standard ERC1155 batch receiver response
    /// @return selector The ERC1155 batch receiver selector
    function onERC1155BatchReceived() internal pure returns (bytes4 selector) {
        return ERC1155_BATCH_RECEIVED;
    }

    /// @notice Flash loan callback response
    /// @return selector The flash loan callback selector
    function onFlashLoan() internal pure returns (bytes4 selector) {
        return FLASH_CALLBACK;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate callback ID
    /// @param caller Callback caller
    /// @param target Callback target
    /// @param selector Function selector
    /// @param nonce Unique nonce
    /// @return callbackId Generated ID
    function generateCallbackId(
        address caller,
        address target,
        bytes4 selector,
        uint256 nonce
    ) internal view returns (bytes32 callbackId) {
        return keccak256(abi.encode(caller, target, selector, nonce, block.chainid));
    }

    /// @notice Check if return data indicates success
    /// @param data Return data to check
    /// @return isSuccess True if data indicates success
    function isSuccessReturn(bytes memory data) internal pure returns (bool isSuccess) {
        if (data.length == 0) return true;

        if (data.length >= 32) {
            bool decoded = abi.decode(data, (bool));
            return decoded;
        }

        return false;
    }

    /// @notice Validate return data size
    /// @param data Return data to validate
    function validateReturnSize(bytes memory data) internal pure {
        if (data.length > MAX_RETURN_SIZE) {
            revert ReturnDataTooLarge(data.length, MAX_RETURN_SIZE);
        }
    }

    /// @notice Pack multiple bytes into single bytes
    /// @param dataArray Array of bytes to pack
    /// @return packed Packed bytes with length prefixes
    function packMultipleBytes(bytes[] memory dataArray) internal pure returns (bytes memory packed) {
        for (uint256 i; i < dataArray.length;) {
            packed = abi.encodePacked(packed, uint32(dataArray[i].length), dataArray[i]);
            unchecked { ++i; }
        }
    }

    /// @notice Check if address is a contract
    /// @param addr Address to check
    /// @return isContract True if address has code
    function isContract(address addr) internal view returns (bool isContract) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
