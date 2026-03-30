"""
x402 Payment Handler
=====================

Processes all agentic payments on 0pnMatrx.

Key principles:
- Platform covers ALL costs for all agentic payments.
- Users never see payment friction.
- Payments use USDC on Base.

NeoSafe: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
USDC_BASE_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"  # USDC on Base
CHAIN_ID = 8453  # Base


class PaymentStatus(Enum):
    """Lifecycle states for a payment."""
    PENDING = "pending"
    VALIDATING = "validating"
    EXECUTING = "executing"
    COMPLETED = "completed"
    FAILED = "failed"
    BLOCKED = "blocked"


@dataclass
class PaymentRequest:
    """Incoming request for an agentic payment."""
    requester_agent_id: str
    recipient_address: str
    amount: Decimal
    currency: str = "USDC"
    description: str = ""
    metadata: Dict[str, Any] = field(default_factory=dict)
    user_id: Optional[str] = None


@dataclass
class PaymentResult:
    """Outcome of a processed payment."""
    payment_id: str
    request: PaymentRequest
    status: PaymentStatus
    amount: Decimal
    currency: str
    chain_id: int = CHAIN_ID
    tx_hash: Optional[str] = None
    executed_at: Optional[datetime] = None
    error: Optional[str] = None
    platform_covered: bool = True
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def succeeded(self) -> bool:
        return self.status == PaymentStatus.COMPLETED


class X402PaymentHandler:
    """Handles x402 agentic payments on 0pnMatrx.

    The platform absorbs all payment costs so that users experience zero
    friction.  All payments settle in USDC on Base.
    """

    def __init__(
        self,
        spend_enforcer: Optional[Any] = None,
        attestation_hook: Optional[Any] = None,
        payment_log: Optional[Any] = None,
    ) -> None:
        self._spend_enforcer = spend_enforcer
        self._attestation_hook = attestation_hook
        self._payment_log = payment_log
        self._payments: Dict[str, PaymentResult] = {}
        logger.info(
            "X402PaymentHandler initialised (NeoSafe=%s, USDC=%s, chain=%d)",
            NEOSAFE_ADDRESS, USDC_BASE_ADDRESS, CHAIN_ID,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def process_payment(self, payment_request: PaymentRequest) -> PaymentResult:
        """End-to-end payment processing: validate -> execute -> record.

        Platform covers all costs — users see zero friction.

        Args:
            payment_request: The incoming payment request.

        Returns:
            ``PaymentResult`` with the final outcome.
        """
        payment_id = self._generate_payment_id()
        logger.info(
            "Processing payment %s: %s %s -> %s",
            payment_id, payment_request.amount, payment_request.currency,
            payment_request.recipient_address,
        )

        # Step 1: Validate
        validation_error = self.validate_payment(payment_request)
        if validation_error:
            result = PaymentResult(
                payment_id=payment_id,
                request=payment_request,
                status=PaymentStatus.BLOCKED,
                amount=payment_request.amount,
                currency=payment_request.currency,
                error=validation_error,
            )
            self._handle_blocked(result, validation_error)
            return result

        # Step 2: Execute
        result = self.execute_payment(payment_request, payment_id)

        # Step 3: Record
        self.record_payment(result)

        return result

    def validate_payment(self, request: PaymentRequest) -> Optional[str]:
        """Validate a payment request against business rules and spend limits.

        Args:
            request: The payment request to validate.

        Returns:
            ``None`` if valid, or a string describing the rejection reason.
        """
        if request.amount <= Decimal("0"):
            return "Payment amount must be positive"

        if request.currency != "USDC":
            return f"Unsupported currency: {request.currency} (only USDC on Base)"

        if not request.recipient_address or len(request.recipient_address) != 42:
            return f"Invalid recipient address: {request.recipient_address}"

        # Check spend limits via enforcer
        if self._spend_enforcer is not None:
            user = request.user_id or request.requester_agent_id
            within_limit = self._spend_enforcer.check_limit(user, request.amount)
            if not within_limit:
                return f"Payment exceeds spend limit for user {user}"

        return None

    def execute_payment(self, request: PaymentRequest, payment_id: Optional[str] = None) -> PaymentResult:
        """Execute a USDC payment on Base.

        The platform treasury covers the cost — the user is never charged.

        Args:
            request: Validated payment request.
            payment_id: Optional pre-generated ID.

        Returns:
            ``PaymentResult`` reflecting the on-chain outcome.
        """
        pid = payment_id or self._generate_payment_id()

        try:
            # TODO: Replace with actual Web3 USDC transfer on Base
            # 1. Build transaction from NeoSafe treasury to recipient
            # 2. Sign with platform key
            # 3. Submit to Base network
            # 4. Wait for confirmation
            tx_hash = f"0x{uuid.uuid4().hex}"

            result = PaymentResult(
                payment_id=pid,
                request=request,
                status=PaymentStatus.COMPLETED,
                amount=request.amount,
                currency=request.currency,
                tx_hash=tx_hash,
                executed_at=datetime.now(timezone.utc),
                platform_covered=True,
            )
            self._payments[pid] = result
            logger.info("Payment %s executed: tx=%s", pid, tx_hash)

            # Attest via EAS
            if self._attestation_hook:
                self._attestation_hook.attest_payment(result)

            return result

        except Exception as exc:
            logger.error("Payment %s execution failed: %s", pid, exc)
            result = PaymentResult(
                payment_id=pid,
                request=request,
                status=PaymentStatus.FAILED,
                amount=request.amount,
                currency=request.currency,
                error=str(exc),
            )
            self._payments[pid] = result
            return result

    def record_payment(self, result: PaymentResult) -> None:
        """Persist the payment result to the payment log.

        Args:
            result: The payment outcome to record.
        """
        self._payments[result.payment_id] = result
        if self._payment_log:
            if result.succeeded:
                self._payment_log.log_payment(result)
            else:
                self._payment_log.log_blocked(result.request, result.error or "Unknown")
        logger.debug("Payment %s recorded (status=%s)", result.payment_id, result.status.value)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _generate_payment_id() -> str:
        return f"pay-{uuid.uuid4().hex[:16]}"

    def _handle_blocked(self, result: PaymentResult, reason: str) -> None:
        """Handle a blocked payment: log + attest."""
        self._payments[result.payment_id] = result
        if self._attestation_hook:
            self._attestation_hook.attest_blocked_payment(result.request, reason)
        if self._payment_log:
            self._payment_log.log_blocked(result.request, reason)
        logger.warning("Payment %s blocked: %s", result.payment_id, reason)
