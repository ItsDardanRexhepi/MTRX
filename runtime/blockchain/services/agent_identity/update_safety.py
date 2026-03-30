"""
ERC-8004 Update Safety Validator
=================================

Runs every incoming ERC-8004 update through compatibility checks against
Rexhepi Framework v2 and the platform security layer.

Must pass **BEFORE** the Rexhepi gate.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class SafetyStatus(Enum):
    """Possible outcomes of a safety validation run."""
    PASSED = "passed"
    FAILED = "failed"
    WARNING = "warning"


@dataclass
class SafetyCheck:
    """Result of an individual compatibility check."""
    check_name: str
    status: SafetyStatus
    message: str
    details: Dict[str, Any] = field(default_factory=dict)


@dataclass
class SafetyResult:
    """Aggregate result of safety validation for an update."""
    version: str
    overall_status: SafetyStatus
    rexhepi_compatible: bool
    security_compatible: bool
    checks: List[SafetyCheck] = field(default_factory=list)
    validated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    report: Optional[str] = None

    @property
    def passed(self) -> bool:
        """Convenience flag — ``True`` only when every check passed."""
        return self.overall_status == SafetyStatus.PASSED


@dataclass
class UpdatePayload:
    """Normalised representation of an incoming ERC-8004 update."""
    version: str
    changelog: str
    breaking_changes: bool
    affected_files: List[str] = field(default_factory=list)
    code_diff: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class UpdateSafetyValidator:
    """Validates ERC-8004 updates for compatibility before they reach the Rexhepi gate.

    Every incoming update is checked against:
    1. **Rexhepi Framework v2** — ensures no conflict with execution-gate logic.
    2. **Security layer** — ensures no regressions in the platform security posture.

    Only updates that pass **both** checks are forwarded to the Rexhepi gate.
    """

    # Components whose interfaces must remain stable.
    REXHEPI_CRITICAL_INTERFACES: List[str] = [
        "execution_gate",
        "spend_enforcement",
        "identity_validation",
        "attestation_pipeline",
    ]

    SECURITY_CRITICAL_INTERFACES: List[str] = [
        "access_control",
        "encryption_layer",
        "audit_logging",
        "threat_detection",
    ]

    def __init__(self) -> None:
        self._validation_history: Dict[str, SafetyResult] = {}
        logger.info("UpdateSafetyValidator initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def validate(self, update: UpdatePayload) -> SafetyResult:
        """Run the full safety-validation pipeline on *update*.

        Args:
            update: The incoming ERC-8004 update payload.

        Returns:
            ``SafetyResult`` summarising the validation outcome.
        """
        logger.info("Validating update %s", update.version)

        checks: List[SafetyCheck] = []

        rexhepi_result = self.check_rexhepi_compatibility(update)
        checks.append(rexhepi_result)

        security_result = self.check_security_compatibility(update)
        checks.append(security_result)

        # Schema check — ensure the update does not alter ERC-8004 token schema
        schema_check = self._check_schema_compatibility(update)
        checks.append(schema_check)

        # Breaking-change gate
        if update.breaking_changes:
            checks.append(SafetyCheck(
                check_name="breaking_change_review",
                status=SafetyStatus.WARNING,
                message="Update contains breaking changes — manual review recommended",
            ))

        rexhepi_ok = rexhepi_result.status == SafetyStatus.PASSED
        security_ok = security_result.status == SafetyStatus.PASSED

        if rexhepi_ok and security_ok:
            overall = SafetyStatus.PASSED
        else:
            overall = SafetyStatus.FAILED

        result = SafetyResult(
            version=update.version,
            overall_status=overall,
            rexhepi_compatible=rexhepi_ok,
            security_compatible=security_ok,
            checks=checks,
            report=self.generate_report(update),
        )

        self._validation_history[update.version] = result
        logger.info(
            "Validation for %s: overall=%s rexhepi=%s security=%s",
            update.version, overall.value, rexhepi_ok, security_ok,
        )
        return result

    def check_rexhepi_compatibility(self, update: UpdatePayload) -> SafetyCheck:
        """Check compatibility of *update* with Rexhepi Framework v2.

        Args:
            update: The incoming update payload.

        Returns:
            A ``SafetyCheck`` for the Rexhepi compatibility dimension.
        """
        try:
            conflicts = self._detect_interface_conflicts(
                update, self.REXHEPI_CRITICAL_INTERFACES,
            )
            if conflicts:
                return SafetyCheck(
                    check_name="rexhepi_fw_v2_compatibility",
                    status=SafetyStatus.FAILED,
                    message=f"Conflicts with Rexhepi FW v2 interfaces: {', '.join(conflicts)}",
                    details={"conflicts": conflicts},
                )
            return SafetyCheck(
                check_name="rexhepi_fw_v2_compatibility",
                status=SafetyStatus.PASSED,
                message="Compatible with Rexhepi Framework v2",
            )
        except Exception as exc:
            logger.error("Rexhepi compatibility check failed: %s", exc)
            return SafetyCheck(
                check_name="rexhepi_fw_v2_compatibility",
                status=SafetyStatus.FAILED,
                message=f"Rexhepi compatibility check error: {exc}",
            )

    def check_security_compatibility(self, update: UpdatePayload) -> SafetyCheck:
        """Check compatibility of *update* with the platform security layer.

        Args:
            update: The incoming update payload.

        Returns:
            A ``SafetyCheck`` for the security compatibility dimension.
        """
        try:
            conflicts = self._detect_interface_conflicts(
                update, self.SECURITY_CRITICAL_INTERFACES,
            )
            if conflicts:
                return SafetyCheck(
                    check_name="security_layer_compatibility",
                    status=SafetyStatus.FAILED,
                    message=f"Conflicts with security layer interfaces: {', '.join(conflicts)}",
                    details={"conflicts": conflicts},
                )
            return SafetyCheck(
                check_name="security_layer_compatibility",
                status=SafetyStatus.PASSED,
                message="Compatible with platform security layer",
            )
        except Exception as exc:
            logger.error("Security compatibility check failed: %s", exc)
            return SafetyCheck(
                check_name="security_layer_compatibility",
                status=SafetyStatus.FAILED,
                message=f"Security compatibility check error: {exc}",
            )

    def generate_report(self, update: UpdatePayload) -> str:
        """Generate a human-readable safety report for *update*.

        Args:
            update: The update being validated.

        Returns:
            Multi-line report string.
        """
        lines = [
            f"=== ERC-8004 Update Safety Report ===",
            f"Version       : {update.version}",
            f"Breaking      : {'Yes' if update.breaking_changes else 'No'}",
            f"Affected files: {len(update.affected_files)}",
            f"",
        ]

        cached = self._validation_history.get(update.version)
        if cached:
            lines.append(f"Overall status: {cached.overall_status.value}")
            lines.append(f"Rexhepi compat: {'PASS' if cached.rexhepi_compatible else 'FAIL'}")
            lines.append(f"Security compat: {'PASS' if cached.security_compatible else 'FAIL'}")
            lines.append("")
            for check in cached.checks:
                lines.append(f"  [{check.status.value.upper()}] {check.check_name}: {check.message}")
        else:
            lines.append("No cached validation result — run validate() first.")

        report = "\n".join(lines)
        logger.debug("Generated safety report for %s", update.version)
        return report

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _detect_interface_conflicts(
        update: UpdatePayload,
        critical_interfaces: List[str],
    ) -> List[str]:
        """Detect whether *update* modifies any critical interface.

        Returns:
            List of conflicting interface names (empty if clean).
        """
        conflicts: List[str] = []
        for iface in critical_interfaces:
            for affected in update.affected_files:
                if iface in affected.lower():
                    conflicts.append(iface)
                    break
        return conflicts

    @staticmethod
    def _check_schema_compatibility(update: UpdatePayload) -> SafetyCheck:
        """Verify that the update does not alter the core ERC-8004 token schema.

        Returns:
            ``SafetyCheck`` result.
        """
        schema_files = [f for f in update.affected_files if "schema" in f.lower() or "token" in f.lower()]
        if schema_files:
            return SafetyCheck(
                check_name="schema_compatibility",
                status=SafetyStatus.WARNING,
                message=f"Update touches schema-related files: {schema_files}",
                details={"schema_files": schema_files},
            )
        return SafetyCheck(
            check_name="schema_compatibility",
            status=SafetyStatus.PASSED,
            message="No schema changes detected",
        )
