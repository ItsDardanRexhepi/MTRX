// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title OpenMatrixDAO
 * @notice Component 6 - DAO Conversion and Management
 * @dev Enables autonomous business-to-DAO conversion with configurable
 *      governance rules. Conversion gas fees are covered 100% by the platform.
 *
 * Maintenance fee schedule (treasury-based, adjusts BOTH directions):
 *   New DAO conversions:
 *     $0   - $25M treasury   -> 2.0 % annually
 *     $25M - $50M treasury   -> 2.5 % annually
 *     $50M - $250M treasury  -> 5.0 % annually
 *     >$250M treasury        -> 10.0 % annually
 *
 *   Existing DAO onboarding:
 *     Onboarding fee: FREE
 *     Maintenance: 1.0 % flat annually (regardless of treasury size)
 *
 * Monthly fee routing: All fees route automatically to NeoSafe.
 * Fee boundary: Treasury fees ONLY. NOT additive with Component 1 fees.
 */
contract OpenMatrixDAO is Ownable, ReentrancyGuard {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice The NeoSafe multi-sig that receives all maintenance fees.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Basis-point denominator.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Treasury tier thresholds (in USD with 18 decimals).
    uint256 public constant TIER1_CEILING = 25_000_000e18;   // $25M
    uint256 public constant TIER2_CEILING = 50_000_000e18;   // $50M
    uint256 public constant TIER3_CEILING = 250_000_000e18;  // $250M

    /// @notice New-conversion maintenance fee rates (annual, basis points).
    uint256 public constant NEW_TIER1_BPS = 200;   // 2.0%
    uint256 public constant NEW_TIER2_BPS = 250;   // 2.5%
    uint256 public constant NEW_TIER3_BPS = 500;   // 5.0%
    uint256 public constant NEW_TIER4_BPS = 1000;  // 10.0%

    /// @notice Existing DAO flat annual maintenance rate (basis points).
    uint256 public constant EXISTING_DAO_BPS = 100; // 1.0%

    /// @notice Monthly divisor for annual-to-monthly fee calculation.
    uint256 public constant MONTHS_PER_YEAR = 12;

    // ----------------------------------------------------------------
    // Enums
    // ----------------------------------------------------------------

    enum DAOStatus {
        PENDING_CONVERSION,
        ACTIVE,
        SUSPENDED,
        DISSOLVED
    }

    enum DAOOrigin {
        NEW_CONVERSION,
        EXISTING_ONBOARDING
    }

    enum GovernanceModel {
        TOKEN_WEIGHTED,
        ONE_MEMBER_ONE_VOTE,
        QUADRATIC,
        DELEGATED,
        CUSTOM
    }

    // ----------------------------------------------------------------
    // Structs
    // ----------------------------------------------------------------

    struct GovernanceConfig {
        GovernanceModel model;
        uint256 proposalThresholdBps;   // min token % to create proposal
        uint256 quorumBps;              // min participation for validity
        uint256 votingPeriod;           // seconds
        uint256 executionDelay;         // timelock in seconds
        bool allowDelegation;
        string customRulesURI;          // IPFS URI for custom rules
    }

    struct DAORecord {
        bytes32 daoId;
        address creator;
        string name;
        DAOStatus status;
        DAOOrigin origin;
        GovernanceConfig governance;
        uint256 treasuryValueUSD;       // 18-decimal USD value
        uint256 createdAt;
        uint256 lastFeeTimestamp;
        uint256 totalFeesRouted;
        bool governanceApproved;        // humans must approve final structure
    }

    struct MonthlyFeeRecord {
        bytes32 daoId;
        uint256 treasuryAtCalculation;
        uint256 applicableBps;
        uint256 feeAmount;
        uint256 routedAt;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Rexhepi gate address authorised to call gated functions.
    address public rexhepiGate;

    /// @notice DAO registry keyed by daoId.
    mapping(bytes32 => DAORecord) public daoRegistry;

    /// @notice Fee history per DAO.
    mapping(bytes32 => MonthlyFeeRecord[]) private _feeHistory;

    /// @notice All DAO IDs for enumeration.
    bytes32[] public allDAOIds;

    /// @notice Running counter for unique DAO identifiers.
    uint256 public daoCount;

    /// @notice Total fees routed to NeoSafe across all DAOs.
    uint256 public totalRoutedToNeoSafe;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event DAOCreated(
        bytes32 indexed daoId,
        address indexed creator,
        string name,
        DAOOrigin origin,
        uint256 timestamp
    );

    event GovernanceApproved(
        bytes32 indexed daoId,
        GovernanceModel model,
        uint256 timestamp
    );

    event GovernanceUpdated(
        bytes32 indexed daoId,
        GovernanceModel newModel,
        uint256 timestamp
    );

    event MonthlyFeeRouted(
        bytes32 indexed daoId,
        uint256 treasuryValue,
        uint256 applicableBps,
        uint256 feeAmount,
        uint256 timestamp
    );

    event DAOStatusChanged(
        bytes32 indexed daoId,
        DAOStatus previousStatus,
        DAOStatus newStatus,
        uint256 timestamp
    );

    event TreasuryUpdated(
        bytes32 indexed daoId,
        uint256 previousValue,
        uint256 newValue,
        uint256 timestamp
    );

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyThroughRexhepiGate() {
        require(
            msg.sender == rexhepiGate,
            "OpenMatrixDAO: caller is not the Rexhepi gate"
        );
        _;
    }

    modifier daoExists(bytes32 _daoId) {
        require(
            daoRegistry[_daoId].createdAt != 0,
            "OpenMatrixDAO: DAO does not exist"
        );
        _;
    }

    modifier daoActive(bytes32 _daoId) {
        require(
            daoRegistry[_daoId].status == DAOStatus.ACTIVE,
            "OpenMatrixDAO: DAO is not active"
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
            "OpenMatrixDAO: gate cannot be zero address"
        );
        rexhepiGate = _rexhepiGate;
    }

    // ----------------------------------------------------------------
    // External Functions - DAO Lifecycle
    // ----------------------------------------------------------------

    /**
     * @notice Initiate a new business-to-DAO conversion.
     * @dev Gas fees for conversion are covered by the platform (off-chain).
     *      The DAO starts in PENDING_CONVERSION until governance is approved.
     * @param _name             Human-readable name for the DAO.
     * @param _governance       Initial governance configuration.
     * @param _initialTreasury  Starting treasury value in USD (18 decimals).
     * @return daoId            Unique identifier for the new DAO.
     */
    function initiateConversion(
        string calldata _name,
        GovernanceConfig calldata _governance,
        uint256 _initialTreasury
    )
        external
        onlyThroughRexhepiGate
        nonReentrant
        returns (bytes32 daoId)
    {
        require(bytes(_name).length > 0, "OpenMatrixDAO: name cannot be empty");

        daoCount++;
        daoId = keccak256(
            abi.encodePacked(msg.sender, _name, daoCount, block.timestamp)
        );

        require(
            daoRegistry[daoId].createdAt == 0,
            "OpenMatrixDAO: DAO ID collision"
        );

        daoRegistry[daoId] = DAORecord({
            daoId: daoId,
            creator: msg.sender,
            name: _name,
            status: DAOStatus.PENDING_CONVERSION,
            origin: DAOOrigin.NEW_CONVERSION,
            governance: _governance,
            treasuryValueUSD: _initialTreasury,
            createdAt: block.timestamp,
            lastFeeTimestamp: block.timestamp,
            totalFeesRouted: 0,
            governanceApproved: false
        });

        allDAOIds.push(daoId);

        emit DAOCreated(
            daoId,
            msg.sender,
            _name,
            DAOOrigin.NEW_CONVERSION,
            block.timestamp
        );
    }

    /**
     * @notice Onboard an existing DAO to the platform (free onboarding).
     * @param _name             Human-readable name for the DAO.
     * @param _governance       Existing governance configuration.
     * @param _initialTreasury  Current treasury value in USD (18 decimals).
     * @return daoId            Unique identifier for the onboarded DAO.
     */
    function onboardExistingDAO(
        string calldata _name,
        GovernanceConfig calldata _governance,
        uint256 _initialTreasury
    )
        external
        onlyThroughRexhepiGate
        nonReentrant
        returns (bytes32 daoId)
    {
        require(bytes(_name).length > 0, "OpenMatrixDAO: name cannot be empty");

        daoCount++;
        daoId = keccak256(
            abi.encodePacked(msg.sender, _name, daoCount, block.timestamp)
        );

        require(
            daoRegistry[daoId].createdAt == 0,
            "OpenMatrixDAO: DAO ID collision"
        );

        daoRegistry[daoId] = DAORecord({
            daoId: daoId,
            creator: msg.sender,
            name: _name,
            status: DAOStatus.ACTIVE,
            origin: DAOOrigin.EXISTING_ONBOARDING,
            governance: _governance,
            treasuryValueUSD: _initialTreasury,
            createdAt: block.timestamp,
            lastFeeTimestamp: block.timestamp,
            totalFeesRouted: 0,
            governanceApproved: true  // existing DAOs already have governance
        });

        allDAOIds.push(daoId);

        emit DAOCreated(
            daoId,
            msg.sender,
            _name,
            DAOOrigin.EXISTING_ONBOARDING,
            block.timestamp
        );
    }

    /**
     * @notice Approve the final governance structure for a pending DAO.
     * @dev This is the human-approval step; only after this does the DAO
     *      become ACTIVE.
     * @param _daoId The DAO to approve.
     */
    function approveGovernance(
        bytes32 _daoId
    ) external onlyThroughRexhepiGate daoExists(_daoId) {
        DAORecord storage dao = daoRegistry[_daoId];
        require(
            dao.status == DAOStatus.PENDING_CONVERSION,
            "OpenMatrixDAO: DAO not pending conversion"
        );
        require(
            !dao.governanceApproved,
            "OpenMatrixDAO: governance already approved"
        );

        dao.governanceApproved = true;
        dao.status = DAOStatus.ACTIVE;
        dao.lastFeeTimestamp = block.timestamp;

        emit GovernanceApproved(_daoId, dao.governance.model, block.timestamp);
        emit DAOStatusChanged(
            _daoId,
            DAOStatus.PENDING_CONVERSION,
            DAOStatus.ACTIVE,
            block.timestamp
        );
    }

    /**
     * @notice Update the governance configuration of an active DAO.
     * @param _daoId      The DAO to update.
     * @param _governance The new governance configuration.
     */
    function updateGovernance(
        bytes32 _daoId,
        GovernanceConfig calldata _governance
    ) external onlyThroughRexhepiGate daoExists(_daoId) daoActive(_daoId) {
        daoRegistry[_daoId].governance = _governance;
        emit GovernanceUpdated(_daoId, _governance.model, block.timestamp);
    }

    // ----------------------------------------------------------------
    // External Functions - Fee Management
    // ----------------------------------------------------------------

    /**
     * @notice Update the treasury value for a DAO (from oracle / off-chain feed).
     * @param _daoId   The DAO to update.
     * @param _newValue New treasury value in USD (18 decimals).
     */
    function updateTreasuryValue(
        bytes32 _daoId,
        uint256 _newValue
    ) external onlyThroughRexhepiGate daoExists(_daoId) {
        uint256 previous = daoRegistry[_daoId].treasuryValueUSD;
        daoRegistry[_daoId].treasuryValueUSD = _newValue;

        emit TreasuryUpdated(_daoId, previous, _newValue, block.timestamp);
    }

    /**
     * @notice Calculate and route the monthly maintenance fee for a DAO.
     * @dev Fee tier is computed from the CURRENT treasury value at the moment
     *      of calculation and adjusts in BOTH directions (up and down).
     * @param _daoId The DAO to charge.
     */
    function routeMonthlyFee(
        bytes32 _daoId
    )
        external
        payable
        onlyThroughRexhepiGate
        nonReentrant
        daoExists(_daoId)
        daoActive(_daoId)
    {
        DAORecord storage dao = daoRegistry[_daoId];

        uint256 treasuryValue = dao.treasuryValueUSD;
        uint256 annualBps = _getMaintenanceBps(dao.origin, treasuryValue);
        uint256 monthlyFee = _calculateMonthlyFee(treasuryValue, annualBps);

        require(
            msg.value >= monthlyFee,
            "OpenMatrixDAO: insufficient fee amount"
        );

        // Record the fee
        _feeHistory[_daoId].push(MonthlyFeeRecord({
            daoId: _daoId,
            treasuryAtCalculation: treasuryValue,
            applicableBps: annualBps,
            feeAmount: monthlyFee,
            routedAt: block.timestamp
        }));

        dao.lastFeeTimestamp = block.timestamp;
        dao.totalFeesRouted += monthlyFee;
        totalRoutedToNeoSafe += monthlyFee;

        // Route to NeoSafe
        (bool sent, ) = payable(NEOSAFE).call{value: monthlyFee}("");
        require(sent, "OpenMatrixDAO: failed to route fee to NeoSafe");

        // Refund excess
        uint256 excess = msg.value - monthlyFee;
        if (excess > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: excess}("");
            require(refunded, "OpenMatrixDAO: failed to refund excess");
        }

        emit MonthlyFeeRouted(
            _daoId,
            treasuryValue,
            annualBps,
            monthlyFee,
            block.timestamp
        );
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    /**
     * @notice Get the applicable annual maintenance rate for a DAO.
     * @param _daoId The DAO to query.
     * @return bps The annual fee rate in basis points.
     */
    function getMaintenanceRate(
        bytes32 _daoId
    ) external view daoExists(_daoId) returns (uint256 bps) {
        DAORecord storage dao = daoRegistry[_daoId];
        bps = _getMaintenanceBps(dao.origin, dao.treasuryValueUSD);
    }

    /**
     * @notice Estimate the next monthly fee for a DAO.
     * @param _daoId The DAO to query.
     * @return fee The estimated monthly fee in wei-equivalent USD.
     */
    function estimateMonthlyFee(
        bytes32 _daoId
    ) external view daoExists(_daoId) returns (uint256 fee) {
        DAORecord storage dao = daoRegistry[_daoId];
        uint256 annualBps = _getMaintenanceBps(dao.origin, dao.treasuryValueUSD);
        fee = _calculateMonthlyFee(dao.treasuryValueUSD, annualBps);
    }

    /**
     * @notice Get the fee history for a DAO.
     * @param _daoId The DAO to query.
     * @return records Array of monthly fee records.
     */
    function getFeeHistory(
        bytes32 _daoId
    ) external view daoExists(_daoId) returns (MonthlyFeeRecord[] memory records) {
        records = _feeHistory[_daoId];
    }

    /**
     * @notice Get the total number of DAOs registered.
     * @return count Total DAO count.
     */
    function getDAOCount() external view returns (uint256 count) {
        count = allDAOIds.length;
    }

    // ----------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------

    /**
     * @notice Change the status of a DAO. Owner or gate only.
     * @param _daoId    The DAO to update.
     * @param _newStatus The new status.
     */
    function setDAOStatus(
        bytes32 _daoId,
        DAOStatus _newStatus
    ) external onlyThroughRexhepiGate daoExists(_daoId) {
        DAOStatus previous = daoRegistry[_daoId].status;
        daoRegistry[_daoId].status = _newStatus;

        emit DAOStatusChanged(_daoId, previous, _newStatus, block.timestamp);
    }

    /**
     * @notice Update the Rexhepi gate address. Owner-only.
     * @param _newGate The new gate address.
     */
    function setRexhepiGate(address _newGate) external onlyOwner {
        require(
            _newGate != address(0),
            "OpenMatrixDAO: gate cannot be zero address"
        );
        rexhepiGate = _newGate;
    }

    // ----------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------

    /**
     * @dev Determine the annual maintenance BPS based on DAO origin and
     *      current treasury value. Adjusts BOTH directions.
     * @param _origin        Whether this is a new conversion or existing onboarding.
     * @param _treasuryValue Current treasury value in USD (18 decimals).
     * @return bps           Annual maintenance rate in basis points.
     */
    function _getMaintenanceBps(
        DAOOrigin _origin,
        uint256 _treasuryValue
    ) internal pure returns (uint256 bps) {
        // Existing DAOs always pay 1% flat regardless of treasury size
        if (_origin == DAOOrigin.EXISTING_ONBOARDING) {
            return EXISTING_DAO_BPS;
        }

        // New conversions: tiered by current treasury, adjusts BOTH directions
        if (_treasuryValue <= TIER1_CEILING) {
            bps = NEW_TIER1_BPS;    // 2.0%
        } else if (_treasuryValue <= TIER2_CEILING) {
            bps = NEW_TIER2_BPS;    // 2.5%
        } else if (_treasuryValue <= TIER3_CEILING) {
            bps = NEW_TIER3_BPS;    // 5.0%
        } else {
            bps = NEW_TIER4_BPS;    // 10.0%
        }
    }

    /**
     * @dev Calculate the monthly fee from annual rate and treasury value.
     * @param _treasuryValue Treasury value in USD (18 decimals).
     * @param _annualBps     Annual rate in basis points.
     * @return monthlyFee    The monthly fee amount.
     */
    function _calculateMonthlyFee(
        uint256 _treasuryValue,
        uint256 _annualBps
    ) internal pure returns (uint256 monthlyFee) {
        uint256 annualFee = (_treasuryValue * _annualBps) / BPS_DENOMINATOR;
        monthlyFee = annualFee / MONTHS_PER_YEAR;
    }

    // ----------------------------------------------------------------
    // Receive / Fallback
    // ----------------------------------------------------------------

    receive() external payable {}
    fallback() external payable {}
}
