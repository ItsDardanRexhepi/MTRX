"""
Approval Gate for Matrix-to-0pnMatrx Bridge.

Before any component export proceeds, the approval gate sends a Telegram
message to Dardan (chat ID 7161847911) with a complete summary of what
is being exported, sanitizer findings, and a request for explicit approval.

No automatic exports ever — the gate blocks until explicit approval is received.
"""

import logging
import time
from typing import Any, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Polling interval (seconds) when waiting for approval response
APPROVAL_POLL_INTERVAL: int = 10
APPROVAL_TIMEOUT: int = 3600  # 1 hour max wait


class ApprovalGate:
    """
    Gatekeeper that prevents any bridge export without explicit Dardan approval.

    Flow:
        1. Receives export request with sanitizer result.
        2. Sends detailed Telegram message to Dardan.
        3. Blocks until explicit APPROVE / REJECT received.
        4. Returns True only on APPROVE.
    """

    def __init__(self, notifier: Optional[Any] = None) -> None:
        if notifier is None:
            from runtime.matrix.bridge.telegram_notifier import TelegramNotifier
            notifier = TelegramNotifier()
        self.notifier = notifier
        self._approval_store: dict = {}  # component_name -> "approved" | "rejected" | "pending"

    # ── Public API ─────────────────────────────────────────────────────────

    def request_approval(
        self,
        component_name: str,
        sanitizer_result: Any,
    ) -> bool:
        """
        Send an approval request and block until a decision is received.

        Args:
            component_name: The component requesting export approval.
            sanitizer_result: The SanitizationResult from the sanitizer scan.

        Returns:
            True if approved, False if rejected or timed out.
        """
        self._approval_store[component_name] = "pending"

        # Build summary
        summary = self._build_summary(component_name, sanitizer_result)

        # Send Telegram approval request
        response = self.notifier.send_approval_request(component_name, summary)
        if not response.success:
            logger.error(
                "Failed to send approval request for '%s': %s",
                component_name,
                response.error,
            )
            return False

        logger.info(
            "Approval request sent for '%s'. Waiting for explicit response...",
            component_name,
        )

        # Block until approval is received or timeout
        return self._wait_for_approval(component_name)

    def send_telegram_alert(self, message: str) -> bool:
        """Send an arbitrary alert message to Dardan via Telegram."""
        response = self.notifier.send_alert(message)
        return response.success

    def check_approval_status(self, component_name: str) -> str:
        """
        Check current approval status for a component.

        Returns:
            "approved", "rejected", or "pending"
        """
        return self._approval_store.get(component_name, "pending")

    def set_approval(self, component_name: str, approved: bool) -> None:
        """
        Programmatic approval setter — used when processing Telegram
        callback or webhook responses.

        Args:
            component_name: The component to approve/reject.
            approved: True for approved, False for rejected.
        """
        status = "approved" if approved else "rejected"
        self._approval_store[component_name] = status
        logger.info("Approval for '%s' set to '%s'", component_name, status)

    # ── Internal helpers ───────────────────────────────────────────────────

    def _build_summary(self, component_name: str, sanitizer_result: Any) -> str:
        """Build a human-readable summary for the Telegram approval message."""
        lines = [
            f"*Sanitizer Status:* {'CLEAN' if sanitizer_result.is_clean else 'VIOLATIONS FOUND'}",
            f"*Files Scanned:* {sanitizer_result.scanned_files_count}",
            f"*Violations:* {len(sanitizer_result.violations)}",
        ]

        if sanitizer_result.violations:
            lines.append("\n*Violation Details:*")
            for v in sanitizer_result.violations[:10]:  # cap at 10 in message
                lines.append(
                    f"  - `{v.file_path}:{v.line_number}` [{v.category}] {v.pattern_description}"
                )
            if len(sanitizer_result.violations) > 10:
                lines.append(
                    f"  ... and {len(sanitizer_result.violations) - 10} more"
                )

        lines.extend([
            "",
            f"*Target:* 0pnMatrx deployment",
            f"*NeoSafe:* `{NEOSAFE_ADDRESS}`",
            f"*Timestamp:* {sanitizer_result.timestamp}",
        ])

        return "\n".join(lines)

    def _wait_for_approval(self, component_name: str) -> bool:
        """
        Poll the approval store until an explicit decision arrives or timeout.

        In production, a Telegram webhook or polling bot would call
        `set_approval()` when Dardan responds. This loop monitors that state.
        """
        elapsed = 0
        while elapsed < APPROVAL_TIMEOUT:
            status = self._approval_store.get(component_name, "pending")
            if status == "approved":
                logger.info("Component '%s' APPROVED by Dardan", component_name)
                return True
            if status == "rejected":
                logger.warning("Component '%s' REJECTED by Dardan", component_name)
                return False

            time.sleep(APPROVAL_POLL_INTERVAL)
            elapsed += APPROVAL_POLL_INTERVAL

        logger.error(
            "Approval timeout (%ds) for '%s'. Export blocked.",
            APPROVAL_TIMEOUT,
            component_name,
        )
        self._approval_store[component_name] = "rejected"
        return False
