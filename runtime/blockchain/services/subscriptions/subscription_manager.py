"""
Subscription Manager — orchestrates the full subscription lifecycle.

Part of Component 29 (Subscription Rewards).
Handles subscribing, renewing, cancelling, and querying subscription state.
10% platform fee on all payments flows to NeoSafe.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

from runtime.blockchain.services.subscriptions.tier_registry import (
    TierRegistry, Tier, Frequency,
)
from runtime.blockchain.services.subscriptions.renewal_engine import RenewalEngine

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
PLATFORM_FEE_BPS: int = 1000  # 10%


class SubscriptionStatus(Enum):
    """Subscription lifecycle states."""
    ACTIVE = "active"
    GRACE_PERIOD = "grace_period"
    CANCELLED = "cancelled"
    LAPSED = "lapsed"


@dataclass
class Subscription:
    """A user's subscription to a tier."""
    subscription_id: str
    tier_id: str
    subscriber: str
    start_time: float = field(default_factory=time.time)
    expires_at: float = 0.0
    auto_renew: bool = True
    cancelled: bool = False
    retry_used: bool = False
    total_paid_wei: int = 0
    renewal_count: int = 0


@dataclass
class PaymentRecord:
    """Record of a subscription payment."""
    subscription_id: str
    subscriber: str
    creator: str
    amount_wei: int
    platform_fee_wei: int
    creator_amount_wei: int
    payment_token: str
    timestamp: float = field(default_factory=time.time)


class SubscriptionManager:
    """
    Orchestrates subscriptions: subscribe, renew, cancel, query status.

    Architecture:
    - TierRegistry: tier definitions
    - RenewalEngine: auto-renewal and retry logic
    - 10% platform fee sent to NeoSafe on every payment
    """

    def __init__(
        self,
        tier_registry: Optional[TierRegistry] = None,
        renewal_engine: Optional[RenewalEngine] = None,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._tiers = tier_registry or TierRegistry()
        self._renewals = renewal_engine or RenewalEngine()
        self._execute = execute_fn
        self._subscriptions: Dict[str, Subscription] = {}
        self._by_subscriber: Dict[str, List[str]] = {}
        self._payments: List[PaymentRecord] = []
        self._counter: int = 0
        logger.info("SubscriptionManager initialised.")

    # ── Tier Passthrough ──────────────────────────────────────────────

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
        """Create a subscription tier (delegates to TierRegistry)."""
        return self._tiers.create_tier(
            creator=creator,
            payment_token=payment_token,
            price_wei=price_wei,
            frequency=frequency,
            name=name,
            metadata_uri=metadata_uri,
            custom_period=custom_period,
        )

    # ── Subscribe ─────────────────────────────────────────────────────

    def subscribe(
        self,
        subscriber: str,
        tier_id: str,
        auto_renew: bool = True,
    ) -> Subscription:
        """
        Subscribe a user to a tier.

        Args:
            subscriber: Subscriber's wallet address.
            tier_id: The tier to subscribe to.
            auto_renew: Whether to auto-renew.

        Returns:
            The created Subscription.
        """
        if not subscriber.startswith("0x"):
            raise ValueError("Invalid subscriber address.")
        tier = self._tiers.get_tier(tier_id)
        if tier is None:
            raise ValueError(f"Tier {tier_id} not found.")
        if not tier.active:
            raise ValueError(f"Tier {tier_id} is not active.")

        # Process initial payment
        fee_wei, creator_amount = self._compute_fee(tier.price_wei)
        self._record_payment(
            subscription_id="pending",
            subscriber=subscriber,
            creator=tier.creator,
            amount_wei=tier.price_wei,
            fee_wei=fee_wei,
            creator_amount=creator_amount,
            token=tier.payment_token,
        )

        self._counter += 1
        sid = f"SUB-{self._counter:08d}"
        now = time.time()

        sub = Subscription(
            subscription_id=sid,
            tier_id=tier_id,
            subscriber=subscriber,
            start_time=now,
            expires_at=now + tier.period,
            auto_renew=auto_renew,
            total_paid_wei=tier.price_wei,
        )
        self._subscriptions[sid] = sub
        self._by_subscriber.setdefault(subscriber, []).append(sid)
        self._tiers.increment_subscriber_count(tier_id)

        # Fix the pending payment record
        if self._payments:
            self._payments[-1].subscription_id = sid

        logger.info(
            "Subscribed | id=%s | subscriber=%s | tier=%s | expires=%f",
            sid, subscriber, tier_id, sub.expires_at,
        )
        return sub

    # ── Renew ─────────────────────────────────────────────────────────

    def renew(self, subscription_id: str) -> Subscription:
        """
        Manually renew a subscription.

        Extends expiry by the tier's period and charges payment.
        """
        sub = self._get_sub(subscription_id)
        tier = self._tiers.get_tier(sub.tier_id)
        if tier is None:
            raise ValueError(f"Tier {sub.tier_id} no longer exists.")
        if sub.cancelled:
            raise ValueError("Cannot renew a cancelled subscription.")

        fee_wei, creator_amount = self._compute_fee(tier.price_wei)

        success = self._renewals.attempt_renewal(
            subscription_id=subscription_id,
            subscriber=sub.subscriber,
            creator=tier.creator,
            amount_wei=tier.price_wei,
            payment_token=tier.payment_token,
        )
        if not success:
            raise ValueError("Renewal payment failed.")

        now = time.time()
        # Extend from current expiry or now, whichever is later
        base = max(sub.expires_at, now)
        sub.expires_at = base + tier.period
        sub.renewal_count += 1
        sub.total_paid_wei += tier.price_wei

        self._record_payment(
            subscription_id=subscription_id,
            subscriber=sub.subscriber,
            creator=tier.creator,
            amount_wei=tier.price_wei,
            fee_wei=fee_wei,
            creator_amount=creator_amount,
            token=tier.payment_token,
        )

        logger.info(
            "Renewed | id=%s | new_expiry=%f | count=%d",
            subscription_id, sub.expires_at, sub.renewal_count,
        )
        return sub

    def retry_renewal(self, subscription_id: str) -> Subscription:
        """
        Retry a failed renewal during grace period.
        Only one retry is allowed per renewal cycle.
        """
        sub = self._get_sub(subscription_id)
        if sub.retry_used:
            raise ValueError("Retry already used for this cycle.")
        if not self._renewals.is_in_grace_period(sub.expires_at):
            raise ValueError("Not in grace period.")

        sub.retry_used = True
        return self.renew(subscription_id)

    # ── Cancel ────────────────────────────────────────────────────────

    def cancel_subscription(
        self, subscription_id: str, caller: str,
    ) -> Subscription:
        """Cancel a subscription. Only the subscriber can cancel."""
        sub = self._get_sub(subscription_id)
        if sub.subscriber != caller:
            raise ValueError("Only the subscriber can cancel.")
        if sub.cancelled:
            raise ValueError("Already cancelled.")

        sub.cancelled = True
        sub.auto_renew = False
        self._tiers.decrement_subscriber_count(sub.tier_id)

        logger.info("Cancelled | id=%s", subscription_id)
        return sub

    def set_auto_renew(
        self, subscription_id: str, caller: str, auto_renew: bool,
    ) -> Subscription:
        """Toggle auto-renewal."""
        sub = self._get_sub(subscription_id)
        if sub.subscriber != caller:
            raise ValueError("Only the subscriber can change auto-renew.")
        sub.auto_renew = auto_renew
        logger.info(
            "Auto-renew set | id=%s | auto_renew=%s",
            subscription_id, auto_renew,
        )
        return sub

    # ── Queries ───────────────────────────────────────────────────────

    def is_active(self, subscription_id: str) -> bool:
        """Check if subscription is currently active."""
        sub = self._subscriptions.get(subscription_id)
        if sub is None:
            return False
        if sub.cancelled:
            return False
        return time.time() <= sub.expires_at

    def is_in_grace_period(self, subscription_id: str) -> bool:
        """Check if subscription is in grace period."""
        sub = self._subscriptions.get(subscription_id)
        if sub is None:
            return False
        return self._renewals.is_in_grace_period(sub.expires_at)

    def time_remaining(self, subscription_id: str) -> int:
        """Return seconds until expiry (0 if expired)."""
        sub = self._subscriptions.get(subscription_id)
        if sub is None:
            return 0
        remaining = sub.expires_at - time.time()
        return max(0, int(remaining))

    def get_status(self, subscription_id: str) -> SubscriptionStatus:
        """Get the current status of a subscription."""
        sub = self._subscriptions.get(subscription_id)
        if sub is None:
            raise ValueError(f"Subscription {subscription_id} not found.")
        if sub.cancelled:
            return SubscriptionStatus.CANCELLED
        if self.is_active(subscription_id):
            return SubscriptionStatus.ACTIVE
        if self._renewals.is_in_grace_period(sub.expires_at):
            return SubscriptionStatus.GRACE_PERIOD
        return SubscriptionStatus.LAPSED

    def get_subscription(self, subscription_id: str) -> Optional[Subscription]:
        """Get subscription by ID."""
        return self._subscriptions.get(subscription_id)

    def get_subscriber_history(self, subscriber: str) -> List[Subscription]:
        """Get all subscriptions for a subscriber."""
        ids = self._by_subscriber.get(subscriber, [])
        return [self._subscriptions[sid] for sid in ids if sid in self._subscriptions]

    # ── Internal ──────────────────────────────────────────────────────

    def _compute_fee(self, amount_wei: int) -> tuple[int, int]:
        """Compute platform fee and creator amount."""
        fee = (amount_wei * PLATFORM_FEE_BPS) // 10_000
        creator_amount = amount_wei - fee
        return fee, creator_amount

    def _record_payment(
        self,
        subscription_id: str,
        subscriber: str,
        creator: str,
        amount_wei: int,
        fee_wei: int,
        creator_amount: int,
        token: str,
    ) -> None:
        """Record a payment in the audit trail."""
        self._payments.append(PaymentRecord(
            subscription_id=subscription_id,
            subscriber=subscriber,
            creator=creator,
            amount_wei=amount_wei,
            platform_fee_wei=fee_wei,
            creator_amount_wei=creator_amount,
            payment_token=token,
        ))

    def _get_sub(self, subscription_id: str) -> Subscription:
        """Get subscription or raise."""
        sub = self._subscriptions.get(subscription_id)
        if sub is None:
            raise ValueError(f"Subscription {subscription_id} not found.")
        return sub
