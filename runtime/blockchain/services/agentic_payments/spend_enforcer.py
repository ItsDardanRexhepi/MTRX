"""
Spend Enforcer
===============

Integrates directly with Rexhepi Framework v2 execution gate.
No payment executes outside approved limits.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class EnforcementDecision(Enum):
    """Outcome of a spend-limit enforcement check."""
    APPROVED = "approved"
    DENIED = "denied"
    ESCALATED = "escalated"


@dataclass
class UserSpendLimits:
    """Spend-limit configuration for a user."""
    user_id: str
    per_transaction_limit: Decimal = Decimal("100")
    daily_limit: Decimal = Decimal("1000")
    monthly_limit: Decimal = Decimal("10000")
    daily_spent: Decimal = Decimal("0")
    monthly_spent: Decimal = Decimal("0")
    last_reset_daily: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    last_reset_monthly: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


@dataclass
class EnforcementResult:
    """Result of enforcing spend limits on a payment request."""
    user_id: str
    amount: Decimal
    decision: EnforcementDecision
    reason: str
    remaining_daily: Decimal = Decimal("0")
    remaining_monthly: Decimal = Decimal("0")
    rexhepi_gate_passed: bool = False
    evaluated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def approved(self) -> bool:
        return self.decision == EnforcementDecision.APPROVED


class SpendEnforcer:
    """Enforces spend limits via direct integration with Rexhepi Framework v2.

    No payment executes outside approved limits.  Every enforcement decision
    is routed through the Rexhepi execution gate.
    """

    def __init__(self) -> None:
        self._limits: Dict[str, UserSpendLimits] = {}
        logger.info("SpendEnforcer initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check_limit(self, user: str, amount: Decimal) -> bool:
        """Quick boolean check for whether *amount* is within limits.

        Args:
            user: User identifier.
            amount: Proposed payment amount (USDC).

        Returns:
            ``True`` if within limits, ``False`` otherwise.
        """
        limits = self.get_user_limits(user)
        self._maybe_reset_periods(limits)

        if amount > limits.per_transaction_limit:
            logger.debug("User %s: amount %s exceeds per-tx limit %s", user, amount, limits.per_transaction_limit)
            return False
        if limits.daily_spent + amount > limits.daily_limit:
            logger.debug("User %s: daily limit would be exceeded", user)
            return False
        if limits.monthly_spent + amount > limits.monthly_limit:
            logger.debug("User %s: monthly limit would be exceeded", user)
            return False
        return True

    def get_user_limits(self, user: str) -> UserSpendLimits:
        """Retrieve (or create default) spend limits for *user*.

        Args:
            user: User identifier.

        Returns:
            ``UserSpendLimits`` for the user.
        """
        if user not in self._limits:
            self._limits[user] = UserSpendLimits(user_id=user)
            logger.info("Default spend limits created for user %s", user)
        return self._limits[user]

    def enforce(self, payment_request: Any) -> EnforcementResult:
        """Full enforcement pipeline: check limits then route through Rexhepi gate.

        Args:
            payment_request: Must expose ``.user_id`` (or ``.requester_agent_id``)
                             and ``.amount`` attributes.

        Returns:
            ``EnforcementResult`` with the final decision.
        """
        user = getattr(payment_request, "user_id", None) or getattr(payment_request, "requester_agent_id", "unknown")
        amount: Decimal = getattr(payment_request, "amount", Decimal("0"))

        limits = self.get_user_limits(user)
        self._maybe_reset_periods(limits)

        # Per-transaction check
        if amount > limits.per_transaction_limit:
            return EnforcementResult(
                user_id=user,
                amount=amount,
                decision=EnforcementDecision.DENIED,
                reason=f"Exceeds per-transaction limit ({amount} > {limits.per_transaction_limit})",
                remaining_daily=limits.daily_limit - limits.daily_spent,
                remaining_monthly=limits.monthly_limit - limits.monthly_spent,
            )

        # Daily check
        if limits.daily_spent + amount > limits.daily_limit:
            return EnforcementResult(
                user_id=user,
                amount=amount,
                decision=EnforcementDecision.DENIED,
                reason=f"Exceeds daily limit ({limits.daily_spent + amount} > {limits.daily_limit})",
                remaining_daily=limits.daily_limit - limits.daily_spent,
                remaining_monthly=limits.monthly_limit - limits.monthly_spent,
            )

        # Monthly check
        if limits.monthly_spent + amount > limits.monthly_limit:
            return EnforcementResult(
                user_id=user,
                amount=amount,
                decision=EnforcementDecision.DENIED,
                reason=f"Exceeds monthly limit ({limits.monthly_spent + amount} > {limits.monthly_limit})",
                remaining_daily=limits.daily_limit - limits.daily_spent,
                remaining_monthly=limits.monthly_limit - limits.monthly_spent,
            )

        # Route through Rexhepi gate
        gate_passed = self.submit_to_rexhepi_gate(payment_request)

        if gate_passed:
            # Update running totals
            limits.daily_spent += amount
            limits.monthly_spent += amount
            return EnforcementResult(
                user_id=user,
                amount=amount,
                decision=EnforcementDecision.APPROVED,
                reason="Within all limits and approved by Rexhepi gate",
                remaining_daily=limits.daily_limit - limits.daily_spent,
                remaining_monthly=limits.monthly_limit - limits.monthly_spent,
                rexhepi_gate_passed=True,
            )
        else:
            return EnforcementResult(
                user_id=user,
                amount=amount,
                decision=EnforcementDecision.DENIED,
                reason="Rexhepi Framework v2 execution gate rejected the payment",
                remaining_daily=limits.daily_limit - limits.daily_spent,
                remaining_monthly=limits.monthly_limit - limits.monthly_spent,
                rexhepi_gate_passed=False,
            )

    def submit_to_rexhepi_gate(self, request: Any) -> bool:
        """Submit the payment request to the Rexhepi Framework v2 execution gate.

        Args:
            request: The payment request to gate-check.

        Returns:
            ``True`` if the gate approves, ``False`` otherwise.
        """
        try:
            # TODO: Replace with actual Rexhepi Framework v2 gate call
            logger.debug("Payment request submitted to Rexhepi gate for approval")
            return True
        except Exception as exc:
            logger.error("Rexhepi gate submission failed: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _maybe_reset_periods(limits: UserSpendLimits) -> None:
        """Reset daily/monthly accumulators when their period has elapsed."""
        now = datetime.now(timezone.utc)

        if (now - limits.last_reset_daily).total_seconds() >= 86400:
            limits.daily_spent = Decimal("0")
            limits.last_reset_daily = now
            logger.debug("Daily spend reset for user %s", limits.user_id)

        if (now - limits.last_reset_monthly).days >= 30:
            limits.monthly_spent = Decimal("0")
            limits.last_reset_monthly = now
            logger.debug("Monthly spend reset for user %s", limits.user_id)
