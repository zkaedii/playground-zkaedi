// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title RandomnessLib
/// @notice Secure on-chain randomness utilities with multiple generation methods
/// @dev Implements commit-reveal, VRF integration, and verifiable random functions
/// @author playground-zkaedi
library RandomnessLib {
    // ============ Custom Errors ============
    error InvalidCommitment();
    error CommitmentNotFound();
    error CommitmentExpired();
    error CommitmentAlreadyRevealed();
    error RevealTooEarly();
    error RevealTooLate();
    error InvalidReveal();
    error InvalidProof();
    error RequestNotFound();
    error RequestAlreadyFulfilled();
    error InsufficientEntropy();
    error InvalidRange();
    error InvalidSeed();
    error BatchSizeTooLarge();
    error VRFNotConfigured();
    error CallbackFailed();

    // ============ Constants ============
    uint256 internal constant MAX_BATCH_SIZE = 100;
    uint256 internal constant MIN_REVEAL_DELAY = 1; // Minimum 1 block
    uint256 internal constant MAX_REVEAL_DELAY = 256; // Maximum 256 blocks (blockhash limit)
    uint256 internal constant DEFAULT_REVEAL_WINDOW = 50; // 50 blocks to reveal

    // ============ Enums ============
    enum RandomnessSource {
        CommitReveal,        // Two-phase commitment scheme
        BlockHash,           // Blockhash-based (limited security)
        VRF,                 // Chainlink VRF or similar
        RANDAO,              // Post-merge beacon randomness
        Hybrid               // Combination of sources
    }

    enum RequestStatus {
        Pending,
        Committed,
        Revealed,
        Fulfilled,
        Expired,
        Cancelled
    }

    // ============ Structs ============

    /// @notice Commit-reveal commitment
    struct Commitment {
        bytes32 commitHash;       // keccak256(secret, address, nonce)
        address committer;
        uint256 commitBlock;      // Block when committed
        uint256 revealDeadline;   // Block number deadline
        uint256 revealedValue;    // Revealed random value
        RequestStatus status;
    }

    /// @notice VRF request configuration
    struct VRFConfig {
        address coordinator;      // VRF coordinator address
        bytes32 keyHash;          // VRF key hash
        uint64 subscriptionId;    // Subscription ID
        uint32 callbackGasLimit;  // Gas limit for callback
        uint16 requestConfirmations; // Block confirmations
        uint32 numWords;          // Number of random words
        bool initialized;
    }

    /// @notice VRF request tracking
    struct VRFRequest {
        uint256 requestId;
        address requester;
        uint256 requestBlock;
        uint256[] randomWords;
        RequestStatus status;
        bytes32 callbackData;     // Optional callback data
    }

    /// @notice Randomness request
    struct RandomRequest {
        bytes32 requestId;
        address requester;
        uint256 seed;
        uint256 minBlock;         // Earliest block for fulfillment
        uint256 maxBlock;         // Latest block for fulfillment
        uint256 result;
        RandomnessSource source;
        RequestStatus status;
    }

    /// @notice Entropy accumulator for hybrid randomness
    struct EntropyAccumulator {
        bytes32 accumulatedEntropy;
        uint256 contributorCount;
        uint256 lastUpdate;
        mapping(address => bytes32) contributions;
        address[] contributors;
        bool finalized;
    }

    /// @notice Commit-reveal manager
    struct CommitRevealManager {
        mapping(bytes32 => Commitment) commitments;
        mapping(address => bytes32[]) userCommitments;
        uint256 totalCommitments;
        uint256 revealWindow;     // Blocks allowed for reveal
        bool initialized;
    }

    // ============ Commit-Reveal Functions ============

    /// @notice Initialize commit-reveal manager
    function initializeCommitReveal(
        CommitRevealManager storage manager,
        uint256 revealWindow
    ) internal {
        if (revealWindow == 0) revealWindow = DEFAULT_REVEAL_WINDOW;
        if (revealWindow > MAX_REVEAL_DELAY) revealWindow = MAX_REVEAL_DELAY;

        manager.revealWindow = revealWindow;
        manager.totalCommitments = 0;
        manager.initialized = true;
    }

    /// @notice Create commitment hash
    /// @param secret The secret value
    /// @param sender The committer address
    /// @param nonce A unique nonce
    function createCommitmentHash(
        bytes32 secret,
        address sender,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(secret, sender, nonce));
    }

    /// @notice Submit a commitment
    function commit(
        CommitRevealManager storage manager,
        bytes32 commitHash,
        address committer
    ) internal returns (bytes32 commitmentId) {
        if (!manager.initialized) revert InvalidCommitment();
        if (commitHash == bytes32(0)) revert InvalidCommitment();

        commitmentId = keccak256(abi.encodePacked(
            commitHash,
            committer,
            block.number,
            manager.totalCommitments
        ));

        manager.commitments[commitmentId] = Commitment({
            commitHash: commitHash,
            committer: committer,
            commitBlock: block.number,
            revealDeadline: block.number + manager.revealWindow,
            revealedValue: 0,
            status: RequestStatus.Committed
        });

        manager.userCommitments[committer].push(commitmentId);
        manager.totalCommitments++;

        return commitmentId;
    }

    /// @notice Reveal a commitment
    function reveal(
        CommitRevealManager storage manager,
        bytes32 commitmentId,
        bytes32 secret,
        uint256 nonce
    ) internal returns (uint256 randomValue) {
        Commitment storage c = manager.commitments[commitmentId];

        if (c.commitHash == bytes32(0)) revert CommitmentNotFound();
        if (c.status != RequestStatus.Committed) revert CommitmentAlreadyRevealed();
        if (block.number <= c.commitBlock) revert RevealTooEarly();
        if (block.number > c.revealDeadline) revert CommitmentExpired();

        // Verify the reveal
        bytes32 expectedHash = createCommitmentHash(secret, c.committer, nonce);
        if (expectedHash != c.commitHash) revert InvalidReveal();

        // Generate random value combining secret and future blockhash
        bytes32 blockEntropy = blockhash(c.commitBlock + 1);
        if (blockEntropy == bytes32(0)) {
            // Fallback if blockhash not available
            blockEntropy = keccak256(abi.encodePacked(block.prevrandao, block.timestamp));
        }

        randomValue = uint256(keccak256(abi.encodePacked(secret, blockEntropy, commitmentId)));

        c.revealedValue = randomValue;
        c.status = RequestStatus.Revealed;

        return randomValue;
    }

    /// @notice Get commitment info
    function getCommitment(
        CommitRevealManager storage manager,
        bytes32 commitmentId
    ) internal view returns (Commitment memory) {
        return manager.commitments[commitmentId];
    }

    /// @notice Check if commitment can be revealed
    function canReveal(
        CommitRevealManager storage manager,
        bytes32 commitmentId
    ) internal view returns (bool, string memory reason) {
        Commitment storage c = manager.commitments[commitmentId];

        if (c.commitHash == bytes32(0)) return (false, "Not found");
        if (c.status != RequestStatus.Committed) return (false, "Already revealed");
        if (block.number <= c.commitBlock) return (false, "Too early");
        if (block.number > c.revealDeadline) return (false, "Expired");

        return (true, "");
    }

    // ============ VRF Integration Functions ============

    /// @notice Initialize VRF configuration
    function initializeVRF(
        VRFConfig storage config,
        address coordinator,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) internal {
        if (coordinator == address(0)) revert VRFNotConfigured();

        config.coordinator = coordinator;
        config.keyHash = keyHash;
        config.subscriptionId = subscriptionId;
        config.callbackGasLimit = callbackGasLimit;
        config.requestConfirmations = requestConfirmations;
        config.numWords = 1;
        config.initialized = true;
    }

    /// @notice Create VRF request data (to be sent to coordinator)
    function createVRFRequest(
        VRFConfig storage config
    ) internal view returns (bytes memory requestData) {
        if (!config.initialized) revert VRFNotConfigured();

        return abi.encode(
            config.keyHash,
            config.subscriptionId,
            config.requestConfirmations,
            config.callbackGasLimit,
            config.numWords
        );
    }

    /// @notice Process VRF fulfillment
    function fulfillVRF(
        VRFRequest storage request,
        uint256[] memory randomWords
    ) internal returns (uint256 primaryRandom) {
        if (request.status == RequestStatus.Fulfilled) revert RequestAlreadyFulfilled();
        if (randomWords.length == 0) revert InsufficientEntropy();

        request.randomWords = randomWords;
        request.status = RequestStatus.Fulfilled;

        return randomWords[0];
    }

    // ============ Blockhash-Based Randomness ============

    /// @notice Generate random number from future blockhash
    /// @dev Less secure, use only for low-stakes applications
    function generateFromBlockhash(
        uint256 seed,
        uint256 targetBlock
    ) internal view returns (uint256, bool valid) {
        if (block.number <= targetBlock) {
            return (0, false); // Block not yet mined
        }

        if (block.number > targetBlock + 256) {
            return (0, false); // Blockhash no longer available
        }

        bytes32 blockHash = blockhash(targetBlock);
        if (blockHash == bytes32(0)) {
            return (0, false);
        }

        uint256 random = uint256(keccak256(abi.encodePacked(blockHash, seed)));
        return (random, true);
    }

    /// @notice Get RANDAO value (post-merge)
    function getRANDAO() internal view returns (uint256) {
        return block.prevrandao;
    }

    /// @notice Generate random using RANDAO with additional entropy
    function generateFromRANDAO(
        uint256 seed,
        bytes32 additionalEntropy
    ) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            seed,
            additionalEntropy,
            block.timestamp,
            msg.sender
        )));
    }

    // ============ Entropy Accumulator Functions ============

    /// @notice Initialize entropy accumulator
    function initializeEntropy(EntropyAccumulator storage acc) internal {
        acc.accumulatedEntropy = bytes32(0);
        acc.contributorCount = 0;
        acc.lastUpdate = block.timestamp;
        acc.finalized = false;
    }

    /// @notice Contribute entropy to accumulator
    function contributeEntropy(
        EntropyAccumulator storage acc,
        address contributor,
        bytes32 entropy
    ) internal returns (bytes32 newEntropy) {
        if (acc.finalized) revert InsufficientEntropy();
        if (entropy == bytes32(0)) revert InvalidSeed();

        // Check if already contributed
        if (acc.contributions[contributor] != bytes32(0)) {
            // Update existing contribution
            acc.accumulatedEntropy = keccak256(abi.encodePacked(
                acc.accumulatedEntropy,
                entropy,
                block.timestamp
            ));
        } else {
            // New contributor
            acc.contributions[contributor] = entropy;
            acc.contributors.push(contributor);
            acc.contributorCount++;

            acc.accumulatedEntropy = keccak256(abi.encodePacked(
                acc.accumulatedEntropy,
                entropy,
                contributor,
                acc.contributorCount
            ));
        }

        acc.lastUpdate = block.timestamp;
        return acc.accumulatedEntropy;
    }

    /// @notice Finalize entropy and get random value
    function finalizeEntropy(
        EntropyAccumulator storage acc,
        uint256 minContributors
    ) internal returns (uint256 randomValue) {
        if (acc.contributorCount < minContributors) revert InsufficientEntropy();
        if (acc.finalized) revert InsufficientEntropy();

        // Add final blockchain entropy
        bytes32 finalEntropy = keccak256(abi.encodePacked(
            acc.accumulatedEntropy,
            block.prevrandao,
            block.timestamp,
            blockhash(block.number - 1)
        ));

        acc.accumulatedEntropy = finalEntropy;
        acc.finalized = true;

        return uint256(finalEntropy);
    }

    // ============ Random Number Utilities ============

    /// @notice Generate random number in range [min, max]
    function randomInRange(
        uint256 randomValue,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (min >= max) revert InvalidRange();
        return min + (randomValue % (max - min + 1));
    }

    /// @notice Generate random number in range [0, max)
    function randomBelow(uint256 randomValue, uint256 max) internal pure returns (uint256) {
        if (max == 0) revert InvalidRange();
        return randomValue % max;
    }

    /// @notice Generate random boolean
    function randomBool(uint256 randomValue) internal pure returns (bool) {
        return randomValue % 2 == 0;
    }

    /// @notice Generate random boolean with custom probability (in BPS)
    function randomBoolWithProbability(
        uint256 randomValue,
        uint256 probabilityBps
    ) internal pure returns (bool) {
        return (randomValue % 10000) < probabilityBps;
    }

    /// @notice Generate array of random numbers
    function randomBatch(
        uint256 seed,
        uint256 count,
        uint256 max
    ) internal pure returns (uint256[] memory) {
        if (count > MAX_BATCH_SIZE) revert BatchSizeTooLarge();
        if (max == 0) revert InvalidRange();

        uint256[] memory randoms = new uint256[](count);
        bytes32 currentSeed = bytes32(seed);

        for (uint256 i = 0; i < count; i++) {
            currentSeed = keccak256(abi.encodePacked(currentSeed, i));
            randoms[i] = uint256(currentSeed) % max;
        }

        return randoms;
    }

    /// @notice Fisher-Yates shuffle for array indices
    /// @param seed Random seed for shuffling
    /// @param length Number of indices to generate (must be > 0 and <= MAX_BATCH_SIZE)
    /// @return indices Shuffled array of indices [0, length)
    function shuffleIndices(
        uint256 seed,
        uint256 length
    ) internal pure returns (uint256[] memory) {
        if (length == 0) revert InvalidRange();
        if (length > MAX_BATCH_SIZE) revert BatchSizeTooLarge();

        uint256[] memory indices = new uint256[](length);

        // Initialize
        for (uint256 i = 0; i < length; i++) {
            indices[i] = i;
        }

        // Shuffle (only needed if length > 1)
        if (length > 1) {
            bytes32 currentSeed = bytes32(seed);
            for (uint256 i = length - 1; i > 0; i--) {
                currentSeed = keccak256(abi.encodePacked(currentSeed, i));
                uint256 j = uint256(currentSeed) % (i + 1);

                // Swap
                (indices[i], indices[j]) = (indices[j], indices[i]);
            }
        }

        return indices;
    }

    /// @notice Select random subset (k items from n)
    /// @param seed Random seed for selection
    /// @param n Total number of items to select from (must be > 0)
    /// @param k Number of items to select (must be > 0 and <= n)
    /// @return selected Array of k randomly selected indices from [0, n)
    function randomSubset(
        uint256 seed,
        uint256 n,
        uint256 k
    ) internal pure returns (uint256[] memory) {
        if (n == 0) revert InvalidRange();
        if (k == 0) revert InvalidRange();
        if (k > n) revert InvalidRange();
        if (k > MAX_BATCH_SIZE) revert BatchSizeTooLarge();

        uint256[] memory selected = new uint256[](k);
        uint256[] memory shuffled = shuffleIndices(seed, n);

        for (uint256 i = 0; i < k; i++) {
            selected[i] = shuffled[i];
        }

        return selected;
    }

    /// @notice Weighted random selection
    function weightedRandom(
        uint256 randomValue,
        uint256[] memory weights
    ) internal pure returns (uint256 selectedIndex) {
        if (weights.length == 0) revert InvalidRange();

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }

        if (totalWeight == 0) revert InvalidRange();

        uint256 target = randomValue % totalWeight;
        uint256 cumulative = 0;

        for (uint256 i = 0; i < weights.length; i++) {
            cumulative += weights[i];
            if (target < cumulative) {
                return i;
            }
        }

        return weights.length - 1;
    }

    // ============ Verification Functions ============

    /// @notice Verify randomness was generated correctly (for commit-reveal)
    function verifyCommitReveal(
        bytes32 commitHash,
        bytes32 secret,
        address committer,
        uint256 nonce
    ) internal pure returns (bool) {
        return commitHash == createCommitmentHash(secret, committer, nonce);
    }

    /// @notice Generate verifiable random seed from multiple inputs
    function generateVerifiableSeed(
        bytes32[] memory inputs
    ) internal view returns (bytes32) {
        bytes memory packed = abi.encodePacked(block.prevrandao, block.timestamp);

        for (uint256 i = 0; i < inputs.length; i++) {
            packed = abi.encodePacked(packed, inputs[i]);
        }

        return keccak256(packed);
    }

    // ============ Request Management ============

    /// @notice Create random request
    function createRequest(
        RandomRequest storage request,
        address requester,
        uint256 seed,
        uint256 delayBlocks,
        RandomnessSource source
    ) internal returns (bytes32 requestId) {
        if (delayBlocks < MIN_REVEAL_DELAY) delayBlocks = MIN_REVEAL_DELAY;
        if (delayBlocks > MAX_REVEAL_DELAY) delayBlocks = MAX_REVEAL_DELAY;

        requestId = keccak256(abi.encodePacked(
            requester,
            seed,
            block.number,
            block.timestamp
        ));

        request.requestId = requestId;
        request.requester = requester;
        request.seed = seed;
        request.minBlock = block.number + delayBlocks;
        request.maxBlock = block.number + delayBlocks + DEFAULT_REVEAL_WINDOW;
        request.source = source;
        request.status = RequestStatus.Pending;

        return requestId;
    }

    /// @notice Fulfill random request
    function fulfillRequest(
        RandomRequest storage request
    ) internal returns (uint256 randomValue) {
        if (request.status == RequestStatus.Fulfilled) revert RequestAlreadyFulfilled();
        if (block.number < request.minBlock) revert RevealTooEarly();
        if (block.number > request.maxBlock) revert RevealTooLate();

        bytes32 blockEntropy = blockhash(request.minBlock);
        if (blockEntropy == bytes32(0)) {
            blockEntropy = bytes32(block.prevrandao);
        }

        randomValue = uint256(keccak256(abi.encodePacked(
            request.seed,
            blockEntropy,
            request.requestId
        )));

        request.result = randomValue;
        request.status = RequestStatus.Fulfilled;

        return randomValue;
    }

    /// @notice Check if request can be fulfilled
    function canFulfill(RandomRequest storage request) internal view returns (bool) {
        return request.status == RequestStatus.Pending &&
               block.number >= request.minBlock &&
               block.number <= request.maxBlock;
    }
}
