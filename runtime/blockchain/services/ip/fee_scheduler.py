"""
Fee Scheduler — routes 5 % of average revenue to NeoSafe every 90 days.

Part of Component 15 (IP and Royalty Management).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Optional

from runtime.blockchain.services.ip.revenue_tracker import RevenueTracker

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class FeePayment:
    """Record of a single NeoSafe fee disbursement."""
    ip_id: str
    amount_wei: int
    period_revenue_wei: int
    timestamp: float
    tx_hash: Optional[str] = None


class FeeScheduler:
    """
    Schedules and executes the 5 % NeoSafe fee every 90 days,
    based on the average revenue tracked by RevenueTracker.
    """

    NEOSAFE: str = NEOSAFE_ADDRESS
    FEE_BPS: int = 500          # 5 %
    PERIOD_SECONDS: int = 90 * 24 * 3600  # 90 days

    def __init__(self, revenue_tracker: RevenueTracker) -> None:
        """
        Args:
            revenue_tracker: The canonical RevenueTracker instance for lookups.
        """
        self._tracker = revenue_tracker
        # ip_id -> timestamp of last payout
        self._last_payouts: dict[str, float] = {}
        # Historical payout records
        self._payment_history: list[FeePayment] = []
        logger.info("FeeScheduler initialised — NeoSafe: %s", self.NEOSAFE)

    # ── Eligibility ───────────────────────────────────────────────────

    def is_period_elapsed(self, ip_id: str) -> bool:
        """Check whether 90 days have passed since the last payout."""
        last = self._last_payouts.get(ip_id)
        if last is None:
            period_start = self._tracker.get_period_start(ip_id)
            if period_start is None:
                return False
            return (time.time() - period_start) >= self.PERIOD_SECONDS
        return (time.time() - last) >= self.PERIOD_SECONDS

    def next_payout_time(self, ip_id: str) -> Optional[float]:
        """Return the timestamp when the next payout becomes eligible."""
        last = self._last_payouts.get(ip_id)
        if last is not None:
            return last + self.PERIOD_SECONDS

        period_start = self._tracker.get_period_start(ip_id)
        if period_start is None:
            return None
        return period_start + self.PERIOD_SECONDS

    # ── Fee Calculation ───────────────────────────────────────────────

    def calculate_fee(self, ip_id: str) -> int:
        """
        Calculate the NeoSafe fee for the current period.

        Returns:
            Fee amount in wei (5 % of accumulated period revenue).
        """
        period_revenue = self._tracker.get_current_period_revenue(ip_id)
        fee = (period_revenue * self.FEE_BPS) // 10_000
        return fee

    # ── Disbursement ──────────────────────────────────────────────────

    def disburse(self, ip_id: str, send_transaction_fn=None) -> Optional[FeePayment]:
        """
        Disburse the 5 % fee to NeoSafe if the 90-day period has elapsed.

        Args:
            ip_id: The IP work identifier.
            send_transaction_fn: Optional callable(to_address, amount_wei) -> tx_hash.
                If None, the payment is recorded locally without on-chain execution.

        Returns:
            FeePayment record, or None if the period has not elapsed or fee is zero.

        Raises:
            RuntimeError: If the period has not yet elapsed.
        """
        if not self.is_period_elapsed(ip_id):
            next_time = self.next_payout_time(ip_id)
            raise RuntimeError(
                f"90-day period has not elapsed for IP {ip_id}. "
                f"Next eligible: {next_time}"
            )

        fee = self.calculate_fee(ip_id)
        if fee == 0:
            logger.info("No revenue accumulated for IP %s — nothing to disburse.", ip_id)
            self._tracker.reset_period(ip_id)
            self._last_payouts[ip_id] = time.time()
            return None

        period_revenue = self._tracker.get_current_period_revenue(ip_id)

        tx_hash: Optional[str] = None
        if send_transaction_fn is not None:
            try:
                tx_hash = send_transaction_fn(self.NEOSAFE, fee)
            except Exception:
                logger.exception(
                    "Failed to send NeoSafe fee for IP %s (%d wei).", ip_id, fee
                )
                raise

        payment = FeePayment(
            ip_id=ip_id,
            amount_wei=fee,
            period_revenue_wei=period_revenue,
            timestamp=time.time(),
            tx_hash=tx_hash,
        )
        self._payment_history.append(payment)

        # Reset the period in the tracker
        self._tracker.reset_period(ip_id)
        self._last_payouts[ip_id] = time.time()

        logger.info(
            "Disbursed %d wei (5%% of %d wei) to NeoSafe for IP %s. tx=%s",
            fee, period_revenue, ip_id, tx_hash,
        )
        return payment

    # ── History ────────────────────────────────────────────────────────

    def get_payment_history(self, ip_id: Optional[str] = None) -> list[FeePayment]:
        """Return payment history, optionally filtered by IP."""
        if ip_id is None:
            return list(self._payment_history)
        return [p for p in self._payment_history if p.ip_id == ip_id]

    def total_fees_paid(self, ip_id: str) -> int:
        """Return total NeoSafe fees paid for an IP work (lifetime)."""
        return sum(p.amount_wei for p in self._payment_history if p.ip_id == ip_id)
