"""
Tier Registry — manages subscription tier definitions.

Part of Component 29 (Subscription Rewards).
Handles tier CRUD, activation/deactivation, and creator management.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class Frequency(Enum):
    """Subscription billing frequency."""
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    QUARTERLY = "quarterly"
    ANNUALLY = "annually"
    CUSTOM = "custom"


# Default period durations in seconds
FREQUENCY_SECONDS: Dict[Frequency, int] = {
    Frequency.DAILY: 86_400,
    Frequency.WEEKLY: 7 * 86_400,
    Frequency.MONTHLY: 30 * 86_400,
    Frequency.QUARTERLY: 90 * 86_400,
    Frequency.ANNUALLY: 365 * 86_400,
    Frequency.CUSTOM: 0,
}


@dataclass
class Tier:
    """A subscription tier definition."""
    tier_id: str
    creator: str
    payment_token: str
    price_wei: int
    period: int                  # Duration in seconds
    frequency: Frequency
    name: str
    metadata_uri: str
    active: bool = True
    subscriber_count: int = 0
    created_at: float = field(default_factory=time.time)


class TierRegistry:
    """
    Manages subscription tier definitions for creators.

    Creators can define multiple tiers with different pricing and durations.
    """

    def __init__(self) -> None:
        self._tiers: Dict[str, Tier] = {}
        self._by_creator: Dict[str, List[str]] = {}
        self._counter: int = 0
        logger.info("TierRegistry initialised.")

    def create_tier(
        self,
        creator: str,
        payment_token: str,
        price_wei: int,
        frequency: Frequency,
        name: str,
        metadata_uri: str = "",
        custom_period: int = 0,
    ) -> Tier:
        """
        Create a new subscription tier.

        Args:
            creator: Creator's wallet address.
            payment_token: Token used for payment.
            price_wei: Price per period in wei.
            frequency: Billing frequency.
            name: Human-readable tier name.
            metadata_uri: Optional metadata URI.
            custom_period: Duration in seconds (required for CUSTOM frequency).

        Returns:
            The created Tier.
        """
        if not creator.startswith("0x"):
            raise ValueError("Invalid creator address.")
        if price_wei <= 0:
            raise ValueError("Price must be positive.")
        if not name:
            raise ValueError("Tier name must not be empty.")

        if frequency == Frequency.CUSTOM:
            if custom_period <= 0:
                raise ValueError("Custom frequency requires a positive period.")
            period = custom_period
        else:
            period = FREQUENCY_SECONDS[frequency]

        self._counter += 1
        tid = f"TIER-{self._counter:08d}"

        tier = Tier(
            tier_id=tid,
            creator=creator,
            payment_token=payment_token,
            price_wei=price_wei,
            period=period,
            frequency=frequency,
            name=name,
            metadata_uri=metadata_uri,
        )
        self._tiers[tid] = tier
        self._by_creator.setdefault(creator, []).append(tid)

        logger.info(
            "Tier created | id=%s | creator=%s | name=%s | price=%d",
            tid, creator, name, price_wei,
        )
        return tier

    def update_tier(
        self,
        tier_id: str,
        caller: str,
        new_price_wei: Optional[int] = None,
        new_name: Optional[str] = None,
    ) -> Tier:
        """Update tier price and/or name. Only the creator can update."""
        tier = self._get_tier(tier_id)
        if tier.creator != caller:
            raise ValueError("Only the tier creator can update it.")
        if new_price_wei is not None:
            if new_price_wei <= 0:
                raise ValueError("Price must be positive.")
            tier.price_wei = new_price_wei
        if new_name is not None:
            if not new_name:
                raise ValueError("Name must not be empty.")
            tier.name = new_name
        logger.info("Tier updated | id=%s", tier_id)
        return tier

    def deactivate_tier(self, tier_id: str, caller: str) -> Tier:
        """Deactivate a tier. No new subscriptions allowed."""
        tier = self._get_tier(tier_id)
        if tier.creator != caller:
            raise ValueError("Only the tier creator can deactivate it.")
        tier.active = False
        logger.info("Tier deactivated | id=%s", tier_id)
        return tier

    def activate_tier(self, tier_id: str, caller: str) -> Tier:
        """Re-activate a deactivated tier."""
        tier = self._get_tier(tier_id)
        if tier.creator != caller:
            raise ValueError("Only the tier creator can activate it.")
        tier.active = True
        logger.info("Tier activated | id=%s", tier_id)
        return tier

    def increment_subscriber_count(self, tier_id: str) -> None:
        """Increment subscriber count (called by SubscriptionManager)."""
        self._get_tier(tier_id).subscriber_count += 1

    def decrement_subscriber_count(self, tier_id: str) -> None:
        """Decrement subscriber count."""
        tier = self._get_tier(tier_id)
        tier.subscriber_count = max(0, tier.subscriber_count - 1)

    def get_tier(self, tier_id: str) -> Optional[Tier]:
        """Get tier by ID or None."""
        return self._tiers.get(tier_id)

    def get_creator_tiers(self, creator: str) -> List[Tier]:
        """Get all tiers by a creator."""
        ids = self._by_creator.get(creator, [])
        return [self._tiers[tid] for tid in ids if tid in self._tiers]

    def _get_tier(self, tier_id: str) -> Tier:
        """Get tier or raise."""
        tier = self._tiers.get(tier_id)
        if tier is None:
            raise ValueError(f"Tier {tier_id} not found.")
        return tier
