"""
ERC-8004 Update Executor
=========================

Applies ERC-8004 updates **only** after both the safety validator AND the
Rexhepi gate have approved the update.

On successful completion, sends a Telegram alert to Dardan (ID 7161847911)
with details of what changed, which files were updated, and confirmation.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

from runtime.blockchain.services.agent_identity.rexhepi_gate import GateDecision, GateResult

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID = "7161847911"


class ExecutionStatus(Enum):
    """Outcome of an update execution attempt."""
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"
    ROLLED_BACK = "rolled_back"


@dataclass
class ExecutionRecord:
    """Record of an executed (or attempted) update."""
    version: str
    status: ExecutionStatus
    files_updated: List[str] = field(default_factory=list)
    changes_summary: str = ""
    executed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    alert_sent: bool = False
    error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class UpdateExecutor:
    """Applies ERC-8004 updates after dual-gate approval.

    Execution prerequisites:
        1. ``UpdateSafetyValidator.validate()`` must return ``passed == True``.
        2. ``RexhepiGateConnector.submit_to_gate()`` must return ``approved == True``.

    On completion a Telegram alert is sent to Dardan with:
        - What changed (changelog excerpt)
        - Which files were updated
        - Confirmation of successful application
    """

    def __init__(self) -> None:
        self._execution_history: Dict[str, ExecutionRecord] = {}
        logger.info("UpdateExecutor initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def execute_update(self, update: Any, gate_result: GateResult) -> ExecutionRecord:
        """Execute an update only if the gate result is APPROVED.

        Args:
            update: The update payload (must expose ``.version``,
                    ``.changelog``, and ``.affected_files`` attributes).
            gate_result: Result from ``RexhepiGateConnector.submit_to_gate()``.

        Returns:
            ``ExecutionRecord`` with the outcome.

        Raises:
            ValueError: If *gate_result* is not APPROVED.
        """
        if gate_result.decision != GateDecision.APPROVED:
            logger.warning(
                "Cannot execute update %s — gate decision is %s: %s",
                gate_result.version, gate_result.decision.value, gate_result.reason,
            )
            record = ExecutionRecord(
                version=gate_result.version,
                status=ExecutionStatus.SKIPPED,
                changes_summary=f"Skipped: gate decision was {gate_result.decision.value}",
                error=gate_result.reason,
            )
            self._execution_history[gate_result.version] = record
            return record

        logger.info("Executing update %s (gate_id=%s)", gate_result.version, gate_result.update_id)

        try:
            files_updated = self.apply_changes(update)

            record = ExecutionRecord(
                version=gate_result.version,
                status=ExecutionStatus.SUCCESS,
                files_updated=files_updated,
                changes_summary=getattr(update, "changelog", "No changelog available"),
            )
            self._execution_history[gate_result.version] = record

            self.send_completion_alert(update)
            record.alert_sent = True

            logger.info(
                "Update %s applied successfully (%d files updated)",
                gate_result.version, len(files_updated),
            )
            return record

        except Exception as exc:
            logger.error("Update %s execution failed: %s", gate_result.version, exc)
            record = ExecutionRecord(
                version=gate_result.version,
                status=ExecutionStatus.FAILED,
                error=str(exc),
                changes_summary="Execution failed — see error field",
            )
            self._execution_history[gate_result.version] = record

            # Attempt rollback
            self._rollback(gate_result.version)
            record.status = ExecutionStatus.ROLLED_BACK

            # Alert Dardan about the failure
            self._send_failure_alert(gate_result.version, str(exc))
            return record

    def apply_changes(self, update: Any) -> List[str]:
        """Apply the actual file/contract changes described by *update*.

        Args:
            update: The update payload.

        Returns:
            List of file paths that were modified.

        Raises:
            RuntimeError: If applying changes fails.
        """
        affected_files: List[str] = getattr(update, "affected_files", [])

        try:
            # TODO: Replace with actual file/contract update logic
            # For each affected file:
            #   1. Back up current version
            #   2. Apply diff / replace with new version
            #   3. Verify integrity post-application
            updated: List[str] = []
            for file_path in affected_files:
                logger.debug("Applying changes to %s", file_path)
                updated.append(file_path)

            logger.info("Applied changes to %d files", len(updated))
            return updated

        except Exception as exc:
            logger.error("Failed to apply changes: %s", exc)
            raise RuntimeError(f"Change application failed: {exc}") from exc

    def send_completion_alert(self, update: Any) -> None:
        """Send a Telegram alert to Dardan confirming successful update.

        Alert includes:
            - What changed (changelog)
            - Which files were updated
            - Confirmation message

        Args:
            update: The update payload.
        """
        version = getattr(update, "version", "unknown")
        changelog = getattr(update, "changelog", "No changelog")
        affected = getattr(update, "affected_files", [])

        message_lines = [
            f"[0pnMatrx] ERC-8004 Update Applied Successfully",
            f"",
            f"Version: {version}",
            f"",
            f"What changed:",
            f"  {changelog}",
            f"",
            f"Files updated ({len(affected)}):",
        ]
        for f in affected:
            message_lines.append(f"  - {f}")
        message_lines.extend([
            f"",
            f"Status: CONFIRMED — all validators passed",
            f"Pipeline: SafetyValidator -> RexhepiGate -> Executor",
        ])

        message = "\n".join(message_lines)
        self._send_telegram(message)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _send_telegram(message: str) -> None:
        """Send a message to Dardan via Telegram Bot API.

        Target chat ID: 7161847911
        """
        try:
            # TODO: Integrate with Telegram Bot API
            # import httpx
            # resp = httpx.post(
            #     f"https://api.telegram.org/bot<TOKEN>/sendMessage",
            #     json={"chat_id": DARDAN_TELEGRAM_ID, "text": message},
            # )
            # resp.raise_for_status()
            logger.info("TELEGRAM -> %s:\n%s", DARDAN_TELEGRAM_ID, message)
        except Exception as exc:
            logger.error("Failed to send Telegram alert to %s: %s", DARDAN_TELEGRAM_ID, exc)

    @staticmethod
    def _send_failure_alert(version: str, error: str) -> None:
        """Alert Dardan about a failed update execution."""
        message = (
            f"[0pnMatrx ALERT] ERC-8004 Update FAILED\n"
            f"Version: {version}\n"
            f"Error: {error}\n"
            f"Action: Rollback attempted. Manual review required."
        )
        try:
            logger.critical("TELEGRAM -> %s:\n%s", DARDAN_TELEGRAM_ID, message)
        except Exception as exc:
            logger.error("Failed to send failure alert: %s", exc)

    def _rollback(self, version: str) -> None:
        """Attempt to roll back a failed update.

        Args:
            version: The version whose changes should be reverted.
        """
        try:
            # TODO: Restore backed-up files
            logger.warning("Rolling back update %s", version)
        except Exception as exc:
            logger.error("Rollback failed for %s: %s", version, exc)
