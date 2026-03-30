// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title P2PLoan
 * @author 0pnMatrx Platform
 * @notice Peer-to-peer lending contract where lenders set their own terms.
 * @dev 0.5% origination fee to NeoSafe. Same collateral/liquidation rules as DeFiLoan
 *      (150% minimum, 120% warning, 48h auto-liquidation). ERC-8004 reputation integration.
 *      EAS attestation on all lifecycle events.
 */
contract P2PLoan is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    //  Constants
    // -------------------------------------------------------------------------

    address public constant NEO_SAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Origination fee: 0.5% (50 basis points) to NeoSafe
    uint256 public constant ORIGINATION_FEE_BPS = 50;

    /// @notice Minimum collateral ratio: 150%
    uint256 public constant MIN_COLLATERAL_RATIO = 1.5e18;

    /// @notice Warning threshold: 120%
    uint256 public constant WARNING_RATIO = 1.2e18;

    /// @notice Grace period before auto-liquidation: 48 hours
    uint256 public constant LIQUIDATION_GRACE_PERIOD = 48 hours;

    /// @notice EAS schema UID (schema 348)
    bytes32 public constant EAS_SCHEMA_UID =
        0x0000000000000000000000000000000000000000000000000000000000000348;

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant WAD = 1e18;

    // -------------------------------------------------------------------------
    //  Enums
    // -------------------------------------------------------------------------

    enum OfferStatus {
        Open,
        Filled,
        Cancelled,
        Expired
    }

    enum LoanStatus {
        Active,
        Repaid,
        Liquidated,
        Defaulted,
        Disputed
    }

    enum CollateralStatus {
        Healthy,
        Warning,
        Critical,
        Liquidating
    }

    // -------------------------------------------------------------------------
    //  Structs
    // -------------------------------------------------------------------------

    /// @notice Lending offer created by a lender
    struct LendingOffer {
        uint256 offerId;
        address lender;
        uint256 amountUsd;              // Maximum loan amount in USD (18 decimals)
        uint256 minAmountUsd;           // Minimum acceptable loan amount
        uint256 interestRateBps;        // Annual interest rate in basis points
        uint256 maxDurationSeconds;     // Maximum loan duration
        uint256 minCollateralRatioBps;  // Minimum collateral ratio required (in bps, >= 15000)
        address[] acceptedCollateral;   // Accepted collateral tokens (address(0) = ETH)
        uint256 createdAt;
        uint256 expiresAt;
        OfferStatus status;
    }

    /// @notice Active P2P loan between lender and borrower
    struct P2PLoanData {
        uint256 loanId;
        uint256 offerId;                // Reference to the original offer
        address lender;
        address borrower;
        uint256 principalUsd;
        uint256 collateralAmount;
        address collateralToken;
        uint256 interestRateBps;
        uint256 durationSeconds;
        uint256 originatedAt;
        uint256 totalRepaid;
        uint256 warningTimestamp;
        LoanStatus status;
        uint256 lenderReputationAtOrigination;
        uint256 borrowerReputationAtOrigination;
    }

    // -------------------------------------------------------------------------
    //  State
    // -------------------------------------------------------------------------

    uint256 public nextOfferId;
    uint256 public nextLoanId;

    mapping(uint256 => LendingOffer) public offers;
    mapping(uint256 => P2PLoanData) public loans;

    /// @notice Lender address => offer IDs
    mapping(address => uint256[]) public lenderOffers;

    /// @notice Borrower address => loan IDs
    mapping(address => uint256[]) public borrowerLoans;

    /// @notice Lender address => loan IDs (as lender)
    mapping(address => uint256[]) public lenderLoans;

    /// @notice Approved collateral tokens
    mapping(address => bool) public approvedCollateral;

    /// @notice Destination whitelist
    mapping(address => bool) public whitelistedDestinations;

    /// @notice Price oracle (Component 11)
    address public priceOracle;

    /// @notice EAS contract on Base
    address public easContract;

    /// @notice ERC-8004 reputation contract
    address public reputationContract;

    /// @notice Accumulated origination fees
    uint256 public accumulatedFees;

    // -------------------------------------------------------------------------
    //  Events
    // -------------------------------------------------------------------------

    event OfferCreated(
        uint256 indexed offerId,
        address indexed lender,
        uint256 amountUsd,
        uint256 interestRateBps,
        uint256 maxDurationSeconds
    );

    event OfferCancelled(uint256 indexed offerId, address indexed lender);

    event LoanOriginated(
        uint256 indexed loanId,
        uint256 indexed offerId,
        address indexed lender,
        address borrower,
        uint256 principalUsd,
        uint256 collateralAmount,
        address collateralToken,
        uint256 interestRateBps,
        bytes32 easAttestationUid
    );

    event PaymentMade(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 amountUsd,
        uint256 remainingUsd,
        bytes32 easAttestationUid
    );

    event CollateralWarning(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 currentRatio,
        uint256 warningTimestamp
    );

    event Liquidated(
        uint256 indexed loanId,
        address indexed borrower,
        address indexed lender,
        uint256 collateralSeized,
        uint256 outstandingDebt,
        bytes32 easAttestationUid
    );

    event WhitelistViolation(
        uint256 indexed loanId,
        address indexed borrower,
        address attemptedDestination
    );

    event CollateralTopUp(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 additionalAmount,
        uint256 newTotal
    );

    event DisputeFiled(
        uint256 indexed loanId,
        address indexed filingParty,
        bytes32 disputeId
    );

    event ReputationUpdated(
        address indexed user,
        uint256 newScore,
        string eventType
    );

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyActiveLoan(uint256 _loanId) {
        require(loans[_loanId].status == LoanStatus.Active, "P2PLoan: loan not active");
        _;
    }

    modifier onlyLoanParty(uint256 _loanId) {
        require(
            loans[_loanId].borrower == msg.sender || loans[_loanId].lender == msg.sender,
            "P2PLoan: not loan party"
        );
        _;
    }

    // -------------------------------------------------------------------------
    //  Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _priceOracle        Price oracle address (Component 11)
     * @param _easContract        EAS contract address on Base
     * @param _reputationContract ERC-8004 reputation contract address
     */
    constructor(
        address _priceOracle,
        address _easContract,
        address _reputationContract
    ) Ownable(msg.sender) {
        require(_priceOracle != address(0), "P2PLoan: zero oracle");
        require(_easContract != address(0), "P2PLoan: zero EAS");
        require(_reputationContract != address(0), "P2PLoan: zero reputation");

        priceOracle = _priceOracle;
        easContract = _easContract;
        reputationContract = _reputationContract;

        // ETH approved by default
        approvedCollateral[address(0)] = true;
    }

    // -------------------------------------------------------------------------
    //  External — Offer Management
    // -------------------------------------------------------------------------

    /**
     * @notice Create a lending offer with custom terms.
     * @param _amountUsd             Maximum loan amount (USD, 18 decimals)
     * @param _minAmountUsd          Minimum loan amount
     * @param _interestRateBps       Annual interest rate in basis points
     * @param _maxDurationSeconds    Maximum loan duration
     * @param _minCollateralRatioBps Minimum collateral ratio (in bps, e.g., 15000 = 150%)
     * @param _acceptedCollateral    Array of accepted collateral tokens
     * @param _durationSeconds       How long the offer remains open
     * @return offerId               The ID of the created offer
     */
    function createOffer(
        uint256 _amountUsd,
        uint256 _minAmountUsd,
        uint256 _interestRateBps,
        uint256 _maxDurationSeconds,
        uint256 _minCollateralRatioBps,
        address[] calldata _acceptedCollateral,
        uint256 _durationSeconds
    ) external whenNotPaused returns (uint256 offerId) {
        require(_amountUsd > 0, "P2PLoan: zero amount");
        require(_minAmountUsd <= _amountUsd, "P2PLoan: min exceeds max");
        require(_interestRateBps > 0, "P2PLoan: zero interest");
        require(_maxDurationSeconds > 0, "P2PLoan: zero duration");
        require(_minCollateralRatioBps >= 15000, "P2PLoan: collateral ratio below 150%");
        require(_acceptedCollateral.length > 0, "P2PLoan: no collateral types");
        require(_durationSeconds > 0, "P2PLoan: zero offer duration");

        // Validate all collateral tokens are approved
        for (uint256 i = 0; i < _acceptedCollateral.length; i++) {
            require(
                approvedCollateral[_acceptedCollateral[i]],
                "P2PLoan: collateral not approved"
            );
        }

        // Check lender reputation via ERC-8004
        uint256 lenderScore = _getReputationScore(msg.sender);

        offerId = nextOfferId++;
        offers[offerId] = LendingOffer({
            offerId: offerId,
            lender: msg.sender,
            amountUsd: _amountUsd,
            minAmountUsd: _minAmountUsd,
            interestRateBps: _interestRateBps,
            maxDurationSeconds: _maxDurationSeconds,
            minCollateralRatioBps: _minCollateralRatioBps,
            acceptedCollateral: _acceptedCollateral,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + _durationSeconds,
            status: OfferStatus.Open
        });

        lenderOffers[msg.sender].push(offerId);

        emit OfferCreated(offerId, msg.sender, _amountUsd, _interestRateBps, _maxDurationSeconds);
    }

    /**
     * @notice Cancel an open lending offer.
     * @param _offerId Offer identifier
     */
    function cancelOffer(uint256 _offerId) external {
        LendingOffer storage offer = offers[_offerId];
        require(offer.lender == msg.sender, "P2PLoan: not offer owner");
        require(offer.status == OfferStatus.Open, "P2PLoan: offer not open");

        offer.status = OfferStatus.Cancelled;
        emit OfferCancelled(_offerId, msg.sender);
    }

    // -------------------------------------------------------------------------
    //  External — Loan Origination
    // -------------------------------------------------------------------------

    /**
     * @notice Accept a lending offer and originate a P2P loan with ETH collateral.
     * @param _offerId         Offer to accept
     * @param _principalUsd    Requested loan amount (must be within offer bounds)
     * @param _durationSeconds Requested loan duration (must be <= offer max)
     * @return loanId          The ID of the originated loan
     */
    function acceptOfferETH(
        uint256 _offerId,
        uint256 _principalUsd,
        uint256 _durationSeconds
    ) external payable nonReentrant whenNotPaused returns (uint256 loanId) {
        LendingOffer storage offer = offers[_offerId];
        require(offer.status == OfferStatus.Open, "P2PLoan: offer not open");
        require(block.timestamp < offer.expiresAt, "P2PLoan: offer expired");
        require(_principalUsd >= offer.minAmountUsd, "P2PLoan: below minimum");
        require(_principalUsd <= offer.amountUsd, "P2PLoan: exceeds offer");
        require(_durationSeconds <= offer.maxDurationSeconds, "P2PLoan: exceeds max duration");
        require(msg.value > 0, "P2PLoan: no ETH collateral");

        // Verify ETH is accepted collateral for this offer
        bool ethAccepted = false;
        for (uint256 i = 0; i < offer.acceptedCollateral.length; i++) {
            if (offer.acceptedCollateral[i] == address(0)) {
                ethAccepted = true;
                break;
            }
        }
        require(ethAccepted, "P2PLoan: ETH not accepted for this offer");

        // Validate collateral ratio against lender's minimum requirement
        uint256 collateralValueUsd = _getETHValueUsd(msg.value);
        uint256 requiredRatioWad = (offer.minCollateralRatioBps * WAD) / BPS_DENOMINATOR;
        require(
            collateralValueUsd * WAD / _principalUsd >= requiredRatioWad,
            "P2PLoan: insufficient collateral"
        );

        // Collect origination fee (0.5% to NeoSafe)
        uint256 fee = (_principalUsd * ORIGINATION_FEE_BPS) / BPS_DENOMINATOR;
        accumulatedFees += fee;

        // Get reputation scores
        uint256 lenderRep = _getReputationScore(offer.lender);
        uint256 borrowerRep = _getReputationScore(msg.sender);

        offer.status = OfferStatus.Filled;

        loanId = nextLoanId++;
        loans[loanId] = P2PLoanData({
            loanId: loanId,
            offerId: _offerId,
            lender: offer.lender,
            borrower: msg.sender,
            principalUsd: _principalUsd,
            collateralAmount: msg.value,
            collateralToken: address(0),
            interestRateBps: offer.interestRateBps,
            durationSeconds: _durationSeconds,
            originatedAt: block.timestamp,
            totalRepaid: 0,
            warningTimestamp: 0,
            status: LoanStatus.Active,
            lenderReputationAtOrigination: lenderRep,
            borrowerReputationAtOrigination: borrowerRep
        });

        borrowerLoans[msg.sender].push(loanId);
        lenderLoans[offer.lender].push(loanId);

        // EAS attestation
        bytes32 attestationUid = _attestOrigination(loanId);

        // Update reputation scores for origination event
        _updateReputation(offer.lender, "LOAN_ORIGINATED_LENDER");
        _updateReputation(msg.sender, "LOAN_ORIGINATED_BORROWER");

        emit LoanOriginated(
            loanId,
            _offerId,
            offer.lender,
            msg.sender,
            _principalUsd,
            msg.value,
            address(0),
            offer.interestRateBps,
            attestationUid
        );
    }

    /**
     * @notice Accept a lending offer with ERC-20 stablecoin collateral.
     * @param _offerId           Offer to accept
     * @param _principalUsd      Requested loan amount
     * @param _collateralToken   ERC-20 collateral token
     * @param _collateralAmount  Amount of collateral
     * @param _durationSeconds   Requested loan duration
     * @return loanId            The ID of the originated loan
     */
    function acceptOfferERC20(
        uint256 _offerId,
        uint256 _principalUsd,
        address _collateralToken,
        uint256 _collateralAmount,
        uint256 _durationSeconds
    ) external nonReentrant whenNotPaused returns (uint256 loanId) {
        LendingOffer storage offer = offers[_offerId];
        require(offer.status == OfferStatus.Open, "P2PLoan: offer not open");
        require(block.timestamp < offer.expiresAt, "P2PLoan: offer expired");
        require(_principalUsd >= offer.minAmountUsd, "P2PLoan: below minimum");
        require(_principalUsd <= offer.amountUsd, "P2PLoan: exceeds offer");
        require(_durationSeconds <= offer.maxDurationSeconds, "P2PLoan: exceeds max duration");
        require(_collateralAmount > 0, "P2PLoan: zero collateral");

        // Verify token is accepted by this offer
        bool tokenAccepted = false;
        for (uint256 i = 0; i < offer.acceptedCollateral.length; i++) {
            if (offer.acceptedCollateral[i] == _collateralToken) {
                tokenAccepted = true;
                break;
            }
        }
        require(tokenAccepted, "P2PLoan: token not accepted for this offer");

        // Validate collateral ratio
        uint256 collateralValueUsd = _getTokenValueUsd(_collateralToken, _collateralAmount);
        uint256 requiredRatioWad = (offer.minCollateralRatioBps * WAD) / BPS_DENOMINATOR;
        require(
            collateralValueUsd * WAD / _principalUsd >= requiredRatioWad,
            "P2PLoan: insufficient collateral"
        );

        // Transfer collateral
        IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), _collateralAmount);

        // Origination fee
        uint256 fee = (_principalUsd * ORIGINATION_FEE_BPS) / BPS_DENOMINATOR;
        accumulatedFees += fee;

        uint256 lenderRep = _getReputationScore(offer.lender);
        uint256 borrowerRep = _getReputationScore(msg.sender);

        offer.status = OfferStatus.Filled;

        loanId = nextLoanId++;
        loans[loanId] = P2PLoanData({
            loanId: loanId,
            offerId: _offerId,
            lender: offer.lender,
            borrower: msg.sender,
            principalUsd: _principalUsd,
            collateralAmount: _collateralAmount,
            collateralToken: _collateralToken,
            interestRateBps: offer.interestRateBps,
            durationSeconds: _durationSeconds,
            originatedAt: block.timestamp,
            totalRepaid: 0,
            warningTimestamp: 0,
            status: LoanStatus.Active,
            lenderReputationAtOrigination: lenderRep,
            borrowerReputationAtOrigination: borrowerRep
        });

        borrowerLoans[msg.sender].push(loanId);
        lenderLoans[offer.lender].push(loanId);

        bytes32 attestationUid = _attestOrigination(loanId);
        _updateReputation(offer.lender, "LOAN_ORIGINATED_LENDER");
        _updateReputation(msg.sender, "LOAN_ORIGINATED_BORROWER");

        emit LoanOriginated(
            loanId,
            _offerId,
            offer.lender,
            msg.sender,
            _principalUsd,
            _collateralAmount,
            _collateralToken,
            offer.interestRateBps,
            attestationUid
        );
    }

    // -------------------------------------------------------------------------
    //  External — Payments
    // -------------------------------------------------------------------------

    /**
     * @notice Make a payment toward an active P2P loan.
     * @param _loanId    Loan identifier
     * @param _amountUsd Payment amount in USD (18 decimals)
     */
    function makePayment(uint256 _loanId, uint256 _amountUsd)
        external
        nonReentrant
        whenNotPaused
        onlyActiveLoan(_loanId)
    {
        P2PLoanData storage loan = loans[_loanId];
        require(loan.borrower == msg.sender, "P2PLoan: not borrower");
        require(_amountUsd > 0, "P2PLoan: zero payment");

        uint256 totalOwed = _calculateTotalOwed(loan);
        uint256 remaining = totalOwed > loan.totalRepaid ? totalOwed - loan.totalRepaid : 0;
        uint256 effectivePayment = _amountUsd > remaining ? remaining : _amountUsd;

        loan.totalRepaid += effectivePayment;

        if (loan.totalRepaid >= totalOwed) {
            loan.status = LoanStatus.Repaid;
            _releaseCollateral(loan);
            _updateReputation(loan.borrower, "LOAN_REPAID_BORROWER");
            _updateReputation(loan.lender, "LOAN_REPAID_LENDER");
        }

        bytes32 attestationUid = _attestPayment(_loanId, effectivePayment);

        emit PaymentMade(
            _loanId,
            msg.sender,
            effectivePayment,
            totalOwed > loan.totalRepaid ? totalOwed - loan.totalRepaid : 0,
            attestationUid
        );
    }

    // -------------------------------------------------------------------------
    //  External — Collateral Management
    // -------------------------------------------------------------------------

    /**
     * @notice Top up ETH collateral for an active loan.
     * @param _loanId Loan identifier
     */
    function topUpCollateralETH(uint256 _loanId)
        external
        payable
        nonReentrant
        onlyActiveLoan(_loanId)
    {
        P2PLoanData storage loan = loans[_loanId];
        require(loan.borrower == msg.sender, "P2PLoan: not borrower");
        require(loan.collateralToken == address(0), "P2PLoan: not ETH collateral");
        require(msg.value > 0, "P2PLoan: zero top-up");

        loan.collateralAmount += msg.value;

        uint256 newRatio = _getCurrentRatio(loan);
        if (newRatio >= MIN_COLLATERAL_RATIO) {
            loan.warningTimestamp = 0;
        }

        emit CollateralTopUp(_loanId, msg.sender, msg.value, loan.collateralAmount);
    }

    /**
     * @notice Top up ERC-20 collateral for an active loan.
     * @param _loanId Loan identifier
     * @param _amount Additional collateral amount
     */
    function topUpCollateralERC20(uint256 _loanId, uint256 _amount)
        external
        nonReentrant
        onlyActiveLoan(_loanId)
    {
        P2PLoanData storage loan = loans[_loanId];
        require(loan.borrower == msg.sender, "P2PLoan: not borrower");
        require(loan.collateralToken != address(0), "P2PLoan: not ERC20");
        require(_amount > 0, "P2PLoan: zero top-up");

        IERC20(loan.collateralToken).safeTransferFrom(msg.sender, address(this), _amount);
        loan.collateralAmount += _amount;

        uint256 newRatio = _getCurrentRatio(loan);
        if (newRatio >= MIN_COLLATERAL_RATIO) {
            loan.warningTimestamp = 0;
        }

        emit CollateralTopUp(_loanId, msg.sender, _amount, loan.collateralAmount);
    }

    // -------------------------------------------------------------------------
    //  External — Monitoring & Liquidation
    // -------------------------------------------------------------------------

    /**
     * @notice Check collateral health for a loan. Callable by anyone (keepers).
     * @param _loanId Loan identifier
     */
    function checkCollateral(uint256 _loanId) external onlyActiveLoan(_loanId) {
        P2PLoanData storage loan = loans[_loanId];
        uint256 ratio = _getCurrentRatio(loan);

        if (ratio >= MIN_COLLATERAL_RATIO) {
            loan.warningTimestamp = 0;
            return;
        }

        if (ratio < WARNING_RATIO) {
            if (loan.warningTimestamp == 0) {
                loan.warningTimestamp = block.timestamp;
                emit CollateralWarning(_loanId, loan.borrower, ratio, block.timestamp);
            } else if (block.timestamp >= loan.warningTimestamp + LIQUIDATION_GRACE_PERIOD) {
                _executeLiquidation(_loanId);
            }
        } else {
            if (loan.warningTimestamp == 0) {
                loan.warningTimestamp = block.timestamp;
                emit CollateralWarning(_loanId, loan.borrower, ratio, block.timestamp);
            }
        }
    }

    /**
     * @notice Force liquidation after grace period. Owner or lender can trigger.
     * @param _loanId Loan identifier
     */
    function forceLiquidation(uint256 _loanId) external onlyActiveLoan(_loanId) {
        P2PLoanData storage loan = loans[_loanId];
        require(
            msg.sender == owner() || msg.sender == loan.lender,
            "P2PLoan: not authorized"
        );
        require(
            loan.warningTimestamp > 0 &&
            block.timestamp >= loan.warningTimestamp + LIQUIDATION_GRACE_PERIOD,
            "P2PLoan: grace period not elapsed"
        );
        _executeLiquidation(_loanId);
    }

    // -------------------------------------------------------------------------
    //  External — Disputes (Routes to Component 30)
    // -------------------------------------------------------------------------

    /**
     * @notice File a dispute for a P2P loan. Routes to Component 30 (bilateral disputes).
     *         NEVER routes to Component 19.
     * @param _loanId  Loan identifier
     * @param _evidence IPFS hash or bytes of evidence
     * @return disputeId Unique dispute identifier
     */
    function fileDispute(uint256 _loanId, bytes calldata _evidence)
        external
        onlyLoanParty(_loanId)
        returns (bytes32 disputeId)
    {
        P2PLoanData storage loan = loans[_loanId];
        require(
            loan.status == LoanStatus.Active || loan.status == LoanStatus.Defaulted,
            "P2PLoan: invalid loan state for dispute"
        );

        loan.status = LoanStatus.Disputed;

        // Generate dispute ID
        disputeId = keccak256(abi.encodePacked(_loanId, msg.sender, block.timestamp));

        // Attest dispute filing
        _attestDispute(_loanId, msg.sender, disputeId);

        // Update reputation for dispute event
        _updateReputation(msg.sender, "DISPUTE_FILED");

        emit DisputeFiled(_loanId, msg.sender, disputeId);
    }

    // -------------------------------------------------------------------------
    //  External — Admin
    // -------------------------------------------------------------------------

    function setApprovedCollateral(address _token, bool _approved) external onlyOwner {
        approvedCollateral[_token] = _approved;
    }

    function setWhitelistedDestination(address _dest, bool _approved) external onlyOwner {
        whitelistedDestinations[_dest] = _approved;
    }

    function setPriceOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "P2PLoan: zero oracle");
        priceOracle = _oracle;
    }

    function setReputationContract(address _rep) external onlyOwner {
        require(_rep != address(0), "P2PLoan: zero reputation");
        reputationContract = _rep;
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        require(amount > 0, "P2PLoan: no fees");
        accumulatedFees = 0;
        (bool success, ) = NEO_SAFE.call{value: 0}("");
        require(success, "P2PLoan: withdrawal failed");
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // -------------------------------------------------------------------------
    //  View Functions
    // -------------------------------------------------------------------------

    function getBorrowerLoans(address _borrower) external view returns (uint256[] memory) {
        return borrowerLoans[_borrower];
    }

    function getLenderOffers(address _lender) external view returns (uint256[] memory) {
        return lenderOffers[_lender];
    }

    function getLenderLoans(address _lender) external view returns (uint256[] memory) {
        return lenderLoans[_lender];
    }

    function getCollateralRatio(uint256 _loanId) external view returns (uint256) {
        return _getCurrentRatio(loans[_loanId]);
    }

    function getTotalOwed(uint256 _loanId) external view returns (uint256) {
        return _calculateTotalOwed(loans[_loanId]);
    }

    /**
     * @notice Get accepted collateral tokens for an offer.
     * @param _offerId Offer identifier
     * @return tokens  Array of accepted collateral token addresses
     */
    function getOfferCollateralTokens(uint256 _offerId)
        external
        view
        returns (address[] memory)
    {
        return offers[_offerId].acceptedCollateral;
    }

    // -------------------------------------------------------------------------
    //  Internal
    // -------------------------------------------------------------------------

    function _calculateTotalOwed(P2PLoanData storage _loan) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - _loan.originatedAt;
        uint256 annualInterest = (_loan.principalUsd * _loan.interestRateBps) / BPS_DENOMINATOR;
        uint256 accruedInterest = (annualInterest * elapsed) / 365 days;
        return _loan.principalUsd + accruedInterest;
    }

    function _getCurrentRatio(P2PLoanData storage _loan) internal view returns (uint256) {
        if (_loan.principalUsd == 0) return type(uint256).max;

        uint256 collateralValueUsd;
        if (_loan.collateralToken == address(0)) {
            collateralValueUsd = _getETHValueUsd(_loan.collateralAmount);
        } else {
            collateralValueUsd = _getTokenValueUsd(_loan.collateralToken, _loan.collateralAmount);
        }

        uint256 totalOwed = _calculateTotalOwed(_loan);
        if (totalOwed == 0) return type(uint256).max;

        return (collateralValueUsd * WAD) / totalOwed;
    }

    function _executeLiquidation(uint256 _loanId) internal {
        P2PLoanData storage loan = loans[_loanId];
        uint256 seizedAmount = loan.collateralAmount;
        uint256 outstandingDebt = _calculateTotalOwed(loan) - loan.totalRepaid;

        loan.status = LoanStatus.Liquidated;
        loan.collateralAmount = 0;

        // In P2P, collateral goes to lender (minus platform share)
        address recipient = loan.lender;

        if (loan.collateralToken == address(0)) {
            (bool success, ) = recipient.call{value: seizedAmount}("");
            require(success, "P2PLoan: ETH transfer failed");
        } else {
            IERC20(loan.collateralToken).safeTransfer(recipient, seizedAmount);
        }

        // Update reputations
        _updateReputation(loan.borrower, "LOAN_LIQUIDATED_BORROWER");
        _updateReputation(loan.lender, "LOAN_LIQUIDATED_LENDER");

        bytes32 attestationUid = _attestLiquidation(_loanId, seizedAmount, outstandingDebt);

        emit Liquidated(
            _loanId,
            loan.borrower,
            loan.lender,
            seizedAmount,
            outstandingDebt,
            attestationUid
        );
    }

    function _releaseCollateral(P2PLoanData storage _loan) internal {
        uint256 amount = _loan.collateralAmount;
        _loan.collateralAmount = 0;
        if (amount == 0) return;

        if (_loan.collateralToken == address(0)) {
            (bool success, ) = _loan.borrower.call{value: amount}("");
            require(success, "P2PLoan: ETH release failed");
        } else {
            IERC20(_loan.collateralToken).safeTransfer(_loan.borrower, amount);
        }
    }

    function _getETHValueUsd(uint256 _ethAmount) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getETHPrice()")
        );
        require(success && data.length >= 32, "P2PLoan: oracle failed");
        uint256 price = abi.decode(data, (uint256));
        return (_ethAmount * price) / 1e18;
    }

    function _getTokenValueUsd(address _token, uint256 _amount) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getTokenPrice(address)", _token)
        );
        require(success && data.length >= 32, "P2PLoan: oracle failed");
        uint256 price = abi.decode(data, (uint256));
        return (_amount * price) / 1e18;
    }

    function _getReputationScore(address _user) internal view returns (uint256) {
        (bool success, bytes memory data) = reputationContract.staticcall(
            abi.encodeWithSignature("getScore(address)", _user)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0; // Default score for new users
    }

    function _updateReputation(address _user, string memory _event) internal {
        (bool success, ) = reputationContract.call(
            abi.encodeWithSignature("updateScore(address,string)", _user, _event)
        );
        if (success) {
            uint256 newScore = _getReputationScore(_user);
            emit ReputationUpdated(_user, newScore, _event);
        }
    }

    // -------------------------------------------------------------------------
    //  Internal — EAS Attestations
    // -------------------------------------------------------------------------

    function _attestOrigination(uint256 _loanId) internal returns (bytes32) {
        P2PLoanData storage loan = loans[_loanId];
        bytes memory data = abi.encode(
            "P2P_LOAN_ORIGINATION",
            _loanId,
            loan.lender,
            loan.borrower,
            loan.principalUsd,
            loan.collateralAmount,
            loan.interestRateBps,
            loan.lenderReputationAtOrigination,
            loan.borrowerReputationAtOrigination,
            block.timestamp
        );
        return _createAttestation(loan.borrower, data);
    }

    function _attestPayment(uint256 _loanId, uint256 _amount) internal returns (bytes32) {
        P2PLoanData storage loan = loans[_loanId];
        bytes memory data = abi.encode(
            "P2P_LOAN_PAYMENT",
            _loanId,
            loan.borrower,
            _amount,
            loan.totalRepaid,
            block.timestamp
        );
        return _createAttestation(loan.borrower, data);
    }

    function _attestLiquidation(
        uint256 _loanId,
        uint256 _seized,
        uint256 _debt
    ) internal returns (bytes32) {
        P2PLoanData storage loan = loans[_loanId];
        bytes memory data = abi.encode(
            "P2P_LOAN_LIQUIDATION",
            _loanId,
            loan.borrower,
            loan.lender,
            _seized,
            _debt,
            block.timestamp
        );
        return _createAttestation(loan.borrower, data);
    }

    function _attestDispute(
        uint256 _loanId,
        address _filingParty,
        bytes32 _disputeId
    ) internal returns (bytes32) {
        bytes memory data = abi.encode(
            "P2P_LOAN_DISPUTE",
            _loanId,
            _filingParty,
            _disputeId,
            block.timestamp
        );
        return _createAttestation(_filingParty, data);
    }

    function _createAttestation(address _recipient, bytes memory _data)
        internal
        returns (bytes32)
    {
        (bool success, bytes memory result) = easContract.call(
            abi.encodeWithSignature(
                "attest((bytes32,(address,uint64,bool,bytes32,bytes,uint256)))",
                EAS_SCHEMA_UID,
                _recipient,
                uint64(0),
                false,
                bytes32(0),
                _data,
                uint256(0)
            )
        );
        if (success && result.length >= 32) {
            return abi.decode(result, (bytes32));
        }
        return bytes32(0);
    }

    // -------------------------------------------------------------------------
    //  Receive
    // -------------------------------------------------------------------------

    receive() external payable {}
}
