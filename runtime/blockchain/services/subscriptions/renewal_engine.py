"""
Renewal Engine — handles auto-renewal, grace periods, and retry logic.

Part of Component 29 (Subscription Rewards).
Processes renewals for active subscriptions with configurable grace period.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

GRACE_PERIOD_SECONDS: int = 3 * 86_400  # 3 days grace period


@dataclass
class RenewalAttempt:
    """Record of a renewal attempt."""
    subscription_id: str
    attempted_at: float = field(default_factory=time.time)
    success: bool = False
    error: str = ""


class RenewalEngine:
    """
    Processes subscription renewals with grace periods and retry logic.

    When a subscription expires:
    1. If auto_renew is on, attempt payment immediately.
    2. If payment fails, enter grace period (3 days).
    3. One retry attempt is allowed during grace period.
    4. After grace period expires without payment, subscription lapses.
    """

    def __init__(
        self,
        payment_fn: Optional[Callable[[str, str, int, str], bool]] = None,
    ) -> None:
        """
        Args:
            payment_fn: Callable(subscriber, creator, amount_wei, token) -> success.
                        If None, renewals are tracked but payments are not executed.
        """
        self._payment_fn = payment_fn
        self._attempts: Dict[str, List[RenewalAttempt]] = {}
        logger.info("RenewalEngine initialised.")

    def attempt_renewal(
        self,
        subscription_id: str,
        subscriber: str,
        creator: str,
        amount_wei: int,
        payment_token: str,
    ) -> bool:
        """
        Attempt to renew a subscription via payment.

        Args:
            subscription_id: The subscription to renew.
            subscriber: Subscriber's address.
            creator: Creator's address (payment recipient).
            amount_wei: Renewal cost.
            payment_token: Token used for payment.

        Returns:
            True if renewal payment succeeded, False otherwise.
        """
        attempt = RenewalAttempt(subscription_id=subscription_id)

        if self._payment_fn is not None:
            try:
                success = self._payment_fn(
                    subscriber, creator, amount_wei, payment_token,
                )
                attempt.success = success
                if not success:
                    attempt.error = "Payment returned false."
            except Exception as exc:
                attempt.success = False
                attempt.error = str(exc)
                logger.warning(
                    "Renewal payment failed | sub=%s | error=%s",
                    subscription_id, exc,
                )
        else:
            # No payment function — simulate success for tracking
            attempt.success = True

        self._attempts.setdefault(subscription_id, []).append(attempt)

        if attempt.success:
            logger.info("Renewal succeeded | sub=%s", subscription_id)
        else:
            logger.info(
                "Renewal failed | sub=%s | error=%s",
                subscription_id, attempt.error,
            )
        return attempt.success

    def is_in_grace_period(self, expires_at: float) -> bool:
        """Check if a subscription is within its grace period."""
        now = time.time()
        return expires_at < now <= (expires_at + GRACE_PERIOD_SECONDS)

    def is_lapsed(self, expires_at: float) -> bool:
        """Check if a subscription has lapsed past its grace period."""
        now = time.time()
        return now > (expires_at + GRACE_PERIOD_SECONDS)

    def has_retry_available(self, subscription_id: str) -> bool:
        """Check if a retry attempt is still available."""
        attempts = self._attempts.get(subscription_id, [])
        failed_attempts = [a for a in attempts if not a.success]
        return len(failed_attempts) < 2  # One original + one retry

    def get_attempts(self, subscription_id: str) -> List[RenewalAttempt]:
        """Get all renewal attempts for a subscription."""
        return self._attempts.get(subscription_id, [])
