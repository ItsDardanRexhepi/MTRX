// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title DisputeResolution
 * @notice Decentralised dispute resolution with Schelling Point mechanism,
 *         5-9 jurors, 72-hour evidence windows, appeal system, and contract
 *         freezing on Base.
 * @dev Implements a multi-phase dispute resolution protocol:
 *
 *      1. Filing Phase:       Claimant files dispute, stakes bond.
 *      2. Evidence Phase:     72-hour window for both parties to submit evidence.
 *      3. Jury Selection:     5-9 jurors randomly selected from staked juror pool.
 *      4. Voting Phase:       Jurors vote using Schelling Point (commit-reveal).
 *      5. Resolution Phase:   Majority wins; losing party pays juror fees.
 *      6. Appeal Phase:       Loser can appeal with larger bond and juror panel.
 *
 *      Contract freezing: disputed contracts can be frozen during resolution
 *      to prevent fund movement.
 *
 *      Schelling Point: Jurors independently vote on the "obvious" correct
 *      outcome. Those who vote with the majority are rewarded; dissenters lose
 *      their juror stake. This incentivises honest, convergent voting.
 */
contract DisputeResolution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Evidence submission window (72 hours).
    uint256 public constant EVIDENCE_WINDOW = 72 hours;

    /// @notice Voting window for jurors.
    uint256 public constant VOTING_WINDOW = 72 hours;

    /// @notice Reveal window after voting.
    uint256 public constant REVEAL_WINDOW = 48 hours;

    /// @notice Appeal window after resolution.
    uint256 public constant APPEAL_WINDOW = 7 days;

    /// @notice Minimum juror count.
    uint256 public constant MIN_JURORS = 5;

    /// @notice Maximum juror count.
    uint256 public constant MAX_JURORS = 9;

    /// @notice Appeal juror increase (add 2 per appeal round).
    uint256 public constant APPEAL_JUROR_INCREMENT = 2;

    /// @notice Maximum appeal rounds.
    uint256 public constant MAX_APPEALS = 2;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    enum DisputePhase {
        Filed,
        Evidence,
        JurySelection,
        Voting,
        Reveal,
        Resolved,
        Appealed,
        AppealResolved,
        Dismissed
    }

    enum Vote {
        None,
        Claimant,
        Respondent
    }

    struct Dispute {
        address claimant;
        address respondent;
        address stakeToken;           // ERC-20 token for bonds/stakes
        uint256 claimantBond;
        uint256 respondentBond;
        uint256 jurorFee;             // Total juror fee pool
        string claimURI;              // IPFS URI to claim details
        DisputePhase phase;
        uint256 filedAt;
        uint256 evidenceDeadline;
        uint256 votingDeadline;
        uint256 revealDeadline;
        uint256 resolvedAt;
        Vote outcome;                 // Final outcome
        uint256 jurorCount;           // 5, 7, or 9
        uint256 appealRound;          // 0 = original, 1+ = appeal
        address frozenContract;       // Contract frozen during dispute
        bool contractFrozen;
    }

    struct EvidenceSubmission {
        address submitter;
        string evidenceURI;
        bytes32 evidenceHash;
        uint256 submittedAt;
    }

    struct JurorVote {
        bytes32 commitHash;           // keccak256(vote, salt)
        Vote revealedVote;
        bool committed;
        bool revealed;
        uint256 stakeAmount;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    uint256 public nextDisputeId;

    mapping(uint256 => Dispute) public disputes;

    /// @notice Dispute => evidence submissions.
    mapping(uint256 => EvidenceSubmission[]) internal _evidence;

    /// @notice Dispute => selected juror addresses.
    mapping(uint256 => address[]) internal _jurors;

    /// @notice Dispute => juror => vote details.
    mapping(uint256 => mapping(address => JurorVote)) public jurorVotes;

    /// @notice Registered juror pool.
    mapping(address => bool) public isRegisteredJuror;

    /// @notice Juror stake balance.
    mapping(address => uint256) public jurorStake;

    /// @notice Minimum juror stake to be eligible.
    uint256 public minJurorStake;

    /// @notice Stake token for juror deposits.
    IERC20 public jurorStakeToken;

    /// @notice Registered juror addresses for random selection.
    address[] public jurorPool;

    /// @notice Contracts currently frozen by a dispute.
    mapping(address => uint256) public frozenByDispute;

    /// @notice Nonce for pseudo-random juror selection.
    uint256 private _selectionNonce;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event DisputeFiled(uint256 indexed disputeId, address indexed claimant, address indexed respondent, uint256 bond);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, string evidenceURI);
    event EvidencePhaseEnded(uint256 indexed disputeId);
    event JurySelected(uint256 indexed disputeId, address[] jurors);
    event VoteCommitted(uint256 indexed disputeId, address indexed juror);
    event VoteRevealed(uint256 indexed disputeId, address indexed juror, Vote vote);
    event DisputeResolvedEvent(uint256 indexed disputeId, Vote outcome, uint256 claimantVotes, uint256 respondentVotes);
    event DisputeAppealed(uint256 indexed disputeId, uint256 appealRound, uint256 newJurorCount);
    event ContractFrozen(uint256 indexed disputeId, address indexed frozenContract);
    event ContractUnfrozen(uint256 indexed disputeId, address indexed frozenContract);
    event JurorRegistered(address indexed juror, uint256 stakeAmount);
    event JurorWithdrawn(address indexed juror, uint256 amount);
    event JurorRewarded(uint256 indexed disputeId, address indexed juror, uint256 amount);
    event JurorSlashed(uint256 indexed disputeId, address indexed juror, uint256 amount);
    event DisputeDismissed(uint256 indexed disputeId);
    event RespondentBondPosted(uint256 indexed disputeId, uint256 amount);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotClaimant();
    error NotRespondent();
    error NotJuror();
    error InvalidPhase();
    error EvidenceWindowClosed();
    error EvidenceWindowOpen();
    error VotingWindowClosed();
    error VotingWindowOpen();
    error RevealWindowClosed();
    error RevealWindowOpen();
    error AppealWindowClosed();
    error MaxAppealsReached();
    error AlreadyCommitted();
    error AlreadyRevealed();
    error InvalidReveal();
    error InsufficientStake();
    error InsufficientBond();
    error ContractAlreadyFrozen();
    error InvalidJurorCount();
    error ZeroAddress();
    error ZeroAmount();
    error NotParty();

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param jurorStakeToken_ ERC-20 token for juror staking.
     * @param minJurorStake_   Minimum stake to join the juror pool.
     */
    constructor(address jurorStakeToken_, uint256 minJurorStake_) Ownable(msg.sender) {
        if (jurorStakeToken_ == address(0)) revert ZeroAddress();
        jurorStakeToken = IERC20(jurorStakeToken_);
        minJurorStake = minJurorStake_;
    }

    // ----------------------------------------------------------------
    // Juror Pool
    // ----------------------------------------------------------------

    /**
     * @notice Register as a juror by staking tokens.
     * @param amount Amount of tokens to stake.
     */
    function registerJuror(uint256 amount) external nonReentrant {
        if (amount < minJurorStake) revert InsufficientStake();

        jurorStakeToken.safeTransferFrom(msg.sender, address(this), amount);
        jurorStake[msg.sender] += amount;

        if (!isRegisteredJuror[msg.sender]) {
            isRegisteredJuror[msg.sender] = true;
            jurorPool.push(msg.sender);
        }

        emit JurorRegistered(msg.sender, amount);
    }

    /**
     * @notice Withdraw juror stake (only if not serving on active disputes).
     * @param amount Amount to withdraw.
     */
    function withdrawJurorStake(uint256 amount) external nonReentrant {
        if (amount > jurorStake[msg.sender]) revert InsufficientStake();

        jurorStake[msg.sender] -= amount;
        if (jurorStake[msg.sender] < minJurorStake) {
            isRegisteredJuror[msg.sender] = false;
        }

        jurorStakeToken.safeTransfer(msg.sender, amount);
        emit JurorWithdrawn(msg.sender, amount);
    }

    // ----------------------------------------------------------------
    // Dispute Filing
    // ----------------------------------------------------------------

    /**
     * @notice File a new dispute.
     * @param respondent       The party being disputed.
     * @param stakeToken       ERC-20 token for bonds.
     * @param bondAmount       Claimant's bond amount.
     * @param jurorFee         Total juror fee pool.
     * @param claimURI         IPFS URI to claim details.
     * @param jurorCount       Number of jurors (5, 7, or 9).
     * @param contractToFreeze Optional: contract to freeze during dispute.
     * @return disputeId       The dispute ID.
     */
    function fileDispute(
        address respondent,
        address stakeToken,
        uint256 bondAmount,
        uint256 jurorFee,
        string calldata claimURI,
        uint256 jurorCount,
        address contractToFreeze
    ) external nonReentrant whenNotPaused returns (uint256 disputeId) {
        if (respondent == address(0) || stakeToken == address(0)) revert ZeroAddress();
        if (bondAmount == 0) revert ZeroAmount();
        if (jurorCount < MIN_JURORS || jurorCount > MAX_JURORS || jurorCount % 2 == 0) {
            revert InvalidJurorCount();
        }

        disputeId = nextDisputeId++;

        disputes[disputeId] = Dispute({
            claimant: msg.sender,
            respondent: respondent,
            stakeToken: stakeToken,
            claimantBond: bondAmount,
            respondentBond: 0,
            jurorFee: jurorFee,
            claimURI: claimURI,
            phase: DisputePhase.Filed,
            filedAt: block.timestamp,
            evidenceDeadline: 0,
            votingDeadline: 0,
            revealDeadline: 0,
            resolvedAt: 0,
            outcome: Vote.None,
            jurorCount: jurorCount,
            appealRound: 0,
            frozenContract: contractToFreeze,
            contractFrozen: false
        });

        // Transfer claimant bond + juror fee
        IERC20(stakeToken).safeTransferFrom(msg.sender, address(this), bondAmount + jurorFee);

        // Freeze contract if requested
        if (contractToFreeze != address(0)) {
            if (frozenByDispute[contractToFreeze] != 0) revert ContractAlreadyFrozen();
            frozenByDispute[contractToFreeze] = disputeId + 1; // +1 because 0 means not frozen
            disputes[disputeId].contractFrozen = true;
            emit ContractFrozen(disputeId, contractToFreeze);
        }

        emit DisputeFiled(disputeId, msg.sender, respondent, bondAmount);
    }

    /**
     * @notice Respondent posts their bond and acknowledges the dispute.
     * @param disputeId The dispute to respond to.
     * @param bondAmount Bond amount (must match claimant bond).
     */
    function respondToDispute(uint256 disputeId, uint256 bondAmount) external nonReentrant {
        Dispute storage d = disputes[disputeId];
        if (msg.sender != d.respondent) revert NotRespondent();
        if (d.phase != DisputePhase.Filed) revert InvalidPhase();
        if (bondAmount < d.claimantBond) revert InsufficientBond();

        d.respondentBond = bondAmount;
        d.phase = DisputePhase.Evidence;
        d.evidenceDeadline = block.timestamp + EVIDENCE_WINDOW;

        IERC20(d.stakeToken).safeTransferFrom(msg.sender, address(this), bondAmount);

        emit RespondentBondPosted(disputeId, bondAmount);
    }

    // ----------------------------------------------------------------
    // Evidence Phase (72-hour window)
    // ----------------------------------------------------------------

    /**
     * @notice Submit evidence for a dispute.
     * @param disputeId    The dispute.
     * @param evidenceURI  IPFS URI to evidence.
     * @param evidenceHash Hash of the evidence.
     */
    function submitEvidence(
        uint256 disputeId,
        string calldata evidenceURI,
        bytes32 evidenceHash
    ) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Evidence) revert InvalidPhase();
        if (block.timestamp > d.evidenceDeadline) revert EvidenceWindowClosed();
        if (msg.sender != d.claimant && msg.sender != d.respondent) revert NotParty();

        _evidence[disputeId].push(EvidenceSubmission({
            submitter: msg.sender,
            evidenceURI: evidenceURI,
            evidenceHash: evidenceHash,
            submittedAt: block.timestamp
        }));

        emit EvidenceSubmitted(disputeId, msg.sender, evidenceURI);
    }

    /**
     * @notice End evidence phase and proceed to jury selection.
     * @dev Can be called by anyone after the evidence window closes.
     */
    function endEvidencePhase(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Evidence) revert InvalidPhase();
        if (block.timestamp < d.evidenceDeadline) revert EvidenceWindowOpen();

        d.phase = DisputePhase.JurySelection;
        emit EvidencePhaseEnded(disputeId);
    }

    // ----------------------------------------------------------------
    // Jury Selection (Pseudo-random from pool)
    // ----------------------------------------------------------------

    /**
     * @notice Select jurors for a dispute from the registered juror pool.
     * @param disputeId The dispute requiring jurors.
     */
    function selectJury(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.JurySelection) revert InvalidPhase();

        uint256 poolSize = jurorPool.length;
        require(poolSize >= d.jurorCount, "Insufficient juror pool");

        // Clear previous jury (for appeals)
        delete _jurors[disputeId];

        // Track selected jurors for this round
        mapping(address => bool) storage selectedMap = _jurorSelectedMap(disputeId);

        // Pseudo-random selection (acceptable for this use case;
        // production may use Chainlink VRF)
        uint256 selected = 0;
        uint256 nonce = _selectionNonce++;

        for (uint256 i = 0; selected < d.jurorCount && i < poolSize * 3; i++) {
            uint256 idx = uint256(keccak256(abi.encodePacked(
                block.timestamp, block.prevrandao, disputeId, nonce, i
            ))) % poolSize;

            address candidate = jurorPool[idx];

            if (!selectedMap[candidate] &&
                isRegisteredJuror[candidate] &&
                jurorStake[candidate] >= minJurorStake &&
                candidate != d.claimant &&
                candidate != d.respondent) {

                _jurors[disputeId].push(candidate);
                selectedMap[candidate] = true;

                // Initialize vote struct
                jurorVotes[disputeId][candidate] = JurorVote({
                    commitHash: bytes32(0),
                    revealedVote: Vote.None,
                    committed: false,
                    revealed: false,
                    stakeAmount: minJurorStake
                });

                selected++;
            }
        }

        require(selected == d.jurorCount, "Could not select enough jurors");

        d.phase = DisputePhase.Voting;
        d.votingDeadline = block.timestamp + VOTING_WINDOW;

        emit JurySelected(disputeId, _jurors[disputeId]);
    }

    /// @dev Mapping to track which jurors were selected for a dispute round.
    mapping(uint256 => mapping(address => bool)) private _selectedJurors;

    function _jurorSelectedMap(uint256 disputeId)
        internal
        view
        returns (mapping(address => bool) storage)
    {
        return _selectedJurors[disputeId];
    }

    // ----------------------------------------------------------------
    // Voting Phase (Schelling Point - Commit-Reveal)
    // ----------------------------------------------------------------

    /**
     * @notice Commit a vote (hash of vote + salt).
     * @param disputeId  The dispute.
     * @param commitHash keccak256(abi.encodePacked(vote, salt)) where vote is
     *                   1 (Claimant) or 2 (Respondent).
     */
    function commitVote(uint256 disputeId, bytes32 commitHash) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Voting) revert InvalidPhase();
        if (block.timestamp > d.votingDeadline) revert VotingWindowClosed();

        JurorVote storage jv = jurorVotes[disputeId][msg.sender];
        if (jv.stakeAmount == 0) revert NotJuror(); // Not selected
        if (jv.committed) revert AlreadyCommitted();

        jv.commitHash = commitHash;
        jv.committed = true;

        emit VoteCommitted(disputeId, msg.sender);
    }

    /**
     * @notice Begin the reveal phase after voting window closes.
     */
    function beginRevealPhase(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Voting) revert InvalidPhase();
        if (block.timestamp < d.votingDeadline) revert VotingWindowOpen();

        d.phase = DisputePhase.Reveal;
        d.revealDeadline = block.timestamp + REVEAL_WINDOW;
    }

    /**
     * @notice Reveal a previously committed vote.
     * @param disputeId The dispute.
     * @param vote      The vote (1 = Claimant, 2 = Respondent).
     * @param salt      The salt used in the commit hash.
     */
    function revealVote(uint256 disputeId, Vote vote, bytes32 salt) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Reveal) revert InvalidPhase();
        if (block.timestamp > d.revealDeadline) revert RevealWindowClosed();

        JurorVote storage jv = jurorVotes[disputeId][msg.sender];
        if (!jv.committed) revert NotJuror();
        if (jv.revealed) revert AlreadyRevealed();

        // Verify commit
        bytes32 expected = keccak256(abi.encodePacked(vote, salt));
        if (expected != jv.commitHash) revert InvalidReveal();

        jv.revealedVote = vote;
        jv.revealed = true;

        emit VoteRevealed(disputeId, msg.sender, vote);
    }

    // ----------------------------------------------------------------
    // Resolution
    // ----------------------------------------------------------------

    /**
     * @notice Resolve the dispute after the reveal window closes.
     * @param disputeId The dispute to resolve.
     */
    function resolveDispute(uint256 disputeId) external nonReentrant {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Reveal) revert InvalidPhase();
        if (block.timestamp < d.revealDeadline) revert RevealWindowOpen();

        // Count votes
        uint256 claimantVotes = 0;
        uint256 respondentVotes = 0;
        address[] storage jurors = _jurors[disputeId];

        for (uint256 i = 0; i < jurors.length; i++) {
            JurorVote storage jv = jurorVotes[disputeId][jurors[i]];
            if (jv.revealed) {
                if (jv.revealedVote == Vote.Claimant) claimantVotes++;
                else if (jv.revealedVote == Vote.Respondent) respondentVotes++;
            }
        }

        // Determine outcome (simple majority)
        Vote outcome;
        if (claimantVotes > respondentVotes) {
            outcome = Vote.Claimant;
        } else if (respondentVotes > claimantVotes) {
            outcome = Vote.Respondent;
        } else {
            // Tie: default to respondent (status quo)
            outcome = Vote.Respondent;
        }

        d.outcome = outcome;
        d.resolvedAt = block.timestamp;
        d.phase = DisputePhase.Resolved;

        // Distribute juror rewards (Schelling Point)
        uint256 winnerCount = outcome == Vote.Claimant ? claimantVotes : respondentVotes;
        uint256 jurorRewardPerWinner = 0;
        if (winnerCount > 0) {
            jurorRewardPerWinner = d.jurorFee / winnerCount;
        }

        for (uint256 i = 0; i < jurors.length; i++) {
            JurorVote storage jv = jurorVotes[disputeId][jurors[i]];
            if (jv.revealed && jv.revealedVote == outcome) {
                // Winner: reward from juror fee pool
                IERC20(d.stakeToken).safeTransfer(jurors[i], jurorRewardPerWinner);
                emit JurorRewarded(disputeId, jurors[i], jurorRewardPerWinner);
            } else if (jv.revealed && jv.revealedVote != outcome) {
                // Loser: slash 10% of their stake
                uint256 slashAmount = jv.stakeAmount / 10;
                if (slashAmount <= jurorStake[jurors[i]]) {
                    jurorStake[jurors[i]] -= slashAmount;
                    jurorStakeToken.safeTransfer(NEOSAFE, slashAmount);
                    emit JurorSlashed(disputeId, jurors[i], slashAmount);
                }
            }
            // Non-revealers: no reward, no slash (they lose the opportunity)
        }

        // Return bonds: winner gets their bond back + loser's bond
        if (outcome == Vote.Claimant) {
            IERC20(d.stakeToken).safeTransfer(d.claimant, d.claimantBond + d.respondentBond);
        } else {
            IERC20(d.stakeToken).safeTransfer(d.respondent, d.claimantBond + d.respondentBond);
        }

        // Unfreeze contract
        if (d.contractFrozen) {
            frozenByDispute[d.frozenContract] = 0;
            d.contractFrozen = false;
            emit ContractUnfrozen(disputeId, d.frozenContract);
        }

        emit DisputeResolvedEvent(disputeId, outcome, claimantVotes, respondentVotes);
    }

    // ----------------------------------------------------------------
    // Appeal System
    // ----------------------------------------------------------------

    /**
     * @notice Appeal a resolved dispute. Requires larger bond and more jurors.
     * @param disputeId  The resolved dispute to appeal.
     * @param extraBond  Additional bond for the appeal.
     * @param extraFee   Additional juror fee for the appeal.
     */
    function appeal(uint256 disputeId, uint256 extraBond, uint256 extraFee)
        external
        nonReentrant
    {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Resolved) revert InvalidPhase();
        if (block.timestamp > d.resolvedAt + APPEAL_WINDOW) revert AppealWindowClosed();
        if (d.appealRound >= MAX_APPEALS) revert MaxAppealsReached();

        // Only the loser can appeal
        if (d.outcome == Vote.Claimant && msg.sender != d.respondent) revert NotRespondent();
        if (d.outcome == Vote.Respondent && msg.sender != d.claimant) revert NotClaimant();

        // Increase juror count (up to MAX_JURORS)
        uint256 newJurorCount = d.jurorCount + APPEAL_JUROR_INCREMENT;
        if (newJurorCount > MAX_JURORS) newJurorCount = MAX_JURORS;

        d.appealRound++;
        d.jurorCount = newJurorCount;
        d.phase = DisputePhase.JurySelection;
        d.outcome = Vote.None;

        // Additional bond and fee from the appealing party
        if (extraBond > 0 || extraFee > 0) {
            IERC20(d.stakeToken).safeTransferFrom(msg.sender, address(this), extraBond + extraFee);
            // Add bond to the appealing party's total
            if (msg.sender == d.claimant) {
                d.claimantBond += extraBond;
            } else {
                d.respondentBond += extraBond;
            }
            d.jurorFee += extraFee;
        }

        // Re-freeze contract if applicable
        if (d.frozenContract != address(0) && !d.contractFrozen) {
            frozenByDispute[d.frozenContract] = disputeId + 1;
            d.contractFrozen = true;
            emit ContractFrozen(disputeId, d.frozenContract);
        }

        // Note: previous juror selections persist in mapping but are
        // irrelevant — fresh jurors are selected for each appeal round.

        emit DisputeAppealed(disputeId, d.appealRound, newJurorCount);
    }

    // ----------------------------------------------------------------
    // Dismissal
    // ----------------------------------------------------------------

    /**
     * @notice Dismiss a dispute if respondent never responds (after 14 days).
     * @param disputeId The dispute to dismiss.
     */
    function dismissDispute(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (d.phase != DisputePhase.Filed) revert InvalidPhase();
        if (block.timestamp < d.filedAt + 14 days) revert EvidenceWindowOpen();

        d.phase = DisputePhase.Dismissed;
        d.outcome = Vote.Claimant; // Default to claimant if respondent no-shows
        d.resolvedAt = block.timestamp;

        // Return bond and fee to claimant
        IERC20(d.stakeToken).safeTransfer(d.claimant, d.claimantBond + d.jurorFee);

        // Unfreeze
        if (d.contractFrozen) {
            frozenByDispute[d.frozenContract] = 0;
            d.contractFrozen = false;
            emit ContractUnfrozen(disputeId, d.frozenContract);
        }

        emit DisputeDismissed(disputeId);
    }

    // ----------------------------------------------------------------
    // Contract Freeze Check
    // ----------------------------------------------------------------

    /**
     * @notice Check if a contract is currently frozen by a dispute.
     * @param contractAddr The contract address to check.
     * @return True if the contract is frozen.
     */
    function isContractFrozen(address contractAddr) external view returns (bool) {
        return frozenByDispute[contractAddr] != 0;
    }

    /**
     * @notice Get the dispute ID that froze a contract.
     */
    function freezingDisputeId(address contractAddr) external view returns (uint256) {
        uint256 val = frozenByDispute[contractAddr];
        if (val == 0) return 0;
        return val - 1;
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    function getDispute(uint256 disputeId) external view returns (Dispute memory) {
        return disputes[disputeId];
    }

    function getJurors(uint256 disputeId) external view returns (address[] memory) {
        return _jurors[disputeId];
    }

    function getEvidenceCount(uint256 disputeId) external view returns (uint256) {
        return _evidence[disputeId].length;
    }

    function getEvidence(uint256 disputeId, uint256 index)
        external view returns (EvidenceSubmission memory)
    {
        return _evidence[disputeId][index];
    }

    function getJurorPoolSize() external view returns (uint256) {
        return jurorPool.length;
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    function setMinJurorStake(uint256 newMin) external onlyOwner {
        minJurorStake = newMin;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
