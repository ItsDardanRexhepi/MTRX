// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PrivacyProtection
 * @notice Irrevocable privacy commitment with automatic revenue routing on
 *         violation and buyer compliance enforcement on Base.
 * @dev Encodes the platform's privacy commitments as immutable on-chain logic.
 *      If a privacy violation is reported and verified, revenue from the
 *      violating entity is automatically routed to affected users as compensation.
 *
 *      Key properties:
 *        - Privacy commitments are IRREVOCABLE once registered.
 *        - Violations trigger automatic compensation from escrowed revenue.
 *        - Buyers (data consumers) must attest to compliance before accessing data.
 *        - Violation reports go through a multi-step verification process.
 *        - The commitment registry is append-only (no deletions).
 */
contract PrivacyProtection is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Violation compensation percentage from escrowed revenue (100% of escrow).
    uint256 public constant VIOLATION_COMPENSATION_BPS = 10_000;

    /// @notice Basis-point denominator.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    enum ViolationStatus {
        Reported,
        UnderInvestigation,
        Verified,
        Dismissed,
        Compensated
    }

    enum BuyerComplianceStatus {
        Pending,
        Attested,
        Revoked
    }

    struct PrivacyCommitment {
        bytes32 commitmentHash;       // Hash of the full commitment document
        string commitmentURI;         // IPFS URI to the commitment document
        uint256 registeredAt;
        address registeredBy;
        bool active;                  // Always true once registered (irrevocable)
    }

    struct ViolationReport {
        address reporter;
        address violator;
        uint256 commitmentId;         // Which commitment was violated
        string evidenceURI;           // Evidence of violation
        bytes32 evidenceHash;
        ViolationStatus status;
        uint256 reportedAt;
        uint256 resolvedAt;
        address investigator;
        uint256 compensationAmount;
        address[] affectedUsers;
    }

    struct BuyerCompliance {
        address buyer;
        uint256[] commitmentIds;      // Which commitments the buyer attested to
        BuyerComplianceStatus status;
        uint256 attestedAt;
        string complianceProofURI;
    }

    struct RevenueEscrow {
        address entity;               // The entity whose revenue is escrowed
        address token;                // ERC-20 payment token
        uint256 balance;              // Current escrow balance
        uint256 totalDeposited;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    uint256 public nextCommitmentId;
    uint256 public nextViolationId;
    uint256 public nextBuyerComplianceId;

    mapping(uint256 => PrivacyCommitment) public commitments;
    mapping(uint256 => ViolationReport) internal _violations;
    mapping(uint256 => BuyerCompliance) public buyerCompliances;

    /// @notice Entity => token => revenue escrow.
    mapping(address => mapping(address => RevenueEscrow)) public escrows;

    /// @notice Authorised investigators for violation reports.
    mapping(address => bool) public isInvestigator;

    /// @notice Buyer address => compliance ID.
    mapping(address => uint256) public buyerComplianceId;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event CommitmentRegistered(uint256 indexed commitmentId, bytes32 commitmentHash, string commitmentURI);
    event ViolationReported(uint256 indexed violationId, address indexed reporter, address indexed violator, uint256 commitmentId);
    event ViolationInvestigationStarted(uint256 indexed violationId, address indexed investigator);
    event ViolationVerified(uint256 indexed violationId, uint256 compensationAmount);
    event ViolationDismissed(uint256 indexed violationId);
    event ViolationCompensated(uint256 indexed violationId, uint256 totalCompensation, uint256 affectedUserCount);
    event RevenueEscrowed(address indexed entity, address indexed token, uint256 amount);
    event BuyerComplianceAttested(uint256 indexed complianceId, address indexed buyer);
    event BuyerComplianceRevoked(uint256 indexed complianceId, address indexed buyer);
    event InvestigatorAdded(address indexed investigator);
    event InvestigatorRemoved(address indexed investigator);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error CommitmentNotFound();
    error ViolationNotFound();
    error NotInvestigator();
    error NotReporter();
    error InvalidStatus();
    error InsufficientEscrow();
    error NoAffectedUsers();
    error BuyerNotCompliant();
    error AlreadyAttested();
    error ZeroAddress();
    error EmptyCommitment();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyInvestigator() {
        if (!isInvestigator[msg.sender] && msg.sender != owner()) revert NotInvestigator();
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // ----------------------------------------------------------------
    // Privacy Commitments (IRREVOCABLE)
    // ----------------------------------------------------------------

    /**
     * @notice Register an irrevocable privacy commitment.
     * @dev Once registered, commitments CANNOT be modified or deleted.
     * @param commitmentHash Hash of the commitment document.
     * @param commitmentURI  IPFS URI to the full commitment document.
     * @return commitmentId  The commitment ID.
     */
    function registerCommitment(bytes32 commitmentHash, string calldata commitmentURI)
        external
        onlyOwner
        returns (uint256 commitmentId)
    {
        if (commitmentHash == bytes32(0)) revert EmptyCommitment();

        commitmentId = nextCommitmentId++;

        commitments[commitmentId] = PrivacyCommitment({
            commitmentHash: commitmentHash,
            commitmentURI: commitmentURI,
            registeredAt: block.timestamp,
            registeredBy: msg.sender,
            active: true // IRREVOCABLE: always true
        });

        emit CommitmentRegistered(commitmentId, commitmentHash, commitmentURI);
    }

    // ----------------------------------------------------------------
    // Revenue Escrow
    // ----------------------------------------------------------------

    /**
     * @notice Deposit revenue into escrow for a given entity.
     * @dev Revenue is held in escrow and automatically routed to affected
     *      users if a privacy violation by this entity is verified.
     * @param entity The entity whose revenue is being escrowed.
     * @param token  ERC-20 token.
     * @param amount Amount to escrow.
     */
    function escrowRevenue(address entity, address token, uint256 amount)
        external
        nonReentrant
    {
        if (entity == address(0) || token == address(0)) revert ZeroAddress();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        RevenueEscrow storage e = escrows[entity][token];
        if (e.entity == address(0)) {
            e.entity = entity;
            e.token = token;
        }
        e.balance += amount;
        e.totalDeposited += amount;

        emit RevenueEscrowed(entity, token, amount);
    }

    // ----------------------------------------------------------------
    // Violation Reporting & Resolution
    // ----------------------------------------------------------------

    /**
     * @notice Report a privacy violation.
     * @param violator     The entity that violated privacy.
     * @param commitmentId Which commitment was violated.
     * @param evidenceURI  URI to the evidence.
     * @param evidenceHash Hash of the evidence.
     * @param affectedUsers Array of affected user addresses.
     * @return violationId The violation report ID.
     */
    function reportViolation(
        address violator,
        uint256 commitmentId,
        string calldata evidenceURI,
        bytes32 evidenceHash,
        address[] calldata affectedUsers
    ) external returns (uint256 violationId) {
        if (violator == address(0)) revert ZeroAddress();
        if (!commitments[commitmentId].active) revert CommitmentNotFound();
        if (affectedUsers.length == 0) revert NoAffectedUsers();

        violationId = nextViolationId++;

        ViolationReport storage v = _violations[violationId];
        v.reporter = msg.sender;
        v.violator = violator;
        v.commitmentId = commitmentId;
        v.evidenceURI = evidenceURI;
        v.evidenceHash = evidenceHash;
        v.status = ViolationStatus.Reported;
        v.reportedAt = block.timestamp;
        v.affectedUsers = affectedUsers;

        emit ViolationReported(violationId, msg.sender, violator, commitmentId);
    }

    /**
     * @notice Begin investigation of a violation report.
     */
    function investigateViolation(uint256 violationId) external onlyInvestigator {
        ViolationReport storage v = _violations[violationId];
        if (v.status != ViolationStatus.Reported) revert InvalidStatus();

        v.status = ViolationStatus.UnderInvestigation;
        v.investigator = msg.sender;

        emit ViolationInvestigationStarted(violationId, msg.sender);
    }

    /**
     * @notice Verify a violation and set compensation amount.
     * @param violationId        The violation to verify.
     * @param compensationAmount Total compensation to distribute to affected users.
     */
    function verifyViolation(uint256 violationId, uint256 compensationAmount)
        external
        onlyInvestigator
    {
        ViolationReport storage v = _violations[violationId];
        if (v.status != ViolationStatus.UnderInvestigation) revert InvalidStatus();

        v.status = ViolationStatus.Verified;
        v.compensationAmount = compensationAmount;
        v.resolvedAt = block.timestamp;

        emit ViolationVerified(violationId, compensationAmount);
    }

    /**
     * @notice Dismiss a violation report.
     */
    function dismissViolation(uint256 violationId) external onlyInvestigator {
        ViolationReport storage v = _violations[violationId];
        if (v.status != ViolationStatus.Reported &&
            v.status != ViolationStatus.UnderInvestigation) revert InvalidStatus();

        v.status = ViolationStatus.Dismissed;
        v.resolvedAt = block.timestamp;

        emit ViolationDismissed(violationId);
    }

    /**
     * @notice Execute automatic compensation from escrowed revenue.
     * @param violationId The verified violation.
     * @param token       The ERC-20 token to use from escrow.
     */
    function executeCompensation(uint256 violationId, address token)
        external
        onlyOwner
        nonReentrant
    {
        ViolationReport storage v = _violations[violationId];
        if (v.status != ViolationStatus.Verified) revert InvalidStatus();

        RevenueEscrow storage e = escrows[v.violator][token];
        if (e.balance < v.compensationAmount) revert InsufficientEscrow();

        uint256 perUser = v.compensationAmount / v.affectedUsers.length;
        uint256 totalPaid = 0;

        for (uint256 i = 0; i < v.affectedUsers.length; i++) {
            if (v.affectedUsers[i] != address(0)) {
                IERC20(token).safeTransfer(v.affectedUsers[i], perUser);
                totalPaid += perUser;
            }
        }

        e.balance -= totalPaid;
        v.status = ViolationStatus.Compensated;

        emit ViolationCompensated(violationId, totalPaid, v.affectedUsers.length);
    }

    // ----------------------------------------------------------------
    // Buyer Compliance
    // ----------------------------------------------------------------

    /**
     * @notice Buyer attests to compliance with privacy commitments.
     * @param commitmentIds Array of commitment IDs the buyer attests to.
     * @param proofURI      URI to compliance proof documentation.
     * @return complianceId The compliance attestation ID.
     */
    function attestCompliance(
        uint256[] calldata commitmentIds,
        string calldata proofURI
    ) external returns (uint256 complianceId) {
        if (buyerComplianceId[msg.sender] != 0) {
            // Check if existing attestation is still valid
            BuyerCompliance storage existing = buyerCompliances[buyerComplianceId[msg.sender]];
            if (existing.status == BuyerComplianceStatus.Attested) revert AlreadyAttested();
        }

        // Validate all commitments exist
        for (uint256 i = 0; i < commitmentIds.length; i++) {
            if (!commitments[commitmentIds[i]].active) revert CommitmentNotFound();
        }

        complianceId = ++nextBuyerComplianceId;

        buyerCompliances[complianceId] = BuyerCompliance({
            buyer: msg.sender,
            commitmentIds: commitmentIds,
            status: BuyerComplianceStatus.Attested,
            attestedAt: block.timestamp,
            complianceProofURI: proofURI
        });

        buyerComplianceId[msg.sender] = complianceId;

        emit BuyerComplianceAttested(complianceId, msg.sender);
    }

    /**
     * @notice Revoke a buyer's compliance attestation.
     * @param buyer The buyer whose compliance to revoke.
     */
    function revokeCompliance(address buyer) external onlyOwner {
        uint256 compId = buyerComplianceId[buyer];
        if (compId == 0) revert BuyerNotCompliant();

        buyerCompliances[compId].status = BuyerComplianceStatus.Revoked;

        emit BuyerComplianceRevoked(compId, buyer);
    }

    /**
     * @notice Check if a buyer is currently compliant.
     */
    function isBuyerCompliant(address buyer) external view returns (bool) {
        uint256 compId = buyerComplianceId[buyer];
        if (compId == 0) return false;
        return buyerCompliances[compId].status == BuyerComplianceStatus.Attested;
    }

    // ----------------------------------------------------------------
    // Investigator Management
    // ----------------------------------------------------------------

    function addInvestigator(address investigator) external onlyOwner {
        if (investigator == address(0)) revert ZeroAddress();
        isInvestigator[investigator] = true;
        emit InvestigatorAdded(investigator);
    }

    function removeInvestigator(address investigator) external onlyOwner {
        isInvestigator[investigator] = false;
        emit InvestigatorRemoved(investigator);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    function getCommitment(uint256 id) external view returns (PrivacyCommitment memory) {
        return commitments[id];
    }

    function getViolationStatus(uint256 id) external view returns (ViolationStatus) {
        return _violations[id].status;
    }

    function getViolationAffectedUsers(uint256 id) external view returns (address[] memory) {
        return _violations[id].affectedUsers;
    }

    function getEscrowBalance(address entity, address token) external view returns (uint256) {
        return escrows[entity][token].balance;
    }
}
