// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title APILib
 * @notice API encoding/decoding utilities for on-chain oracle and external data integration
 * @dev Provides JSON encoding, HTTP-style request/response handling, signature verification,
 *      and rate limiting helpers for smart contract APIs
 */
library APILib {
    // ============ CONSTANTS ============

    /// @notice Maximum request/response size
    uint256 internal constant MAX_PAYLOAD_SIZE = 32768; // 32KB

    /// @notice HTTP status codes
    uint256 internal constant STATUS_OK = 200;
    uint256 internal constant STATUS_CREATED = 201;
    uint256 internal constant STATUS_BAD_REQUEST = 400;
    uint256 internal constant STATUS_UNAUTHORIZED = 401;
    uint256 internal constant STATUS_FORBIDDEN = 403;
    uint256 internal constant STATUS_NOT_FOUND = 404;
    uint256 internal constant STATUS_RATE_LIMITED = 429;
    uint256 internal constant STATUS_SERVER_ERROR = 500;

    /// @notice Content types
    bytes32 internal constant CONTENT_TYPE_JSON = keccak256("application/json");
    bytes32 internal constant CONTENT_TYPE_CBOR = keccak256("application/cbor");
    bytes32 internal constant CONTENT_TYPE_PROTOBUF = keccak256("application/protobuf");

    // ============ TYPES ============

    /// @notice API request structure
    struct Request {
        bytes32 id;              // Unique request ID
        string method;           // HTTP-like method (GET, POST, etc.)
        string endpoint;         // Target endpoint/path
        bytes params;            // Encoded parameters
        bytes32 contentType;     // Content type
        uint256 timestamp;       // Request timestamp
        address sender;          // Request sender
        bytes signature;         // Optional signature
    }

    /// @notice API response structure
    struct Response {
        bytes32 requestId;       // Corresponding request ID
        uint256 status;          // Status code
        bytes data;              // Response data
        bytes32 contentType;     // Response content type
        uint256 timestamp;       // Response timestamp
        bytes32 dataHash;        // Hash of response data for verification
    }

    /// @notice Rate limit configuration
    struct RateLimitConfig {
        uint256 maxRequests;     // Maximum requests per window
        uint256 windowSize;      // Time window in seconds
        uint256 cooldownPeriod;  // Cooldown after limit hit
    }

    /// @notice Rate limit state
    struct RateLimitState {
        uint256 requestCount;    // Current request count
        uint256 windowStart;     // Current window start time
        uint256 cooldownUntil;   // Cooldown end time (if in cooldown)
    }

    /// @notice API key configuration
    struct APIKey {
        bytes32 keyHash;         // Hash of the API key
        uint256 tier;            // Access tier (0=free, 1=basic, 2=premium, etc.)
        uint256 rateLimit;       // Custom rate limit (0 = use default)
        uint256 expiresAt;       // Expiration timestamp (0 = never)
        bool isActive;           // Whether key is active
    }

    /// @notice Webhook configuration
    struct Webhook {
        bytes32 id;              // Webhook ID
        string url;              // Target URL (for off-chain reference)
        bytes32 secret;          // Webhook secret for signing
        string[] events;         // Subscribed event types
        bool isActive;           // Whether webhook is active
    }

    /// @notice Batch request
    struct BatchRequest {
        Request[] requests;      // Array of requests
        bool atomic;             // Whether to fail all if one fails
    }

    // ============ ERRORS ============

    error InvalidRequest();
    error RateLimitExceeded();
    error InvalidAPIKey();
    error RequestExpired();
    error InvalidSignature();
    error PayloadTooLarge();

    // ============ REQUEST BUILDING ============

    /**
     * @notice Create a new API request
     * @param method HTTP-like method
     * @param endpoint Target endpoint
     * @param params Encoded parameters
     * @return Constructed request
     */
    function createRequest(
        string memory method,
        string memory endpoint,
        bytes memory params
    ) internal view returns (Request memory) {
        if (bytes(params).length > MAX_PAYLOAD_SIZE) revert PayloadTooLarge();

        bytes32 id = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            endpoint,
            params
        ));

        return Request({
            id: id,
            method: method,
            endpoint: endpoint,
            params: params,
            contentType: CONTENT_TYPE_JSON,
            timestamp: block.timestamp,
            sender: msg.sender,
            signature: ""
        });
    }

    /**
     * @notice Create a GET request
     * @param endpoint Target endpoint
     * @param queryParams URL-encoded query parameters
     * @return GET request
     */
    function get(string memory endpoint, bytes memory queryParams) internal view returns (Request memory) {
        return createRequest("GET", endpoint, queryParams);
    }

    /**
     * @notice Create a POST request
     * @param endpoint Target endpoint
     * @param body Request body
     * @return POST request
     */
    function post(string memory endpoint, bytes memory body) internal view returns (Request memory) {
        return createRequest("POST", endpoint, body);
    }

    /**
     * @notice Sign a request
     * @param request Request to sign
     * @param signature Signature bytes
     * @return Signed request
     */
    function signRequest(Request memory request, bytes memory signature) internal pure returns (Request memory) {
        request.signature = signature;
        return request;
    }

    /**
     * @notice Get request hash for signing
     * @param request Request to hash
     * @return Request hash
     */
    function getRequestHash(Request memory request) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            request.id,
            request.method,
            request.endpoint,
            request.params,
            request.timestamp,
            request.sender
        ));
    }

    // ============ RESPONSE BUILDING ============

    /**
     * @notice Create a success response
     * @param requestId Original request ID
     * @param data Response data
     * @return Success response
     */
    function success(bytes32 requestId, bytes memory data) internal view returns (Response memory) {
        return Response({
            requestId: requestId,
            status: STATUS_OK,
            data: data,
            contentType: CONTENT_TYPE_JSON,
            timestamp: block.timestamp,
            dataHash: keccak256(data)
        });
    }

    /**
     * @notice Create an error response
     * @param requestId Original request ID
     * @param status Error status code
     * @param message Error message
     * @return Error response
     */
    function error(bytes32 requestId, uint256 status, string memory message) internal view returns (Response memory) {
        bytes memory data = abi.encodePacked('{"error":"', message, '"}');

        return Response({
            requestId: requestId,
            status: status,
            data: data,
            contentType: CONTENT_TYPE_JSON,
            timestamp: block.timestamp,
            dataHash: keccak256(data)
        });
    }

    /**
     * @notice Check if response is successful
     * @param response Response to check
     * @return True if status is 2xx
     */
    function isSuccess(Response memory response) internal pure returns (bool) {
        return response.status >= 200 && response.status < 300;
    }

    // ============ JSON ENCODING ============

    /**
     * @notice Encode key-value pair as JSON
     * @param key JSON key
     * @param value JSON value (already formatted)
     * @return JSON string
     */
    function jsonPair(string memory key, string memory value) internal pure returns (string memory) {
        return string(abi.encodePacked('"', key, '":', value));
    }

    /**
     * @notice Encode string value for JSON
     * @param value String to encode
     * @return JSON string value with quotes
     */
    function jsonString(string memory value) internal pure returns (string memory) {
        return string(abi.encodePacked('"', value, '"'));
    }

    /**
     * @notice Encode uint256 value for JSON
     * @param value Number to encode
     * @return JSON number string
     */
    function jsonNumber(uint256 value) internal pure returns (string memory) {
        return _uintToString(value);
    }

    /**
     * @notice Encode int256 value for JSON
     * @param value Number to encode
     * @return JSON number string
     */
    function jsonInt(int256 value) internal pure returns (string memory) {
        if (value >= 0) {
            return _uintToString(uint256(value));
        }
        return string(abi.encodePacked("-", _uintToString(uint256(-value))));
    }

    /**
     * @notice Encode boolean value for JSON
     * @param value Boolean to encode
     * @return JSON boolean string
     */
    function jsonBool(bool value) internal pure returns (string memory) {
        return value ? "true" : "false";
    }

    /**
     * @notice Encode address value for JSON
     * @param addr Address to encode
     * @return JSON string with address
     */
    function jsonAddress(address addr) internal pure returns (string memory) {
        return string(abi.encodePacked('"', _addressToString(addr), '"'));
    }

    /**
     * @notice Encode bytes32 value for JSON
     * @param data Bytes32 to encode
     * @return JSON string with hex
     */
    function jsonBytes32(bytes32 data) internal pure returns (string memory) {
        return string(abi.encodePacked('"0x', _bytes32ToHex(data), '"'));
    }

    /**
     * @notice Build JSON object from pairs
     * @param pairs Array of key-value pair strings
     * @return JSON object string
     */
    function jsonObject(string[] memory pairs) internal pure returns (string memory) {
        if (pairs.length == 0) return "{}";

        string memory result = "{";
        for (uint256 i = 0; i < pairs.length; i++) {
            if (i > 0) {
                result = string(abi.encodePacked(result, ","));
            }
            result = string(abi.encodePacked(result, pairs[i]));
        }
        return string(abi.encodePacked(result, "}"));
    }

    /**
     * @notice Build JSON array from values
     * @param values Array of value strings
     * @return JSON array string
     */
    function jsonArray(string[] memory values) internal pure returns (string memory) {
        if (values.length == 0) return "[]";

        string memory result = "[";
        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) {
                result = string(abi.encodePacked(result, ","));
            }
            result = string(abi.encodePacked(result, values[i]));
        }
        return string(abi.encodePacked(result, "]"));
    }

    // ============ PARAMETER ENCODING ============

    /**
     * @notice Encode URL query parameters
     * @param keys Parameter keys
     * @param values Parameter values
     * @return URL-encoded query string
     */
    function encodeQueryParams(string[] memory keys, string[] memory values) internal pure returns (bytes memory) {
        require(keys.length == values.length, "Length mismatch");

        if (keys.length == 0) return "";

        string memory result = string(abi.encodePacked(keys[0], "=", values[0]));

        for (uint256 i = 1; i < keys.length; i++) {
            result = string(abi.encodePacked(result, "&", keys[i], "=", values[i]));
        }

        return bytes(result);
    }

    /**
     * @notice Encode parameters using ABI encoding
     * @param types Array of type strings (for documentation)
     * @param data ABI-encoded data
     * @return Encoded parameters with type info
     */
    function encodeParams(string[] memory types, bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(types, data);
    }

    // ============ RATE LIMITING ============

    /**
     * @notice Check if request is within rate limits
     * @param state Current rate limit state
     * @param config Rate limit configuration
     * @param currentTime Current timestamp
     * @return allowed Whether request is allowed
     * @return newState Updated rate limit state
     */
    function checkRateLimit(
        RateLimitState memory state,
        RateLimitConfig memory config,
        uint256 currentTime
    ) internal pure returns (bool allowed, RateLimitState memory newState) {
        newState = state;

        // Check cooldown
        if (currentTime < state.cooldownUntil) {
            return (false, newState);
        }

        // Check if window has reset
        if (currentTime >= state.windowStart + config.windowSize) {
            newState.windowStart = currentTime;
            newState.requestCount = 1;
            newState.cooldownUntil = 0;
            return (true, newState);
        }

        // Check if under limit
        if (state.requestCount < config.maxRequests) {
            newState.requestCount = state.requestCount + 1;
            return (true, newState);
        }

        // Rate limited - set cooldown
        newState.cooldownUntil = currentTime + config.cooldownPeriod;
        return (false, newState);
    }

    /**
     * @notice Get remaining requests in current window
     * @param state Current rate limit state
     * @param config Rate limit configuration
     * @param currentTime Current timestamp
     * @return Remaining requests
     */
    function getRemainingRequests(
        RateLimitState memory state,
        RateLimitConfig memory config,
        uint256 currentTime
    ) internal pure returns (uint256) {
        if (currentTime >= state.windowStart + config.windowSize) {
            return config.maxRequests;
        }
        if (state.requestCount >= config.maxRequests) {
            return 0;
        }
        return config.maxRequests - state.requestCount;
    }

    /**
     * @notice Get time until rate limit resets
     * @param state Current rate limit state
     * @param config Rate limit configuration
     * @param currentTime Current timestamp
     * @return Seconds until reset
     */
    function getTimeUntilReset(
        RateLimitState memory state,
        RateLimitConfig memory config,
        uint256 currentTime
    ) internal pure returns (uint256) {
        if (currentTime < state.cooldownUntil) {
            return state.cooldownUntil - currentTime;
        }

        uint256 windowEnd = state.windowStart + config.windowSize;
        if (currentTime >= windowEnd) {
            return 0;
        }
        return windowEnd - currentTime;
    }

    // ============ API KEY MANAGEMENT ============

    /**
     * @notice Create API key hash
     * @param key Raw API key
     * @return Key hash
     */
    function hashAPIKey(string memory key) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(key));
    }

    /**
     * @notice Validate API key
     * @param keyHash Provided key hash
     * @param apiKey Stored API key config
     * @param currentTime Current timestamp
     * @return True if key is valid
     */
    function validateAPIKey(
        bytes32 keyHash,
        APIKey memory apiKey,
        uint256 currentTime
    ) internal pure returns (bool) {
        if (!apiKey.isActive) return false;
        if (apiKey.keyHash != keyHash) return false;
        if (apiKey.expiresAt != 0 && currentTime > apiKey.expiresAt) return false;
        return true;
    }

    /**
     * @notice Create new API key configuration
     * @param keyHash Hash of the API key
     * @param tier Access tier
     * @param rateLimit Custom rate limit
     * @param validityPeriod Validity period in seconds (0 = never expires)
     * @param currentTime Current timestamp
     * @return API key configuration
     */
    function createAPIKey(
        bytes32 keyHash,
        uint256 tier,
        uint256 rateLimit,
        uint256 validityPeriod,
        uint256 currentTime
    ) internal pure returns (APIKey memory) {
        return APIKey({
            keyHash: keyHash,
            tier: tier,
            rateLimit: rateLimit,
            expiresAt: validityPeriod > 0 ? currentTime + validityPeriod : 0,
            isActive: true
        });
    }

    // ============ SIGNATURE VERIFICATION ============

    /**
     * @notice Verify request signature
     * @param request Request to verify
     * @param expectedSigner Expected signer address
     * @return True if signature is valid
     */
    function verifyRequestSignature(Request memory request, address expectedSigner) internal pure returns (bool) {
        if (request.signature.length != 65) return false;

        bytes32 messageHash = getRequestHash(request);
        bytes32 ethSignedHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));

        address signer = _recoverSigner(ethSignedHash, request.signature);
        return signer == expectedSigner;
    }

    /**
     * @notice Create webhook signature
     * @param webhookSecret Webhook secret
     * @param payload Payload to sign
     * @param timestamp Timestamp for replay protection
     * @return Signature hash
     */
    function createWebhookSignature(
        bytes32 webhookSecret,
        bytes memory payload,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            webhookSecret,
            timestamp,
            keccak256(payload)
        ));
    }

    /**
     * @notice Verify webhook signature
     * @param webhookSecret Webhook secret
     * @param payload Received payload
     * @param timestamp Timestamp from header
     * @param signature Signature from header
     * @param maxAge Maximum age in seconds
     * @param currentTime Current timestamp
     * @return True if signature is valid
     */
    function verifyWebhookSignature(
        bytes32 webhookSecret,
        bytes memory payload,
        uint256 timestamp,
        bytes32 signature,
        uint256 maxAge,
        uint256 currentTime
    ) internal pure returns (bool) {
        // Check timestamp freshness
        if (currentTime > timestamp + maxAge) return false;

        bytes32 expectedSig = createWebhookSignature(webhookSecret, payload, timestamp);
        return signature == expectedSig;
    }

    // ============ PAGINATION ============

    /**
     * @notice Calculate pagination offset
     * @param page Page number (1-indexed)
     * @param pageSize Items per page
     * @return Offset for data retrieval
     */
    function getPaginationOffset(uint256 page, uint256 pageSize) internal pure returns (uint256) {
        if (page == 0) page = 1;
        return (page - 1) * pageSize;
    }

    /**
     * @notice Calculate total pages
     * @param totalItems Total number of items
     * @param pageSize Items per page
     * @return Total number of pages
     */
    function getTotalPages(uint256 totalItems, uint256 pageSize) internal pure returns (uint256) {
        if (pageSize == 0) return 0;
        return (totalItems + pageSize - 1) / pageSize;
    }

    /**
     * @notice Create pagination metadata JSON
     * @param page Current page
     * @param pageSize Items per page
     * @param totalItems Total items
     * @return JSON pagination object
     */
    function paginationMeta(uint256 page, uint256 pageSize, uint256 totalItems) internal pure returns (string memory) {
        uint256 totalPages = getTotalPages(totalItems, pageSize);

        string[] memory pairs = new string[](4);
        pairs[0] = jsonPair("page", jsonNumber(page));
        pairs[1] = jsonPair("pageSize", jsonNumber(pageSize));
        pairs[2] = jsonPair("totalItems", jsonNumber(totalItems));
        pairs[3] = jsonPair("totalPages", jsonNumber(totalPages));

        return jsonObject(pairs);
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Recover signer from signature
     */
    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) v += 27;

        return ecrecover(hash, v, r, s);
    }

    /**
     * @notice Convert uint256 to string
     */
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @notice Convert address to string
     */
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            result[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i) + 4)) & 0xf];
            result[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i))) & 0xf];
        }

        return string(result);
    }

    /**
     * @notice Convert bytes32 to hex string
     */
    function _bytes32ToHex(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(64);

        for (uint256 i = 0; i < 32; i++) {
            result[i * 2] = alphabet[uint8(data[i] >> 4)];
            result[i * 2 + 1] = alphabet[uint8(data[i] & 0x0f)];
        }

        return string(result);
    }
}
