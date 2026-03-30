// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title OpenMatrixStaking
 * @author MTRX Protocol
 * @notice Simple ETH staking on Base with an immutable 5% flat commission.
 * @dev 1 ETH minimum stake enforced. Commission is taken from rewards only.
 *      Stake/unstake freely. Rewards deposited by owner, distributed pro-rata.
 */
contract OpenMatrixStaking is ReentrancyGuard, Ownable, Pausable {

    /// @notice NeoSafe treasury on Base
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Immutable 5% commission on rewards (500 BPS)
    uint256 public constant COMMISSION_BPS = 500;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum stake of 1 ETH
    uint256 public constant MIN_STAKE = 1 ether;

    /// @notice Precision multiplier for reward-per-token accounting
    uint256 private constant PRECISION = 1e18;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice Total ETH currently staked
    uint256 public totalStaked;

    /// @notice Accumulated reward per staked wei (scaled by PRECISION)
    uint256 public rewardPerTokenStored;

    /// @notice Total rewards ever deposited
    uint256 public totalRewardsDeposited;

    /// @notice Total commission paid to NeoSafe
    uint256 public totalCommissionPaid;

    struct StakerInfo {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    /// @notice staker => info
    mapping(address => StakerInfo) public stakers;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted when a user stakes ETH
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user unstakes ETH
    event Unstaked(address indexed user, uint256 amount);

    /// @notice Emitted when rewards are deposited into the pool
    event RewardsDeposited(uint256 amount, uint256 commissionTaken);

    /// @notice Emitted when a user claims rewards
    event RewardsClaimed(address indexed user, uint256 amount);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    /// @dev Sync pending rewards for the given account before action.
    modifier updateRewards(address _account) {
        if (_account != address(0)) {
            StakerInfo storage info = stakers[_account];
            info.pendingRewards += _earned(_account);
            info.rewardDebt = rewardPerTokenStored;
        }
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // -----------------------------------------------------------------------
    // Staking
    // -----------------------------------------------------------------------

    /**
     * @notice Stake ETH. Minimum 1 ETH required.
     */
    function stake()
        external
        payable
        whenNotPaused
        updateRewards(msg.sender)
        nonReentrant
    {
        require(msg.value >= MIN_STAKE, "Staking: minimum 1 ETH");
        stakers[msg.sender].stakedAmount += msg.value;
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    /**
     * @notice Unstake a specified amount of ETH.
     * @param _amount Amount to unstake in wei.
     */
    function unstake(uint256 _amount)
        external
        updateRewards(msg.sender)
        nonReentrant
    {
        StakerInfo storage info = stakers[msg.sender];
        require(_amount > 0, "Staking: zero amount");
        require(info.stakedAmount >= _amount, "Staking: insufficient stake");

        uint256 remaining = info.stakedAmount - _amount;
        require(remaining == 0 || remaining >= MIN_STAKE, "Staking: remaining below minimum");

        info.stakedAmount -= _amount;
        totalStaked -= _amount;

        (bool sent, ) = msg.sender.call{value: _amount}("");
        require(sent, "Staking: ETH transfer failed");
        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @notice Claim all pending staking rewards.
     */
    function claimRewards()
        external
        updateRewards(msg.sender)
        nonReentrant
    {
        StakerInfo storage info = stakers[msg.sender];
        uint256 reward = info.pendingRewards;
        require(reward > 0, "Staking: no rewards");

        info.pendingRewards = 0;

        (bool sent, ) = msg.sender.call{value: reward}("");
        require(sent, "Staking: reward transfer failed");
        emit RewardsClaimed(msg.sender, reward);
    }

    // -----------------------------------------------------------------------
    // Reward Distribution (Owner)
    // -----------------------------------------------------------------------

    /**
     * @notice Deposit rewards into the pool. 5% commission goes to NeoSafe.
     * @dev Remaining 95% is distributed pro-rata to all current stakers.
     */
    function depositRewards() external payable onlyOwner nonReentrant {
        require(msg.value > 0, "Staking: zero rewards");
        require(totalStaked > 0, "Staking: no stakers");

        uint256 commission = (msg.value * COMMISSION_BPS) / BPS_DENOMINATOR;
        uint256 netRewards = msg.value - commission;

        totalRewardsDeposited += msg.value;
        totalCommissionPaid += commission;
        rewardPerTokenStored += (netRewards * PRECISION) / totalStaked;

        (bool sent, ) = NEOSAFE.call{value: commission}("");
        require(sent, "Staking: commission transfer failed");

        emit RewardsDeposited(msg.value, commission);
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    /// @notice Pause staking (emergency).
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause staking.
    function unpause() external onlyOwner { _unpause(); }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    /**
     * @notice Get total pending rewards for a staker.
     * @param _account Staker address.
     * @return Total claimable rewards in wei.
     */
    function pendingRewardsOf(address _account) external view returns (uint256) {
        return stakers[_account].pendingRewards + _earned(_account);
    }

    /**
     * @notice Get staker info.
     * @param _account Staker address.
     */
    function getStakerInfo(address _account) external view returns (StakerInfo memory) {
        return stakers[_account];
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    function _earned(address _account) internal view returns (uint256) {
        StakerInfo storage info = stakers[_account];
        return (info.stakedAmount * (rewardPerTokenStored - info.rewardDebt)) / PRECISION;
    }

    receive() external payable {}
}
