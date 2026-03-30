"""
Compliance Gateway — scaffold with injection points for compliance checks.

Part of Component 17 (Payments).
Provides a pluggable compliance architecture where jurisdiction-specific
rules can be injected without modifying the core payment flow.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


class ComplianceCheckType(Enum):
    """Types of compliance checks."""
    SANCTIONS = "sanctions"
    KYC_VERIFICATION = "kyc_verification"
    AML_SCREENING = "aml_screening"
    TRANSACTION_LIMIT = "transaction_limit"
    JURISDICTION = "jurisdiction"
    CUSTOM = "custom"


class ComplianceResult(Enum):
    """Outcome of a compliance check."""
    APPROVED = "approved"
    DENIED = "denied"
    PENDING_REVIEW = "pending_review"
    REQUIRES_KYC = "requires_kyc"


@dataclass
class ComplianceCheckResult:
    """Result of a single compliance check."""
    check_type: ComplianceCheckType
    result: ComplianceResult
    reason: str
    checked_at: float = field(default_factory=time.time)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ComplianceReport:
    """Aggregate compliance report for a transaction."""
    sender: str
    recipient: str
    amount_wei: int
    approved: bool
    checks: List[ComplianceCheckResult] = field(default_factory=list)
    overall_reason: str = ""
    generated_at: float = field(default_factory=time.time)


# Type alias for compliance check plugins
CompliancePlugin = Callable[[str, str, int], ComplianceCheckResult]


class ComplianceGateway:
    """
    Pluggable compliance gateway with injection points.

    Architecture:
    - Pre-check plugins: Run before payment processing
    - Post-check plugins: Run after payment completion
    - Jurisdiction plugins: Jurisdiction-specific rules
    - Custom plugins: Arbitrary compliance logic

    Plugins are callables that accept (sender, recipient, amount_wei)
    and return a ComplianceCheckResult. New compliance requirements
    can be added by registering plugins without modifying core logic.
    """

    def __init__(self) -> None:
        # Registered plugins by check type
        self._pre_check_plugins: Dict[str, CompliancePlugin] = {}
        self._post_check_plugins: Dict[str, CompliancePlugin] = {}
        self._jurisdiction_plugins: Dict[str, CompliancePlugin] = {}

        # Audit trail
        self._audit_log: List[ComplianceReport] = []

        # Configurable thresholds (injection points)
        self._thresholds: Dict[str, int] = {
            "enhanced_due_diligence_wei": 10_000 * 10**18,  # $10k+ requires EDD
            "reporting_threshold_wei": 50_000 * 10**18,     # $50k+ auto-reported
        }

        logger.info("ComplianceGateway initialised with plugin architecture.")

    # ── Plugin Registration (Injection Points) ────────────────────────

    def register_pre_check(self, name: str, plugin: CompliancePlugin) -> None:
        """
        Register a pre-payment compliance check plugin.

        Args:
            name: Unique name for this plugin.
            plugin: Callable(sender, recipient, amount_wei) -> ComplianceCheckResult.
        """
        self._pre_check_plugins[name] = plugin
        logger.info("Pre-check compliance plugin registered: %s", name)

    def register_post_check(self, name: str, plugin: CompliancePlugin) -> None:
        """
        Register a post-payment compliance check plugin.

        Args:
            name: Unique name for this plugin.
            plugin: Callable(sender, recipient, amount_wei) -> ComplianceCheckResult.
        """
        self._post_check_plugins[name] = plugin
        logger.info("Post-check compliance plugin registered: %s", name)

    def register_jurisdiction_check(
        self, jurisdiction: str, plugin: CompliancePlugin,
    ) -> None:
        """
        Register a jurisdiction-specific compliance plugin.

        Args:
            jurisdiction: Jurisdiction code (e.g., "US", "EU", "UK").
            plugin: Compliance check callable.
        """
        self._jurisdiction_plugins[jurisdiction] = plugin
        logger.info("Jurisdiction compliance plugin registered: %s", jurisdiction)

    def unregister_plugin(self, name: str) -> None:
        """Remove a plugin by name from all registries."""
        removed = False
        for registry in (self._pre_check_plugins, self._post_check_plugins):
            if name in registry:
                del registry[name]
                removed = True
        if name in self._jurisdiction_plugins:
            del self._jurisdiction_plugins[name]
            removed = True
        if removed:
            logger.info("Compliance plugin removed: %s", name)

    # ── Compliance Checks ─────────────────────────────────────────────

    def pre_check(
        self,
        sender: str,
        recipient: str,
        amount_wei: int,
        jurisdiction: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Run all pre-payment compliance checks.

        Args:
            sender: Payer address.
            recipient: Payee address.
            amount_wei: Payment amount in wei.
            jurisdiction: Optional jurisdiction code.

        Returns:
            Dict with 'approved' (bool), 'reason' (str), and 'checks' list.
        """
        checks: List[ComplianceCheckResult] = []

        # Run all pre-check plugins
        for name, plugin in self._pre_check_plugins.items():
            try:
                result = plugin(sender, recipient, amount_wei)
                checks.append(result)
            except Exception:
                logger.exception("Pre-check plugin '%s' failed.", name)
                checks.append(ComplianceCheckResult(
                    check_type=ComplianceCheckType.CUSTOM,
                    result=ComplianceResult.PENDING_REVIEW,
                    reason=f"Plugin '{name}' encountered an error.",
                ))

        # Run jurisdiction-specific checks
        if jurisdiction and jurisdiction in self._jurisdiction_plugins:
            try:
                result = self._jurisdiction_plugins[jurisdiction](
                    sender, recipient, amount_wei,
                )
                checks.append(result)
            except Exception:
                logger.exception("Jurisdiction plugin '%s' failed.", jurisdiction)

        # Built-in threshold checks
        checks.append(self._check_thresholds(sender, recipient, amount_wei))

        # Aggregate results
        approved = all(
            c.result in (ComplianceResult.APPROVED, ComplianceResult.PENDING_REVIEW)
            for c in checks
        )
        denied_reasons = [
            c.reason for c in checks if c.result == ComplianceResult.DENIED
        ]

        report = ComplianceReport(
            sender=sender,
            recipient=recipient,
            amount_wei=amount_wei,
            approved=approved,
            checks=checks,
            overall_reason="; ".join(denied_reasons) if denied_reasons else "All checks passed.",
        )
        self._audit_log.append(report)

        return {
            "approved": approved,
            "reason": report.overall_reason,
            "checks": [
                {
                    "type": c.check_type.value,
                    "result": c.result.value,
                    "reason": c.reason,
                }
                for c in checks
            ],
        }

    def post_check(
        self,
        sender: str,
        recipient: str,
        amount_wei: int,
        tx_hash: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Run all post-payment compliance checks.

        Args:
            sender: Payer address.
            recipient: Payee address.
            amount_wei: Payment amount in wei.
            tx_hash: Transaction hash of the completed payment.

        Returns:
            Dict with check results (informational, does not block).
        """
        checks: List[ComplianceCheckResult] = []
        for name, plugin in self._post_check_plugins.items():
            try:
                result = plugin(sender, recipient, amount_wei)
                checks.append(result)
            except Exception:
                logger.exception("Post-check plugin '%s' failed.", name)

        return {
            "checks": [
                {"type": c.check_type.value, "result": c.result.value, "reason": c.reason}
                for c in checks
            ],
            "tx_hash": tx_hash,
        }

    # ── Configuration ─────────────────────────────────────────────────

    def set_threshold(self, name: str, value_wei: int) -> None:
        """Set a compliance threshold value."""
        self._thresholds[name] = value_wei
        logger.info("Compliance threshold '%s' set to %d wei.", name, value_wei)

    def get_threshold(self, name: str) -> Optional[int]:
        """Get a compliance threshold value."""
        return self._thresholds.get(name)

    def get_audit_log(self, limit: int = 100) -> List[ComplianceReport]:
        """Return recent compliance reports."""
        return list(reversed(self._audit_log[-limit:]))

    # ── Internal ──────────────────────────────────────────────────────

    def _check_thresholds(
        self, sender: str, recipient: str, amount_wei: int,
    ) -> ComplianceCheckResult:
        """Run built-in threshold checks."""
        edd_threshold = self._thresholds.get("enhanced_due_diligence_wei", 0)

        if edd_threshold > 0 and amount_wei >= edd_threshold:
            return ComplianceCheckResult(
                check_type=ComplianceCheckType.TRANSACTION_LIMIT,
                result=ComplianceResult.PENDING_REVIEW,
                reason=f"Amount exceeds enhanced due diligence threshold ({edd_threshold} wei).",
            )

        return ComplianceCheckResult(
            check_type=ComplianceCheckType.TRANSACTION_LIMIT,
            result=ComplianceResult.APPROVED,
            reason="Amount within standard limits.",
        )
