// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title GameFunding
 * @author MTRX Protocol
 * @notice Milestone-based game funding with 80/20 cost split on Base.
 * @dev Platform (NeoSafe) pays 80% of each milestone, developer pays 20%.
 *      Funds released in tranches per milestone completion.
 *      60-day inactivity auto-pause. If the game never launches after all
 *      milestones are funded, the developer owes 50% back.
 *      A GameRevenue contract must be deployed before any funding begins.
 */
contract GameFunding is Ownable, ReentrancyGuard, Pausable {
    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @notice NeoSafe treasury on Base
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Platform share of each milestone cost (80%)
    uint256 public constant PLATFORM_SHARE_BPS = 8000;

    /// @notice Developer share of each milestone cost (20%)
    uint256 public constant DEVELOPER_SHARE_BPS = 2000;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Seconds of inactivity before auto-pause (60 days)
    uint256 public constant INACTIVITY_THRESHOLD = 60 days;

    /// @notice Percentage developer owes back if game never launches (50%)
    uint256 public constant CLAWBACK_BPS = 5000;

    // -----------------------------------------------------------------------
    // Enums & Structs
    // -----------------------------------------------------------------------

    enum MilestoneStatus { Pending, Funded, Completed, Cancelled }
    enum GameStatus { Active, Launched, Abandoned }

    struct Milestone {
        string description;
        uint256 cost;
        uint256 platformDeposit;
        uint256 developerDeposit;
        uint256 releasedToDeveloper;
        MilestoneStatus status;
    }

    struct Game {
        address developer;
        address revenueContract;
        GameStatus status;
        uint256 totalFunded;
        uint256 totalReleased;
        uint256 lastActivityTimestamp;
        uint256 milestoneCount;
        uint256 clawbackOwed;
        bool clawbackSettled;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(uint256 => Milestone)) public milestones;
    uint256 public nextGameId;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event GameCreated(uint256 indexed gameId, address indexed developer, address revenueContract);
    event MilestoneAdded(uint256 indexed gameId, uint256 indexed milestoneIndex, string description, uint256 cost);
    event PlatformFunded(uint256 indexed gameId, uint256 indexed milestoneIndex, uint256 amount);
    event DeveloperFunded(uint256 indexed gameId, uint256 indexed milestoneIndex, uint256 amount);
    event MilestoneCompleted(uint256 indexed gameId, uint256 indexed milestoneIndex, uint256 amountReleased);
    event GameLaunched(uint256 indexed gameId);
    event GameAbandoned(uint256 indexed gameId, uint256 clawbackAmount);
    event ClawbackSettled(uint256 indexed gameId, uint256 amount);
    event InactivityPaused(uint256 indexed gameId);
    event MilestoneCancelled(uint256 indexed gameId, uint256 indexed milestoneIndex);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyDeveloper(uint256 _gameId) {
        require(msg.sender == games[_gameId].developer, "GameFunding: not developer");
        _;
    }

    modifier onlyActiveGame(uint256 _gameId) {
        require(games[_gameId].status == GameStatus.Active, "GameFunding: game not active");
        _;
    }

    modifier touchActivity(uint256 _gameId) {
        games[_gameId].lastActivityTimestamp = block.timestamp;
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // -----------------------------------------------------------------------
    // Game Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice Create a new game funding project. Revenue contract must already exist.
     * @param _developer Developer wallet address.
     * @param _revenueContract Address of the deployed GameRevenue contract.
     * @return gameId Unique game identifier.
     */
    function createGame(address _developer, address _revenueContract)
        external
        onlyOwner
        returns (uint256 gameId)
    {
        require(_developer != address(0), "GameFunding: zero developer");
        require(_revenueContract != address(0), "GameFunding: revenue contract required");
        require(_isContract(_revenueContract), "GameFunding: revenue addr not a contract");

        gameId = nextGameId++;
        Game storage g = games[gameId];
        g.developer = _developer;
        g.revenueContract = _revenueContract;
        g.status = GameStatus.Active;
        g.lastActivityTimestamp = block.timestamp;

        emit GameCreated(gameId, _developer, _revenueContract);
    }

    /**
     * @notice Add a milestone to an active game.
     * @param _gameId Game identifier.
     * @param _description Milestone description.
     * @param _cost Total cost in wei.
     */
    function addMilestone(uint256 _gameId, string calldata _description, uint256 _cost)
        external
        onlyOwner
        onlyActiveGame(_gameId)
        touchActivity(_gameId)
    {
        require(_cost > 0, "GameFunding: zero cost");

        uint256 idx = games[_gameId].milestoneCount++;
        Milestone storage m = milestones[_gameId][idx];
        m.description = _description;
        m.cost = _cost;
        m.status = MilestoneStatus.Pending;

        emit MilestoneAdded(_gameId, idx, _description, _cost);
    }

    /**
     * @notice Platform deposits its 80% share for a milestone.
     * @param _gameId Game identifier.
     * @param _milestoneIndex Milestone index.
     */
    function fundPlatformShare(uint256 _gameId, uint256 _milestoneIndex)
        external
        payable
        onlyOwner
        onlyActiveGame(_gameId)
        whenNotPaused
        touchActivity(_gameId)
    {
        Milestone storage m = milestones[_gameId][_milestoneIndex];
        require(m.status == MilestoneStatus.Pending, "GameFunding: not pending");

        uint256 required = (m.cost * PLATFORM_SHARE_BPS) / BPS_DENOMINATOR;
        require(m.platformDeposit + msg.value <= required, "GameFunding: exceeds platform share");

        m.platformDeposit += msg.value;
        games[_gameId].totalFunded += msg.value;

        emit PlatformFunded(_gameId, _milestoneIndex, msg.value);
        _checkMilestoneFunded(_gameId, _milestoneIndex);
    }

    /**
     * @notice Developer deposits their 20% share for a milestone.
     * @param _gameId Game identifier.
     * @param _milestoneIndex Milestone index.
     */
    function fundDeveloperShare(uint256 _gameId, uint256 _milestoneIndex)
        external
        payable
        onlyDeveloper(_gameId)
        onlyActiveGame(_gameId)
        whenNotPaused
        touchActivity(_gameId)
    {
        Milestone storage m = milestones[_gameId][_milestoneIndex];
        require(m.status == MilestoneStatus.Pending, "GameFunding: not pending");

        uint256 required = (m.cost * DEVELOPER_SHARE_BPS) / BPS_DENOMINATOR;
        require(m.developerDeposit + msg.value <= required, "GameFunding: exceeds developer share");

        m.developerDeposit += msg.value;
        games[_gameId].totalFunded += msg.value;

        emit DeveloperFunded(_gameId, _milestoneIndex, msg.value);
        _checkMilestoneFunded(_gameId, _milestoneIndex);
    }

    /**
     * @notice Mark a milestone as completed and release funds to the developer.
     * @param _gameId Game identifier.
     * @param _milestoneIndex Milestone index.
     */
    function completeMilestone(uint256 _gameId, uint256 _milestoneIndex)
        external
        onlyOwner
        onlyActiveGame(_gameId)
        nonReentrant
        whenNotPaused
        touchActivity(_gameId)
    {
        Milestone storage m = milestones[_gameId][_milestoneIndex];
        require(m.status == MilestoneStatus.Funded, "GameFunding: not funded");

        m.status = MilestoneStatus.Completed;
        uint256 toRelease = m.platformDeposit + m.developerDeposit;
        m.releasedToDeveloper = toRelease;
        games[_gameId].totalReleased += toRelease;

        (bool sent, ) = games[_gameId].developer.call{value: toRelease}("");
        require(sent, "GameFunding: ETH transfer failed");

        emit MilestoneCompleted(_gameId, _milestoneIndex, toRelease);
    }

    /**
     * @notice Mark the game as officially launched. No clawback applies.
     * @param _gameId Game identifier.
     */
    function markGameLaunched(uint256 _gameId) external onlyOwner onlyActiveGame(_gameId) {
        games[_gameId].status = GameStatus.Launched;
        emit GameLaunched(_gameId);
    }

    /**
     * @notice Mark the game as abandoned. Developer owes 50% of total released back.
     * @param _gameId Game identifier.
     */
    function markGameAbandoned(uint256 _gameId) external onlyOwner onlyActiveGame(_gameId) {
        Game storage g = games[_gameId];
        g.status = GameStatus.Abandoned;
        g.clawbackOwed = (g.totalReleased * CLAWBACK_BPS) / BPS_DENOMINATOR;
        emit GameAbandoned(_gameId, g.clawbackOwed);
    }

    /**
     * @notice Developer settles their clawback debt, funds go to NeoSafe.
     * @param _gameId Game identifier.
     */
    function settleClawback(uint256 _gameId) external payable nonReentrant {
        Game storage g = games[_gameId];
        require(g.status == GameStatus.Abandoned, "GameFunding: not abandoned");
        require(!g.clawbackSettled, "GameFunding: already settled");
        require(msg.value >= g.clawbackOwed, "GameFunding: insufficient payment");

        g.clawbackSettled = true;

        (bool sent, ) = NEOSAFE.call{value: msg.value}("");
        require(sent, "GameFunding: clawback transfer failed");

        emit ClawbackSettled(_gameId, msg.value);
    }

    /**
     * @notice Cancel a pending or funded milestone and refund deposits.
     * @param _gameId Game identifier.
     * @param _milestoneIndex Milestone index.
     */
    function cancelMilestone(uint256 _gameId, uint256 _milestoneIndex)
        external
        onlyOwner
        nonReentrant
    {
        Milestone storage m = milestones[_gameId][_milestoneIndex];
        require(
            m.status == MilestoneStatus.Pending || m.status == MilestoneStatus.Funded,
            "GameFunding: cannot cancel"
        );

        m.status = MilestoneStatus.Cancelled;
        Game storage g = games[_gameId];

        if (m.platformDeposit > 0) {
            uint256 refund = m.platformDeposit;
            m.platformDeposit = 0;
            g.totalFunded -= refund;
            (bool s, ) = NEOSAFE.call{value: refund}("");
            require(s, "GameFunding: platform refund failed");
        }

        if (m.developerDeposit > 0) {
            uint256 refund = m.developerDeposit;
            m.developerDeposit = 0;
            g.totalFunded -= refund;
            (bool s, ) = g.developer.call{value: refund}("");
            require(s, "GameFunding: dev refund failed");
        }

        emit MilestoneCancelled(_gameId, _milestoneIndex);
    }

    /**
     * @notice Anyone can trigger an inactivity pause if 60 days elapsed since last activity.
     * @param _gameId Game identifier.
     */
    function triggerInactivityPause(uint256 _gameId) external {
        Game storage g = games[_gameId];
        require(g.status == GameStatus.Active, "GameFunding: not active");
        require(
            block.timestamp >= g.lastActivityTimestamp + INACTIVITY_THRESHOLD,
            "GameFunding: not inactive yet"
        );
        _pause();
        emit InactivityPaused(_gameId);
    }

    /**
     * @notice Owner unpauses the contract after resolving inactivity.
     */
    function unpauseContract() external onlyOwner {
        _unpause();
    }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    /// @notice Get milestone details.
    function getMilestone(uint256 _gameId, uint256 _idx) external view returns (Milestone memory) {
        return milestones[_gameId][_idx];
    }

    /// @notice Get game details.
    function getGame(uint256 _gameId) external view returns (Game memory) {
        return games[_gameId];
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    function _checkMilestoneFunded(uint256 _gameId, uint256 _idx) internal {
        Milestone storage m = milestones[_gameId][_idx];
        uint256 pReq = (m.cost * PLATFORM_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 dReq = (m.cost * DEVELOPER_SHARE_BPS) / BPS_DENOMINATOR;
        if (m.platformDeposit >= pReq && m.developerDeposit >= dReq) {
            m.status = MilestoneStatus.Funded;
        }
    }

    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(_addr) }
        return size > 0;
    }

    receive() external payable {}
}
