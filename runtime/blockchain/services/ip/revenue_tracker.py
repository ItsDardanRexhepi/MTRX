"""
Revenue Tracker — tracks all IP revenue with 90-day rolling averages.

Part of Component 15 (IP and Royalty Management).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

logger = logging.getLogger(__name__)


class TransactionType(str, Enum):
    """Qualifying transaction types that can trigger royalties."""
    RESALE = "resale"
    LICENSING = "licensing"
    STREAMING = "streaming"
    REPRODUCTION = "reproduction"
    DERIVATIVE = "derivative"


@dataclass
class RevenueEntry:
    """Single revenue event for an IP work."""
    ip_id: str
    amount_wei: int
    transaction_type: TransactionType
    timestamp: float
    tx_hash: Optional[str] = None
    payer: Optional[str] = None


@dataclass
class PeriodSummary:
    """Aggregated revenue for a 90-day period."""
    period_start: float
    period_end: float
    total_revenue_wei: int
    transaction_count: int
    average_per_transaction_wei: float
    by_type: dict[TransactionType, int] = field(default_factory=dict)


class RevenueTracker:
    """
    Tracks all IP revenue and computes 90-day rolling averages.

    Revenue entries are stored per IP work and used by FeeScheduler
    to compute the 5 % NeoSafe fee every 90 days.
    """

    PERIOD_SECONDS: int = 90 * 24 * 3600  # 90 days

    def __init__(self) -> None:
        # ip_id -> list of RevenueEntry (chronological)
        self._ledger: dict[str, list[RevenueEntry]] = {}
        # ip_id -> running total for current period
        self._period_totals: dict[str, int] = {}
        # ip_id -> period start timestamp
        self._period_starts: dict[str, float] = {}
        logger.info("RevenueTracker initialised.")

    # ── Recording ─────────────────────────────────────────────────────

    def record_revenue(self, entry: RevenueEntry) -> None:
        """
        Record a revenue event.

        Args:
            entry: The revenue entry to record.

        Raises:
            ValueError: If the amount is non-positive.
        """
        if entry.amount_wei <= 0:
            raise ValueError(f"Revenue amount must be positive, got {entry.amount_wei}")

        ip_id = entry.ip_id

        if ip_id not in self._ledger:
            self._ledger[ip_id] = []
            self._period_totals[ip_id] = 0
            self._period_starts[ip_id] = entry.timestamp

        self._ledger[ip_id].append(entry)
        self._period_totals[ip_id] += entry.amount_wei

        logger.debug(
            "Recorded revenue for IP %s: %d wei (%s)",
            ip_id, entry.amount_wei, entry.transaction_type.value,
        )

    # ── Queries ───────────────────────────────────────────────────────

    def get_total_revenue(self, ip_id: str) -> int:
        """Return lifetime total revenue in wei for an IP work."""
        entries = self._ledger.get(ip_id, [])
        return sum(e.amount_wei for e in entries)

    def get_current_period_revenue(self, ip_id: str) -> int:
        """Return accumulated revenue for the current 90-day period."""
        return self._period_totals.get(ip_id, 0)

    def get_period_start(self, ip_id: str) -> Optional[float]:
        """Return the timestamp when the current period started."""
        return self._period_starts.get(ip_id)

    def get_90day_average(self, ip_id: str) -> float:
        """
        Compute the average daily revenue over the current 90-day window.

        Returns:
            Average daily revenue in wei (float). Zero if no data.
        """
        start = self._period_starts.get(ip_id)
        if start is None:
            return 0.0

        elapsed = time.time() - start
        if elapsed <= 0:
            return 0.0

        days_elapsed = elapsed / 86_400
        total = self._period_totals.get(ip_id, 0)
        return total / max(days_elapsed, 1.0)

    def get_period_summary(self, ip_id: str) -> Optional[PeriodSummary]:
        """
        Build a summary for the current period.

        Returns:
            PeriodSummary or None if no data exists.
        """
        start = self._period_starts.get(ip_id)
        if start is None:
            return None

        entries = self._ledger.get(ip_id, [])
        period_entries = [e for e in entries if e.timestamp >= start]

        if not period_entries:
            return None

        total = sum(e.amount_wei for e in period_entries)
        by_type: dict[TransactionType, int] = {}
        for e in period_entries:
            by_type[e.transaction_type] = by_type.get(e.transaction_type, 0) + e.amount_wei

        return PeriodSummary(
            period_start=start,
            period_end=start + self.PERIOD_SECONDS,
            total_revenue_wei=total,
            transaction_count=len(period_entries),
            average_per_transaction_wei=total / len(period_entries),
            by_type=by_type,
        )

    def get_revenue_by_type(
        self, ip_id: str, tx_type: TransactionType
    ) -> int:
        """Return total revenue for a specific transaction type."""
        entries = self._ledger.get(ip_id, [])
        return sum(e.amount_wei for e in entries if e.transaction_type == tx_type)

    def get_entry_count(self, ip_id: str) -> int:
        """Return the number of revenue entries for an IP work."""
        return len(self._ledger.get(ip_id, []))

    # ── Period Reset ──────────────────────────────────────────────────

    def reset_period(self, ip_id: str) -> int:
        """
        Reset the current period accumulator (called after NeoSafe payout).

        Returns:
            The accumulated amount that was reset.
        """
        accumulated = self._period_totals.get(ip_id, 0)
        self._period_totals[ip_id] = 0
        self._period_starts[ip_id] = time.time()
        logger.info(
            "Period reset for IP %s — accumulated was %d wei.", ip_id, accumulated
        )
        return accumulated
