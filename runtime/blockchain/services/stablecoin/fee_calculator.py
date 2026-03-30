"""
Fee Calculator
===============

Tiered fee calculation for stablecoin transfers that exceed the free
transfer limit. Fee tiers are based on transfer amount with lower
percentages for larger transfers.

All fee revenue routes to NeoSafe via FeeRouter.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import List, Optional, Tuple

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class FeeTier:
    """A single fee tier defining the rate for a transfer amount range.

    Attributes:
        min_amount: Minimum transfer amount for this tier (inclusive).
        max_amount: Maximum transfer amount for this tier (exclusive).
            None means no upper limit.
        rate_bps: Fee rate in basis points (1 bps = 0.01%).
        flat_fee: Optional flat fee added on top of the percentage.
    """
    min_amount: Decimal
    max_amount: Optional[Decimal]
    rate_bps: int
    flat_fee: Decimal = Decimal("0")

    def applies_to(self, amount: Decimal) -> bool:
        """Check if this tier applies to the given amount."""
        if amount < self.min_amount:
            return False
        if self.max_amount is not None and amount >= self.max_amount:
            return False
        return True

    def compute_fee(self, amount: Decimal) -> Decimal:
        """Compute fee for the given amount under this tier."""
        percentage_fee = amount * Decimal(self.rate_bps) / Decimal("10000")
        return percentage_fee + self.flat_fee


@dataclass
class FeeBreakdown:
    """Detailed fee calculation result."""
    transfer_amount: Decimal
    tier_used: FeeTier
    percentage_fee: Decimal
    flat_fee: Decimal
    total_fee: Decimal
    effective_rate_bps: int
    net_amount: Decimal


class FeeCalculator:
    """Tiered fee calculation for stablecoin transfers.

    Default tiers (can be overridden):
    - $0 to $100: 50 bps (0.50%)
    - $100 to $1,000: 30 bps (0.30%)
    - $1,000 to $10,000: 20 bps (0.20%)
    - $10,000 to $100,000: 10 bps (0.10%)
    - $100,000+: 5 bps (0.05%)

    Parameters
    ----------
    custom_tiers : list of FeeTier, optional
        Custom tier configuration to override defaults.
    minimum_fee : Decimal
        Minimum fee charged regardless of tier calculation.
    maximum_fee : Decimal or None
        Maximum fee cap. None means no cap.
    """

    DEFAULT_TIERS: List[FeeTier] = [
        FeeTier(min_amount=Decimal("0"), max_amount=Decimal("100"), rate_bps=50),
        FeeTier(min_amount=Decimal("100"), max_amount=Decimal("1000"), rate_bps=30),
        FeeTier(min_amount=Decimal("1000"), max_amount=Decimal("10000"), rate_bps=20),
        FeeTier(min_amount=Decimal("10000"), max_amount=Decimal("100000"), rate_bps=10),
        FeeTier(min_amount=Decimal("100000"), max_amount=None, rate_bps=5),
    ]

    def __init__(
        self,
        custom_tiers: Optional[List[FeeTier]] = None,
        minimum_fee: Decimal = Decimal("0.01"),
        maximum_fee: Optional[Decimal] = None,
    ) -> None:
        self._tiers = custom_tiers or list(self.DEFAULT_TIERS)
        self._minimum_fee = minimum_fee
        self._maximum_fee = maximum_fee
        # Sort tiers by min_amount
        self._tiers.sort(key=lambda t: t.min_amount)
        logger.info(
            "FeeCalculator initialised with %d tiers (min_fee=%.4f)",
            len(self._tiers), minimum_fee,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def calculate_fee(self, amount: Decimal) -> Decimal:
        """Calculate the fee for a transfer amount.

        Args:
            amount: The transfer amount.

        Returns:
            The total fee to charge.
        """
        breakdown = self.calculate_fee_breakdown(amount)
        return breakdown.total_fee

    def calculate_fee_breakdown(self, amount: Decimal) -> FeeBreakdown:
        """Calculate fee with full breakdown.

        Args:
            amount: The transfer amount.

        Returns:
            FeeBreakdown with detailed calculation.

        Raises:
            ValueError: If no tier matches the amount.
        """
        tier = self._find_tier(amount)
        if tier is None:
            raise ValueError(f"No fee tier found for amount {amount}")

        percentage_fee = amount * Decimal(tier.rate_bps) / Decimal("10000")
        total = percentage_fee + tier.flat_fee

        # Apply minimum
        total = max(total, self._minimum_fee)

        # Apply maximum
        if self._maximum_fee is not None:
            total = min(total, self._maximum_fee)

        effective_bps = int(total / amount * Decimal("10000")) if amount > 0 else 0

        return FeeBreakdown(
            transfer_amount=amount,
            tier_used=tier,
            percentage_fee=percentage_fee,
            flat_fee=tier.flat_fee,
            total_fee=total,
            effective_rate_bps=effective_bps,
            net_amount=amount - total,
        )

    def get_tiers(self) -> List[FeeTier]:
        """Return the current fee tier configuration."""
        return list(self._tiers)

    def update_tiers(self, tiers: List[FeeTier]) -> None:
        """Update the fee tier configuration.

        Args:
            tiers: New tier configuration.
        """
        self._tiers = sorted(tiers, key=lambda t: t.min_amount)
        logger.info("Fee tiers updated (%d tiers)", len(self._tiers))

    def estimate_fees(
        self, amounts: List[Decimal]
    ) -> List[Tuple[Decimal, Decimal]]:
        """Estimate fees for multiple amounts.

        Args:
            amounts: List of transfer amounts.

        Returns:
            List of (amount, fee) tuples.
        """
        return [(a, self.calculate_fee(a)) for a in amounts]

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _find_tier(self, amount: Decimal) -> Optional[FeeTier]:
        """Find the applicable fee tier for an amount."""
        for tier in self._tiers:
            if tier.applies_to(amount):
                return tier
        return None
