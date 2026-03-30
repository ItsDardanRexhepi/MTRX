// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LoyaltyRewards
 * @notice Smart Loyalty and Rewards contract for the MTRX platform.
 *         Supports platform-native rewards from treasury and business-deployed
 *         reward programs where the platform takes zero commission.
 * @dev Milestone volume thresholds are INJECTION POINTS to be configured by
 *      Dardan before production launch.
 */
contract LoyaltyRewards is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant PLATFORM_ADMIN_ROLE = keccak256("PLATFORM_ADMIN_ROLE");
    bytes32 public constant BUSINESS_DEPLOYER_ROLE = keccak256("BUSINESS_DEPLOYER_ROLE");
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");

    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    // =========================================================================
    //  INJECTION POINTS — Milestone Volume Thresholds
    //  Request actual threshold values from Dardan before production launch.
    // =========================================================================

    // INJECTION POINT: Request actual threshold values from Dardan before production launch
    uint256 public milestoneThresholdTier1 = 0; // Placeholder — set before launch
    // INJECTION POINT: Request actual threshold values from Dardan before production launch
    uint256 public milestoneThresholdTier2 = 0; // Placeholder — set before launch
    // INJECTION POINT: Request actual threshold values from Dardan before production launch
    uint256 public milestoneThresholdTier3 = 0; // Placeholder — set before launch
    // INJECTION POINT: Request actual threshold values from Dardan before production launch
    uint256 public milestoneThresholdTier4 = 0; // Placeholder — set before launch
    // INJECTION POINT: Request actual threshold values from Dardan before production launch
    uint256 public milestoneThresholdTier5 = 0; // Placeholder — set before launch

    // =========================================================================
    //  Platform Reward Triggers (on-chain activity via EAS Schema 348)
    // =========================================================================

    enum TriggerType {
        FIRST_TRANSACTION,
        FIRST_SMART_CONTRACT_DEPLOYED,
        FIRST_GOVERNANCE_VOTE,
        FIRST_DEFI_LOAN_REPAID,
        FIRST_NFT_MINTED,
        PLATFORM_ANNIVERSARY
    }

    struct PlatformReward {
        uint256 amount;
        TriggerType triggerType;
        uint256 distributedAt;
        bool claimed;
    }

    struct BusinessProgram {
        address business;
        string terms;
        uint256 rewardPool;
        bool active;
        uint256 createdAt;
        uint256 optInCount;
    }

    // user => trigger => fulfilled
    mapping(address => mapping(TriggerType => bool)) public triggerFulfilled;
    // user => rewards list
    mapping(address => PlatformReward[]) public userPlatformRewards;
    // program id => BusinessProgram
    mapping(uint256 => BusinessProgram) public businessPrograms;
    // user => program id => opted in
    mapping(address => mapping(uint256 => bool)) public userOptedIn;

    uint256 public nextProgramId;

    IERC20 public rewardToken;

    // =========================================================================
    //  Events
    // =========================================================================

    event PlatformRewardDistributed(address indexed user, TriggerType triggerType, uint256 amount);
    event BusinessProgramDeployed(uint256 indexed programId, address indexed business);
    event UserOptedIn(address indexed user, uint256 indexed programId);
    event UserOptedOut(address indexed user, uint256 indexed programId);
    event BusinessRewardDistributed(uint256 indexed programId, address indexed user, uint256 amount);
    event MilestoneThresholdUpdated(uint8 tier, uint256 newValue);

    // =========================================================================
    //  Constructor
    // =========================================================================

    constructor(address _rewardToken) {
        require(_rewardToken != address(0), "Invalid reward token");
        rewardToken = IERC20(_rewardToken);
        _grantRole(DEFAULT_ADMIN_ROLE, NEOSAFE);
        _grantRole(PLATFORM_ADMIN_ROLE, NEOSAFE);
        _grantRole(REWARD_DISTRIBUTOR_ROLE, NEOSAFE);
    }

    // =========================================================================
    //  Milestone Threshold Management (Injection Points)
    // =========================================================================

    /**
     * @notice Set milestone volume thresholds. Must be called before launch.
     * @dev INJECTION POINT: Request actual threshold values from Dardan before production launch
     */
    function setMilestoneThresholds(
        uint256 _tier1,
        uint256 _tier2,
        uint256 _tier3,
        uint256 _tier4,
        uint256 _tier5
    ) external onlyRole(PLATFORM_ADMIN_ROLE) {
        require(_tier1 < _tier2 && _tier2 < _tier3 && _tier3 < _tier4 && _tier4 < _tier5, "Non-ascending thresholds");
        milestoneThresholdTier1 = _tier1;
        milestoneThresholdTier2 = _tier2;
        milestoneThresholdTier3 = _tier3;
        milestoneThresholdTier4 = _tier4;
        milestoneThresholdTier5 = _tier5;
        emit MilestoneThresholdUpdated(1, _tier1);
        emit MilestoneThresholdUpdated(2, _tier2);
        emit MilestoneThresholdUpdated(3, _tier3);
        emit MilestoneThresholdUpdated(4, _tier4);
        emit MilestoneThresholdUpdated(5, _tier5);
    }

    // =========================================================================
    //  Platform Rewards — From Treasury, Zero Data Sharing
    // =========================================================================

    /**
     * @notice Distribute a platform-native reward based on verifiable on-chain trigger.
     * @param user The recipient wallet address.
     * @param triggerType The on-chain activity trigger.
     * @param amount The reward amount in reward token units.
     */
    function distributePlatformReward(
        address user,
        TriggerType triggerType,
        uint256 amount
    ) external onlyRole(REWARD_DISTRIBUTOR_ROLE) nonReentrant whenNotPaused {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Zero amount");
        require(!triggerFulfilled[user][triggerType], "Trigger already fulfilled");

        triggerFulfilled[user][triggerType] = true;

        userPlatformRewards[user].push(PlatformReward({
            amount: amount,
            triggerType: triggerType,
            distributedAt: block.timestamp,
            claimed: true
        }));

        rewardToken.safeTransfer(user, amount);
        emit PlatformRewardDistributed(user, triggerType, amount);
    }

    // =========================================================================
    //  Business Rewards — Platform Takes NOTHING
    // =========================================================================

    /**
     * @notice Business deploys own reward program, sets own terms.
     *         Platform takes ZERO commission. User data NEVER shared.
     */
    function deployBusinessProgram(
        string calldata terms,
        uint256 rewardPool
    ) external nonReentrant whenNotPaused returns (uint256 programId) {
        require(bytes(terms).length > 0, "Empty terms");
        require(rewardPool > 0, "Zero pool");

        programId = nextProgramId++;
        businessPrograms[programId] = BusinessProgram({
            business: msg.sender,
            terms: terms,
            rewardPool: rewardPool,
            active: true,
            createdAt: block.timestamp,
            optInCount: 0
        });

        // Business funds the reward pool — platform takes nothing
        rewardToken.safeTransferFrom(msg.sender, address(this), rewardPool);
        emit BusinessProgramDeployed(programId, msg.sender);
    }

    /**
     * @notice User opts into a business reward program.
     */
    function optInToProgram(uint256 programId) external whenNotPaused {
        BusinessProgram storage prog = businessPrograms[programId];
        require(prog.active, "Program inactive");
        require(!userOptedIn[msg.sender][programId], "Already opted in");

        userOptedIn[msg.sender][programId] = true;
        prog.optInCount++;
        emit UserOptedIn(msg.sender, programId);
    }

    /**
     * @notice User opts out of a business reward program.
     */
    function optOutOfProgram(uint256 programId) external {
        require(userOptedIn[msg.sender][programId], "Not opted in");
        userOptedIn[msg.sender][programId] = false;
        businessPrograms[programId].optInCount--;
        emit UserOptedOut(msg.sender, programId);
    }

    /**
     * @notice Distribute a business reward. Platform takes NOTHING.
     *         Only the owning business can distribute from their program.
     */
    function distributeBusinessReward(
        uint256 programId,
        address user,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        BusinessProgram storage prog = businessPrograms[programId];
        require(msg.sender == prog.business, "Not program owner");
        require(prog.active, "Program inactive");
        require(userOptedIn[user][programId], "User not opted in");
        require(amount <= prog.rewardPool, "Exceeds pool");

        prog.rewardPool -= amount;
        // 100% goes to user — platform takes ZERO
        rewardToken.safeTransfer(user, amount);
        emit BusinessRewardDistributed(programId, user, amount);
    }

    // =========================================================================
    //  View Functions
    // =========================================================================

    function getUserPlatformRewardCount(address user) external view returns (uint256) {
        return userPlatformRewards[user].length;
    }

    function isTriggerFulfilled(address user, TriggerType triggerType) external view returns (bool) {
        return triggerFulfilled[user][triggerType];
    }

    function getProgramDetails(uint256 programId) external view returns (BusinessProgram memory) {
        return businessPrograms[programId];
    }

    // =========================================================================
    //  Admin
    // =========================================================================

    function pause() external onlyRole(PLATFORM_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PLATFORM_ADMIN_ROLE) {
        _unpause();
    }
}
