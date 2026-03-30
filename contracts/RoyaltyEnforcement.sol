// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IPRegistry.sol";

/**
 * @title RoyaltyEnforcement
 * @notice Auto-routes royalties on every qualifying transaction.
 *
 *  - 5 % of revenue every 90 days to NeoSafe.
 *  - Royalty: 2 % flat in perpetuity to IP holders.
 *  - No gas cost passed to IP holders (paid by caller / platform).
 *  - Qualifying types: resale, licensing, streaming, reproduction, derivative.
 *  - Owner can ADD types but NEVER remove existing ones (delegated to IPRegistry).
 */
contract RoyaltyEnforcement {

    // ─── Constants ───────────────────────────────────────────────────────

    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    uint16  public constant ROYALTY_BPS        = 200;   // 2 %
    uint16  public constant NEOSAFE_FEE_BPS    = 500;   // 5 %
    uint256 public constant REVENUE_PERIOD     = 90 days;

    // ─── State ───────────────────────────────────────────────────────────

    IPRegistry public immutable registry;

    struct RevenuePeriod {
        uint256 accumulated;       // wei accumulated this period
        uint256 periodStart;       // timestamp when current period began
        uint256 lastNeoSafePayout; // timestamp of last NeoSafe disbursement
    }

    /// @dev ipId => RevenuePeriod
    mapping(bytes32 => RevenuePeriod) public revenuePeriods;

    /// @dev ipId => total royalties paid to owner (lifetime)
    mapping(bytes32 => uint256) public totalRoyaltiesPaid;

    /// @dev ipId => total NeoSafe fees paid (lifetime)
    mapping(bytes32 => uint256) public totalNeoSafeFees;

    // ─── Events ──────────────────────────────────────────────────────────

    event RoyaltyPaid(
        bytes32 indexed ipId,
        address indexed ipOwner,
        uint256 amount,
        IPRegistry.TransactionType txType
    );

    event NeoSafeFeePaid(
        bytes32 indexed ipId,
        uint256 amount,
        uint256 periodRevenue
    );

    event RevenueRecorded(
        bytes32 indexed ipId,
        uint256 amount,
        IPRegistry.TransactionType txType
    );

    // ─── Errors ──────────────────────────────────────────────────────────

    error NotQualifyingType(bytes32 ipId, IPRegistry.TransactionType txType);
    error ZeroAmount();
    error TransferFailed();
    error PeriodNotElapsed(bytes32 ipId, uint256 nextEligible);

    // ─── Constructor ─────────────────────────────────────────────────────

    constructor(address _registry) {
        registry = IPRegistry(_registry);
    }

    // ─── Core: Process Qualifying Transaction ────────────────────────────

    /**
     * @notice Called on every qualifying transaction. Auto-routes 2 % royalty
     *         to the IP holder (gas paid by caller) and accumulates revenue
     *         for the 90-day NeoSafe fee.
     * @param ipId    Registered IP identifier.
     * @param txType  The transaction type (must be qualifying for this work).
     */
    function processTransaction(
        bytes32 ipId,
        IPRegistry.TransactionType txType
    ) external payable {
        if (msg.value == 0) revert ZeroAmount();

        // Verify this is a qualifying type for the IP
        if (!registry.isQualifyingType(ipId, txType))
            revert NotQualifyingType(ipId, txType);

        IPRegistry.IPRecord memory record = registry.getIPRecord(ipId);

        // ── Royalty to IP holder (2 % flat, perpetuity) ──
        uint256 royalty = (msg.value * ROYALTY_BPS) / 10_000;
        if (royalty > 0) {
            (bool ok, ) = record.owner.call{value: royalty}("");
            if (!ok) revert TransferFailed();
            totalRoyaltiesPaid[ipId] += royalty;
            emit RoyaltyPaid(ipId, record.owner, royalty, txType);
        }

        // ── Accumulate revenue for 90-day NeoSafe cycle ──
        RevenuePeriod storage rp = revenuePeriods[ipId];
        if (rp.periodStart == 0) {
            rp.periodStart = block.timestamp;
            rp.lastNeoSafePayout = block.timestamp;
        }
        rp.accumulated += msg.value;

        emit RevenueRecorded(ipId, msg.value, txType);
    }

    // ─── NeoSafe 90-Day Fee Disbursement ─────────────────────────────────

    /**
     * @notice Disburse 5 % of accumulated revenue to NeoSafe.
     *         Callable by anyone once the 90-day period has elapsed.
     */
    function disburseNeoSafeFee(bytes32 ipId) external {
        RevenuePeriod storage rp = revenuePeriods[ipId];
        uint256 nextEligible = rp.lastNeoSafePayout + REVENUE_PERIOD;

        if (block.timestamp < nextEligible)
            revert PeriodNotElapsed(ipId, nextEligible);

        uint256 fee = (rp.accumulated * NEOSAFE_FEE_BPS) / 10_000;

        if (fee > 0) {
            rp.accumulated = 0;
            rp.periodStart = block.timestamp;
            rp.lastNeoSafePayout = block.timestamp;

            (bool ok, ) = NEOSAFE.call{value: fee}("");
            if (!ok) revert TransferFailed();

            totalNeoSafeFees[ipId] += fee;
            emit NeoSafeFeePaid(ipId, fee, rp.accumulated);
        } else {
            // Reset period even if nothing to pay
            rp.accumulated = 0;
            rp.periodStart = block.timestamp;
            rp.lastNeoSafePayout = block.timestamp;
        }
    }

    // ─── Views ───────────────────────────────────────────────────────────

    function getRevenuePeriod(bytes32 ipId)
        external view returns (RevenuePeriod memory)
    {
        return revenuePeriods[ipId];
    }

    function nextNeoSafePayoutTime(bytes32 ipId)
        external view returns (uint256)
    {
        return revenuePeriods[ipId].lastNeoSafePayout + REVENUE_PERIOD;
    }

    // ─── Receive ETH ─────────────────────────────────────────────────────

    receive() external payable {}
}
