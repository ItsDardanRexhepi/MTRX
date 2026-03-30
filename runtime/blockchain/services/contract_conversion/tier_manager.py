"""
Tier Manager — Permanent Tier Tracking & Advancement
=====================================================

Tracks user revenue on a rolling 12-month basis and manages tier
advancement.  Tier advancement is **PERMANENT** — once a user reaches
a higher tier they can never drop back.

Thresholds (rolling 12-month cumulative platform revenue):
    Tier 1  : < 2 ETH
    Tier 2  : 2 - 5 ETH
    Tier 3  : > 5 ETH
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal
from enum import IntEnum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TIER1_CEILING = Decimal("2")    # < 2 ETH  -> Tier 1
TIER2_CEILING = Decimal("5")    # 2-5 ETH  -> Tier 2, > 5 ETH -> Tier 3
ROLLING_WINDOW_SECONDS = 365 * 24 * 60 * 60  # 365 days


class Tier(IntEnum):
    """Tier levels mirroring the on-chain enum."""
    TIER_1 = 0
    TIER_2 = 1
    TIER_3 = 2


# Revenue share basis points per tier.
TIER_SHARE_BPS: Dict[Tier, int] = {
    Tier.TIER_1: 1000,  # 10 %
    Tier.TIER_2: 500,   #  5 %
    Tier.TIER_3: 250,   #  2.5 %
}


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------

@dataclass
class RevenueEntry:
    """A single timestamped revenue event."""
    amount: Decimal
    timestamp: float  # UNIX epoch seconds

    @property
    def is_within_window(self) -> bool:
        """Return ``True`` if this entry falls within the rolling 12-month window."""
        return (time.time() - self.timestamp) <= ROLLING_WINDOW_SECONDS


@dataclass
class TierInfo:
    """Complete tier information for a user."""
    user_address: str
    current_tier: int                       # matches Tier IntEnum value
    cumulative_revenue: Decimal = Decimal("0")
    rolling_12m_revenue: Decimal = Decimal("0")
    tier_locked_at: float = 0.0             # UNIX timestamp of last advancement
    is_artist: bool = False
    highest_tier_ever: int = 0              # ensures permanence
    revenue_history: List[RevenueEntry] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Tier Manager
# ---------------------------------------------------------------------------

class TierManager:
    """
    Manages user tiers based on rolling 12-month platform revenue.

    Key invariant: **tier advancement is permanent**.  A user who once
    qualified for Tier 3 will remain Tier 3 even if their rolling
    revenue later drops below the threshold.

    Usage::

        tm = TierManager()
        tm.update_revenue("0xabc...", Decimal("1.5"))
        info = tm.get_user_tier("0xabc...")
    """

    def __init__(self, web3_provider: Any = None) -> None:
        """
        Parameters
        ----------
        web3_provider
            Optional ``web3.Web3`` instance for on-chain tier syncing.
        """
        self._w3 = web3_provider
        self._users: Dict[str, TierInfo] = {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_user_tier(self, user_address: str) -> TierInfo:
        """
        Retrieve the full tier information for *user_address*.

        Creates a default ``TierInfo`` (Tier 1) if the user has not been
        seen before.

        Parameters
        ----------
        user_address : str
            Ethereum address (``0x``-prefixed).

        Returns
        -------
        TierInfo
        """
        address = self._normalise(user_address)
        if address not in self._users:
            self._users[address] = TierInfo(
                user_address=address,
                current_tier=Tier.TIER_1,
                tier_locked_at=time.time(),
            )
            logger.info("Initialised new user tier record for %s (TIER_1)", address)
        return self._users[address]

    def update_revenue(self, user_address: str, amount: Decimal) -> TierInfo:
        """
        Record a revenue event for *user_address* and check for tier
        advancement.

        Parameters
        ----------
        user_address : str
            Ethereum address.
        amount : Decimal
            Revenue amount in ETH.

        Returns
        -------
        TierInfo
            Updated tier information.

        Raises
        ------
        ValueError
            If *amount* is non-positive.
        """
        if amount <= 0:
            raise ValueError(f"Revenue amount must be positive, got {amount}")

        address = self._normalise(user_address)
        info = self.get_user_tier(address)

        entry = RevenueEntry(amount=amount, timestamp=time.time())
        info.revenue_history.append(entry)
        info.cumulative_revenue += amount

        # Re-calculate rolling 12-month revenue.
        info.rolling_12m_revenue = self.get_rolling_12_month_revenue(address)

        # Check tier advancement.
        self.check_tier_advancement(address)

        logger.info(
            "Recorded %s ETH for %s (cumulative=%s, rolling_12m=%s, tier=%s)",
            amount, address, info.cumulative_revenue,
            info.rolling_12m_revenue, Tier(info.current_tier).name,
        )
        return info

    def check_tier_advancement(self, user_address: str) -> Optional[Tier]:
        """
        Evaluate whether the user qualifies for a higher tier and advance
        if so.

        Tier advancement is **PERMANENT** — the user can never drop back
        to a lower tier even if rolling revenue decreases.

        Parameters
        ----------
        user_address : str

        Returns
        -------
        Tier or None
            The new tier if advancement occurred, ``None`` otherwise.
        """
        address = self._normalise(user_address)
        info = self.get_user_tier(address)
        rolling = self.get_rolling_12_month_revenue(address)

        # Determine the tier the rolling revenue qualifies for.
        if rolling > TIER2_CEILING:
            qualified_tier = Tier.TIER_3
        elif rolling >= TIER1_CEILING:
            qualified_tier = Tier.TIER_2
        else:
            qualified_tier = Tier.TIER_1

        current = Tier(info.current_tier)

        # Only advance — never drop.
        if qualified_tier > current:
            self.advance_tier(address, qualified_tier)
            return qualified_tier

        return None

    def advance_tier(self, user_address: str, new_tier: Tier) -> TierInfo:
        """
        Permanently advance *user_address* to *new_tier*.

        Parameters
        ----------
        user_address : str
        new_tier : Tier

        Returns
        -------
        TierInfo

        Raises
        ------
        ValueError
            If *new_tier* is not higher than the user's current tier.
        """
        address = self._normalise(user_address)
        info = self.get_user_tier(address)
        current = Tier(info.current_tier)

        if new_tier <= current:
            raise ValueError(
                f"Cannot advance {address} from {current.name} to {new_tier.name}. "
                "Tier advancement must go upward and is permanent."
            )

        previous = current
        info.current_tier = int(new_tier)
        info.tier_locked_at = time.time()
        info.highest_tier_ever = max(info.highest_tier_ever, int(new_tier))

        logger.info(
            "Tier advanced for %s: %s -> %s (rolling_12m=%s ETH)",
            address, previous.name, new_tier.name, info.rolling_12m_revenue,
        )

        # Sync to chain if web3 is available.
        self._sync_tier_on_chain(address, new_tier)

        return info

    def get_rolling_12_month_revenue(self, user_address: str) -> Decimal:
        """
        Calculate the rolling 12-month cumulative revenue for *user_address*.

        Parameters
        ----------
        user_address : str

        Returns
        -------
        Decimal
            Sum of all revenue entries within the last 365 days.
        """
        address = self._normalise(user_address)
        info = self._users.get(address)
        if info is None:
            return Decimal("0")

        cutoff = time.time() - ROLLING_WINDOW_SECONDS
        total = Decimal("0")
        for entry in info.revenue_history:
            if entry.timestamp >= cutoff:
                total += entry.amount

        return total

    # ------------------------------------------------------------------
    # Batch & Query Helpers
    # ------------------------------------------------------------------

    def get_all_users(self) -> Dict[str, TierInfo]:
        """Return the full user-tier registry."""
        return dict(self._users)

    def get_users_by_tier(self, tier: Tier) -> List[TierInfo]:
        """Return all users at the specified tier."""
        return [
            info for info in self._users.values()
            if info.current_tier == int(tier)
        ]

    def get_tier_distribution(self) -> Dict[str, int]:
        """Return a count of users at each tier."""
        dist = {t.name: 0 for t in Tier}
        for info in self._users.values():
            tier_name = Tier(info.current_tier).name
            dist[tier_name] += 1
        return dist

    def prune_old_entries(self) -> int:
        """
        Remove revenue entries older than the 12-month window from all
        users.  Returns the total number of entries pruned.

        Note: pruning does **not** affect tier status since advancement
        is permanent.
        """
        cutoff = time.time() - ROLLING_WINDOW_SECONDS
        pruned = 0
        for info in self._users.values():
            before = len(info.revenue_history)
            info.revenue_history = [
                e for e in info.revenue_history if e.timestamp >= cutoff
            ]
            pruned += before - len(info.revenue_history)
            # Recalculate rolling.
            info.rolling_12m_revenue = sum(
                (e.amount for e in info.revenue_history), Decimal("0")
            )
        if pruned:
            logger.info("Pruned %d stale revenue entries across all users.", pruned)
        return pruned

    # ------------------------------------------------------------------
    # Private Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _normalise(address: str) -> str:
        """Normalise and validate an Ethereum address."""
        addr = address.strip()
        if not addr.startswith("0x") or len(addr) != 42:
            raise ValueError(f"Invalid Ethereum address: {addr}")
        return addr

    def _sync_tier_on_chain(self, address: str, tier: Tier) -> None:
        """Attempt to record a tier advancement on-chain."""
        if self._w3 is None:
            logger.debug("No web3 provider; skipping on-chain tier sync for %s", address)
            return

        try:
            # In production this would call ContractConversion.advanceTier()
            # via the Rexhepi gate.
            logger.info(
                "On-chain tier sync: %s advanced to %s", address, tier.name
            )
        except Exception as exc:
            logger.error("On-chain tier sync failed for %s: %s", address, exc)
