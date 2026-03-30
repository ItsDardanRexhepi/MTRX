"""
Payment Processor — orchestrates payment flows across methods, fees, and compliance.

Part of Component 17 (Payments).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class PaymentStatus(Enum):
    """Payment lifecycle states."""
    INITIATED = "initiated"
    COMPLIANCE_CHECK = "compliance_check"
    FEE_CALCULATED = "fee_calculated"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    REFUNDED = "refunded"


@dataclass
class Payment:
    """A single payment record."""
    payment_id: str
    sender: str
    recipient: str
    amount_wei: int
    currency: str
    fee_wei: int = 0
    net_amount_wei: int = 0
    status: PaymentStatus = PaymentStatus.INITIATED
    method: str = "native"
    created_at: float = field(default_factory=time.time)
    completed_at: Optional[float] = None
    tx_hash: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None


class PaymentProcessor:
    """
    Orchestrates end-to-end payment processing.

    Flow:
    1. Compliance pre-check
    2. Fee calculation via FeeEnforcer
    3. Currency conversion if needed (via Component 11 oracle)
    4. Payment execution via selected method
    5. Confirmation and receipt generation
    """

    def __init__(
        self,
        fee_enforcer: Optional[Any] = None,
        converter: Optional[Any] = None,
        compliance: Optional[Any] = None,
        method_registry: Optional[Any] = None,
        execute_fn: Optional[Callable[[str, str, int], Optional[str]]] = None,
    ) -> None:
        """
        Args:
            fee_enforcer: FeeEnforcer instance for fee calculation.
            converter: CurrencyConverter for cross-currency payments.
            compliance: ComplianceGateway for pre-checks.
            method_registry: PaymentMethodRegistry for method resolution.
            execute_fn: Callable(sender, recipient, amount_wei) -> tx_hash.
        """
        self._fees = fee_enforcer
        self._converter = converter
        self._compliance = compliance
        self._methods = method_registry
        self._execute = execute_fn

        self._payments: Dict[str, Payment] = {}
        self._counter: int = 0
        logger.info("PaymentProcessor initialised.")

    # ── Payment Processing ────────────────────────────────────────────

    def initiate_payment(
        self,
        sender: str,
        recipient: str,
        amount_wei: int,
        currency: str = "ETH",
        method: str = "native",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Payment:
        """
        Initiate a new payment.

        Args:
            sender: Payer address.
            recipient: Payee address.
            amount_wei: Payment amount in wei.
            currency: Currency code.
            method: Payment method name.
            metadata: Optional additional data.

        Returns:
            The created Payment in INITIATED status.

        Raises:
            ValueError: If inputs are invalid.
        """
        if not sender.startswith("0x") or not recipient.startswith("0x"):
            raise ValueError("Both sender and recipient must be valid addresses.")
        if amount_wei <= 0:
            raise ValueError("Payment amount must be positive.")
        if sender == recipient:
            raise ValueError("Sender and recipient cannot be the same.")

        self._counter += 1
        payment_id = f"PAY-{self._counter:08d}"

        payment = Payment(
            payment_id=payment_id,
            sender=sender,
            recipient=recipient,
            amount_wei=amount_wei,
            currency=currency,
            method=method,
            metadata=metadata or {},
        )
        self._payments[payment_id] = payment

        logger.info(
            "Payment initiated | id=%s | %s -> %s | %d wei",
            payment_id, sender, recipient, amount_wei,
        )
        return payment

    def process_payment(self, payment_id: str) -> Payment:
        """
        Execute the full payment pipeline.

        Args:
            payment_id: ID of the payment to process.

        Returns:
            The updated Payment.

        Raises:
            ValueError: If payment not found or in invalid state.
        """
        payment = self._get_payment(payment_id)
        if payment.status != PaymentStatus.INITIATED:
            raise ValueError(
                f"Payment {payment_id} is in {payment.status.value} state, expected INITIATED."
            )

        try:
            # Step 1: Compliance check
            payment.status = PaymentStatus.COMPLIANCE_CHECK
            if self._compliance is not None:
                result = self._compliance.pre_check(
                    sender=payment.sender,
                    recipient=payment.recipient,
                    amount_wei=payment.amount_wei,
                )
                if not result.get("approved", True):
                    payment.status = PaymentStatus.FAILED
                    payment.error = result.get("reason", "Compliance check failed.")
                    return payment

            # Step 2: Fee calculation
            payment.status = PaymentStatus.FEE_CALCULATED
            if self._fees is not None:
                fee_result = self._fees.calculate_fee(
                    sender=payment.sender,
                    amount_wei=payment.amount_wei,
                )
                payment.fee_wei = fee_result.fee_wei
                payment.net_amount_wei = payment.amount_wei - payment.fee_wei
            else:
                payment.fee_wei = 0
                payment.net_amount_wei = payment.amount_wei

            # Step 3: Execute payment
            payment.status = PaymentStatus.PROCESSING
            if self._execute is not None:
                payment.tx_hash = self._execute(
                    payment.sender,
                    payment.recipient,
                    payment.net_amount_wei,
                )

            payment.status = PaymentStatus.COMPLETED
            payment.completed_at = time.time()

            logger.info(
                "Payment completed | id=%s | net=%d | fee=%d | tx=%s",
                payment_id, payment.net_amount_wei, payment.fee_wei, payment.tx_hash,
            )
        except Exception as exc:
            payment.status = PaymentStatus.FAILED
            payment.error = str(exc)
            logger.exception("Payment %s failed.", payment_id)

        return payment

    def refund_payment(self, payment_id: str) -> Payment:
        """
        Refund a completed payment.

        Args:
            payment_id: The payment to refund.

        Returns:
            The updated Payment in REFUNDED status.
        """
        payment = self._get_payment(payment_id)
        if payment.status != PaymentStatus.COMPLETED:
            raise ValueError(f"Can only refund COMPLETED payments, got {payment.status.value}.")

        if self._execute is not None:
            self._execute(payment.recipient, payment.sender, payment.net_amount_wei)

        payment.status = PaymentStatus.REFUNDED
        payment.metadata["refunded_at"] = time.time()
        logger.info("Payment %s refunded.", payment_id)
        return payment

    # ── Queries ───────────────────────────────────────────────────────

    def get_payment(self, payment_id: str) -> Optional[Payment]:
        """Retrieve a payment by ID."""
        return self._payments.get(payment_id)

    def get_payments_by_sender(self, sender: str) -> List[Payment]:
        """Get all payments from a sender."""
        return [p for p in self._payments.values() if p.sender == sender]

    def get_payments_by_recipient(self, recipient: str) -> List[Payment]:
        """Get all payments to a recipient."""
        return [p for p in self._payments.values() if p.recipient == recipient]

    # ── Internal ──────────────────────────────────────────────────────

    def _get_payment(self, payment_id: str) -> Payment:
        """Get a payment or raise."""
        payment = self._payments.get(payment_id)
        if payment is None:
            raise ValueError(f"Payment {payment_id} not found.")
        return payment
