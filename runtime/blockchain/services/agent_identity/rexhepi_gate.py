"""
Rexhepi Gate Connector
=======================

Routes validated ERC-8004 updates through the Rexhepi Framework v2
execution gate.

Pipeline position: **AFTER** UpdateSafetyValidator, **BEFORE** UpdateExecutor.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, Optional

from runtime.blockchain.services.agent_identity.update_safety import SafetyResult

logger = logging.getLogger(__name__)


class GateDecision(Enum):
    """Possible decisions from the Rexhepi execution gate."""
    APPROVED = "approved"
    REJECTED = "rejected"
    PENDING = "pending"
    ERROR = "error"


@dataclass
class GateResult:
    """Result returned by the Rexhepi Framework v2 execution gate."""
    update_id: str
    version: str
    decision: GateDecision
    reason: str
    evaluated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    gate_signature: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def approved(self) -> bool:
        return self.decision == GateDecision.APPROVED


@dataclass
class GateSubmission:
    """Internal envelope for a submission to the Rexhepi gate."""
    update_id: str
    version: str
    safety_result: SafetyResult
    submitted_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


class RexhepiGateConnector:
    """Routes validated updates through the Rexhepi Framework v2 execution gate.

    Must be invoked **after** the safety validator passes and **before** the
    update executor applies changes.

    Flow:
        UpdateSafetyValidator  -->  RexhepiGateConnector  -->  UpdateExecutor
    """

    def __init__(self) -> None:
        self._submissions: Dict[str, GateSubmission] = {}
        self._results: Dict[str, GateResult] = {}
        self._submission_counter: int = 0
        logger.info("RexhepiGateConnector initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def submit_to_gate(self, update: Any, safety_result: SafetyResult) -> GateResult:
        """Submit a validated update to the Rexhepi Framework v2 execution gate.

        The update must have already passed the ``UpdateSafetyValidator``.
        If the safety result indicates failure the gate rejects immediately.

        Args:
            update: The update payload (must expose a ``.version`` attribute).
            safety_result: Output of ``UpdateSafetyValidator.validate()``.

        Returns:
            ``GateResult`` containing the gate's decision.

        Raises:
            ValueError: If *safety_result* has not passed validation.
        """
        if not safety_result.passed:
            logger.warning(
                "Rejecting submission for %s — safety validation did not pass",
                safety_result.version,
            )
            return GateResult(
                update_id=self._next_id(),
                version=safety_result.version,
                decision=GateDecision.REJECTED,
                reason="Safety validation did not pass — cannot submit to Rexhepi gate",
            )

        update_id = self._next_id()
        submission = GateSubmission(
            update_id=update_id,
            version=safety_result.version,
            safety_result=safety_result,
        )
        self._submissions[update_id] = submission

        result = self._evaluate_at_gate(submission)
        self._results[update_id] = result

        logger.info(
            "Rexhepi gate decision for %s (id=%s): %s — %s",
            result.version, update_id, result.decision.value, result.reason,
        )
        return result

    def check_gate_status(self, update_id: str) -> GateResult:
        """Check the current gate status for a previously submitted update.

        Args:
            update_id: Identifier returned by ``submit_to_gate``.

        Returns:
            ``GateResult`` for the submission.

        Raises:
            KeyError: If *update_id* is unknown.
        """
        if update_id not in self._results:
            raise KeyError(f"No gate result found for update_id={update_id}")
        return self._results[update_id]

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _next_id(self) -> str:
        self._submission_counter += 1
        return f"gate-{self._submission_counter}"

    def _evaluate_at_gate(self, submission: GateSubmission) -> GateResult:
        """Run the Rexhepi Framework v2 evaluation logic.

        Returns:
            ``GateResult`` with the gate's decision.
        """
        try:
            # TODO: Replace with actual Rexhepi Framework v2 gate call
            # The gate verifies:
            #   1. Safety result integrity
            #   2. Update does not violate execution policies
            #   3. Rexhepi FW internal constraints are honoured

            rexhepi_ok = submission.safety_result.rexhepi_compatible
            security_ok = submission.safety_result.security_compatible

            if rexhepi_ok and security_ok:
                return GateResult(
                    update_id=submission.update_id,
                    version=submission.version,
                    decision=GateDecision.APPROVED,
                    reason="Update approved by Rexhepi Framework v2 execution gate",
                    gate_signature=f"rexhepi-sig-{submission.update_id}",
                )
            else:
                reasons = []
                if not rexhepi_ok:
                    reasons.append("Rexhepi FW incompatibility")
                if not security_ok:
                    reasons.append("Security layer incompatibility")
                return GateResult(
                    update_id=submission.update_id,
                    version=submission.version,
                    decision=GateDecision.REJECTED,
                    reason=f"Rejected: {'; '.join(reasons)}",
                )
        except Exception as exc:
            logger.error("Rexhepi gate evaluation error: %s", exc)
            return GateResult(
                update_id=submission.update_id,
                version=submission.version,
                decision=GateDecision.ERROR,
                reason=f"Gate evaluation error: {exc}",
            )
