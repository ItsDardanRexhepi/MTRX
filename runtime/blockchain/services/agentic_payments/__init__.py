"""
x402 Agentic Payments Service
===============================

Handles all agentic payments on 0pnMatrx using the x402 protocol.
The platform covers ALL costs — users never see payment friction.
Payments settle in USDC on Base.

Includes:
- Payment processing and execution
- Spend limit enforcement via Rexhepi Framework v2
- User-driven limit updates with EAS attestation (schema 348)
- Payment attestation hooks
- Comprehensive payment logging (completed + blocked)
- Zero-friction payment UI
"""

from runtime.blockchain.services.agentic_payments.handler import X402PaymentHandler
from runtime.blockchain.services.agentic_payments.spend_enforcer import SpendEnforcer
from runtime.blockchain.services.agentic_payments.limit_updater import SpendLimitUpdater
from runtime.blockchain.services.agentic_payments.attestation_hook import PaymentAttestationHook
from runtime.blockchain.services.agentic_payments.payment_log import PaymentLog
from runtime.blockchain.services.agentic_payments.payment_ui import PaymentUI

__all__ = [
    "X402PaymentHandler",
    "SpendEnforcer",
    "SpendLimitUpdater",
    "PaymentAttestationHook",
    "PaymentLog",
    "PaymentUI",
]
