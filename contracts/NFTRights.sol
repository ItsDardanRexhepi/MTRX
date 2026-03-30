// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IOpenMatrixNFT
 * @notice Interface to the OpenMatrixNFT contract for querying token info
 */
interface IOpenMatrixNFT {
    function getCreator(uint256 tokenId) external view returns (address);
    function getCreatorRoyaltyBps(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

/**
 * @title NFTRights
 * @author OpenMatrix Platform
 * @notice Rights management contract with 90-day valuation assessment and 7-day payment window.
 *
 * Lifecycle:
 *   1. At mint: startValuationTimer() called by OpenMatrixNFT contract
 *   2. After 90 days: anyone can call assessValue() to trigger valuation
 *   3. Creator has 7 days to pay 10% of assessed value
 *   4. If payment not received within 7 days: rights revert 100% to platform
 *      - Automatic, no human intervention, no exceptions
 *
 * NeoSafe: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
 */
contract NFTRights is Ownable, ReentrancyGuard {

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice NeoSafe treasury
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Valuation assessment period: 90 days from mint
    uint256 public constant VALUATION_PERIOD = 90 days;

    /// @notice Payment window after valuation: 7 days
    uint256 public constant PAYMENT_WINDOW = 7 days;

    /// @notice Payment percentage of assessed value (10% = 1000 bps)
    uint256 public constant PAYMENT_PERCENTAGE_BPS = 1000;

    /// @notice BPS denominator
    uint256 private constant BPS_DENOMINATOR = 10000;

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    /// @notice Reference to the OpenMatrixNFT contract
    IOpenMatrixNFT public nftContract;

    /// @notice Platform address that receives reverted rights
    address public platformAddress;

    /// @notice Rights status for each token
    enum RightsStatus {
        ACTIVE,              // Normal — creator holds rights
        VALUATION_PENDING,   // 90 days elapsed, awaiting valuation assessment
        PAYMENT_PENDING,     // Valuation assessed, awaiting creator payment
        PAYMENT_RECEIVED,    // Creator paid — rights confirmed permanently
        RIGHTS_REVERTED      // Creator failed to pay — rights reverted to platform
    }

    /// @notice Per-token rights tracking
    struct TokenRights {
        uint256 mintTimestamp;          // When the valuation timer started
        uint256 valuationDeadline;      // mintTimestamp + 90 days
        uint256 assessedValue;          // Value determined at 90-day mark
        uint256 paymentDeadline;        // valuationDeadline + 7 days (set after assessment)
        uint256 requiredPayment;        // 10% of assessed value
        uint256 paymentReceived;        // Amount actually paid
        address creator;                // Original creator address
        RightsStatus status;            // Current rights status
        string valuationMethodology;    // How the value was determined
        bool timerActive;               // Whether the timer has been started
    }

    /// @notice Mapping from tokenId to rights data
    mapping(uint256 => TokenRights) public tokenRights;

    /// @notice Authorized callers (the NFT contract and admin)
    mapping(address => bool) public authorizedCallers;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event ValuationTimerStarted(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 valuationDeadline
    );

    event ValuationAssessed(
        uint256 indexed tokenId,
        uint256 assessedValue,
        uint256 requiredPayment,
        uint256 paymentDeadline,
        string methodology
    );

    event PaymentRequested(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 requiredPayment,
        uint256 paymentDeadline
    );

    event PaymentReceived(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );

    event RightsReverted(
        uint256 indexed tokenId,
        address indexed previousCreator,
        address indexed platform,
        uint256 assessedValue,
        uint256 reversionTimestamp
    );

    event PlatformAddressUpdated(address indexed newPlatform);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyAuthorized() {
        require(
            authorizedCallers[msg.sender] || msg.sender == owner(),
            "NFTRights: caller not authorized"
        );
        _;
    }

    modifier tokenTimerActive(uint256 tokenId) {
        require(tokenRights[tokenId].timerActive, "NFTRights: timer not started for this token");
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(address _nftContract, address _platformAddress) Ownable(msg.sender) {
        require(_nftContract != address(0), "NFTRights: NFT contract cannot be zero");
        require(_platformAddress != address(0), "NFTRights: platform address cannot be zero");

        nftContract = IOpenMatrixNFT(_nftContract);
        platformAddress = _platformAddress;

        // Authorize the NFT contract to start timers
        authorizedCallers[_nftContract] = true;
    }

    // ──────────────────────────────────────────────
    //  Core Functions
    // ──────────────────────────────────────────────

    /**
     * @notice Start the 90-day valuation assessment timer. Called by OpenMatrixNFT at mint time.
     * @param tokenId The newly minted token ID
     */
    function startValuationTimer(uint256 tokenId) external onlyAuthorized {
        require(!tokenRights[tokenId].timerActive, "NFTRights: timer already active");

        address creator = nftContract.getCreator(tokenId);
        require(creator != address(0), "NFTRights: token has no creator");

        uint256 deadline = block.timestamp + VALUATION_PERIOD;

        tokenRights[tokenId] = TokenRights({
            mintTimestamp: block.timestamp,
            valuationDeadline: deadline,
            assessedValue: 0,
            paymentDeadline: 0,
            requiredPayment: 0,
            paymentReceived: 0,
            creator: creator,
            status: RightsStatus.ACTIVE,
            valuationMethodology: "",
            timerActive: true
        });

        emit ValuationTimerStarted(tokenId, creator, deadline);
    }

    /**
     * @notice Assess the value of an NFT after the 90-day period.
     *         Can be called by anyone after the valuation deadline.
     *         The assessed value and methodology are supplied by the off-chain valuation engine
     *         (Component 3 Python runtime) via the authorized caller.
     *
     * @param tokenId     Token ID to assess
     * @param value       Assessed value in wei (from off-chain valuation engine)
     * @param methodology Description of how the value was determined
     */
    function assessValue(
        uint256 tokenId,
        uint256 value,
        string calldata methodology
    ) external onlyAuthorized tokenTimerActive(tokenId) {
        TokenRights storage rights = tokenRights[tokenId];

        require(rights.status == RightsStatus.ACTIVE, "NFTRights: invalid status for assessment");
        require(block.timestamp >= rights.valuationDeadline, "NFTRights: 90-day period not elapsed");
        require(value > 0, "NFTRights: assessed value must be > 0");

        uint256 paymentDeadline = block.timestamp + PAYMENT_WINDOW;
        uint256 requiredPayment = (value * PAYMENT_PERCENTAGE_BPS) / BPS_DENOMINATOR;

        rights.assessedValue = value;
        rights.paymentDeadline = paymentDeadline;
        rights.requiredPayment = requiredPayment;
        rights.status = RightsStatus.PAYMENT_PENDING;
        rights.valuationMethodology = methodology;

        emit ValuationAssessed(tokenId, value, requiredPayment, paymentDeadline, methodology);
        emit PaymentRequested(tokenId, rights.creator, requiredPayment, paymentDeadline);
    }

    /**
     * @notice Request payment notification — emits event for off-chain systems to notify creator.
     *         Can be called by anyone after valuation is assessed.
     * @param tokenId Token ID
     */
    function requestPayment(uint256 tokenId) external tokenTimerActive(tokenId) {
        TokenRights storage rights = tokenRights[tokenId];
        require(
            rights.status == RightsStatus.PAYMENT_PENDING,
            "NFTRights: no payment pending"
        );
        require(block.timestamp <= rights.paymentDeadline, "NFTRights: payment window expired");

        emit PaymentRequested(tokenId, rights.creator, rights.requiredPayment, rights.paymentDeadline);
    }

    /**
     * @notice Creator pays the required 10% of assessed value to retain rights.
     *         Payment goes to NeoSafe treasury.
     * @param tokenId Token ID to pay for
     */
    function makePayment(uint256 tokenId) external payable nonReentrant tokenTimerActive(tokenId) {
        TokenRights storage rights = tokenRights[tokenId];

        require(rights.status == RightsStatus.PAYMENT_PENDING, "NFTRights: no payment pending");
        require(block.timestamp <= rights.paymentDeadline, "NFTRights: payment window expired");
        require(msg.sender == rights.creator, "NFTRights: only creator can pay");
        require(msg.value >= rights.requiredPayment, "NFTRights: insufficient payment");

        rights.paymentReceived = msg.value;
        rights.status = RightsStatus.PAYMENT_RECEIVED;

        // Route payment to NeoSafe
        (bool sent, ) = NEOSAFE.call{value: msg.value}("");
        require(sent, "NFTRights: payment to NeoSafe failed");

        emit PaymentReceived(tokenId, rights.creator, msg.value, block.timestamp);
    }

    /**
     * @notice Execute rights reversion if the creator has not paid within the 7-day window.
     *         Automatic, no human intervention, no exceptions.
     *         Can be called by ANYONE after the payment deadline has passed.
     *
     * @param tokenId Token ID whose rights should revert
     */
    function executeRightsReversion(uint256 tokenId) external nonReentrant tokenTimerActive(tokenId) {
        TokenRights storage rights = tokenRights[tokenId];

        require(
            rights.status == RightsStatus.PAYMENT_PENDING,
            "NFTRights: not in payment-pending status"
        );
        require(
            block.timestamp > rights.paymentDeadline,
            "NFTRights: payment window still open"
        );

        // Rights revert 100% completely and permanently to platform
        rights.status = RightsStatus.RIGHTS_REVERTED;

        // Transfer the NFT to the platform address
        address currentOwner = nftContract.ownerOf(tokenId);
        if (currentOwner != platformAddress) {
            // The NFT contract must have approved this contract for transfers,
            // or this contract must be an approved operator
            try nftContract.transferFrom(currentOwner, platformAddress, tokenId) {
                // Transfer successful
            } catch {
                // If transfer fails (e.g., no approval), the rights status is still reverted
                // Platform can claim the NFT separately
            }
        }

        emit RightsReverted(
            tokenId,
            rights.creator,
            platformAddress,
            rights.assessedValue,
            block.timestamp
        );
    }

    // ──────────────────────────────────────────────
    //  Batch Operations (for automation)
    // ──────────────────────────────────────────────

    /**
     * @notice Check and execute reversion for multiple tokens in a single transaction.
     *         Designed for automated keeper/cron job execution.
     * @param tokenIds Array of token IDs to check
     * @return reverted Array of token IDs that were actually reverted
     */
    function batchCheckAndRevert(uint256[] calldata tokenIds) external returns (uint256[] memory reverted) {
        uint256[] memory temp = new uint256[](tokenIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            TokenRights storage rights = tokenRights[tokenIds[i]];

            if (
                rights.timerActive &&
                rights.status == RightsStatus.PAYMENT_PENDING &&
                block.timestamp > rights.paymentDeadline
            ) {
                rights.status = RightsStatus.RIGHTS_REVERTED;

                address currentOwner = nftContract.ownerOf(tokenIds[i]);
                if (currentOwner != platformAddress) {
                    try nftContract.transferFrom(currentOwner, platformAddress, tokenIds[i]) {} catch {}
                }

                emit RightsReverted(
                    tokenIds[i],
                    rights.creator,
                    platformAddress,
                    rights.assessedValue,
                    block.timestamp
                );

                temp[count] = tokenIds[i];
                count++;
            }
        }

        reverted = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            reverted[j] = temp[j];
        }
    }

    // ──────────────────────────────────────────────
    //  View Functions
    // ──────────────────────────────────────────────

    /**
     * @notice Get the current rights status for a token
     */
    function getRightsStatus(uint256 tokenId) external view returns (RightsStatus) {
        return tokenRights[tokenId].status;
    }

    /**
     * @notice Get time remaining until valuation deadline
     * @return remaining Seconds remaining (0 if deadline passed)
     */
    function getTimeUntilValuation(uint256 tokenId) external view returns (uint256 remaining) {
        TokenRights storage rights = tokenRights[tokenId];
        if (!rights.timerActive || block.timestamp >= rights.valuationDeadline) {
            return 0;
        }
        return rights.valuationDeadline - block.timestamp;
    }

    /**
     * @notice Get time remaining in the payment window
     * @return remaining Seconds remaining (0 if not in payment window or expired)
     */
    function getPaymentTimeRemaining(uint256 tokenId) external view returns (uint256 remaining) {
        TokenRights storage rights = tokenRights[tokenId];
        if (rights.status != RightsStatus.PAYMENT_PENDING || block.timestamp >= rights.paymentDeadline) {
            return 0;
        }
        return rights.paymentDeadline - block.timestamp;
    }

    /**
     * @notice Check if a token's rights have been reverted
     */
    function isReverted(uint256 tokenId) external view returns (bool) {
        return tokenRights[tokenId].status == RightsStatus.RIGHTS_REVERTED;
    }

    /**
     * @notice Check if a token is eligible for rights reversion (deadline passed, unpaid)
     */
    function isEligibleForReversion(uint256 tokenId) external view returns (bool) {
        TokenRights storage rights = tokenRights[tokenId];
        return (
            rights.timerActive &&
            rights.status == RightsStatus.PAYMENT_PENDING &&
            block.timestamp > rights.paymentDeadline
        );
    }

    /**
     * @notice Get full rights information for a token
     */
    function getFullRightsInfo(uint256 tokenId) external view returns (
        uint256 mintTimestamp,
        uint256 valuationDeadline,
        uint256 assessedValue,
        uint256 paymentDeadline,
        uint256 requiredPayment,
        uint256 paymentReceived,
        address creator,
        RightsStatus status,
        string memory methodology
    ) {
        TokenRights storage rights = tokenRights[tokenId];
        return (
            rights.mintTimestamp,
            rights.valuationDeadline,
            rights.assessedValue,
            rights.paymentDeadline,
            rights.requiredPayment,
            rights.paymentReceived,
            rights.creator,
            rights.status,
            rights.valuationMethodology
        );
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    function setPlatformAddress(address _platform) external onlyOwner {
        require(_platform != address(0), "NFTRights: zero address");
        platformAddress = _platform;
        emit PlatformAddressUpdated(_platform);
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "NFTRights: zero address");
        nftContract = IOpenMatrixNFT(_nftContract);
        authorizedCallers[_nftContract] = true;
    }

    /**
     * @notice Contract can receive ETH (for payment routing)
     */
    receive() external payable {}
}
