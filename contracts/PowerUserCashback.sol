// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PowerUserCashback
 * @notice Annual 1% net revenue cashback for power users ($10k+ spend) on Base.
 * @dev Users who spend $10,000 or more (in USD-equivalent) within a calendar
 *      year qualify for a 1% cashback on net platform revenue attributable
 *      to their activity.
 *
 *      Distribution schedule:
 *        - Rewards are calculated for the prior calendar year.
 *        - Distribution occurs on January 15 of the following year.
 *        - Platform owner funds the reward pool before distribution.
 *        - Users must claim within 90 days or rewards are forfeited.
 *
 *      The $10k threshold is measured in USD (with 18 decimals internally).
 */
contract PowerUserCashback is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Cashback rate in basis points (1% = 100 bps).
    uint256 public constant CASHBACK_BPS = 100;

    /// @notice Basis-point denominator.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Minimum annual spend threshold ($10,000 with 18 decimals).
    uint256 public constant THRESHOLD_USD = 10_000e18;

    /// @notice Claim window after distribution (90 days).
    uint256 public constant CLAIM_WINDOW = 90 days;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    struct YearlyDistribution {
        uint256 rewardPoolBalance;    // Total funded reward pool for this year
        uint256 totalClaimed;         // Total claimed so far
        uint256 distributionTimestamp;// When distribution was enabled (Jan 15)
        bool funded;                  // Whether the reward pool has been funded
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Payment token for cashback (e.g. USDC).
    IERC20 public immutable rewardToken;

    /// @notice Year => distribution details.
    mapping(uint256 => YearlyDistribution) public distributions;

    /// @notice Year => user => total USD spend recorded.
    mapping(uint256 => mapping(address => uint256)) public userYearlySpend;

    /// @notice Year => user => net revenue attributable to user.
    mapping(uint256 => mapping(address => uint256)) public userNetRevenue;

    /// @notice Year => user => reward amount allocated.
    mapping(uint256 => mapping(address => uint256)) public userReward;

    /// @notice Year => user => whether reward has been claimed.
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @notice Authorised spend recorders (platform services).
    mapping(address => bool) public isRecorder;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event SpendRecorded(address indexed user, uint256 indexed year, uint256 amountUSD);
    event NetRevenueRecorded(address indexed user, uint256 indexed year, uint256 amount);
    event RewardAllocated(address indexed user, uint256 indexed year, uint256 reward);
    event DistributionFunded(uint256 indexed year, uint256 amount);
    event DistributionEnabled(uint256 indexed year, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 indexed year, uint256 amount);
    event UnclaimedForfeited(uint256 indexed year, uint256 amount);
    event RecorderAdded(address indexed recorder);
    event RecorderRemoved(address indexed recorder);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotRecorder();
    error BelowThreshold();
    error NotDistributed();
    error AlreadyClaimed();
    error ClaimWindowExpired();
    error NoReward();
    error NotFunded();
    error AlreadyFunded();
    error ZeroAddress();
    error ZeroAmount();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyRecorder() {
        if (!isRecorder[msg.sender] && msg.sender != owner()) revert NotRecorder();
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param rewardToken_ ERC-20 token used for cashback payments (e.g. USDC).
     */
    constructor(address rewardToken_) Ownable(msg.sender) {
        if (rewardToken_ == address(0)) revert ZeroAddress();
        rewardToken = IERC20(rewardToken_);
    }

    // ----------------------------------------------------------------
    // Spend Recording
    // ----------------------------------------------------------------

    /**
     * @notice Record a user's USD-equivalent spend on the platform.
     * @param user      The user address.
     * @param year      The calendar year.
     * @param amountUSD The spend amount in USD (18 decimals).
     */
    function recordSpend(address user, uint256 year, uint256 amountUSD)
        external
        onlyRecorder
    {
        if (user == address(0)) revert ZeroAddress();
        if (amountUSD == 0) revert ZeroAmount();

        userYearlySpend[year][user] += amountUSD;
        emit SpendRecorded(user, year, amountUSD);
    }

    /**
     * @notice Record net revenue attributable to a user.
     * @param user   The user address.
     * @param year   The calendar year.
     * @param amount Net revenue amount in reward token denomination.
     */
    function recordNetRevenue(address user, uint256 year, uint256 amount)
        external
        onlyRecorder
    {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        userNetRevenue[year][user] += amount;
        emit NetRevenueRecorded(user, year, amount);
    }

    // ----------------------------------------------------------------
    // Reward Allocation
    // ----------------------------------------------------------------

    /**
     * @notice Allocate a reward for a qualifying user.
     * @dev Called by the owner after the year ends. User must have >= $10k spend.
     *      Reward = 1% of their net revenue contribution.
     * @param user The user to allocate rewards for.
     * @param year The calendar year.
     */
    function allocateReward(address user, uint256 year) external onlyOwner {
        if (userYearlySpend[year][user] < THRESHOLD_USD) revert BelowThreshold();

        uint256 netRev = userNetRevenue[year][user];
        uint256 reward = (netRev * CASHBACK_BPS) / BPS_DENOMINATOR;

        userReward[year][user] = reward;
        emit RewardAllocated(user, year, reward);
    }

    /**
     * @notice Batch allocate rewards for multiple users.
     * @param users Array of user addresses.
     * @param year  The calendar year.
     */
    function batchAllocateRewards(address[] calldata users, uint256 year) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            if (userYearlySpend[year][users[i]] >= THRESHOLD_USD) {
                uint256 netRev = userNetRevenue[year][users[i]];
                uint256 reward = (netRev * CASHBACK_BPS) / BPS_DENOMINATOR;
                userReward[year][users[i]] = reward;
                emit RewardAllocated(users[i], year, reward);
            }
        }
    }

    // ----------------------------------------------------------------
    // Distribution Funding & Enabling
    // ----------------------------------------------------------------

    /**
     * @notice Fund the reward pool for a given year.
     * @param year   The calendar year.
     * @param amount Amount of reward tokens to deposit.
     */
    function fundDistribution(uint256 year, uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        YearlyDistribution storage dist = distributions[year];
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        dist.rewardPoolBalance += amount;
        dist.funded = true;

        emit DistributionFunded(year, amount);
    }

    /**
     * @notice Enable distribution for a given year (target: January 15).
     * @param year The calendar year whose rewards are being distributed.
     */
    function enableDistribution(uint256 year) external onlyOwner {
        YearlyDistribution storage dist = distributions[year];
        if (!dist.funded) revert NotFunded();

        dist.distributionTimestamp = block.timestamp;
        emit DistributionEnabled(year, block.timestamp);
    }

    // ----------------------------------------------------------------
    // Claiming
    // ----------------------------------------------------------------

    /**
     * @notice Claim cashback reward for a given year.
     * @param year The calendar year.
     */
    function claimReward(uint256 year) external nonReentrant {
        YearlyDistribution storage dist = distributions[year];
        if (dist.distributionTimestamp == 0) revert NotDistributed();
        if (hasClaimed[year][msg.sender]) revert AlreadyClaimed();
        if (block.timestamp > dist.distributionTimestamp + CLAIM_WINDOW) {
            revert ClaimWindowExpired();
        }

        uint256 reward = userReward[year][msg.sender];
        if (reward == 0) revert NoReward();

        hasClaimed[year][msg.sender] = true;
        dist.totalClaimed += reward;

        rewardToken.safeTransfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, year, reward);
    }

    /**
     * @notice Sweep unclaimed rewards after the claim window expires.
     * @param year The calendar year.
     */
    function sweepUnclaimed(uint256 year) external onlyOwner {
        YearlyDistribution storage dist = distributions[year];
        if (dist.distributionTimestamp == 0) revert NotDistributed();
        if (block.timestamp <= dist.distributionTimestamp + CLAIM_WINDOW) {
            revert ClaimWindowExpired();
        }

        uint256 unclaimed = dist.rewardPoolBalance - dist.totalClaimed;
        if (unclaimed > 0) {
            dist.rewardPoolBalance = dist.totalClaimed;
            rewardToken.safeTransfer(NEOSAFE, unclaimed);
            emit UnclaimedForfeited(year, unclaimed);
        }
    }

    // ----------------------------------------------------------------
    // Recorder Management
    // ----------------------------------------------------------------

    function addRecorder(address recorder) external onlyOwner {
        if (recorder == address(0)) revert ZeroAddress();
        isRecorder[recorder] = true;
        emit RecorderAdded(recorder);
    }

    function removeRecorder(address recorder) external onlyOwner {
        isRecorder[recorder] = false;
        emit RecorderRemoved(recorder);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    function isQualified(address user, uint256 year) external view returns (bool) {
        return userYearlySpend[year][user] >= THRESHOLD_USD;
    }

    function getReward(address user, uint256 year) external view returns (uint256) {
        return userReward[year][user];
    }
}
