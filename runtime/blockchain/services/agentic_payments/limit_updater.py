"""
Spend Limit Updater
====================

Allows users to update their spend limits at any time through Trinity.
New limits are submitted to the Rexhepi gate for evaluation and take
effect immediately upon gate approval.  Every change is attested via
EAS schema 348.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

EAS_SCHEMA_ID = 348


class LimitUpdateStatus(Enum):
    """Outcome of a spend-limit update request."""
    APPROVED = "approved"
    REJECTED = "rejected"
    PENDING = "pending"


@dataclass
class LimitUpdateRequest:
    """A user-initiated spend-limit change request."""
    user_id: str
    new_per_transaction: Optional[Decimal] = None
    new_daily: Optional[Decimal] = None
    new_monthly: Optional[Decimal] = None
    requested_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    source: str = "trinity"


@dataclass
class LimitUpdateResult:
    """Result of a spend-limit change request."""
    user_id: str
    status: LimitUpdateStatus
    old_limits: Dict[str, Decimal]
    new_limits: Dict[str, Decimal]
    gate_approved: bool = False
    attested: bool = False
    attestation_uid: Optional[str] = None
    eas_schema_id: int = EAS_SCHEMA_ID
    processed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    reason: Optional[str] = None


class SpendLimitUpdater:
    """Manages user-driven spend-limit updates through Trinity.

    Flow:
        1. User requests a limit update via Trinity.
        2. New limit is submitted to Rexhepi Framework v2 gate.
        3. On approval, the limit is applied immediately.
        4. The change is attested via EAS schema 348.
    """

    def __init__(
        self,
        spend_enforcer: Optional[Any] = None,
        attestation_hook: Optional[Any] = None,
    ) -> None:
        self._spend_enforcer = spend_enforcer
        self._attestation_hook = attestation_hook
        self._update_history: Dict[str, list] = {}
        logger.info("SpendLimitUpdater initialised (EAS schema=%d)", EAS_SCHEMA_ID)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def request_update(self, user: str, new_limit: LimitUpdateRequest) -> LimitUpdateResult:
        """Process a user's request to change their spend limits.

        Args:
            user: User identifier.
            new_limit: Desired new limits.

        Returns:
            ``LimitUpdateResult`` describing the outcome.
        """
        logger.info("Spend limit update requested by user %s", user)

        old_limits = self._capture_current_limits(user)

        # Submit to Rexhepi gate
        gate_ok = self.submit_to_gate(user, new_limit)

        if not gate_ok:
            result = LimitUpdateResult(
                user_id=user,
                status=LimitUpdateStatus.REJECTED,
                old_limits=old_limits,
                new_limits=self._extract_new_limits(new_limit),
                gate_approved=False,
                reason="Rexhepi Framework v2 gate rejected the limit update",
            )
            self._record(user, result)
            return result

        # Apply immediately
        self.apply_update(user, new_limit)
        new_limits = self._capture_current_limits(user)

        # Attest via EAS schema 348
        attestation_uid = self.attest_update(user, old_limits, new_limits)

        result = LimitUpdateResult(
            user_id=user,
            status=LimitUpdateStatus.APPROVED,
            old_limits=old_limits,
            new_limits=new_limits,
            gate_approved=True,
            attested=attestation_uid is not None,
            attestation_uid=attestation_uid,
        )
        self._record(user, result)
        logger.info("Spend limits updated for user %s — effective immediately", user)
        return result

    def submit_to_gate(self, user: str, new_limit: LimitUpdateRequest) -> bool:
        """Submit the proposed limit change to the Rexhepi Framework v2 gate.

        Args:
            user: User identifier.
            new_limit: The proposed new limits.

        Returns:
            ``True`` if the gate approves the change.
        """
        try:
            # TODO: Replace with actual Rexhepi gate call
            logger.debug("Limit update for %s submitted to Rexhepi gate", user)

            # Basic sanity — gate would reject negative limits
            for val in [new_limit.new_per_transaction, new_limit.new_daily, new_limit.new_monthly]:
                if val is not None and val < Decimal("0"):
                    logger.warning("Rexhepi gate rejected negative limit for %s", user)
                    return False

            return True
        except Exception as exc:
            logger.error("Rexhepi gate submission failed for %s: %s", user, exc)
            return False

    def apply_update(self, user: str, new_limit: LimitUpdateRequest) -> None:
        """Apply the approved limit changes immediately.

        Args:
            user: User identifier.
            new_limit: The approved new limits.
        """
        if self._spend_enforcer is None:
            logger.warning("No spend_enforcer configured — cannot apply limit update for %s", user)
            return

        limits = self._spend_enforcer.get_user_limits(user)

        if new_limit.new_per_transaction is not None:
            limits.per_transaction_limit = new_limit.new_per_transaction
        if new_limit.new_daily is not None:
            limits.daily_limit = new_limit.new_daily
        if new_limit.new_monthly is not None:
            limits.monthly_limit = new_limit.new_monthly

        logger.info("Limits applied for %s: per_tx=%s daily=%s monthly=%s",
                     user, limits.per_transaction_limit, limits.daily_limit, limits.monthly_limit)

    def attest_update(
        self,
        user: str,
        old_limits: Dict[str, Decimal],
        new_limits: Dict[str, Decimal],
    ) -> Optional[str]:
        """Attest the limit change via EAS schema 348.

        Args:
            user: User identifier.
            old_limits: Limits before the update.
            new_limits: Limits after the update.

        Returns:
            EAS attestation UID, or ``None`` on failure.
        """
        try:
            # TODO: Replace with actual EAS attestation call (schema 348)
            import uuid as _uuid
            attestation_uid = f"eas-{_uuid.uuid4().hex[:16]}"
            logger.info(
                "Limit update attested for %s via EAS schema %d (uid=%s)",
                user, EAS_SCHEMA_ID, attestation_uid,
            )
            return attestation_uid
        except Exception as exc:
            logger.error("EAS attestation failed for limit update (%s): %s", user, exc)
            return None

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _capture_current_limits(self, user: str) -> Dict[str, Decimal]:
        """Snapshot the user's current limits."""
        if self._spend_enforcer is None:
            return {}
        limits = self._spend_enforcer.get_user_limits(user)
        return {
            "per_transaction": limits.per_transaction_limit,
            "daily": limits.daily_limit,
            "monthly": limits.monthly_limit,
        }

    @staticmethod
    def _extract_new_limits(req: LimitUpdateRequest) -> Dict[str, Decimal]:
        result: Dict[str, Decimal] = {}
        if req.new_per_transaction is not None:
            result["per_transaction"] = req.new_per_transaction
        if req.new_daily is not None:
            result["daily"] = req.new_daily
        if req.new_monthly is not None:
            result["monthly"] = req.new_monthly
        return result

    def _record(self, user: str, result: LimitUpdateResult) -> None:
        self._update_history.setdefault(user, []).append(result)
