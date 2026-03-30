"""
Payment UI
===========

User-facing payment interface with zero friction.
Users never see payment mechanics — the platform handles everything.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class PaymentFormContext:
    """Context data rendered in the payment form."""
    agent_id: str
    recipient_address: str
    amount: Decimal
    currency: str = "USDC"
    description: str = ""
    platform_covered: bool = True
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class PaymentHistoryView:
    """Rendered view of a user's payment history."""
    user_id: str
    entries: List[Dict[str, Any]]
    total_count: int
    page: int = 1
    page_size: int = 20
    rendered_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


@dataclass
class SpendLimitView:
    """Rendered view of a user's current spend limits."""
    user_id: str
    per_transaction_limit: Decimal
    daily_limit: Decimal
    monthly_limit: Decimal
    daily_spent: Decimal
    monthly_spent: Decimal
    daily_remaining: Decimal
    monthly_remaining: Decimal
    rendered_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


class PaymentUI:
    """Zero-friction payment interface for 0pnMatrx users.

    The UI abstracts all payment complexity.  Users see simple confirmations
    and history — never raw transaction data or gas details.
    """

    def __init__(
        self,
        payment_log: Optional[Any] = None,
        spend_enforcer: Optional[Any] = None,
    ) -> None:
        self._payment_log = payment_log
        self._spend_enforcer = spend_enforcer
        logger.info("PaymentUI initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def render_payment_form(self, context: PaymentFormContext) -> Dict[str, Any]:
        """Render the payment form for user confirmation.

        The form makes it clear that the platform covers all costs.

        Args:
            context: Data to populate the form.

        Returns:
            Serialisable dict representing the rendered form.
        """
        form: Dict[str, Any] = {
            "type": "payment_form",
            "agent_id": context.agent_id,
            "recipient": context.recipient_address,
            "amount": str(context.amount),
            "currency": context.currency,
            "description": context.description,
            "platform_covered": context.platform_covered,
            "user_cost": "0.00",
            "note": "This payment is fully covered by the platform. No cost to you.",
            "actions": [
                {"label": "Confirm", "action": "confirm_payment"},
                {"label": "Cancel", "action": "cancel_payment"},
            ],
            "rendered_at": datetime.now(timezone.utc).isoformat(),
        }
        logger.debug("Payment form rendered for agent %s (amount=%s %s)", context.agent_id, context.amount, context.currency)
        return form

    def show_payment_history(self, user: str, page: int = 1, page_size: int = 20) -> PaymentHistoryView:
        """Show a paginated view of the user's payment history.

        Args:
            user: User identifier.
            page: Page number (1-indexed).
            page_size: Entries per page.

        Returns:
            ``PaymentHistoryView`` ready for rendering.
        """
        if self._payment_log is None:
            logger.warning("No payment_log configured — returning empty history")
            return PaymentHistoryView(
                user_id=user,
                entries=[],
                total_count=0,
                page=page,
                page_size=page_size,
            )

        history = self._payment_log.get_history(user)
        total = len(history)

        start = (page - 1) * page_size
        end = start + page_size
        page_entries = history[start:end]

        rendered_entries = []
        for entry in page_entries:
            rendered_entries.append({
                "entry_id": entry.entry_id,
                "status": entry.status,
                "amount": str(entry.amount),
                "currency": entry.currency,
                "recipient": entry.recipient,
                "timestamp": entry.timestamp.isoformat(),
                "tx_hash": entry.tx_hash,
                "reason": entry.reason,
            })

        view = PaymentHistoryView(
            user_id=user,
            entries=rendered_entries,
            total_count=total,
            page=page,
            page_size=page_size,
        )
        logger.debug("Payment history rendered for %s: page %d/%d", user, page, max(1, (total + page_size - 1) // page_size))
        return view

    def show_spend_limits(self, user: str) -> SpendLimitView:
        """Show the user's current spend limits and remaining budget.

        Args:
            user: User identifier.

        Returns:
            ``SpendLimitView`` ready for rendering.
        """
        if self._spend_enforcer is None:
            logger.warning("No spend_enforcer configured — returning default view")
            return SpendLimitView(
                user_id=user,
                per_transaction_limit=Decimal("0"),
                daily_limit=Decimal("0"),
                monthly_limit=Decimal("0"),
                daily_spent=Decimal("0"),
                monthly_spent=Decimal("0"),
                daily_remaining=Decimal("0"),
                monthly_remaining=Decimal("0"),
            )

        limits = self._spend_enforcer.get_user_limits(user)
        daily_remaining = max(Decimal("0"), limits.daily_limit - limits.daily_spent)
        monthly_remaining = max(Decimal("0"), limits.monthly_limit - limits.monthly_spent)

        view = SpendLimitView(
            user_id=user,
            per_transaction_limit=limits.per_transaction_limit,
            daily_limit=limits.daily_limit,
            monthly_limit=limits.monthly_limit,
            daily_spent=limits.daily_spent,
            monthly_spent=limits.monthly_spent,
            daily_remaining=daily_remaining,
            monthly_remaining=monthly_remaining,
        )
        logger.debug(
            "Spend limits rendered for %s: daily=%s/%s monthly=%s/%s",
            user, limits.daily_spent, limits.daily_limit,
            limits.monthly_spent, limits.monthly_limit,
        )
        return view
