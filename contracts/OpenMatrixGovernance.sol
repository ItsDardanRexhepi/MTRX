// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title OpenMatrixGovernance
 * @notice Platform-wide policy governance with three voting models.
 *         Bilateral disputes are REJECTED at contract level and redirected to Component 30.
 *         Quorum: valid when all PARTICIPATING voters have cast. Non-voters not counted.
 *         Voting is always FREE — no fees.
 *         EAS attestation emitted on every result.
 */

interface IEAS {
    function attest(bytes calldata data) external returns (bytes32);
}

contract OpenMatrixGovernance is Ownable, ReentrancyGuard {

    // ──────────────────────── Enums ────────────────────────

    enum VotingModel { OnePersonOneVote, TokenWeighted, Quadratic }
    enum ProposalStatus { Active, Executed, Cancelled }
    enum VoteChoice { Against, For, Abstain }

    // ──────────────────────── Structs ──────────────────────

    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        string category;          // must NOT be "bilateral_dispute"
        uint256 createdAt;
        uint256 deadline;
        ProposalStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votesAbstain;
        uint256 totalParticipants; // only those who actually voted
        bool executed;
        bytes32 easAttestation;
    }

    struct VoterRecord {
        bool hasVoted;
        VoteChoice choice;
        uint256 weight;            // 1 for one-person-one-vote, token balance for weighted, sqrt for quadratic
    }

    // ──────────────────────── State ───────────────────────

    IEAS public immutable eas;
    address public immutable disputeContract; // Component 30

    VotingModel public votingModel;
    bool public modelLocked;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => VoterRecord)) public votes;

    // Token-weighted / quadratic: token balances
    mapping(address => uint256) public governanceTokenBalance;

    // ──────────────────────── Events ──────────────────────

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        string category,
        uint256 deadline
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteChoice choice,
        uint256 weight
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 totalParticipants,
        bytes32 easAttestation
    );

    event BilateralDisputeRejected(
        address indexed caller,
        string reason,
        address redirectTo
    );

    event VotingModelSet(VotingModel model, address setBy);

    // ──────────────────────── Errors ──────────────────────

    error BilateralDisputeNotAllowed();
    error ModelAlreadyLocked();
    error ProposalNotActive();
    error AlreadyVoted();
    error DeadlinePassed();
    error DeadlineNotReached();
    error NotEnoughTokens();

    // ──────────────────────── Constructor ─────────────────

    constructor(
        address _eas,
        address _disputeContract
    ) Ownable(msg.sender) {
        eas = IEAS(_eas);
        disputeContract = _disputeContract;
        modelLocked = false;
    }

    // ──────────────────────── Model Selection (PERMANENT) ─

    /**
     * @notice Set the voting model. Can only be called ONCE — choice is permanent.
     */
    function setVotingModel(VotingModel _model) external onlyOwner {
        if (modelLocked) revert ModelAlreadyLocked();
        votingModel = _model;
        modelLocked = true;
        emit VotingModelSet(_model, msg.sender);
    }

    // ──────────────────────── Proposals ───────────────────

    /**
     * @notice Create a platform-wide policy proposal.
     *         Bilateral disputes are REJECTED — use Component 30.
     */
    function createProposal(
        string calldata _title,
        string calldata _description,
        string calldata _category,
        uint256 _deadline
    ) external returns (uint256) {
        // REJECT bilateral disputes at contract level
        if (_isBilateralDispute(_category)) {
            emit BilateralDisputeRejected(
                msg.sender,
                "Bilateral disputes must use Component 30 dispute resolution",
                disputeContract
            );
            revert BilateralDisputeNotAllowed();
        }

        require(_deadline > block.timestamp, "Deadline must be in the future");

        proposalCount++;
        uint256 pid = proposalCount;

        proposals[pid] = Proposal({
            id: pid,
            proposer: msg.sender,
            title: _title,
            description: _description,
            category: _category,
            createdAt: block.timestamp,
            deadline: _deadline,
            status: ProposalStatus.Active,
            votesFor: 0,
            votesAgainst: 0,
            votesAbstain: 0,
            totalParticipants: 0,
            executed: false,
            easAttestation: bytes32(0)
        });

        emit ProposalCreated(pid, msg.sender, _title, _category, _deadline);
        return pid;
    }

    // ──────────────────────── Voting ──────────────────────

    /**
     * @notice Cast a vote. Weight depends on the permanently chosen model.
     *         Quorum = all participating voters. Non-voters are irrelevant.
     */
    function castVote(uint256 _proposalId, VoteChoice _choice) external nonReentrant {
        Proposal storage p = proposals[_proposalId];
        if (p.status != ProposalStatus.Active) revert ProposalNotActive();
        if (block.timestamp > p.deadline) revert DeadlinePassed();
        if (votes[_proposalId][msg.sender].hasVoted) revert AlreadyVoted();

        uint256 weight = _calculateWeight(msg.sender);

        votes[_proposalId][msg.sender] = VoterRecord({
            hasVoted: true,
            choice: _choice,
            weight: weight
        });

        if (_choice == VoteChoice.For) {
            p.votesFor += weight;
        } else if (_choice == VoteChoice.Against) {
            p.votesAgainst += weight;
        } else {
            p.votesAbstain += weight;
        }

        p.totalParticipants++;

        emit VoteCast(_proposalId, msg.sender, _choice, weight);
    }

    // ──────────────────────── Execution ───────────────────

    /**
     * @notice Execute a proposal after deadline. Valid as long as >= 1 person voted.
     *         Attests result via EAS.
     */
    function executeProposal(uint256 _proposalId) external nonReentrant {
        Proposal storage p = proposals[_proposalId];
        if (p.status != ProposalStatus.Active) revert ProposalNotActive();
        if (block.timestamp < p.deadline) revert DeadlineNotReached();
        require(p.totalParticipants > 0, "No votes cast");

        p.status = ProposalStatus.Executed;
        p.executed = true;

        // EAS attestation
        bytes memory attestData = abi.encode(
            p.id,
            p.title,
            p.votesFor,
            p.votesAgainst,
            p.votesAbstain,
            p.totalParticipants,
            p.votesFor > p.votesAgainst ? "PASSED" : "FAILED"
        );
        bytes32 uid = eas.attest(attestData);
        p.easAttestation = uid;

        emit ProposalExecuted(
            _proposalId,
            p.votesFor,
            p.votesAgainst,
            p.totalParticipants,
            uid
        );
    }

    /**
     * @notice Cancel a proposal. Only proposer or owner.
     */
    function cancelProposal(uint256 _proposalId) external {
        Proposal storage p = proposals[_proposalId];
        require(
            msg.sender == p.proposer || msg.sender == owner(),
            "Not authorized"
        );
        require(p.status == ProposalStatus.Active, "Not active");
        p.status = ProposalStatus.Cancelled;
    }

    // ──────────────────────── Governance Token ────────────

    /**
     * @notice Assign governance token balance (for token-weighted / quadratic models).
     */
    function setGovernanceBalance(address _voter, uint256 _balance) external onlyOwner {
        governanceTokenBalance[_voter] = _balance;
    }

    // ──────────────────────── Internal ────────────────────

    function _calculateWeight(address _voter) internal view returns (uint256) {
        if (votingModel == VotingModel.OnePersonOneVote) {
            return 1;
        } else if (votingModel == VotingModel.TokenWeighted) {
            uint256 bal = governanceTokenBalance[_voter];
            if (bal == 0) revert NotEnoughTokens();
            return bal;
        } else {
            // Quadratic: sqrt of token balance
            uint256 bal = governanceTokenBalance[_voter];
            if (bal == 0) revert NotEnoughTokens();
            return _sqrt(bal);
        }
    }

    function _isBilateralDispute(string calldata _category) internal pure returns (bool) {
        bytes32 h = keccak256(abi.encodePacked(_category));
        return (
            h == keccak256("bilateral_dispute") ||
            h == keccak256("bilateral") ||
            h == keccak256("dispute") ||
            h == keccak256("two_party_dispute")
        );
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // ──────────────────────── Views ───────────────────────

    function getProposal(uint256 _id) external view returns (Proposal memory) {
        return proposals[_id];
    }

    function getVote(uint256 _proposalId, address _voter) external view returns (VoterRecord memory) {
        return votes[_proposalId][_voter];
    }

    function hasVoted(uint256 _proposalId, address _voter) external view returns (bool) {
        return votes[_proposalId][_voter].hasVoted;
    }
}
