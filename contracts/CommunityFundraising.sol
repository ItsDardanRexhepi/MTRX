// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CommunityFundraising
 * @author MTRX Protocol
 * @notice Community fundraising on Base with 0% platform fee (100% to recipient).
 * @dev Supports four vesting modes: immediate, milestone-based, time-based, hybrid.
 *      Auto-refund if goal not met by deadline.
 *      Milestone verification: Method A (oracle via Component 11) or
 *      Method B (contributor vote via Component 19 quorum).
 */
contract CommunityFundraising is Ownable, ReentrancyGuard, Pausable {

    /// @notice NeoSafe treasury on Base (reference; 0% fee)
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Platform fee is 0%
    uint256 public constant PLATFORM_FEE_BPS = 0;

    // -----------------------------------------------------------------------
    // Enums
    // -----------------------------------------------------------------------

    enum VestingType { Immediate, MilestoneBased, TimeBased, Hybrid }
    enum VerificationMethod { Oracle, ContributorVote }
    enum CampaignStatus { Active, Funded, Failed, Completed }
    enum MilestoneStatus { Pending, Verified, Rejected }

    // -----------------------------------------------------------------------
    // Structs
    // -----------------------------------------------------------------------

    struct Campaign {
        address recipient;
        uint256 goal;
        uint256 deadline;
        uint256 totalRaised;
        uint256 totalReleased;
        CampaignStatus status;
        VestingType vestingType;
        VerificationMethod verificationMethod;
        uint256 milestoneCount;
        uint256 contributorCount;
        uint256 vestingStart;
        uint256 vestingDuration;
        uint256 vestingCliff;
    }

    struct CampaignMilestone {
        string description;
        uint256 releaseAmount;
        MilestoneStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 voteDeadline;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(uint256 => CampaignMilestone)) public campaignMilestones;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasVoted;

    uint256 public nextCampaignId;

    /// @notice Oracle address for Method A (Component 11)
    address public oracleAddress;

    /// @notice Quorum percentage for contributor votes (default 51%)
    uint256 public voteQuorumPercent = 51;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event CampaignCreated(uint256 indexed campaignId, address indexed recipient, uint256 goal, uint256 deadline, VestingType vestingType);
    event ContributionMade(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event CampaignFunded(uint256 indexed campaignId, uint256 totalRaised);
    event CampaignFailed(uint256 indexed campaignId);
    event FundsReleased(uint256 indexed campaignId, address indexed recipient, uint256 amount);
    event ContributorRefunded(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event MilestoneAdded(uint256 indexed campaignId, uint256 indexed milestoneIndex, string description, uint256 releaseAmount);
    event MilestoneVerified(uint256 indexed campaignId, uint256 indexed milestoneIndex, VerificationMethod method);
    event MilestoneRejected(uint256 indexed campaignId, uint256 indexed milestoneIndex);
    event ContributorVoted(uint256 indexed campaignId, uint256 indexed milestoneIndex, address indexed voter, bool inFavor);
    event OracleUpdated(address indexed newOracle);
    event CampaignCompleted(uint256 indexed campaignId);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "CommunityFundraising: not oracle");
        _;
    }

    modifier campaignActive(uint256 _id) {
        require(campaigns[_id].status == CampaignStatus.Active, "CommunityFundraising: not active");
        _;
    }

    modifier campaignFunded(uint256 _id) {
        require(campaigns[_id].status == CampaignStatus.Funded, "CommunityFundraising: not funded");
        _;
    }

    modifier onlyContributor(uint256 _id) {
        require(contributions[_id][msg.sender] > 0, "CommunityFundraising: not contributor");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _oracle) Ownable(msg.sender) {
        oracleAddress = _oracle;
    }

    // -----------------------------------------------------------------------
    // Campaign Management
    // -----------------------------------------------------------------------

    /**
     * @notice Create a new fundraising campaign.
     * @param _recipient Wallet to receive funds.
     * @param _goal Funding goal in wei.
     * @param _deadline Unix timestamp deadline.
     * @param _vestingType Vesting mode.
     * @param _verificationMethod Milestone verification method.
     * @param _vestingDuration Duration for time-based vesting (0 if N/A).
     * @param _vestingCliff Cliff period for time-based vesting (0 if N/A).
     * @return campaignId New campaign identifier.
     */
    function createCampaign(
        address _recipient,
        uint256 _goal,
        uint256 _deadline,
        VestingType _vestingType,
        VerificationMethod _verificationMethod,
        uint256 _vestingDuration,
        uint256 _vestingCliff
    ) external onlyOwner returns (uint256 campaignId) {
        require(_recipient != address(0), "CommunityFundraising: zero recipient");
        require(_goal > 0, "CommunityFundraising: zero goal");
        require(_deadline > block.timestamp, "CommunityFundraising: deadline in past");

        campaignId = nextCampaignId++;
        Campaign storage c = campaigns[campaignId];
        c.recipient = _recipient;
        c.goal = _goal;
        c.deadline = _deadline;
        c.status = CampaignStatus.Active;
        c.vestingType = _vestingType;
        c.verificationMethod = _verificationMethod;
        c.vestingDuration = _vestingDuration;
        c.vestingCliff = _vestingCliff;

        emit CampaignCreated(campaignId, _recipient, _goal, _deadline, _vestingType);
    }

    /**
     * @notice Add a milestone to a campaign (milestone-based or hybrid vesting).
     * @param _campaignId Campaign identifier.
     * @param _description Milestone description.
     * @param _releaseAmount ETH to release upon verification.
     * @param _voteDeadline Voting deadline (0 if oracle-verified).
     */
    function addMilestone(
        uint256 _campaignId,
        string calldata _description,
        uint256 _releaseAmount,
        uint256 _voteDeadline
    ) external onlyOwner {
        Campaign storage c = campaigns[_campaignId];
        require(
            c.vestingType == VestingType.MilestoneBased || c.vestingType == VestingType.Hybrid,
            "CommunityFundraising: wrong vesting type"
        );

        uint256 idx = c.milestoneCount++;
        campaignMilestones[_campaignId][idx] = CampaignMilestone({
            description: _description,
            releaseAmount: _releaseAmount,
            status: MilestoneStatus.Pending,
            votesFor: 0,
            votesAgainst: 0,
            voteDeadline: _voteDeadline
        });

        emit MilestoneAdded(_campaignId, idx, _description, _releaseAmount);
    }

    // -----------------------------------------------------------------------
    // Contributing
    // -----------------------------------------------------------------------

    /**
     * @notice Contribute ETH to an active campaign.
     * @param _campaignId Campaign identifier.
     */
    function contribute(uint256 _campaignId)
        external
        payable
        campaignActive(_campaignId)
        whenNotPaused
    {
        require(msg.value > 0, "CommunityFundraising: zero contribution");
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp <= c.deadline, "CommunityFundraising: deadline passed");

        if (contributions[_campaignId][msg.sender] == 0) {
            c.contributorCount++;
        }
        contributions[_campaignId][msg.sender] += msg.value;
        c.totalRaised += msg.value;

        emit ContributionMade(_campaignId, msg.sender, msg.value);

        if (c.totalRaised >= c.goal) {
            c.status = CampaignStatus.Funded;
            c.vestingStart = block.timestamp;
            emit CampaignFunded(_campaignId, c.totalRaised);
        }
    }

    // -----------------------------------------------------------------------
    // Refunds
    // -----------------------------------------------------------------------

    /**
     * @notice Mark a campaign as failed if deadline passed without meeting goal.
     * @param _campaignId Campaign identifier.
     */
    function checkAndFailCampaign(uint256 _campaignId) external {
        Campaign storage c = campaigns[_campaignId];
        require(c.status == CampaignStatus.Active, "CommunityFundraising: not active");
        require(block.timestamp > c.deadline, "CommunityFundraising: deadline not passed");
        require(c.totalRaised < c.goal, "CommunityFundraising: goal met");

        c.status = CampaignStatus.Failed;
        emit CampaignFailed(_campaignId);
    }

    /**
     * @notice Claim refund for a failed campaign.
     * @param _campaignId Campaign identifier.
     */
    function claimRefund(uint256 _campaignId) external nonReentrant {
        Campaign storage c = campaigns[_campaignId];
        require(c.status == CampaignStatus.Failed, "CommunityFundraising: not failed");

        uint256 amount = contributions[_campaignId][msg.sender];
        require(amount > 0, "CommunityFundraising: no contribution");

        contributions[_campaignId][msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "CommunityFundraising: refund failed");

        emit ContributorRefunded(_campaignId, msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // Fund Release -- Immediate
    // -----------------------------------------------------------------------

    /**
     * @notice Release all funds immediately to recipient.
     * @param _campaignId Campaign identifier.
     */
    function releaseImmediate(uint256 _campaignId)
        external
        campaignFunded(_campaignId)
        nonReentrant
    {
        Campaign storage c = campaigns[_campaignId];
        require(c.vestingType == VestingType.Immediate, "CommunityFundraising: wrong vesting");

        uint256 amount = c.totalRaised - c.totalReleased;
        require(amount > 0, "CommunityFundraising: nothing to release");

        c.totalReleased += amount;
        c.status = CampaignStatus.Completed;

        (bool sent, ) = c.recipient.call{value: amount}("");
        require(sent, "CommunityFundraising: transfer failed");

        emit FundsReleased(_campaignId, c.recipient, amount);
        emit CampaignCompleted(_campaignId);
    }

    // -----------------------------------------------------------------------
    // Fund Release -- Time-based
    // -----------------------------------------------------------------------

    /**
     * @notice Release vested funds based on elapsed time.
     * @param _campaignId Campaign identifier.
     */
    function releaseTimeBased(uint256 _campaignId)
        external
        campaignFunded(_campaignId)
        nonReentrant
    {
        Campaign storage c = campaigns[_campaignId];
        require(
            c.vestingType == VestingType.TimeBased || c.vestingType == VestingType.Hybrid,
            "CommunityFundraising: wrong vesting"
        );
        require(block.timestamp >= c.vestingStart + c.vestingCliff, "CommunityFundraising: cliff not reached");

        uint256 elapsed = block.timestamp - c.vestingStart;
        uint256 vestedAmount;
        if (elapsed >= c.vestingDuration) {
            vestedAmount = c.totalRaised;
        } else {
            vestedAmount = (c.totalRaised * elapsed) / c.vestingDuration;
        }

        uint256 releasable = vestedAmount - c.totalReleased;
        require(releasable > 0, "CommunityFundraising: nothing vested");

        c.totalReleased += releasable;
        if (c.totalReleased >= c.totalRaised) {
            c.status = CampaignStatus.Completed;
            emit CampaignCompleted(_campaignId);
        }

        (bool sent, ) = c.recipient.call{value: releasable}("");
        require(sent, "CommunityFundraising: transfer failed");

        emit FundsReleased(_campaignId, c.recipient, releasable);
    }

    // -----------------------------------------------------------------------
    // Milestone Verification -- Method A: Oracle (Component 11)
    // -----------------------------------------------------------------------

    /**
     * @notice Oracle verifies a milestone and releases funds.
     * @param _campaignId Campaign identifier.
     * @param _milestoneIndex Milestone index.
     */
    function oracleVerifyMilestone(uint256 _campaignId, uint256 _milestoneIndex)
        external
        onlyOracle
        campaignFunded(_campaignId)
        nonReentrant
    {
        Campaign storage c = campaigns[_campaignId];
        require(c.verificationMethod == VerificationMethod.Oracle, "CommunityFundraising: not oracle method");

        CampaignMilestone storage m = campaignMilestones[_campaignId][_milestoneIndex];
        require(m.status == MilestoneStatus.Pending, "CommunityFundraising: not pending");

        m.status = MilestoneStatus.Verified;
        uint256 amount = m.releaseAmount;
        c.totalReleased += amount;

        (bool sent, ) = c.recipient.call{value: amount}("");
        require(sent, "CommunityFundraising: transfer failed");

        emit MilestoneVerified(_campaignId, _milestoneIndex, VerificationMethod.Oracle);
        emit FundsReleased(_campaignId, c.recipient, amount);

        if (c.totalReleased >= c.totalRaised) {
            c.status = CampaignStatus.Completed;
            emit CampaignCompleted(_campaignId);
        }
    }

    /**
     * @notice Oracle rejects a milestone.
     * @param _campaignId Campaign identifier.
     * @param _milestoneIndex Milestone index.
     */
    function oracleRejectMilestone(uint256 _campaignId, uint256 _milestoneIndex) external onlyOracle {
        CampaignMilestone storage m = campaignMilestones[_campaignId][_milestoneIndex];
        require(m.status == MilestoneStatus.Pending, "CommunityFundraising: not pending");
        m.status = MilestoneStatus.Rejected;
        emit MilestoneRejected(_campaignId, _milestoneIndex);
    }

    // -----------------------------------------------------------------------
    // Milestone Verification -- Method B: Contributor Vote (Component 19)
    // -----------------------------------------------------------------------

    /**
     * @notice Contributor votes on a milestone.
     * @param _campaignId Campaign identifier.
     * @param _milestoneIndex Milestone index.
     * @param _inFavor Whether the vote is in favor.
     */
    function voteOnMilestone(uint256 _campaignId, uint256 _milestoneIndex, bool _inFavor)
        external
        onlyContributor(_campaignId)
    {
        Campaign storage c = campaigns[_campaignId];
        require(c.verificationMethod == VerificationMethod.ContributorVote, "CommunityFundraising: not vote method");

        CampaignMilestone storage m = campaignMilestones[_campaignId][_milestoneIndex];
        require(m.status == MilestoneStatus.Pending, "CommunityFundraising: not pending");
        require(!hasVoted[_campaignId][_milestoneIndex][msg.sender], "CommunityFundraising: already voted");
        if (m.voteDeadline > 0) {
            require(block.timestamp <= m.voteDeadline, "CommunityFundraising: vote deadline passed");
        }

        hasVoted[_campaignId][_milestoneIndex][msg.sender] = true;
        if (_inFavor) { m.votesFor++; } else { m.votesAgainst++; }

        emit ContributorVoted(_campaignId, _milestoneIndex, msg.sender, _inFavor);
    }

    /**
     * @notice Tally votes. Release funds if quorum met and majority in favor.
     * @param _campaignId Campaign identifier.
     * @param _milestoneIndex Milestone index.
     */
    function tallyMilestoneVote(uint256 _campaignId, uint256 _milestoneIndex)
        external
        campaignFunded(_campaignId)
        nonReentrant
    {
        Campaign storage c = campaigns[_campaignId];
        CampaignMilestone storage m = campaignMilestones[_campaignId][_milestoneIndex];
        require(m.status == MilestoneStatus.Pending, "CommunityFundraising: not pending");

        uint256 totalVotes = m.votesFor + m.votesAgainst;
        uint256 quorumRequired = (c.contributorCount * voteQuorumPercent) / 100;
        require(totalVotes >= quorumRequired, "CommunityFundraising: quorum not met");

        if (m.votesFor > m.votesAgainst) {
            m.status = MilestoneStatus.Verified;
            uint256 amount = m.releaseAmount;
            c.totalReleased += amount;

            (bool sent, ) = c.recipient.call{value: amount}("");
            require(sent, "CommunityFundraising: transfer failed");

            emit MilestoneVerified(_campaignId, _milestoneIndex, VerificationMethod.ContributorVote);
            emit FundsReleased(_campaignId, c.recipient, amount);

            if (c.totalReleased >= c.totalRaised) {
                c.status = CampaignStatus.Completed;
                emit CampaignCompleted(_campaignId);
            }
        } else {
            m.status = MilestoneStatus.Rejected;
            emit MilestoneRejected(_campaignId, _milestoneIndex);
        }
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    /// @notice Update oracle address.
    function setOracle(address _oracle) external onlyOwner {
        oracleAddress = _oracle;
        emit OracleUpdated(_oracle);
    }

    /// @notice Update vote quorum percentage.
    function setVoteQuorum(uint256 _percent) external onlyOwner {
        require(_percent > 0 && _percent <= 100, "CommunityFundraising: invalid quorum");
        voteQuorumPercent = _percent;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    function getCampaign(uint256 _id) external view returns (Campaign memory) {
        return campaigns[_id];
    }

    function getMilestone(uint256 _campaignId, uint256 _idx) external view returns (CampaignMilestone memory) {
        return campaignMilestones[_campaignId][_idx];
    }

    function getContribution(uint256 _campaignId, address _contributor) external view returns (uint256) {
        return contributions[_campaignId][_contributor];
    }

    receive() external payable {}
}
