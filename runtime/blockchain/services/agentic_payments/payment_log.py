"""
Payment Log
============

Records completed payments AND blocked attempts for full auditability.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class PaymentLogEntry:
    """A single entry in the payment log."""
    entry_id: str
    user_id: str
    agent_id: str
    amount: Decimal
    currency: str
    recipient: str
    status: str  # "completed" | "blocked"
    reason: Optional[str] = None
    tx_hash: Optional[str] = None
    payment_id: Optional[str] = None
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class PaymentStats:
    """Aggregated payment statistics for a user."""
    user_id: str
    total_completed: int = 0
    total_blocked: int = 0
    total_amount_completed: Decimal = Decimal("0")
    total_amount_blocked: Decimal = Decimal("0")
    computed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


class PaymentLog:
    """Comprehensive payment logger for completed and blocked transactions.

    Provides history retrieval and aggregated statistics per user.
    """

    def __init__(self) -> None:
        self._entries: List[PaymentLogEntry] = []
        self._entry_counter: int = 0
        logger.info("PaymentLog initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def log_payment(self, result: Any) -> PaymentLogEntry:
        """Log a successfully completed payment.

        Args:
            result: A ``PaymentResult`` (or duck-typed equivalent) with
                    ``.payment_id``, ``.amount``, ``.currency``, ``.tx_hash``,
                    and ``.request`` attributes.

        Returns:
            The created ``PaymentLogEntry``.
        """
        request = getattr(result, "request", None)
        user_id = getattr(request, "user_id", None) or getattr(request, "requester_agent_id", "unknown") if request else "unknown"
        agent_id = getattr(request, "requester_agent_id", "unknown") if request else "unknown"
        recipient = getattr(request, "recipient_address", "unknown") if request else "unknown"

        entry = PaymentLogEntry(
            entry_id=self._next_id(),
            user_id=user_id,
            agent_id=agent_id,
            amount=getattr(result, "amount", Decimal("0")),
            currency=getattr(result, "currency", "USDC"),
            recipient=recipient,
            status="completed",
            tx_hash=getattr(result, "tx_hash", None),
            payment_id=getattr(result, "payment_id", None),
        )
        self._entries.append(entry)
        logger.info("Logged completed payment %s (amount=%s)", entry.payment_id, entry.amount)
        return entry

    def log_blocked(self, request: Any, reason: str) -> PaymentLogEntry:
        """Log a blocked payment attempt.

        Args:
            request: The original ``PaymentRequest`` that was blocked.
            reason: Human-readable reason for blocking.

        Returns:
            The created ``PaymentLogEntry``.
        """
        user_id = getattr(request, "user_id", None) or getattr(request, "requester_agent_id", "unknown")
        agent_id = getattr(request, "requester_agent_id", "unknown")
        recipient = getattr(request, "recipient_address", "unknown")

        entry = PaymentLogEntry(
            entry_id=self._next_id(),
            user_id=user_id,
            agent_id=agent_id,
            amount=getattr(request, "amount", Decimal("0")),
            currency=getattr(request, "currency", "USDC"),
            recipient=recipient,
            status="blocked",
            reason=reason,
        )
        self._entries.append(entry)
        logger.warning("Logged blocked payment (agent=%s, amount=%s, reason=%s)", agent_id, entry.amount, reason)
        return entry

    def get_history(self, user: str) -> List[PaymentLogEntry]:
        """Retrieve the full payment history for a user.

        Args:
            user: User identifier.

        Returns:
            List of ``PaymentLogEntry`` ordered by timestamp (newest first).
        """
        entries = [e for e in self._entries if e.user_id == user or e.agent_id == user]
        entries.sort(key=lambda e: e.timestamp, reverse=True)
        return entries

    def get_stats(self, user: str) -> PaymentStats:
        """Compute aggregated payment statistics for a user.

        Args:
            user: User identifier.

        Returns:
            ``PaymentStats`` summary.
        """
        history = self.get_history(user)
        completed = [e for e in history if e.status == "completed"]
        blocked = [e for e in history if e.status == "blocked"]

        return PaymentStats(
            user_id=user,
            total_completed=len(completed),
            total_blocked=len(blocked),
            total_amount_completed=sum((e.amount for e in completed), Decimal("0")),
            total_amount_blocked=sum((e.amount for e in blocked), Decimal("0")),
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _next_id(self) -> str:
        self._entry_counter += 1
        return f"log-{self._entry_counter}"
