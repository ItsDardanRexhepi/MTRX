// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BrandRewards
 * @notice Zero platform commission brand loyalty rewards with ZKP eligibility on Base.
 * @dev Brands create reward programs with fully brand-controlled terms.
 *      The platform takes ZERO commission -- 100% of rewards go to users.
 *
 *      ZKP eligibility:
 *        - Brands can require a zero-knowledge proof (ZKP) of eligibility.
 *        - A designated ZKP verifier contract validates proofs on-chain.
 *        - This preserves user privacy while enforcing brand criteria.
 *
 *      Architecture:
 *        - Brands create campaigns and fund them with reward tokens.
 *        - Users claim rewards by proving eligibility (direct or ZKP).
 *        - Brands control all terms: eligibility, limits, expiry.
 *        - Platform takes 0% of reward distributions.
 */
/// @dev Interface for the external ZKP verifier.
interface IZKPVerifier {
    function verifyProof(
        address user,
        uint256 campaignId,
        bytes calldata proof
    ) external view returns (bool);
}

contract BrandRewards is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Platform commission: ZERO. Immutable.
    uint256 public constant PLATFORM_FEE_BPS = 0;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    enum CampaignStatus { Active, Paused, Completed, Cancelled }
    enum EligibilityMode { Open, Allowlist, ZKP }

    struct Campaign {
        address brand;
        address rewardToken;
        uint256 totalBudget;
        uint256 distributed;
        uint256 rewardPerUser;        // Fixed amount per eligible claim
        uint256 maxClaims;            // 0 = unlimited
        uint256 totalClaims;
        uint256 startTime;
        uint256 endTime;
        EligibilityMode eligibilityMode;
        address zkpVerifier;          // ZKP verifier contract (for ZKP mode)
        CampaignStatus status;
        string termsURI;              // Brand-controlled terms (IPFS)
        string metadataURI;           // Campaign metadata
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    uint256 public nextCampaignId;

    mapping(uint256 => Campaign) public campaigns;

    /// @notice Campaign => user => has claimed.
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @notice Campaign => user => is allowlisted.
    mapping(uint256 => mapping(address => bool)) public isAllowlisted;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event CampaignCreated(uint256 indexed campaignId, address indexed brand, address rewardToken, uint256 totalBudget, EligibilityMode mode);
    event CampaignFunded(uint256 indexed campaignId, uint256 amount);
    event RewardClaimed(uint256 indexed campaignId, address indexed user, uint256 amount);
    event CampaignPaused(uint256 indexed campaignId);
    event CampaignResumed(uint256 indexed campaignId);
    event CampaignCompleted(uint256 indexed campaignId);
    event CampaignCancelled(uint256 indexed campaignId, uint256 refundAmount);
    event AllowlistUpdated(uint256 indexed campaignId, address indexed user, bool eligible);
    event ZKPVerifierUpdated(uint256 indexed campaignId, address indexed verifier);
    event TermsUpdated(uint256 indexed campaignId, string termsURI);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotBrand();
    error CampaignNotActive();
    error CampaignExpired();
    error CampaignNotStarted();
    error AlreadyClaimed();
    error NotEligible();
    error MaxClaimsReached();
    error InsufficientBudget();
    error InvalidZKPProof();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidTimeRange();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyBrand(uint256 campaignId) {
        if (msg.sender != campaigns[campaignId].brand) revert NotBrand();
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // ----------------------------------------------------------------
    // Campaign Management
    // ----------------------------------------------------------------

    /**
     * @notice Create a brand reward campaign.
     * @param rewardToken     ERC-20 token for rewards.
     * @param rewardPerUser   Fixed reward per eligible claim.
     * @param maxClaims       Maximum total claims (0 = unlimited).
     * @param startTime       Campaign start timestamp.
     * @param endTime         Campaign end timestamp.
     * @param eligibilityMode Open, Allowlist, or ZKP.
     * @param zkpVerifier     ZKP verifier contract (required for ZKP mode).
     * @param termsURI        URI to brand-controlled terms.
     * @param metadataURI     URI to campaign metadata.
     * @param initialFunding  Initial reward token funding.
     * @return campaignId     The campaign ID.
     */
    function createCampaign(
        address rewardToken,
        uint256 rewardPerUser,
        uint256 maxClaims,
        uint256 startTime,
        uint256 endTime,
        EligibilityMode eligibilityMode,
        address zkpVerifier,
        string calldata termsURI,
        string calldata metadataURI,
        uint256 initialFunding
    ) external whenNotPaused returns (uint256 campaignId) {
        if (rewardToken == address(0)) revert ZeroAddress();
        if (rewardPerUser == 0) revert ZeroAmount();
        if (endTime <= startTime) revert InvalidTimeRange();
        if (eligibilityMode == EligibilityMode.ZKP && zkpVerifier == address(0)) {
            revert ZeroAddress();
        }

        campaignId = nextCampaignId++;

        campaigns[campaignId] = Campaign({
            brand: msg.sender,
            rewardToken: rewardToken,
            totalBudget: 0,
            distributed: 0,
            rewardPerUser: rewardPerUser,
            maxClaims: maxClaims,
            totalClaims: 0,
            startTime: startTime,
            endTime: endTime,
            eligibilityMode: eligibilityMode,
            zkpVerifier: zkpVerifier,
            status: CampaignStatus.Active,
            termsURI: termsURI,
            metadataURI: metadataURI
        });

        emit CampaignCreated(campaignId, msg.sender, rewardToken, 0, eligibilityMode);

        if (initialFunding > 0) {
            _fundCampaign(campaignId, initialFunding);
        }
    }

    /**
     * @notice Add funds to a campaign.
     * @param campaignId Campaign to fund.
     * @param amount     Amount of reward tokens to add.
     */
    function fundCampaign(uint256 campaignId, uint256 amount) external onlyBrand(campaignId) {
        _fundCampaign(campaignId, amount);
    }

    function _fundCampaign(uint256 campaignId, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        Campaign storage c = campaigns[campaignId];
        IERC20(c.rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        c.totalBudget += amount;
        emit CampaignFunded(campaignId, amount);
    }

    // ----------------------------------------------------------------
    // Allowlist Management
    // ----------------------------------------------------------------

    /**
     * @notice Add or remove users from the allowlist.
     * @param campaignId Campaign ID.
     * @param users      Array of user addresses.
     * @param eligible   Array of eligibility flags.
     */
    function updateAllowlist(
        uint256 campaignId,
        address[] calldata users,
        bool[] calldata eligible
    ) external onlyBrand(campaignId) {
        require(users.length == eligible.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            isAllowlisted[campaignId][users[i]] = eligible[i];
            emit AllowlistUpdated(campaignId, users[i], eligible[i]);
        }
    }

    /// @notice Update the ZKP verifier contract.
    function updateZKPVerifier(uint256 campaignId, address verifier)
        external
        onlyBrand(campaignId)
    {
        if (verifier == address(0)) revert ZeroAddress();
        campaigns[campaignId].zkpVerifier = verifier;
        emit ZKPVerifierUpdated(campaignId, verifier);
    }

    /// @notice Update brand terms URI.
    function updateTerms(uint256 campaignId, string calldata termsURI)
        external
        onlyBrand(campaignId)
    {
        campaigns[campaignId].termsURI = termsURI;
        emit TermsUpdated(campaignId, termsURI);
    }

    // ----------------------------------------------------------------
    // Reward Claiming
    // ----------------------------------------------------------------

    /**
     * @notice Claim a reward (Open or Allowlist mode).
     * @param campaignId Campaign to claim from.
     */
    function claimReward(uint256 campaignId) external nonReentrant whenNotPaused {
        Campaign storage c = campaigns[campaignId];
        _validateClaim(c, campaignId);

        if (c.eligibilityMode == EligibilityMode.Allowlist) {
            if (!isAllowlisted[campaignId][msg.sender]) revert NotEligible();
        }
        // Open mode: anyone can claim

        _executeClaim(campaignId, c);
    }

    /**
     * @notice Claim a reward with ZKP proof.
     * @param campaignId Campaign to claim from.
     * @param proof      The zero-knowledge proof bytes.
     */
    function claimRewardWithZKP(uint256 campaignId, bytes calldata proof)
        external
        nonReentrant
        whenNotPaused
    {
        Campaign storage c = campaigns[campaignId];
        _validateClaim(c, campaignId);

        if (c.eligibilityMode != EligibilityMode.ZKP) revert NotEligible();

        // Verify ZKP
        bool valid = IZKPVerifier(c.zkpVerifier).verifyProof(msg.sender, campaignId, proof);
        if (!valid) revert InvalidZKPProof();

        _executeClaim(campaignId, c);
    }

    function _validateClaim(Campaign storage c, uint256 campaignId) internal view {
        if (c.status != CampaignStatus.Active) revert CampaignNotActive();
        if (block.timestamp < c.startTime) revert CampaignNotStarted();
        if (block.timestamp >= c.endTime) revert CampaignExpired();
        if (hasClaimed[campaignId][msg.sender]) revert AlreadyClaimed();
        if (c.maxClaims > 0 && c.totalClaims >= c.maxClaims) revert MaxClaimsReached();
        if (c.distributed + c.rewardPerUser > c.totalBudget) revert InsufficientBudget();
    }

    function _executeClaim(uint256 campaignId, Campaign storage c) internal {
        hasClaimed[campaignId][msg.sender] = true;
        c.totalClaims++;
        c.distributed += c.rewardPerUser;

        // 100% to user -- ZERO platform commission
        IERC20(c.rewardToken).safeTransfer(msg.sender, c.rewardPerUser);

        emit RewardClaimed(campaignId, msg.sender, c.rewardPerUser);

        // Auto-complete if budget exhausted or max claims reached
        if (c.distributed >= c.totalBudget ||
            (c.maxClaims > 0 && c.totalClaims >= c.maxClaims)) {
            c.status = CampaignStatus.Completed;
            emit CampaignCompleted(campaignId);
        }
    }

    // ----------------------------------------------------------------
    // Brand Controls
    // ----------------------------------------------------------------

    function pauseCampaign(uint256 campaignId) external onlyBrand(campaignId) {
        campaigns[campaignId].status = CampaignStatus.Paused;
        emit CampaignPaused(campaignId);
    }

    function resumeCampaign(uint256 campaignId) external onlyBrand(campaignId) {
        campaigns[campaignId].status = CampaignStatus.Active;
        emit CampaignResumed(campaignId);
    }

    /**
     * @notice Cancel a campaign and refund remaining budget to the brand.
     */
    function cancelCampaign(uint256 campaignId) external onlyBrand(campaignId) nonReentrant {
        Campaign storage c = campaigns[campaignId];
        c.status = CampaignStatus.Cancelled;

        uint256 remaining = c.totalBudget - c.distributed;
        if (remaining > 0) {
            IERC20(c.rewardToken).safeTransfer(c.brand, remaining);
        }

        emit CampaignCancelled(campaignId, remaining);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        return campaigns[campaignId];
    }

    function isEligible(uint256 campaignId, address user) external view returns (bool) {
        Campaign storage c = campaigns[campaignId];
        if (hasClaimed[campaignId][user]) return false;
        if (c.eligibilityMode == EligibilityMode.Open) return true;
        if (c.eligibilityMode == EligibilityMode.Allowlist) return isAllowlisted[campaignId][user];
        // ZKP mode: cannot check on-chain without proof
        return false;
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
