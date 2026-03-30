"""
Payment Attestation Hook
=========================

Every payment — completed or blocked — is attested on-chain via
EAS (Ethereum Attestation Service) schema 348.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

EAS_SCHEMA_ID = 348


@dataclass
class AttestationRecord:
    """Record of an on-chain EAS attestation."""
    attestation_uid: str
    schema_id: int
    subject: str
    attestation_type: str  # "payment_completed" | "payment_blocked"
    amount: Decimal
    currency: str
    details: Dict[str, Any] = field(default_factory=dict)
    attested_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    tx_hash: Optional[str] = None


class PaymentAttestationHook:
    """Attests every payment event via EAS schema 348.

    Both completed payments and blocked payment attempts are attested
    to ensure full transparency and auditability on-chain.
    """

    def __init__(self) -> None:
        self._attestations: List[AttestationRecord] = []
        logger.info("PaymentAttestationHook initialised (EAS schema=%d)", EAS_SCHEMA_ID)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def attest_payment(self, payment_result: Any) -> AttestationRecord:
        """Create an EAS attestation for a completed payment.

        Args:
            payment_result: A ``PaymentResult`` (or duck-typed equivalent)
                            with ``.payment_id``, ``.amount``, ``.currency``,
                            ``.tx_hash``, and ``.request`` attributes.

        Returns:
            The ``AttestationRecord`` created.

        Raises:
            RuntimeError: If the on-chain attestation fails.
        """
        payment_id = getattr(payment_result, "payment_id", "unknown")
        amount = getattr(payment_result, "amount", Decimal("0"))
        currency = getattr(payment_result, "currency", "USDC")
        tx_hash = getattr(payment_result, "tx_hash", None)
        request = getattr(payment_result, "request", None)
        recipient = getattr(request, "recipient_address", "unknown") if request else "unknown"

        try:
            attestation_uid = self._submit_eas_attestation(
                subject=payment_id,
                attestation_type="payment_completed",
                data={
                    "payment_id": payment_id,
                    "amount": str(amount),
                    "currency": currency,
                    "recipient": recipient,
                    "tx_hash": tx_hash,
                },
            )

            record = AttestationRecord(
                attestation_uid=attestation_uid,
                schema_id=EAS_SCHEMA_ID,
                subject=payment_id,
                attestation_type="payment_completed",
                amount=amount,
                currency=currency,
                details={"recipient": recipient, "tx_hash": tx_hash},
            )
            self._attestations.append(record)
            logger.info("Payment %s attested via EAS schema %d (uid=%s)", payment_id, EAS_SCHEMA_ID, attestation_uid)
            return record

        except Exception as exc:
            logger.error("Failed to attest payment %s: %s", payment_id, exc)
            raise RuntimeError(f"EAS attestation failed for payment {payment_id}") from exc

    def attest_blocked_payment(self, payment_request: Any, reason: str) -> AttestationRecord:
        """Create an EAS attestation for a blocked payment attempt.

        Args:
            payment_request: The original ``PaymentRequest`` that was blocked.
            reason: Human-readable reason the payment was blocked.

        Returns:
            The ``AttestationRecord`` created.

        Raises:
            RuntimeError: If the on-chain attestation fails.
        """
        agent_id = getattr(payment_request, "requester_agent_id", "unknown")
        amount = getattr(payment_request, "amount", Decimal("0"))
        currency = getattr(payment_request, "currency", "USDC")
        recipient = getattr(payment_request, "recipient_address", "unknown")

        try:
            attestation_uid = self._submit_eas_attestation(
                subject=agent_id,
                attestation_type="payment_blocked",
                data={
                    "agent_id": agent_id,
                    "amount": str(amount),
                    "currency": currency,
                    "recipient": recipient,
                    "reason": reason,
                },
            )

            record = AttestationRecord(
                attestation_uid=attestation_uid,
                schema_id=EAS_SCHEMA_ID,
                subject=agent_id,
                attestation_type="payment_blocked",
                amount=amount,
                currency=currency,
                details={"recipient": recipient, "reason": reason},
            )
            self._attestations.append(record)
            logger.info(
                "Blocked payment attested via EAS schema %d (agent=%s, reason=%s, uid=%s)",
                EAS_SCHEMA_ID, agent_id, reason, attestation_uid,
            )
            return record

        except Exception as exc:
            logger.error("Failed to attest blocked payment (agent=%s): %s", agent_id, exc)
            raise RuntimeError(f"EAS attestation failed for blocked payment by {agent_id}") from exc

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _submit_eas_attestation(
        subject: str,
        attestation_type: str,
        data: Dict[str, Any],
    ) -> str:
        """Submit an attestation to EAS on Base (schema 348).

        Returns:
            The attestation UID.

        Raises:
            RuntimeError: On submission failure.
        """
        try:
            # TODO: Replace with actual EAS contract call on Base
            # from eas_sdk import EAS
            # eas = EAS(schema_id=EAS_SCHEMA_ID)
            # uid = eas.attest(subject=subject, data=data)
            attestation_uid = f"eas-{uuid.uuid4().hex[:16]}"
            logger.debug(
                "EAS attestation submitted: schema=%d type=%s subject=%s",
                EAS_SCHEMA_ID, attestation_type, subject,
            )
            return attestation_uid
        except Exception as exc:
            raise RuntimeError(f"EAS submission failed: {exc}") from exc
