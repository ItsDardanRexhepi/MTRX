// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GameRevenue
 * @author MTRX Protocol
 * @notice Immutable revenue-split contract for games on Base.
 * @dev 80% of all revenue goes to the developer, 20% to NeoSafe.
 *      The developer permanently owns 100% of the game itself.
 *      This contract is intentionally immutable -- no owner, no upgrades,
 *      no parameter changes. Once deployed, the split is permanent.
 */
contract GameRevenue is ReentrancyGuard {
    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @notice NeoSafe treasury on Base
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Developer revenue share (80%)
    uint256 public constant DEVELOPER_SHARE_BPS = 8000;

    /// @notice Platform revenue share (20%)
    uint256 public constant PLATFORM_SHARE_BPS = 2000;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    // -----------------------------------------------------------------------
    // Immutable State
    // -----------------------------------------------------------------------

    /// @notice Developer wallet -- set once at deploy, never changes
    address public immutable developer;

    /// @notice Game identifier for reference
    uint256 public immutable gameId;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice Total revenue received by this contract
    uint256 public totalRevenue;

    /// @notice Total amount distributed to the developer
    uint256 public totalDeveloperPaid;

    /// @notice Total amount distributed to NeoSafe
    uint256 public totalPlatformPaid;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted when revenue is received and distributed
    event RevenueDistributed(
        uint256 indexed gameId,
        uint256 totalAmount,
        uint256 developerAmount,
        uint256 platformAmount
    );

    /// @notice Emitted when ETH is received
    event RevenueReceived(uint256 indexed gameId, address indexed sender, uint256 amount);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /**
     * @notice Deploy an immutable revenue split for a game.
     * @param _developer Developer wallet address (permanent owner of the game).
     * @param _gameId Unique game identifier for event tracking.
     */
    constructor(address _developer, uint256 _gameId) {
        require(_developer != address(0), "GameRevenue: zero developer");
        developer = _developer;
        gameId = _gameId;
    }

    // -----------------------------------------------------------------------
    // Revenue Distribution
    // -----------------------------------------------------------------------

    /**
     * @notice Receive ETH and automatically split 80/20.
     * @dev Called when ETH is sent directly to the contract.
     */
    receive() external payable {
        _distribute(msg.value);
    }

    /**
     * @notice Explicit function to deposit and distribute revenue.
     */
    function depositRevenue() external payable {
        require(msg.value > 0, "GameRevenue: zero value");
        _distribute(msg.value);
    }

    /**
     * @notice Distribute any ETH balance that was sent without triggering receive.
     * @dev Safety function in case ETH arrives via selfdestruct or coinbase.
     */
    function distributeBalance() external nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "GameRevenue: no balance");
        _distribute(balance);
    }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    /// @notice Returns cumulative distribution stats.
    function getStats()
        external
        view
        returns (
            uint256 _totalRevenue,
            uint256 _totalDeveloperPaid,
            uint256 _totalPlatformPaid,
            address _developer
        )
    {
        return (totalRevenue, totalDeveloperPaid, totalPlatformPaid, developer);
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    /**
     * @dev Core distribution logic. Splits incoming ETH 80/20.
     * @param _amount Amount of ETH to distribute.
     */
    function _distribute(uint256 _amount) internal nonReentrant {
        require(_amount > 0, "GameRevenue: nothing to distribute");

        uint256 devShare = (_amount * DEVELOPER_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 platformShare = _amount - devShare;

        totalRevenue += _amount;
        totalDeveloperPaid += devShare;
        totalPlatformPaid += platformShare;

        emit RevenueReceived(gameId, msg.sender, _amount);

        (bool s1, ) = developer.call{value: devShare}("");
        require(s1, "GameRevenue: dev transfer failed");

        (bool s2, ) = NEOSAFE.call{value: platformShare}("");
        require(s2, "GameRevenue: platform transfer failed");

        emit RevenueDistributed(gameId, _amount, devShare, platformShare);
    }
}
