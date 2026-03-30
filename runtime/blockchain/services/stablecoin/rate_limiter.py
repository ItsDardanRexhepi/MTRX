"""
Transfer Rate Limiter
======================

Enforces the 2-per-48-hour rolling window free transfer limit.
Each wallet gets up to 2 free transfers within any 48-hour rolling
window. Transfers beyond the limit incur fees calculated by
FeeCalculator.

The window is rolling, not fixed -- each transfer's timestamp is
tracked and old entries fall off after 48 hours.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Rate limit constants
FREE_TRANSFER_LIMIT: int = 2
WINDOW_SECONDS: int = 48 * 3600  # 48 hours


@dataclass
class TransferRecord:
    """A recorded transfer for rate-limiting purposes."""
    wallet_address: str
    timestamp: float
    amount: Decimal
    was_free: bool
    fee_charged: Decimal = Decimal("0")


@dataclass
class RateLimitStatus:
    """Current rate limit status for a wallet."""
    wallet_address: str
    free_transfers_used: int
    free_transfers_remaining: int
    window_resets_at: Optional[float]
    next_free_at: Optional[float]
    is_rate_limited: bool


class TransferRateLimiter:
    """2-per-48-hour rolling window free transfer limiter.

    Each wallet gets 2 free transfers per rolling 48-hour window.
    When the limit is exhausted, subsequent transfers incur fees.
    Old transfer records automatically fall off after 48 hours.

    Parameters
    ----------
    fee_calculator : Any, optional
        FeeCalculator for computing fees on rate-limited transfers.
    free_limit : int
        Number of free transfers per window (default 2).
    window_seconds : int
        Rolling window duration in seconds (default 48 hours).
    """

    def __init__(
        self,
        fee_calculator: Any = None,
        free_limit: int = FREE_TRANSFER_LIMIT,
        window_seconds: int = WINDOW_SECONDS,
    ) -> None:
        self._fee_calculator = fee_calculator
        self._free_limit = free_limit
        self._window_seconds = window_seconds
        self._transfer_records: Dict[str, List[TransferRecord]] = {}
        logger.info(
            "TransferRateLimiter initialised (free=%d, window=%dh)",
            free_limit, window_seconds // 3600,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check_transfer(
        self, wallet_address: str, amount: Decimal
    ) -> Tuple[bool, Decimal]:
        """Check whether a transfer is free and calculate any fee.

        Does NOT record the transfer. Use record_transfer() after the
        transfer is executed.

        Args:
            wallet_address: The sending wallet.
            amount: Transfer amount.

        Returns:
            Tuple of (is_free, fee_amount). fee_amount is 0 if free.
        """
        self._purge_expired(wallet_address)
        recent = self._transfer_records.get(wallet_address, [])
        used = len(recent)

        if used < self._free_limit:
            return True, Decimal("0")

        # Rate limited -- calculate fee
        fee = self._calculate_fee(amount)
        return False, fee

    def record_transfer(
        self,
        wallet_address: str,
        amount: Decimal,
        was_free: bool,
        fee_charged: Decimal = Decimal("0"),
    ) -> TransferRecord:
        """Record a completed transfer for rate-limiting.

        Args:
            wallet_address: The sending wallet.
            amount: Transfer amount.
            was_free: Whether the transfer was free.
            fee_charged: Fee charged (0 if free).

        Returns:
            The recorded TransferRecord.
        """
        record = TransferRecord(
            wallet_address=wallet_address,
            timestamp=time.time(),
            amount=amount,
            was_free=was_free,
            fee_charged=fee_charged,
        )

        if wallet_address not in self._transfer_records:
            self._transfer_records[wallet_address] = []
        self._transfer_records[wallet_address].append(record)

        logger.debug(
            "Transfer recorded: %s amount=%.4f free=%s fee=%.4f",
            wallet_address, amount, was_free, fee_charged,
        )
        return record

    def get_status(self, wallet_address: str) -> RateLimitStatus:
        """Get the current rate limit status for a wallet.

        Args:
            wallet_address: The wallet to check.

        Returns:
            RateLimitStatus with current window information.
        """
        self._purge_expired(wallet_address)
        recent = self._transfer_records.get(wallet_address, [])
        used = len(recent)
        remaining = max(0, self._free_limit - used)
        is_limited = remaining == 0

        # Calculate when the window resets (oldest transfer falls off)
        window_resets_at: Optional[float] = None
        next_free_at: Optional[float] = None

        if recent:
            oldest = min(r.timestamp for r in recent)
            window_resets_at = oldest + self._window_seconds
            if is_limited:
                next_free_at = window_resets_at

        return RateLimitStatus(
            wallet_address=wallet_address,
            free_transfers_used=used,
            free_transfers_remaining=remaining,
            window_resets_at=window_resets_at,
            next_free_at=next_free_at,
            is_rate_limited=is_limited,
        )

    def get_transfer_history(
        self, wallet_address: str, include_expired: bool = False
    ) -> List[TransferRecord]:
        """Get transfer history for a wallet.

        Args:
            wallet_address: The wallet to query.
            include_expired: Whether to include transfers outside the window.

        Returns:
            List of TransferRecord entries.
        """
        if not include_expired:
            self._purge_expired(wallet_address)
        return list(self._transfer_records.get(wallet_address, []))

    def reset_limit(self, wallet_address: str) -> None:
        """Admin override: reset the rate limit for a wallet.

        Use sparingly -- intended for dispute resolutions or
        platform operational needs.

        Args:
            wallet_address: The wallet to reset.
        """
        self._transfer_records.pop(wallet_address, None)
        logger.warning("Rate limit reset for %s (admin override)", wallet_address)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _purge_expired(self, wallet_address: str) -> None:
        """Remove transfer records outside the rolling window."""
        records = self._transfer_records.get(wallet_address)
        if not records:
            return
        cutoff = time.time() - self._window_seconds
        self._transfer_records[wallet_address] = [
            r for r in records if r.timestamp > cutoff
        ]

    def _calculate_fee(self, amount: Decimal) -> Decimal:
        """Calculate fee for a rate-limited transfer."""
        if self._fee_calculator:
            return self._fee_calculator.calculate_fee(amount)
        # Default: 0.1% fee
        return amount * Decimal("0.001")
