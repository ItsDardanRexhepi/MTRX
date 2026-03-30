"""
Fee Enforcer — enforces the MTRX payment fee schedule.

Part of Component 17 (Payments).

Fee rules:
- FREE for transactions under $1,000 (up to 2 free transactions per 48-hour window)
- 0.5% fee on transactions above $1,000
- Fees are collected to the NeoSafe address
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class FeeCalculation:
    """Result of a fee calculation."""
    sender: str
    amount_wei: int
    fee_wei: int
    fee_percent: float
    is_free: bool
    free_transactions_remaining: int
    reason: str
    neosafe_address: str = NEOSAFE_ADDRESS


@dataclass
class FreeTransactionWindow:
    """Tracks free transactions within a 48-hour window."""
    window_start: float
    transaction_count: int = 0
    transaction_timestamps: List[float] = field(default_factory=list)


class FeeEnforcer:
    """
    Enforces the MTRX payment fee schedule.

    Rules:
    1. Transactions under $1,000 equivalent are FREE
       - Limited to 2 free transactions per 48-hour rolling window per sender
       - After 2 free transactions, the 0.5% fee applies even under $1,000
    2. Transactions at or above $1,000 always incur a 0.5% fee
    3. All fees are sent to the NeoSafe address

    Dollar-equivalent thresholds use the Component 11 oracle for conversion.
    """

    FREE_THRESHOLD_USD: int = 1_000
    FEE_BPS: int = 50                  # 0.5%
    FREE_TX_LIMIT: int = 2
    FREE_WINDOW_SECONDS: int = 48 * 3600  # 48 hours

    def __init__(
        self,
        oracle: Optional[object] = None,
        eth_price_usd: float = 2000.0,
    ) -> None:
        """
        Args:
            oracle: Component 11 oracle for price conversion.
            eth_price_usd: Fallback ETH/USD price if oracle unavailable.
        """
        self._oracle = oracle
        self._eth_price_usd = eth_price_usd

        # sender -> FreeTransactionWindow
        self._windows: Dict[str, FreeTransactionWindow] = {}
        # Total fees collected
        self._total_fees_collected_wei: int = 0

        logger.info(
            "FeeEnforcer initialised | free_threshold=$%d | fee=%.1f%% | "
            "free_limit=%d per %dh",
            self.FREE_THRESHOLD_USD, self.FEE_BPS / 100,
            self.FREE_TX_LIMIT, self.FREE_WINDOW_SECONDS // 3600,
        )

    # ── Fee Calculation ───────────────────────────────────────────────

    def calculate_fee(
        self,
        sender: str,
        amount_wei: int,
        currency: str = "ETH",
    ) -> FeeCalculation:
        """
        Calculate the fee for a payment.

        Args:
            sender: Address of the payer.
            amount_wei: Payment amount in wei.
            currency: Currency code for dollar conversion.

        Returns:
            FeeCalculation with fee details.

        Raises:
            ValueError: If amount is non-positive.
        """
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        usd_value = self._to_usd(amount_wei, currency)
        free_remaining = self._get_free_remaining(sender)

        # Determine if this transaction qualifies for free
        is_free = False
        fee_wei = 0
        reason = ""

        if usd_value < self.FREE_THRESHOLD_USD:
            if free_remaining > 0:
                is_free = True
                fee_wei = 0
                reason = (
                    f"Transaction (${usd_value:,.2f}) is under ${self.FREE_THRESHOLD_USD:,} "
                    f"threshold. {free_remaining} free transaction(s) remaining in this 48h window."
                )
            else:
                is_free = False
                fee_wei = (amount_wei * self.FEE_BPS) // 10_000
                reason = (
                    f"Transaction is under ${self.FREE_THRESHOLD_USD:,} but the "
                    f"{self.FREE_TX_LIMIT} free transactions in this 48h window are used up. "
                    f"0.5% fee applied."
                )
        else:
            is_free = False
            fee_wei = (amount_wei * self.FEE_BPS) // 10_000
            reason = (
                f"Transaction (${usd_value:,.2f}) is at or above ${self.FREE_THRESHOLD_USD:,} "
                f"threshold. 0.5% fee applied."
            )

        fee_percent = (fee_wei / amount_wei * 100) if amount_wei > 0 else 0.0

        return FeeCalculation(
            sender=sender,
            amount_wei=amount_wei,
            fee_wei=fee_wei,
            fee_percent=fee_percent,
            is_free=is_free,
            free_transactions_remaining=max(free_remaining - (1 if is_free else 0), 0),
            reason=reason,
        )

    def record_transaction(self, sender: str, was_free: bool) -> None:
        """
        Record that a transaction occurred (for free transaction tracking).

        Args:
            sender: Address of the payer.
            was_free: Whether this transaction was fee-free.
        """
        if was_free:
            now = time.time()
            window = self._get_or_create_window(sender)
            window.transaction_count += 1
            window.transaction_timestamps.append(now)
            logger.debug(
                "Free transaction recorded for %s (%d/%d in window).",
                sender, window.transaction_count, self.FREE_TX_LIMIT,
            )

    def collect_fee(self, fee_wei: int) -> None:
        """Record fee collection to NeoSafe."""
        self._total_fees_collected_wei += fee_wei
        logger.info(
            "Fee collected: %d wei -> %s | total=%d",
            fee_wei, NEOSAFE_ADDRESS, self._total_fees_collected_wei,
        )

    # ── Queries ───────────────────────────────────────────────────────

    def get_free_remaining(self, sender: str) -> int:
        """Return the number of free transactions remaining for a sender."""
        return self._get_free_remaining(sender)

    def get_total_fees_collected(self) -> int:
        """Return total lifetime fees collected in wei."""
        return self._total_fees_collected_wei

    def get_fee_rate_bps(self) -> int:
        """Return the fee rate in basis points."""
        return self.FEE_BPS

    # ── Internal ──────────────────────────────────────────────────────

    def _get_free_remaining(self, sender: str) -> int:
        """Calculate remaining free transactions in the current 48h window."""
        window = self._windows.get(sender)
        if window is None:
            return self.FREE_TX_LIMIT

        now = time.time()
        # Purge expired timestamps
        cutoff = now - self.FREE_WINDOW_SECONDS
        window.transaction_timestamps = [
            ts for ts in window.transaction_timestamps if ts > cutoff
        ]
        window.transaction_count = len(window.transaction_timestamps)

        remaining = self.FREE_TX_LIMIT - window.transaction_count
        return max(remaining, 0)

    def _get_or_create_window(self, sender: str) -> FreeTransactionWindow:
        """Get or create the free transaction window for a sender."""
        if sender not in self._windows:
            self._windows[sender] = FreeTransactionWindow(window_start=time.time())
        return self._windows[sender]

    def _to_usd(self, amount_wei: int, currency: str = "ETH") -> float:
        """Convert wei amount to USD equivalent."""
        if self._oracle is not None:
            try:
                rate = self._oracle.get_price(currency, "USD")
                eth_amount = amount_wei / 10**18
                return eth_amount * rate
            except Exception:
                logger.warning("Oracle unavailable, using fallback ETH price.")

        eth_amount = amount_wei / 10**18
        return eth_amount * self._eth_price_usd
