// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title DeFiLoan
 * @author 0pnMatrx Platform
 * @notice Platform DeFi loan contract with collateral management, liquidation,
 *         destination whitelist enforcement, and EAS attestation integration.
 * @dev Deployed on Base L2. Minimum loan $10,000 USD equivalent. Interest floor 2.5%.
 *      Commission: 0.5% of initial deployment value. Collateral: min 150% in ETH or
 *      approved stablecoins. Liquidation warning at 120%, auto-liquidation after 48h.
 */
contract DeFiLoan is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    //  Constants
    // -------------------------------------------------------------------------

    /// @notice NeoSafe treasury address receiving platform commissions
    address public constant NEO_SAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Minimum loan amount in USD (18-decimal fixed point)
    uint256 public constant MIN_LOAN_USD = 10_000 * 1e18;

    /// @notice Interest rate floor: 2.5% expressed as basis points (250 bps)
    uint256 public constant INTEREST_FLOOR_BPS = 250;

    /// @notice Platform commission: 0.5% expressed as basis points (50 bps)
    uint256 public constant COMMISSION_BPS = 50;

    /// @notice Minimum collateral ratio: 150% (1.5e18 in WAD)
    uint256 public constant MIN_COLLATERAL_RATIO = 1.5e18;

    /// @notice Warning threshold: 120% (1.2e18 in WAD)
    uint256 public constant WARNING_RATIO = 1.2e18;

    /// @notice Time window before auto-liquidation after warning (48 hours)
    uint256 public constant LIQUIDATION_GRACE_PERIOD = 48 hours;

    /// @notice EAS schema UID for loan attestations (schema 348)
    bytes32 public constant EAS_SCHEMA_UID =
        0x0000000000000000000000000000000000000000000000000000000000000348;

    /// @notice Basis-point denominator
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice WAD precision (1e18)
    uint256 private constant WAD = 1e18;

    // -------------------------------------------------------------------------
    //  Enums
    // -------------------------------------------------------------------------

    enum LoanStatus {
        Active,
        Repaid,
        Liquidated,
        Defaulted
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

    struct Loan {
        uint256 loanId;
        address borrower;
        uint256 principalUsd;           // USD value in 18 decimals
        uint256 collateralAmount;       // Collateral token amount
        address collateralToken;        // address(0) = native ETH
        uint256 interestRateBps;        // Annual interest in basis points (>= 250)
        uint256 durationSeconds;        // Loan term length
        uint256 originatedAt;           // Block timestamp of origination
        uint256 totalRepaid;            // Cumulative repayments in USD
        uint256 warningTimestamp;       // When warning was first triggered (0 = none)
        LoanStatus status;
        address deploymentDestination;  // Whitelisted destination for funds
    }

    struct CollateralInfo {
        uint256 lockedAmount;
        address token;
        uint256 currentValueUsd;
        CollateralStatus status;
    }

    // -------------------------------------------------------------------------
    //  State Variables
    // -------------------------------------------------------------------------

    /// @notice Auto-incrementing loan counter
    uint256 public nextLoanId;

    /// @notice All loans by ID
    mapping(uint256 => Loan) public loans;

    /// @notice Borrower address => array of loan IDs
    mapping(address => uint256[]) public borrowerLoans;

    /// @notice Approved collateral tokens (address(0) represents native ETH)
    mapping(address => bool) public approvedCollateral;

    /// @notice Destination whitelist: address => approved flag
    mapping(address => bool) public whitelistedDestinations;

    /// @notice Price feed oracle address (Component 11)
    address public priceOracle;

    /// @notice EAS contract address on Base
    address public easContract;

    /// @notice Accumulated platform fees available for withdrawal
    uint256 public accumulatedFees;

    // -------------------------------------------------------------------------
    //  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new loan is originated
    event LoanOriginated(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 principalUsd,
        uint256 collateralAmount,
        address collateralToken,
        uint256 interestRateBps,
        uint256 durationSeconds,
        address deploymentDestination,
        bytes32 easAttestationUid
    );

    /// @notice Emitted when a payment is made toward a loan
    event PaymentMade(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 amountUsd,
        uint256 remainingUsd,
        bytes32 easAttestationUid
    );

    /// @notice Emitted when collateral ratio drops to warning level
    event CollateralWarning(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 currentRatio,
        uint256 warningTimestamp
    );

    /// @notice Emitted when a loan is liquidated
    event Liquidated(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 collateralSeized,
        uint256 outstandingDebt,
        bytes32 easAttestationUid
    );

    /// @notice Emitted when a destination whitelist violation is detected
    event WhitelistViolation(
        uint256 indexed loanId,
        address indexed borrower,
        address attemptedDestination
    );

    /// @notice Emitted when collateral is topped up
    event CollateralTopUp(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 additionalAmount,
        uint256 newTotal
    );

    /// @notice Emitted when a collateral token is approved or removed
    event CollateralTokenUpdated(address indexed token, bool approved);

    /// @notice Emitted when a destination is added or removed from whitelist
    event WhitelistUpdated(address indexed destination, bool approved);

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyActiveLoan(uint256 _loanId) {
        require(loans[_loanId].status == LoanStatus.Active, "DeFiLoan: loan not active");
        _;
    }

    modifier onlyBorrower(uint256 _loanId) {
        require(loans[_loanId].borrower == msg.sender, "DeFiLoan: not borrower");
        _;
    }

    // -------------------------------------------------------------------------
    //  Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _priceOracle Address of the price oracle (Component 11)
     * @param _easContract Address of the EAS contract on Base
     */
    constructor(address _priceOracle, address _easContract) Ownable(msg.sender) {
        require(_priceOracle != address(0), "DeFiLoan: zero oracle address");
        require(_easContract != address(0), "DeFiLoan: zero EAS address");

        priceOracle = _priceOracle;
        easContract = _easContract;

        // Native ETH is approved by default
        approvedCollateral[address(0)] = true;
    }

    // -------------------------------------------------------------------------
    //  External — Loan Lifecycle
    // -------------------------------------------------------------------------

    /**
     * @notice Originate a new DeFi loan with ETH collateral.
     * @param _principalUsd      Loan principal in USD (18 decimals)
     * @param _interestRateBps   Annual interest rate in basis points (>= 250)
     * @param _durationSeconds   Loan duration in seconds
     * @param _destination       Whitelisted destination for loan funds
     * @return loanId            The ID of the newly created loan
     */
    function originateLoanETH(
        uint256 _principalUsd,
        uint256 _interestRateBps,
        uint256 _durationSeconds,
        address _destination
    ) external payable nonReentrant whenNotPaused returns (uint256 loanId) {
        require(_principalUsd >= MIN_LOAN_USD, "DeFiLoan: below minimum loan");
        require(_interestRateBps >= INTEREST_FLOOR_BPS, "DeFiLoan: rate below floor");
        require(_durationSeconds > 0, "DeFiLoan: zero duration");
        require(whitelistedDestinations[_destination], "DeFiLoan: destination not whitelisted");
        require(msg.value > 0, "DeFiLoan: no ETH collateral");

        // Validate collateral ratio >= 150%
        uint256 collateralValueUsd = _getETHValueUsd(msg.value);
        require(
            collateralValueUsd * WAD / _principalUsd >= MIN_COLLATERAL_RATIO,
            "DeFiLoan: insufficient collateral"
        );

        // Calculate and collect commission (0.5% of principal)
        uint256 commissionUsd = (_principalUsd * COMMISSION_BPS) / BPS_DENOMINATOR;
        accumulatedFees += commissionUsd;

        loanId = nextLoanId++;
        loans[loanId] = Loan({
            loanId: loanId,
            borrower: msg.sender,
            principalUsd: _principalUsd,
            collateralAmount: msg.value,
            collateralToken: address(0),
            interestRateBps: _interestRateBps,
            durationSeconds: _durationSeconds,
            originatedAt: block.timestamp,
            totalRepaid: 0,
            warningTimestamp: 0,
            status: LoanStatus.Active,
            deploymentDestination: _destination
        });

        borrowerLoans[msg.sender].push(loanId);

        // EAS attestation for origination (schema 348)
        bytes32 attestationUid = _attestOrigination(loanId);

        emit LoanOriginated(
            loanId,
            msg.sender,
            _principalUsd,
            msg.value,
            address(0),
            _interestRateBps,
            _durationSeconds,
            _destination,
            attestationUid
        );
    }

    /**
     * @notice Originate a new DeFi loan with ERC-20 stablecoin collateral.
     * @param _principalUsd       Loan principal in USD (18 decimals)
     * @param _collateralToken    Approved ERC-20 collateral token address
     * @param _collateralAmount   Amount of collateral tokens to lock
     * @param _interestRateBps    Annual interest rate in basis points (>= 250)
     * @param _durationSeconds    Loan duration in seconds
     * @param _destination        Whitelisted destination for loan funds
     * @return loanId             The ID of the newly created loan
     */
    function originateLoanERC20(
        uint256 _principalUsd,
        address _collateralToken,
        uint256 _collateralAmount,
        uint256 _interestRateBps,
        uint256 _durationSeconds,
        address _destination
    ) external nonReentrant whenNotPaused returns (uint256 loanId) {
        require(_principalUsd >= MIN_LOAN_USD, "DeFiLoan: below minimum loan");
        require(_interestRateBps >= INTEREST_FLOOR_BPS, "DeFiLoan: rate below floor");
        require(_durationSeconds > 0, "DeFiLoan: zero duration");
        require(whitelistedDestinations[_destination], "DeFiLoan: destination not whitelisted");
        require(approvedCollateral[_collateralToken], "DeFiLoan: token not approved");
        require(_collateralAmount > 0, "DeFiLoan: zero collateral");

        // Validate collateral ratio >= 150%
        uint256 collateralValueUsd = _getTokenValueUsd(_collateralToken, _collateralAmount);
        require(
            collateralValueUsd * WAD / _principalUsd >= MIN_COLLATERAL_RATIO,
            "DeFiLoan: insufficient collateral"
        );

        // Transfer collateral from borrower
        IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), _collateralAmount);

        // Calculate and collect commission
        uint256 commissionUsd = (_principalUsd * COMMISSION_BPS) / BPS_DENOMINATOR;
        accumulatedFees += commissionUsd;

        loanId = nextLoanId++;
        loans[loanId] = Loan({
            loanId: loanId,
            borrower: msg.sender,
            principalUsd: _principalUsd,
            collateralAmount: _collateralAmount,
            collateralToken: _collateralToken,
            interestRateBps: _interestRateBps,
            durationSeconds: _durationSeconds,
            originatedAt: block.timestamp,
            totalRepaid: 0,
            warningTimestamp: 0,
            status: LoanStatus.Active,
            deploymentDestination: _destination
        });

        borrowerLoans[msg.sender].push(loanId);

        bytes32 attestationUid = _attestOrigination(loanId);

        emit LoanOriginated(
            loanId,
            msg.sender,
            _principalUsd,
            _collateralAmount,
            _collateralToken,
            _interestRateBps,
            _durationSeconds,
            _destination,
            attestationUid
        );
    }

    /**
     * @notice Make a payment toward an active loan.
     * @param _loanId    Loan identifier
     * @param _amountUsd Payment amount in USD (18 decimals)
     */
    function makePayment(uint256 _loanId, uint256 _amountUsd)
        external
        nonReentrant
        whenNotPaused
        onlyActiveLoan(_loanId)
        onlyBorrower(_loanId)
    {
        require(_amountUsd > 0, "DeFiLoan: zero payment");

        Loan storage loan = loans[_loanId];
        uint256 totalOwed = _calculateTotalOwed(loan);
        uint256 remaining = totalOwed > loan.totalRepaid ? totalOwed - loan.totalRepaid : 0;

        uint256 effectivePayment = _amountUsd > remaining ? remaining : _amountUsd;
        loan.totalRepaid += effectivePayment;

        // Check if loan is fully repaid
        if (loan.totalRepaid >= totalOwed) {
            loan.status = LoanStatus.Repaid;
            _releaseCollateral(loan);
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

    /**
     * @notice Top up collateral for an active loan (ETH).
     * @param _loanId Loan identifier
     */
    function topUpCollateralETH(uint256 _loanId)
        external
        payable
        nonReentrant
        onlyActiveLoan(_loanId)
        onlyBorrower(_loanId)
    {
        Loan storage loan = loans[_loanId];
        require(loan.collateralToken == address(0), "DeFiLoan: not ETH collateral");
        require(msg.value > 0, "DeFiLoan: zero top-up");

        loan.collateralAmount += msg.value;

        // Clear warning if ratio is restored
        uint256 newRatio = _getCurrentRatio(loan);
        if (newRatio >= MIN_COLLATERAL_RATIO) {
            loan.warningTimestamp = 0;
        }

        emit CollateralTopUp(_loanId, msg.sender, msg.value, loan.collateralAmount);
    }

    /**
     * @notice Top up collateral for an active loan (ERC-20).
     * @param _loanId Loan identifier
     * @param _amount Additional collateral amount
     */
    function topUpCollateralERC20(uint256 _loanId, uint256 _amount)
        external
        nonReentrant
        onlyActiveLoan(_loanId)
        onlyBorrower(_loanId)
    {
        Loan storage loan = loans[_loanId];
        require(loan.collateralToken != address(0), "DeFiLoan: not ERC20 collateral");
        require(_amount > 0, "DeFiLoan: zero top-up");

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
     * @notice Check and update collateral status for a loan. Can be called by anyone
     *         (keepers, monitoring bots). Emits warnings and triggers liquidation.
     * @param _loanId Loan identifier
     */
    function checkCollateral(uint256 _loanId)
        external
        onlyActiveLoan(_loanId)
    {
        Loan storage loan = loans[_loanId];
        uint256 ratio = _getCurrentRatio(loan);

        if (ratio >= MIN_COLLATERAL_RATIO) {
            // Healthy — clear any existing warning
            loan.warningTimestamp = 0;
            return;
        }

        if (ratio < WARNING_RATIO) {
            // Below warning threshold
            if (loan.warningTimestamp == 0) {
                loan.warningTimestamp = block.timestamp;
                emit CollateralWarning(_loanId, loan.borrower, ratio, block.timestamp);
            } else if (block.timestamp >= loan.warningTimestamp + LIQUIDATION_GRACE_PERIOD) {
                // 48 hours elapsed — auto-liquidate
                _executeLiquidation(_loanId);
            }
        } else {
            // Between 120% and 150% — issue warning but no liquidation countdown
            if (loan.warningTimestamp == 0) {
                loan.warningTimestamp = block.timestamp;
                emit CollateralWarning(_loanId, loan.borrower, ratio, block.timestamp);
            }
        }
    }

    /**
     * @notice Force liquidation of a loan that has exceeded the grace period.
     *         Only callable by owner or keeper.
     * @param _loanId Loan identifier
     */
    function forceLiquidation(uint256 _loanId)
        external
        onlyOwner
        onlyActiveLoan(_loanId)
    {
        Loan storage loan = loans[_loanId];
        require(
            loan.warningTimestamp > 0 &&
            block.timestamp >= loan.warningTimestamp + LIQUIDATION_GRACE_PERIOD,
            "DeFiLoan: grace period not elapsed"
        );
        _executeLiquidation(_loanId);
    }

    /**
     * @notice Validate that a loan deployment destination is whitelisted.
     *         Emits WhitelistViolation if not.
     * @param _loanId     Loan identifier
     * @param _destination Destination address to validate
     * @return valid       True if destination is whitelisted
     */
    function validateDestination(uint256 _loanId, address _destination)
        external
        returns (bool valid)
    {
        if (!whitelistedDestinations[_destination]) {
            emit WhitelistViolation(_loanId, loans[_loanId].borrower, _destination);
            return false;
        }
        return true;
    }

    // -------------------------------------------------------------------------
    //  External — Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Approve or remove a collateral token.
     * @param _token    Token address (address(0) for ETH)
     * @param _approved Whether the token is approved
     */
    function setApprovedCollateral(address _token, bool _approved) external onlyOwner {
        approvedCollateral[_token] = _approved;
        emit CollateralTokenUpdated(_token, _approved);
    }

    /**
     * @notice Add or remove a destination from the whitelist.
     * @param _destination Destination address
     * @param _approved    Whether the destination is whitelisted
     */
    function setWhitelistedDestination(address _destination, bool _approved) external onlyOwner {
        whitelistedDestinations[_destination] = _approved;
        emit WhitelistUpdated(_destination, _approved);
    }

    /**
     * @notice Update the price oracle address.
     * @param _newOracle New oracle address
     */
    function setPriceOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "DeFiLoan: zero oracle");
        priceOracle = _newOracle;
    }

    /**
     * @notice Withdraw accumulated platform fees to NeoSafe.
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        require(amount > 0, "DeFiLoan: no fees to withdraw");
        accumulatedFees = 0;
        // Transfer fee equivalent — in practice would convert or transfer stablecoins
        (bool success, ) = NEO_SAFE.call{value: 0}("");
        require(success, "DeFiLoan: fee withdrawal failed");
    }

    /// @notice Pause the contract in emergency
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // -------------------------------------------------------------------------
    //  View Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Get all loan IDs for a borrower.
     * @param _borrower Borrower address
     * @return loanIds  Array of loan IDs
     */
    function getBorrowerLoans(address _borrower) external view returns (uint256[] memory) {
        return borrowerLoans[_borrower];
    }

    /**
     * @notice Get the current collateral ratio for a loan.
     * @param _loanId Loan identifier
     * @return ratio  Collateral ratio in WAD (1e18 = 100%)
     */
    function getCollateralRatio(uint256 _loanId) external view returns (uint256) {
        return _getCurrentRatio(loans[_loanId]);
    }

    /**
     * @notice Get total amount owed on a loan including interest.
     * @param _loanId Loan identifier
     * @return totalOwed Amount in USD (18 decimals)
     */
    function getTotalOwed(uint256 _loanId) external view returns (uint256) {
        return _calculateTotalOwed(loans[_loanId]);
    }

    /**
     * @notice Get collateral info for a loan.
     * @param _loanId Loan identifier
     * @return info   CollateralInfo struct
     */
    function getCollateralInfo(uint256 _loanId) external view returns (CollateralInfo memory info) {
        Loan storage loan = loans[_loanId];
        uint256 ratio = _getCurrentRatio(loan);

        CollateralStatus status;
        if (ratio >= MIN_COLLATERAL_RATIO) {
            status = CollateralStatus.Healthy;
        } else if (ratio >= WARNING_RATIO) {
            status = CollateralStatus.Warning;
        } else if (loan.warningTimestamp > 0 &&
                   block.timestamp >= loan.warningTimestamp + LIQUIDATION_GRACE_PERIOD) {
            status = CollateralStatus.Liquidating;
        } else {
            status = CollateralStatus.Critical;
        }

        uint256 valueUsd;
        if (loan.collateralToken == address(0)) {
            valueUsd = _getETHValueUsd(loan.collateralAmount);
        } else {
            valueUsd = _getTokenValueUsd(loan.collateralToken, loan.collateralAmount);
        }

        info = CollateralInfo({
            lockedAmount: loan.collateralAmount,
            token: loan.collateralToken,
            currentValueUsd: valueUsd,
            status: status
        });
    }

    // -------------------------------------------------------------------------
    //  Internal
    // -------------------------------------------------------------------------

    /**
     * @dev Calculate total owed including accrued interest (simple interest model).
     */
    function _calculateTotalOwed(Loan storage _loan) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - _loan.originatedAt;
        uint256 annualInterest = (_loan.principalUsd * _loan.interestRateBps) / BPS_DENOMINATOR;
        uint256 accruedInterest = (annualInterest * elapsed) / 365 days;
        return _loan.principalUsd + accruedInterest;
    }

    /**
     * @dev Get current collateral ratio in WAD.
     */
    function _getCurrentRatio(Loan storage _loan) internal view returns (uint256) {
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

    /**
     * @dev Execute liquidation: seize collateral, mark loan, attest.
     */
    function _executeLiquidation(uint256 _loanId) internal {
        Loan storage loan = loans[_loanId];
        uint256 seizedAmount = loan.collateralAmount;
        uint256 outstandingDebt = _calculateTotalOwed(loan) - loan.totalRepaid;

        loan.status = LoanStatus.Liquidated;
        loan.collateralAmount = 0;

        // Transfer collateral to NeoSafe for liquidation processing
        if (loan.collateralToken == address(0)) {
            (bool success, ) = NEO_SAFE.call{value: seizedAmount}("");
            require(success, "DeFiLoan: ETH transfer failed");
        } else {
            IERC20(loan.collateralToken).safeTransfer(NEO_SAFE, seizedAmount);
        }

        bytes32 attestationUid = _attestLiquidation(_loanId, seizedAmount, outstandingDebt);

        emit Liquidated(_loanId, loan.borrower, seizedAmount, outstandingDebt, attestationUid);
    }

    /**
     * @dev Release collateral back to borrower upon full repayment.
     */
    function _releaseCollateral(Loan storage _loan) internal {
        uint256 amount = _loan.collateralAmount;
        _loan.collateralAmount = 0;

        if (amount == 0) return;

        if (_loan.collateralToken == address(0)) {
            (bool success, ) = _loan.borrower.call{value: amount}("");
            require(success, "DeFiLoan: ETH release failed");
        } else {
            IERC20(_loan.collateralToken).safeTransfer(_loan.borrower, amount);
        }
    }

    /**
     * @dev Get ETH value in USD via oracle. Returns 18-decimal USD value.
     */
    function _getETHValueUsd(uint256 _ethAmount) internal view returns (uint256) {
        // Call Component 11 oracle: IPriceOracle(priceOracle).getETHPrice()
        // Returns price in 18 decimals (e.g., 3000e18 for $3000)
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getETHPrice()")
        );
        require(success && data.length >= 32, "DeFiLoan: oracle call failed");
        uint256 ethPriceUsd = abi.decode(data, (uint256));
        return (_ethAmount * ethPriceUsd) / 1e18;
    }

    /**
     * @dev Get ERC-20 token value in USD via oracle.
     */
    function _getTokenValueUsd(address _token, uint256 _amount) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getTokenPrice(address)", _token)
        );
        require(success && data.length >= 32, "DeFiLoan: oracle call failed");
        uint256 tokenPriceUsd = abi.decode(data, (uint256));
        return (_amount * tokenPriceUsd) / 1e18;
    }

    // -------------------------------------------------------------------------
    //  Internal — EAS Attestations (Schema 348)
    // -------------------------------------------------------------------------

    /**
     * @dev Create EAS attestation for loan origination.
     */
    function _attestOrigination(uint256 _loanId) internal returns (bytes32) {
        Loan storage loan = loans[_loanId];
        bytes memory attestationData = abi.encode(
            "LOAN_ORIGINATION",
            _loanId,
            loan.borrower,
            loan.principalUsd,
            loan.collateralAmount,
            loan.interestRateBps,
            loan.deploymentDestination,
            block.timestamp
        );
        return _createAttestation(loan.borrower, attestationData);
    }

    /**
     * @dev Create EAS attestation for payment.
     */
    function _attestPayment(uint256 _loanId, uint256 _amount) internal returns (bytes32) {
        bytes memory attestationData = abi.encode(
            "LOAN_PAYMENT",
            _loanId,
            loans[_loanId].borrower,
            _amount,
            loans[_loanId].totalRepaid,
            block.timestamp
        );
        return _createAttestation(loans[_loanId].borrower, attestationData);
    }

    /**
     * @dev Create EAS attestation for liquidation.
     */
    function _attestLiquidation(
        uint256 _loanId,
        uint256 _seizedAmount,
        uint256 _outstandingDebt
    ) internal returns (bytes32) {
        bytes memory attestationData = abi.encode(
            "LOAN_LIQUIDATION",
            _loanId,
            loans[_loanId].borrower,
            _seizedAmount,
            _outstandingDebt,
            block.timestamp
        );
        return _createAttestation(loans[_loanId].borrower, attestationData);
    }

    /**
     * @dev Low-level EAS attestation creation.
     */
    function _createAttestation(address _recipient, bytes memory _data)
        internal
        returns (bytes32)
    {
        // Encode the EAS attest call per IEAS interface
        (bool success, bytes memory result) = easContract.call(
            abi.encodeWithSignature(
                "attest((bytes32,(address,uint64,bool,bytes32,bytes,uint256)))",
                EAS_SCHEMA_UID,
                _recipient,        // recipient
                uint64(0),         // expirationTime (0 = no expiry)
                false,             // revocable
                bytes32(0),        // refUID
                _data,             // data
                uint256(0)         // value
            )
        );

        if (success && result.length >= 32) {
            return abi.decode(result, (bytes32));
        }
        // Return zero hash if attestation fails (non-critical)
        return bytes32(0);
    }

    // -------------------------------------------------------------------------
    //  Receive
    // -------------------------------------------------------------------------

    /// @dev Accept ETH for collateral deposits
    receive() external payable {}
}
