// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title GameRegistry
 * @notice On-chain game registry with a vetting pipeline for the MTRX platform.
 * @dev Games progress through a multi-stage vetting pipeline before becoming
 *      fully listed. Each stage has designated reviewers who can approve or
 *      reject the game.
 *
 *      Pipeline stages:
 *        1. Submitted   - Developer submits the game for review.
 *        2. UnderReview - A reviewer picks up the submission.
 *        3. TechReview  - Technical/security audit stage.
 *        4. Approved    - Game passes all checks, listed on the platform.
 *        5. Rejected    - Game fails vetting (can be resubmitted).
 *        6. Suspended   - Previously approved game suspended for violations.
 *
 *      Deploys on Base.
 */
contract GameRegistry is Ownable, Pausable {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    enum VettingStage {
        Submitted,
        UnderReview,
        TechReview,
        Approved,
        Rejected,
        Suspended
    }

    struct Game {
        address developer;
        string name;
        string metadataURI;          // IPFS/Arweave URI for game metadata
        VettingStage stage;
        address currentReviewer;
        uint256 submittedAt;
        uint256 approvedAt;
        uint256 rejectedAt;
        string rejectionReason;
        uint256 version;             // Increments on resubmission
    }

    struct ReviewRecord {
        uint256 gameId;
        address reviewer;
        VettingStage fromStage;
        VettingStage toStage;
        string notes;
        uint256 timestamp;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    uint256 public nextGameId;
    uint256 public nextReviewId;

    mapping(uint256 => Game) public games;
    mapping(uint256 => ReviewRecord) public reviewRecords;

    /// @notice Review history per game.
    mapping(uint256 => uint256[]) public gameReviews;

    /// @notice Authorised reviewers.
    mapping(address => bool) public isReviewer;

    /// @notice Tech auditors (separate role from general reviewers).
    mapping(address => bool) public isTechAuditor;

    /// @notice Games submitted by a developer.
    mapping(address => uint256[]) public developerGames;

    /// @notice Count of approved games.
    uint256 public approvedGameCount;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event GameSubmitted(uint256 indexed gameId, address indexed developer, string name, string metadataURI);
    event GamePickedUp(uint256 indexed gameId, address indexed reviewer);
    event GameAdvanced(uint256 indexed gameId, VettingStage indexed newStage, address indexed reviewer);
    event GameApproved(uint256 indexed gameId, address indexed reviewer);
    event GameRejected(uint256 indexed gameId, address indexed reviewer, string reason);
    event GameSuspended(uint256 indexed gameId, string reason);
    event GameReinstated(uint256 indexed gameId);
    event GameResubmitted(uint256 indexed gameId, uint256 newVersion);
    event GameMetadataUpdated(uint256 indexed gameId, string newMetadataURI);
    event ReviewerAdded(address indexed reviewer);
    event ReviewerRemoved(address indexed reviewer);
    event TechAuditorAdded(address indexed auditor);
    event TechAuditorRemoved(address indexed auditor);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotDeveloper();
    error NotReviewer();
    error NotTechAuditor();
    error InvalidStage();
    error GameNotSubmitted();
    error GameNotUnderReview();
    error GameNotInTechReview();
    error GameNotApproved();
    error GameNotRejected();
    error ZeroAddress();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyReviewer() {
        if (!isReviewer[msg.sender] && msg.sender != owner()) revert NotReviewer();
        _;
    }

    modifier onlyTechAuditor() {
        if (!isTechAuditor[msg.sender] && msg.sender != owner()) revert NotTechAuditor();
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor() {}

    // ----------------------------------------------------------------
    // Game Submission
    // ----------------------------------------------------------------

    /**
     * @notice Submit a new game for vetting.
     * @param name        Game name.
     * @param metadataURI IPFS/Arweave URI for game metadata and assets.
     * @return gameId     The new game's ID.
     */
    function submitGame(string calldata name, string calldata metadataURI)
        external
        whenNotPaused
        returns (uint256 gameId)
    {
        gameId = nextGameId++;

        games[gameId] = Game({
            developer: msg.sender,
            name: name,
            metadataURI: metadataURI,
            stage: VettingStage.Submitted,
            currentReviewer: address(0),
            submittedAt: block.timestamp,
            approvedAt: 0,
            rejectedAt: 0,
            rejectionReason: "",
            version: 1
        });

        developerGames[msg.sender].push(gameId);

        emit GameSubmitted(gameId, msg.sender, name, metadataURI);
    }

    /**
     * @notice Resubmit a previously rejected game.
     * @param gameId      The game ID to resubmit.
     * @param metadataURI Updated metadata URI.
     */
    function resubmitGame(uint256 gameId, string calldata metadataURI) external whenNotPaused {
        Game storage game = games[gameId];
        if (msg.sender != game.developer) revert NotDeveloper();
        if (game.stage != VettingStage.Rejected) revert GameNotRejected();

        game.metadataURI = metadataURI;
        game.stage = VettingStage.Submitted;
        game.currentReviewer = address(0);
        game.rejectionReason = "";
        game.rejectedAt = 0;
        game.version++;

        emit GameResubmitted(gameId, game.version);
    }

    // ----------------------------------------------------------------
    // Vetting Pipeline
    // ----------------------------------------------------------------

    /**
     * @notice Reviewer picks up a submitted game for initial review.
     * @param gameId The game to review.
     */
    function pickupForReview(uint256 gameId) external onlyReviewer whenNotPaused {
        Game storage game = games[gameId];
        if (game.stage != VettingStage.Submitted) revert GameNotSubmitted();

        game.stage = VettingStage.UnderReview;
        game.currentReviewer = msg.sender;

        _addReviewRecord(gameId, VettingStage.Submitted, VettingStage.UnderReview, "Picked up for review");

        emit GamePickedUp(gameId, msg.sender);
    }

    /**
     * @notice Advance a game from initial review to tech review.
     * @param gameId The game to advance.
     * @param notes  Review notes.
     */
    function advanceToTechReview(uint256 gameId, string calldata notes) external onlyReviewer {
        Game storage game = games[gameId];
        if (game.stage != VettingStage.UnderReview) revert GameNotUnderReview();

        game.stage = VettingStage.TechReview;
        game.currentReviewer = address(0); // Awaiting tech auditor

        _addReviewRecord(gameId, VettingStage.UnderReview, VettingStage.TechReview, notes);

        emit GameAdvanced(gameId, VettingStage.TechReview, msg.sender);
    }

    /**
     * @notice Tech auditor approves the game after technical review.
     * @param gameId The game to approve.
     * @param notes  Audit notes.
     */
    function approveGame(uint256 gameId, string calldata notes) external onlyTechAuditor {
        Game storage game = games[gameId];
        if (game.stage != VettingStage.TechReview) revert GameNotInTechReview();

        game.stage = VettingStage.Approved;
        game.currentReviewer = msg.sender;
        game.approvedAt = block.timestamp;
        approvedGameCount++;

        _addReviewRecord(gameId, VettingStage.TechReview, VettingStage.Approved, notes);

        emit GameApproved(gameId, msg.sender);
    }

    /**
     * @notice Reject a game at any review stage.
     * @param gameId The game to reject.
     * @param reason Rejection reason.
     */
    function rejectGame(uint256 gameId, string calldata reason) external onlyReviewer {
        Game storage game = games[gameId];
        if (game.stage != VettingStage.UnderReview && game.stage != VettingStage.TechReview) {
            revert InvalidStage();
        }

        VettingStage previousStage = game.stage;
        game.stage = VettingStage.Rejected;
        game.rejectionReason = reason;
        game.rejectedAt = block.timestamp;

        _addReviewRecord(gameId, previousStage, VettingStage.Rejected, reason);

        emit GameRejected(gameId, msg.sender, reason);
    }

    /**
     * @notice Suspend a previously approved game.
     * @param gameId The game to suspend.
     * @param reason Suspension reason.
     */
    function suspendGame(uint256 gameId, string calldata reason) external onlyOwner {
        Game storage game = games[gameId];
        if (game.stage != VettingStage.Approved) revert GameNotApproved();

        game.stage = VettingStage.Suspended;
        approvedGameCount--;

        _addReviewRecord(gameId, VettingStage.Approved, VettingStage.Suspended, reason);

        emit GameSuspended(gameId, reason);
    }

    /**
     * @notice Reinstate a suspended game.
     * @param gameId The game to reinstate.
     */
    function reinstateGame(uint256 gameId) external onlyOwner {
        Game storage game = games[gameId];
        if (game.stage != VettingStage.Suspended) revert InvalidStage();

        game.stage = VettingStage.Approved;
        approvedGameCount++;

        _addReviewRecord(gameId, VettingStage.Suspended, VettingStage.Approved, "Reinstated");

        emit GameReinstated(gameId);
    }

    // ----------------------------------------------------------------
    // Metadata
    // ----------------------------------------------------------------

    /**
     * @notice Update game metadata (developer only, any stage except Approved).
     * @param gameId      The game to update.
     * @param metadataURI New metadata URI.
     */
    function updateMetadata(uint256 gameId, string calldata metadataURI) external {
        Game storage game = games[gameId];
        if (msg.sender != game.developer) revert NotDeveloper();
        // Allow updates unless game is live (Approved) to prevent bait-and-switch
        if (game.stage == VettingStage.Approved) revert InvalidStage();

        game.metadataURI = metadataURI;
        emit GameMetadataUpdated(gameId, metadataURI);
    }

    // ----------------------------------------------------------------
    // Role Management
    // ----------------------------------------------------------------

    function addReviewer(address reviewer) external onlyOwner {
        if (reviewer == address(0)) revert ZeroAddress();
        isReviewer[reviewer] = true;
        emit ReviewerAdded(reviewer);
    }

    function removeReviewer(address reviewer) external onlyOwner {
        isReviewer[reviewer] = false;
        emit ReviewerRemoved(reviewer);
    }

    function addTechAuditor(address auditor) external onlyOwner {
        if (auditor == address(0)) revert ZeroAddress();
        isTechAuditor[auditor] = true;
        emit TechAuditorAdded(auditor);
    }

    function removeTechAuditor(address auditor) external onlyOwner {
        isTechAuditor[auditor] = false;
        emit TechAuditorRemoved(auditor);
    }

    // ----------------------------------------------------------------
    // Internal
    // ----------------------------------------------------------------

    function _addReviewRecord(
        uint256 gameId,
        VettingStage fromStage,
        VettingStage toStage,
        string memory notes
    ) internal {
        uint256 reviewId = nextReviewId++;
        reviewRecords[reviewId] = ReviewRecord({
            gameId: gameId,
            reviewer: msg.sender,
            fromStage: fromStage,
            toStage: toStage,
            notes: notes,
            timestamp: block.timestamp
        });
        gameReviews[gameId].push(reviewId);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    function getGame(uint256 gameId) external view returns (Game memory) {
        return games[gameId];
    }

    function getDeveloperGames(address developer) external view returns (uint256[] memory) {
        return developerGames[developer];
    }

    function getGameReviewHistory(uint256 gameId) external view returns (uint256[] memory) {
        return gameReviews[gameId];
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
