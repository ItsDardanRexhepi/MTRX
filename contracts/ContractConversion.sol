// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ContractConversion
 * @notice Component 1 - Smart Contract Conversion Service
 * @dev Converts natural-language contracts into enforceable on-chain agreements
 *      with tiered revenue sharing routed to the NeoSafe wallet.
 *
 * Revenue-share schedule (sent to NeoSafe):
 *   Tier 1  (<2 ETH rolling 12-month revenue)  -> 10 %
 *   Tier 2  (2-5 ETH)                           ->  5 %
 *   Tier 3  (>5 ETH)                            ->  2.5 %
 *
 * A flat 2.5 % Platform Access Contribution (PAC) is levied on ALL tiers
 * in perpetuity and routed to NeoSafe on every revenue event.
 *
 * Tier advancement is PERMANENT - once a user reaches a higher tier they
 * can never drop back, even if rolling revenue later decreases.
 */
contract ContractConversion is Ownable, ReentrancyGuard {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice The NeoSafe multi-sig that receives all revenue shares.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Tier-1 revenue share in basis points (10 %).
    uint256 public constant TIER1_SHARE_BPS = 1000;

    /// @notice Tier-2 revenue share in basis points (5 %).
    uint256 public constant TIER2_SHARE_BPS = 500;

    /// @notice Tier-3 revenue share in basis points (2.5 %).
    uint256 public constant TIER3_SHARE_BPS = 250;

    /// @notice Platform Access Contribution in basis points (2.5 %).
    uint256 public constant PAC_BPS = 250;

    /// @notice Tier-1 ceiling: cumulative < 2 ETH.
    uint256 public constant TIER1_CEILING = 2 ether;

    /// @notice Tier-2 ceiling: cumulative < 5 ETH.
    uint256 public constant TIER2_CEILING = 5 ether;

    /// @notice Duration of the rolling revenue window (365 days).
    uint256 public constant ROLLING_WINDOW = 365 days;

    /// @notice Denominator for basis-point arithmetic.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ----------------------------------------------------------------
    // Enums
    // ----------------------------------------------------------------

    enum Tier {
        TIER_1,
        TIER_2,
        TIER_3
    }

    enum ArtistClassification {
        UNCLASSIFIED,
        MUSICIAN,
        PHOTOGRAPHER,
        GRAPHIC_DESIGNER,
        PAINTER,
        SCULPTOR,
        WRITER,
        FILMMAKER,
        YOUTUBER,
        PODCASTER,
        DANCER,
        ILLUSTRATOR,
        ANIMATOR,
        ARCHITECT,
        GAME_DESIGNER,
        FASHION_DESIGNER,
        OTHER_CREATIVE
    }

    // ----------------------------------------------------------------
    // Structs
    // ----------------------------------------------------------------

    struct UserTier {
        uint256 cumulativeRevenue;
        Tier currentTier;
        uint256 tierLockedAt;
        bool isArtist;
        ArtistClassification classification;
    }

    struct RevenueRecord {
        uint256 amount;
        uint256 timestamp;
    }

    struct DeployedContract {
        address creator;
        address contractAddress;
        uint256 deployedAt;
        bytes32 documentHash;
        bool active;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Rexhepi gate address authorised to call gated functions.
    address public rexhepiGate;

    /// @notice Per-user tier information.
    mapping(address => UserTier) public userTiers;

    /// @notice Per-user revenue history for rolling-window calculations.
    mapping(address => RevenueRecord[]) private _revenueHistory;

    /// @notice Registry of all contracts deployed through this service.
    mapping(bytes32 => DeployedContract) public deployedContracts;

    /// @notice Running counter used to build unique contract identifiers.
    uint256 public contractCount;

    /// @notice Total revenue routed to NeoSafe over the contract lifetime.
    uint256 public totalRoutedToNeoSafe;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event ContractDeployed(
        bytes32 indexed contractId,
        address indexed creator,
        address contractAddress,
        bytes32 documentHash,
        uint256 timestamp
    );

    event RevenueRecorded(
        address indexed user,
        uint256 amount,
        Tier tier,
        uint256 tierShare,
        uint256 pacShare,
        uint256 timestamp
    );

    event TierAdvanced(
        address indexed user,
        Tier previousTier,
        Tier newTier,
        uint256 cumulativeRevenue,
        uint256 timestamp
    );

    event FundsRouted(
        address indexed from,
        uint256 tierShareAmount,
        uint256 pacAmount,
        uint256 totalAmount,
        uint256 timestamp
    );

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    /**
     * @notice Restricts a function so that only the authorised Rexhepi
     *         gate address may call it.
     */
    modifier onlyThroughRexhepiGate() {
        require(
            msg.sender == rexhepiGate,
            "ContractConversion: caller is not the Rexhepi gate"
        );
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param _rexhepiGate The address authorised to call gated functions.
     */
    constructor(address _rexhepiGate) Ownable(msg.sender) {
        require(
            _rexhepiGate != address(0),
            "ContractConversion: gate cannot be zero address"
        );
        rexhepiGate = _rexhepiGate;
    }

    // ----------------------------------------------------------------
    // External / Public Functions
    // ----------------------------------------------------------------

    /**
     * @notice Deploy a new on-chain contract derived from a parsed document.
     * @param _contractAddress Address of the newly deployed child contract.
     * @param _documentHash    keccak256 hash of the original document.
     * @return contractId      Unique identifier for the deployment record.
     */
    function deployContract(
        address _contractAddress,
        bytes32 _documentHash
    )
        external
        onlyThroughRexhepiGate
        nonReentrant
        returns (bytes32 contractId)
    {
        require(
            _contractAddress != address(0),
            "ContractConversion: contract address cannot be zero"
        );
        require(
            _documentHash != bytes32(0),
            "ContractConversion: document hash cannot be zero"
        );

        contractCount++;
        contractId = keccak256(
            abi.encodePacked(msg.sender, _contractAddress, contractCount)
        );

        require(
            deployedContracts[contractId].creator == address(0),
            "ContractConversion: contract ID collision"
        );

        deployedContracts[contractId] = DeployedContract({
            creator: msg.sender,
            contractAddress: _contractAddress,
            deployedAt: block.timestamp,
            documentHash: _documentHash,
            active: true
        });

        // Initialise the creator's tier if not already present.
        if (userTiers[msg.sender].tierLockedAt == 0) {
            userTiers[msg.sender] = UserTier({
                cumulativeRevenue: 0,
                currentTier: Tier.TIER_1,
                tierLockedAt: block.timestamp,
                isArtist: false,
                classification: ArtistClassification.UNCLASSIFIED
            });
        }

        emit ContractDeployed(
            contractId,
            msg.sender,
            _contractAddress,
            _documentHash,
            block.timestamp
        );
    }

    /**
     * @notice Record revenue for a user, enforce tier share + PAC, and
     *         route the combined amount to NeoSafe.
     * @param _user The address earning the revenue.
     */
    function recordRevenue(
        address _user
    ) external payable onlyThroughRexhepiGate nonReentrant {
        require(msg.value > 0, "ContractConversion: revenue must be > 0");
        require(
            _user != address(0),
            "ContractConversion: user cannot be zero address"
        );

        // --- Update cumulative revenue ------------------------------------
        userTiers[_user].cumulativeRevenue += msg.value;
        _revenueHistory[_user].push(
            RevenueRecord({amount: msg.value, timestamp: block.timestamp})
        );

        // --- Check for tier advancement -----------------------------------
        _checkAndAdvanceTier(_user);

        // --- Calculate shares ---------------------------------------------
        Tier tier = userTiers[_user].currentTier;
        uint256 tierShare = calculateTierShare(_user, msg.value);
        uint256 pacShare = calculatePlatformContribution(msg.value);
        uint256 totalShare = tierShare + pacShare;

        require(
            totalShare <= msg.value,
            "ContractConversion: share exceeds revenue"
        );

        // --- Route to NeoSafe ---------------------------------------------
        _routeToNeoSafe(totalShare, _user, tierShare, pacShare);

        // --- Forward remainder to user ------------------------------------
        uint256 remainder = msg.value - totalShare;
        if (remainder > 0) {
            (bool sent, ) = payable(_user).call{value: remainder}("");
            require(sent, "ContractConversion: failed to send remainder");
        }

        emit RevenueRecorded(
            _user,
            msg.value,
            tier,
            tierShare,
            pacShare,
            block.timestamp
        );
    }

    /**
     * @notice Calculate the tier-based revenue share for a given amount.
     * @param _user   The user whose tier determines the rate.
     * @param _amount The revenue amount in wei.
     * @return share  The tier share in wei.
     */
    function calculateTierShare(
        address _user,
        uint256 _amount
    ) public view returns (uint256 share) {
        Tier tier = userTiers[_user].currentTier;
        uint256 bps;
        if (tier == Tier.TIER_1) {
            bps = TIER1_SHARE_BPS;
        } else if (tier == Tier.TIER_2) {
            bps = TIER2_SHARE_BPS;
        } else {
            bps = TIER3_SHARE_BPS;
        }
        share = (_amount * bps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculate the flat 2.5 % Platform Access Contribution.
     * @param _amount The revenue amount in wei.
     * @return contribution The PAC amount in wei.
     */
    function calculatePlatformContribution(
        uint256 _amount
    ) public pure returns (uint256 contribution) {
        contribution = (_amount * PAC_BPS) / BPS_DENOMINATOR;
    }

    /**
     * @notice Manually trigger a tier advancement check for a user.
     * @param _user The user to evaluate.
     */
    function advanceTier(address _user) external onlyThroughRexhepiGate {
        _checkAndAdvanceTier(_user);
    }

    /**
     * @notice Return the rolling 12-month cumulative revenue for a user.
     * @param _user The address to query.
     * @return total The revenue accumulated in the last 365 days.
     */
    function getRolling12MonthRevenue(
        address _user
    ) external view returns (uint256 total) {
        uint256 cutoff = block.timestamp - ROLLING_WINDOW;
        RevenueRecord[] storage records = _revenueHistory[_user];
        for (uint256 i = 0; i < records.length; i++) {
            if (records[i].timestamp >= cutoff) {
                total += records[i].amount;
            }
        }
    }

    /**
     * @notice Set the artist classification for a user.
     * @param _user           The user to classify.
     * @param _isArtist       Whether the user qualifies as an artist.
     * @param _classification The specific creative category.
     */
    function setArtistClassification(
        address _user,
        bool _isArtist,
        ArtistClassification _classification
    ) external onlyThroughRexhepiGate {
        userTiers[_user].isArtist = _isArtist;
        userTiers[_user].classification = _classification;
    }

    /**
     * @notice Update the Rexhepi gate address. Owner-only.
     * @param _newGate The new gate address.
     */
    function setRexhepiGate(address _newGate) external onlyOwner {
        require(
            _newGate != address(0),
            "ContractConversion: gate cannot be zero address"
        );
        rexhepiGate = _newGate;
    }

    // ----------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------

    /**
     * @dev Evaluate whether the user qualifies for a higher tier and
     *      advance them if so.  Advancement is PERMANENT.
     */
    function _checkAndAdvanceTier(address _user) internal {
        UserTier storage ut = userTiers[_user];
        Tier previous = ut.currentTier;

        // Calculate rolling 12-month revenue for tier evaluation.
        uint256 rollingRevenue = this.getRolling12MonthRevenue(_user);

        Tier newTier;
        if (rollingRevenue > TIER2_CEILING) {
            newTier = Tier.TIER_3;
        } else if (rollingRevenue >= TIER1_CEILING) {
            newTier = Tier.TIER_2;
        } else {
            newTier = Tier.TIER_1;
        }

        // Only advance - never drop.
        if (newTier > previous) {
            ut.currentTier = newTier;
            ut.tierLockedAt = block.timestamp;

            emit TierAdvanced(
                _user,
                previous,
                newTier,
                rollingRevenue,
                block.timestamp
            );
        }
    }

    /**
     * @dev Transfer the combined tier + PAC share to the NeoSafe wallet.
     */
    function _routeToNeoSafe(
        uint256 _total,
        address _from,
        uint256 _tierShare,
        uint256 _pacShare
    ) internal {
        require(_total > 0, "ContractConversion: nothing to route");

        totalRoutedToNeoSafe += _total;

        (bool sent, ) = payable(NEOSAFE).call{value: _total}("");
        require(sent, "ContractConversion: failed to route to NeoSafe");

        emit FundsRouted(
            _from,
            _tierShare,
            _pacShare,
            _total,
            block.timestamp
        );
    }

    // ----------------------------------------------------------------
    // Receive / Fallback
    // ----------------------------------------------------------------

    receive() external payable {}
    fallback() external payable {}
}
