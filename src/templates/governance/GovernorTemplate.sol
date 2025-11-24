// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GovernorTemplate
 * @notice Production-ready on-chain governance template
 * @dev Implements proposal creation, voting, timelock integration, and execution
 *
 * TEMPLATE INSTRUCTIONS:
 * 1. Search and replace "GovernorTemplate" with your governance name
 * 2. Configure voting token address
 * 3. Set quorum, proposal threshold, and voting period
 * 4. Configure timelock delay
 * 5. Customize voting strategies as needed
 */

import {AccessControlLib} from "../utils/AccessControlLib.sol";

interface IVotes {
    function getVotes(address account) external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
    function delegates(address account) external view returns (address);
    function delegate(address delegatee) external;
}

contract GovernorTemplate {
    // ============ CONSTANTS ============
    uint256 public constant VOTING_DELAY = 1 days;       // Time before voting starts
    uint256 public constant VOTING_PERIOD = 7 days;      // Duration of voting
    uint256 public constant TIMELOCK_DELAY = 2 days;     // Delay before execution
    uint256 public constant QUORUM_PERCENTAGE = 400;     // 4% of total supply (in basis points)
    uint256 public constant PROPOSAL_THRESHOLD = 100000e18; // Tokens needed to propose
    uint256 public constant MAX_OPERATIONS = 10;         // Max operations per proposal

    // Vote types
    uint8 public constant VOTE_AGAINST = 0;
    uint8 public constant VOTE_FOR = 1;
    uint8 public constant VOTE_ABSTAIN = 2;

    // ============ ERRORS ============
    error ZeroAddress();
    error ProposalNotFound(uint256 proposalId);
    error ProposalAlreadyExists(uint256 proposalId);
    error InvalidProposalState(ProposalState current, ProposalState required);
    error BelowProposalThreshold(uint256 votes, uint256 threshold);
    error VotingClosed(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error InvalidVoteType(uint8 voteType);
    error EmptyProposal();
    error TooManyOperations(uint256 count);
    error ArrayLengthMismatch();
    error TimelockNotReady(uint256 proposalId);
    error ProposalNotSucceeded(uint256 proposalId);
    error ExecutionFailed(uint256 index);
    error ProposerNotWhitelisted(address proposer);
    error InvalidSignature();
    error SignatureExpired();

    // ============ TYPES ============
    enum ProposalState {
        Pending,    // Created but voting not started
        Active,     // Voting in progress
        Canceled,   // Canceled by proposer or guardian
        Defeated,   // Did not reach quorum or majority
        Succeeded,  // Passed voting
        Queued,     // In timelock
        Expired,    // Timelock expired without execution
        Executed    // Successfully executed
    }

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 eta;              // Execution time (after timelock)
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        mapping(address => Receipt) receipts;
    }

    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint256 votes;
    }

    struct ProposalCore {
        uint256 id;
        address proposer;
        uint256 eta;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
    }

    // ============ STATE ============
    IVotes public immutable token;
    string public name;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) internal proposals;
    mapping(address => uint256) public latestProposalIds;

    // Whitelist for proposers (optional)
    bool public proposerWhitelistEnabled;
    mapping(address => bool) public isProposerWhitelisted;

    // Guardian can cancel proposals
    address public guardian;

    AccessControlLib.AccessControlStorage internal _accessControl;

    // ============ EVENTS ============
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startTime,
        uint256 endTime,
        string description
    );
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);
    event ProposerWhitelistToggled(bool enabled);
    event ProposerWhitelisted(address indexed account, bool whitelisted);

    // ============ CONSTRUCTOR ============
    constructor(
        address _token,
        address admin,
        string memory _name
    ) {
        if (_token == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        token = IVotes(_token);
        name = _name;
        guardian = admin;

        // Initialize access control
        AccessControlLib.initializeStandardRoles(_accessControl, admin);
    }

    // ============ PROPOSAL FUNCTIONS ============

    /**
     * @notice Create a new proposal
     * @param targets Target addresses for calls
     * @param values ETH values for calls
     * @param calldatas Call data for each call
     * @param description Human-readable description
     * @return proposalId The ID of the created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId) {
        // Validate arrays
        if (targets.length == 0) revert EmptyProposal();
        if (targets.length > MAX_OPERATIONS) revert TooManyOperations(targets.length);
        if (targets.length != values.length || targets.length != calldatas.length) {
            revert ArrayLengthMismatch();
        }

        // Check proposer whitelist
        if (proposerWhitelistEnabled && !isProposerWhitelisted[msg.sender]) {
            revert ProposerNotWhitelisted(msg.sender);
        }

        // Check proposal threshold
        uint256 proposerVotes = token.getVotes(msg.sender);
        if (proposerVotes < PROPOSAL_THRESHOLD) {
            revert BelowProposalThreshold(proposerVotes, PROPOSAL_THRESHOLD);
        }

        // Generate proposal ID
        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        Proposal storage proposal = proposals[proposalId];
        if (proposal.startTime != 0) revert ProposalAlreadyExists(proposalId);

        uint256 startTime = block.timestamp + VOTING_DELAY;
        uint256 endTime = startTime + VOTING_PERIOD;

        proposalCount++;
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.startTime = startTime;
        proposal.endTime = endTime;

        latestProposalIds[msg.sender] = proposalId;

        // Create empty signatures array for event
        string[] memory signatures = new string[](targets.length);

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startTime,
            endTime,
            description
        );
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId The proposal ID
     * @param support Vote type (0=against, 1=for, 2=abstain)
     * @return votes The number of votes cast
     */
    function castVote(
        uint256 proposalId,
        uint8 support
    ) external returns (uint256 votes) {
        return _castVote(msg.sender, proposalId, support, "");
    }

    /**
     * @notice Cast a vote with reason
     * @param proposalId The proposal ID
     * @param support Vote type
     * @param reason Reason for the vote
     * @return votes The number of votes cast
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external returns (uint256 votes) {
        return _castVote(msg.sender, proposalId, support, reason);
    }

    /**
     * @notice Queue a successful proposal for execution
     * @param targets Target addresses
     * @param values ETH values
     * @param calldatas Call data
     * @param descriptionHash Hash of the description
     * @return proposalId The queued proposal ID
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage proposal = proposals[proposalId];

        if (state(proposalId) != ProposalState.Succeeded) {
            revert ProposalNotSucceeded(proposalId);
        }

        uint256 eta = block.timestamp + TIMELOCK_DELAY;
        proposal.eta = eta;

        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @notice Execute a queued proposal
     * @param targets Target addresses
     * @param values ETH values
     * @param calldatas Call data
     * @param descriptionHash Hash of the description
     * @return proposalId The executed proposal ID
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage proposal = proposals[proposalId];

        ProposalState currentState = state(proposalId);
        if (currentState != ProposalState.Queued) {
            revert InvalidProposalState(currentState, ProposalState.Queued);
        }

        if (block.timestamp < proposal.eta) {
            revert TimelockNotReady(proposalId);
        }

        proposal.executed = true;

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) revert ExecutionFailed(i);
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal
     * @param targets Target addresses
     * @param values ETH values
     * @param calldatas Call data
     * @param descriptionHash Hash of the description
     * @return proposalId The canceled proposal ID
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage proposal = proposals[proposalId];

        // Only proposer or guardian can cancel
        require(
            msg.sender == proposal.proposer || msg.sender == guardian,
            "Not authorized to cancel"
        );

        ProposalState currentState = state(proposalId);
        require(
            currentState == ProposalState.Pending || currentState == ProposalState.Active,
            "Cannot cancel in current state"
        );

        proposal.canceled = true;

        emit ProposalCanceled(proposalId);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get the current state of a proposal
     * @param proposalId The proposal ID
     * @return The proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.startTime == 0) revert ProposalNotFound(proposalId);

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (block.timestamp < proposal.startTime) {
            return ProposalState.Pending;
        }

        if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        }

        // Voting ended - check results
        if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        }

        if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        }

        // In timelock
        if (block.timestamp < proposal.eta) {
            return ProposalState.Queued;
        }

        // Check if timelock expired (grace period of 14 days)
        if (block.timestamp > proposal.eta + 14 days) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /**
     * @notice Get proposal details
     * @param proposalId The proposal ID
     * @return core Core proposal data
     */
    function getProposal(uint256 proposalId) external view returns (ProposalCore memory core) {
        Proposal storage proposal = proposals[proposalId];
        return ProposalCore({
            id: proposal.id,
            proposer: proposal.proposer,
            eta: proposal.eta,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            forVotes: proposal.forVotes,
            againstVotes: proposal.againstVotes,
            abstainVotes: proposal.abstainVotes,
            canceled: proposal.canceled,
            executed: proposal.executed
        });
    }

    /**
     * @notice Get proposal actions
     * @param proposalId The proposal ID
     * @return targets Target addresses
     * @return values ETH values
     * @return calldatas Call data
     */
    function getActions(uint256 proposalId) external view returns (
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.targets, proposal.values, proposal.calldatas);
    }

    /**
     * @notice Get receipt for a voter
     * @param proposalId The proposal ID
     * @param voter The voter address
     * @return receipt The vote receipt
     */
    function getReceipt(
        uint256 proposalId,
        address voter
    ) external view returns (Receipt memory receipt) {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * @notice Check if voter has voted
     * @param proposalId The proposal ID
     * @param voter The voter address
     * @return True if voted
     */
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].receipts[voter].hasVoted;
    }

    /**
     * @notice Get current quorum requirement
     * @return The quorum in votes
     */
    function quorum() public view returns (uint256) {
        return (token.getPastTotalSupply(block.timestamp - 1) * QUORUM_PERCENTAGE) / 10000;
    }

    /**
     * @notice Get votes for an account at current block
     * @param account The account address
     * @return The voting power
     */
    function getVotes(address account) public view returns (uint256) {
        return token.getVotes(account);
    }

    /**
     * @notice Hash a proposal
     * @param targets Target addresses
     * @param values ETH values
     * @param calldatas Call data
     * @param descriptionHash Hash of description
     * @return The proposal ID
     */
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    // ============ ADMIN FUNCTIONS ============

    function setGuardian(address newGuardian) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        address oldGuardian = guardian;
        guardian = newGuardian;
        emit GuardianChanged(oldGuardian, newGuardian);
    }

    function setProposerWhitelistEnabled(bool enabled) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        proposerWhitelistEnabled = enabled;
        emit ProposerWhitelistToggled(enabled);
    }

    function setProposerWhitelisted(address account, bool whitelisted) external {
        _requireRole(AccessControlLib.DEFAULT_ADMIN_ROLE);
        isProposerWhitelisted[account] = whitelisted;
        emit ProposerWhitelisted(account, whitelisted);
    }

    // ============ ROLE MANAGEMENT ============
    function grantRole(bytes32 role, address account) external {
        AccessControlLib.checkRoleAdmin(_accessControl, role);
        AccessControlLib.grantRole(_accessControl, role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        AccessControlLib.checkRoleAdmin(_accessControl, role);
        AccessControlLib.revokeRole(_accessControl, role, account);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return AccessControlLib.hasRole(_accessControl, role, account);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _castVote(
        address voter,
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) internal returns (uint256 votes) {
        Proposal storage proposal = proposals[proposalId];

        if (state(proposalId) != ProposalState.Active) {
            revert VotingClosed(proposalId);
        }

        if (support > 2) revert InvalidVoteType(support);

        Receipt storage receipt = proposal.receipts[voter];
        if (receipt.hasVoted) revert AlreadyVoted(voter, proposalId);

        // Get votes at proposal start
        votes = token.getPastVotes(voter, proposal.startTime);

        if (support == VOTE_AGAINST) {
            proposal.againstVotes += votes;
        } else if (support == VOTE_FOR) {
            proposal.forVotes += votes;
        } else {
            proposal.abstainVotes += votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes, reason);
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        uint256 quorumVotes = (token.getPastTotalSupply(proposal.startTime) * QUORUM_PERCENTAGE) / 10000;
        return (proposal.forVotes + proposal.againstVotes + proposal.abstainVotes) >= quorumVotes;
    }

    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes;
    }

    function _requireRole(bytes32 role) internal view {
        AccessControlLib.checkRole(_accessControl, role, msg.sender);
    }

    // ============ RECEIVE ============
    receive() external payable {}
}
