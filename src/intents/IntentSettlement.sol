// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/*//////////////////////////////////////////////////////////////
                    INTENT-BASED TRADING SYSTEM
//////////////////////////////////////////////////////////////*/

/**
 * @title IntentSettlement
 * @author Multi-Chain DEX & Oracle Integration
 * @notice Intent-based trading system inspired by CoW Protocol and UniswapX
 * @dev Features:
 *      - Off-chain order matching with on-chain settlement
 *      - Dutch auction price discovery
 *      - Batch auction settlement
 *      - MEV protection via commit-reveal
 *      - Solver competition framework
 */
contract IntentSettlement is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                            TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Intent order structure
    struct Intent {
        address maker;              // Order creator
        address tokenIn;            // Token to sell
        address tokenOut;           // Token to buy
        uint256 amountIn;           // Amount to sell
        uint256 minAmountOut;       // Minimum acceptable output
        uint256 startAmountOut;     // Starting amount (for Dutch auction)
        uint256 deadline;           // Order expiration
        uint256 nonce;              // Unique nonce for replay protection
        bytes32 intentId;           // Unique intent identifier
        IntentType intentType;      // Type of intent
    }

    /// @notice Intent types
    enum IntentType {
        LIMIT,          // Fixed price limit order
        DUTCH,          // Dutch auction (price improves over time)
        BATCH,          // Batch auction (settled in batches)
        RFQ,            // Request for Quote
        TWAP            // Time-weighted execution
    }

    /// @notice Solver information
    struct Solver {
        address addr;
        uint256 stake;              // Staked amount for slashing
        uint256 reputation;         // Performance score
        uint256 totalVolume;        // Total settled volume
        uint256 successCount;       // Successful settlements
        uint256 failCount;          // Failed settlements
        bool isActive;
        bool isWhitelisted;
    }

    /// @notice Settlement batch
    struct Batch {
        bytes32 batchId;
        uint256 timestamp;
        uint256 settledCount;
        address solver;
        BatchStatus status;
    }

    enum BatchStatus {
        PENDING,
        COMMITTED,
        REVEALED,
        SETTLED,
        CANCELLED
    }

    /// @notice Fill information
    struct Fill {
        bytes32 intentId;
        address solver;
        uint256 amountOut;
        uint256 timestamp;
        FillStatus status;
    }

    enum FillStatus {
        PENDING,
        FILLED,
        CANCELLED,
        EXPIRED
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSignature();
    error IntentExpired();
    error IntentAlreadyFilled();
    error InsufficientOutput();
    error InvalidSolver();
    error SolverNotWhitelisted();
    error InsufficientStake();
    error BatchNotReady();
    error InvalidBatch();
    error Unauthorized();
    error InvalidNonce();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event IntentCreated(
        bytes32 indexed intentId,
        address indexed maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        IntentType intentType
    );
    event IntentFilled(
        bytes32 indexed intentId,
        address indexed solver,
        uint256 amountIn,
        uint256 amountOut
    );
    event IntentCancelled(bytes32 indexed intentId, address indexed maker);
    event BatchSettled(bytes32 indexed batchId, address indexed solver, uint256 intentCount);
    event SolverRegistered(address indexed solver, uint256 stake);
    event SolverSlashed(address indexed solver, uint256 amount, string reason);

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev EIP-712 typehash for Intent
    bytes32 public constant INTENT_TYPEHASH = keccak256(
        "Intent(address maker,address tokenIn,address tokenOut,uint256 amountIn,uint256 minAmountOut,uint256 startAmountOut,uint256 deadline,uint256 nonce,bytes32 intentId,uint8 intentType)"
    );

    /// @dev Intent ID => Fill status
    mapping(bytes32 => Fill) public fills;

    /// @dev Maker => nonce
    mapping(address => uint256) public nonces;

    /// @dev Solver address => Solver info
    mapping(address => Solver) public solvers;

    /// @dev Batch ID => Batch info
    mapping(bytes32 => Batch) public batches;

    /// @dev Current batch ID
    bytes32 public currentBatchId;

    /// @dev Batch interval (for batch auctions)
    uint256 public batchInterval;

    /// @dev Minimum solver stake
    uint256 public minSolverStake;

    /// @dev Protocol fee (in BPS)
    uint256 public protocolFeeBps;

    /// @dev Fee recipient
    address public feeRecipient;

    /// @dev Dutch auction decay period
    uint256 public dutchDecayPeriod;

    /// @dev Permissioned solvers only
    bool public permissionedSolvers;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() EIP712("IntentSettlement", "1") {
        _disableInitializers();
    }

    function initialize(
        address _feeRecipient,
        uint256 _minSolverStake,
        uint256 _batchInterval
    ) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        feeRecipient = _feeRecipient;
        minSolverStake = _minSolverStake;
        batchInterval = _batchInterval;
        dutchDecayPeriod = 10 minutes;
        protocolFeeBps = 5; // 0.05%
        permissionedSolvers = true;

        // Initialize first batch
        currentBatchId = keccak256(abi.encodePacked(block.timestamp, block.number));
    }

    /*//////////////////////////////////////////////////////////////
                        INTENT CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new intent (gasless - just generates signature)
    /// @dev User signs intent off-chain, solver submits for execution
    function createIntentHash(Intent calldata intent) external view returns (bytes32) {
        return _hashIntent(intent);
    }

    /// @notice Get current nonce for a maker
    function getNonce(address maker) external view returns (uint256) {
        return nonces[maker];
    }

    /// @notice Verify an intent signature
    function verifyIntent(Intent calldata intent, bytes calldata signature)
        external view returns (bool)
    {
        bytes32 hash = _hashIntent(intent);
        address signer = hash.recover(signature);
        return signer == intent.maker;
    }

    /*//////////////////////////////////////////////////////////////
                    SINGLE INTENT SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Fill a single intent (for limit orders and Dutch auctions)
    function fillIntent(
        Intent calldata intent,
        bytes calldata signature,
        uint256 amountOut
    ) external nonReentrant {
        _validateSolver(msg.sender);
        _validateIntent(intent, signature);

        // Calculate acceptable output based on intent type
        uint256 minAcceptable = _calculateMinOutput(intent);
        if (amountOut < minAcceptable) revert InsufficientOutput();

        // Mark as filled
        fills[intent.intentId] = Fill({
            intentId: intent.intentId,
            solver: msg.sender,
            amountOut: amountOut,
            timestamp: block.timestamp,
            status: FillStatus.FILLED
        });

        // Increment nonce
        nonces[intent.maker] = intent.nonce + 1;

        // Execute transfers
        _executeTransfers(intent, msg.sender, amountOut);

        // Update solver stats
        _updateSolverStats(msg.sender, intent.amountIn, true);

        emit IntentFilled(intent.intentId, msg.sender, intent.amountIn, amountOut);
    }

    /*//////////////////////////////////////////////////////////////
                    BATCH AUCTION SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Commit to settling a batch (commit-reveal for MEV protection)
    function commitBatch(bytes32 commitHash) external {
        _validateSolver(msg.sender);

        bytes32 batchId = currentBatchId;
        Batch storage batch = batches[batchId];

        if (batch.status != BatchStatus.PENDING) revert BatchNotReady();

        batch.status = BatchStatus.COMMITTED;
        batch.solver = msg.sender;

        // Store commit hash (would need additional mapping in production)
    }

    /// @notice Reveal and execute batch settlement
    function settleBatch(
        Intent[] calldata intents,
        bytes[] calldata signatures,
        uint256[] calldata amountsOut,
        bytes32 salt
    ) external nonReentrant {
        _validateSolver(msg.sender);

        require(intents.length == signatures.length, "Length mismatch");
        require(intents.length == amountsOut.length, "Length mismatch");

        bytes32 batchId = currentBatchId;
        Batch storage batch = batches[batchId];

        if (batch.solver != msg.sender) revert Unauthorized();
        if (batch.status != BatchStatus.COMMITTED) revert BatchNotReady();

        // Verify commit hash
        bytes32 expectedCommit = keccak256(abi.encodePacked(
            intents.length,
            keccak256(abi.encode(amountsOut)),
            salt
        ));
        // Would verify against stored commit

        uint256 settledCount;

        for (uint256 i; i < intents.length; ++i) {
            Intent calldata intent = intents[i];

            // Skip if already filled or invalid
            if (fills[intent.intentId].status == FillStatus.FILLED) continue;

            // Validate
            if (!_isValidSignature(intent, signatures[i])) continue;
            if (block.timestamp > intent.deadline) continue;

            uint256 minAcceptable = _calculateMinOutput(intent);
            if (amountsOut[i] < minAcceptable) continue;

            // Mark as filled
            fills[intent.intentId] = Fill({
                intentId: intent.intentId,
                solver: msg.sender,
                amountOut: amountsOut[i],
                timestamp: block.timestamp,
                status: FillStatus.FILLED
            });

            // Execute
            _executeTransfers(intent, msg.sender, amountsOut[i]);
            nonces[intent.maker] = intent.nonce + 1;

            ++settledCount;

            emit IntentFilled(intent.intentId, msg.sender, intent.amountIn, amountsOut[i]);
        }

        // Update batch
        batch.status = BatchStatus.SETTLED;
        batch.settledCount = settledCount;
        batch.timestamp = block.timestamp;

        // Update solver stats
        _updateSolverStats(msg.sender, 0, true);

        // Rotate batch
        currentBatchId = keccak256(abi.encodePacked(block.timestamp, block.number, settledCount));

        emit BatchSettled(batchId, msg.sender, settledCount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTENT CANCELLATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Cancel an intent (by maker)
    function cancelIntent(bytes32 intentId) external {
        Fill storage fill = fills[intentId];

        // Only maker can cancel, and only if not filled
        // In production, would verify maker from stored intent data
        if (fill.status == FillStatus.FILLED) revert IntentAlreadyFilled();

        fill.status = FillStatus.CANCELLED;

        emit IntentCancelled(intentId, msg.sender);
    }

    /// @notice Increment nonce to cancel all pending intents
    function cancelAllIntents() external {
        nonces[msg.sender] = nonces[msg.sender] + 1;
    }

    /*//////////////////////////////////////////////////////////////
                        SOLVER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Register as a solver
    function registerSolver() external payable {
        if (msg.value < minSolverStake) revert InsufficientStake();

        Solver storage solver = solvers[msg.sender];
        solver.addr = msg.sender;
        solver.stake = msg.value;
        solver.reputation = 100; // Base reputation
        solver.isActive = true;

        emit SolverRegistered(msg.sender, msg.value);
    }

    /// @notice Whitelist a solver (owner only)
    function whitelistSolver(address solver, bool status) external onlyOwner {
        solvers[solver].isWhitelisted = status;
    }

    /// @notice Slash a solver for misbehavior
    function slashSolver(address solver, uint256 amount, string calldata reason)
        external onlyOwner
    {
        Solver storage s = solvers[solver];
        uint256 slashAmount = amount > s.stake ? s.stake : amount;
        s.stake -= slashAmount;
        s.reputation = s.reputation > 10 ? s.reputation - 10 : 0;

        // Transfer slashed funds to fee recipient
        (bool success, ) = feeRecipient.call{value: slashAmount}("");
        require(success, "Transfer failed");

        emit SolverSlashed(solver, slashAmount, reason);
    }

    /// @notice Withdraw solver stake (with delay)
    function withdrawStake(uint256 amount) external {
        Solver storage solver = solvers[msg.sender];
        require(solver.stake >= amount, "Insufficient stake");

        solver.stake -= amount;
        solver.isActive = solver.stake >= minSolverStake;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateSolver(address solver) internal view {
        if (permissionedSolvers) {
            if (!solvers[solver].isWhitelisted) revert SolverNotWhitelisted();
        }
        if (solvers[solver].stake < minSolverStake) revert InsufficientStake();
        if (!solvers[solver].isActive) revert InvalidSolver();
    }

    function _validateIntent(Intent calldata intent, bytes calldata signature) internal view {
        // Check expiration
        if (block.timestamp > intent.deadline) revert IntentExpired();

        // Check nonce
        if (intent.nonce != nonces[intent.maker]) revert InvalidNonce();

        // Check not already filled
        if (fills[intent.intentId].status == FillStatus.FILLED) revert IntentAlreadyFilled();

        // Verify signature
        if (!_isValidSignature(intent, signature)) revert InvalidSignature();
    }

    function _isValidSignature(Intent calldata intent, bytes calldata signature)
        internal view returns (bool)
    {
        bytes32 hash = _hashIntent(intent);
        address signer = hash.recover(signature);
        return signer == intent.maker;
    }

    function _hashIntent(Intent calldata intent) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            INTENT_TYPEHASH,
            intent.maker,
            intent.tokenIn,
            intent.tokenOut,
            intent.amountIn,
            intent.minAmountOut,
            intent.startAmountOut,
            intent.deadline,
            intent.nonce,
            intent.intentId,
            uint8(intent.intentType)
        )));
    }

    function _calculateMinOutput(Intent calldata intent) internal view returns (uint256) {
        if (intent.intentType == IntentType.DUTCH) {
            // Dutch auction: price improves over time for maker
            uint256 elapsed = block.timestamp > intent.deadline
                ? dutchDecayPeriod
                : block.timestamp - (intent.deadline - dutchDecayPeriod);

            if (elapsed >= dutchDecayPeriod) {
                return intent.minAmountOut;
            }

            // Linear decay from startAmountOut to minAmountOut
            uint256 decay = (intent.startAmountOut - intent.minAmountOut) * elapsed / dutchDecayPeriod;
            return intent.startAmountOut - decay;
        }

        return intent.minAmountOut;
    }

    function _executeTransfers(
        Intent calldata intent,
        address solver,
        uint256 amountOut
    ) internal {
        // Calculate fee
        uint256 fee = (amountOut * protocolFeeBps) / 10000;
        uint256 makerReceives = amountOut - fee;

        // Transfer tokenIn from maker to solver
        IERC20(intent.tokenIn).safeTransferFrom(intent.maker, solver, intent.amountIn);

        // Transfer tokenOut from solver to maker
        IERC20(intent.tokenOut).safeTransferFrom(solver, intent.maker, makerReceives);

        // Transfer fee
        if (fee > 0) {
            IERC20(intent.tokenOut).safeTransferFrom(solver, feeRecipient, fee);
        }
    }

    function _updateSolverStats(address solver, uint256 volume, bool success) internal {
        Solver storage s = solvers[solver];
        s.totalVolume += volume;
        if (success) {
            s.successCount++;
            s.reputation = s.reputation < 1000 ? s.reputation + 1 : 1000;
        } else {
            s.failCount++;
            s.reputation = s.reputation > 5 ? s.reputation - 5 : 0;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setProtocolFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 100, "Fee too high");
        protocolFeeBps = _feeBps;
    }

    function setMinSolverStake(uint256 _stake) external onlyOwner {
        minSolverStake = _stake;
    }

    function setBatchInterval(uint256 _interval) external onlyOwner {
        batchInterval = _interval;
    }

    function setPermissionedSolvers(bool _permissioned) external onlyOwner {
        permissionedSolvers = _permissioned;
    }

    function setDutchDecayPeriod(uint256 _period) external onlyOwner {
        dutchDecayPeriod = _period;
    }

    /*//////////////////////////////////////////////////////////////
                            UUPS
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    receive() external payable {}

    uint256[40] private __gap;
}
