"""
Telegram Notification Utility for Matrix-to-0pnMatrx Bridge.

Provides centralized Telegram messaging for sanitizer alerts,
approval requests, and deployment notifications.
"""

import logging
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

import requests

logger = logging.getLogger(__name__)

# ── Constants ──────────────────────────────────────────────────────────────────
DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# ── CREDENTIAL INJECTION POINT ─────────────────────────────────────────────────
# Set this via environment variable MATRIX_BRIDGE_TELEGRAM_BOT_TOKEN
# or inject directly before runtime initialisation.
TELEGRAM_BOT_TOKEN: Optional[str] = None
# ───────────────────────────────────────────────────────────────────────────────

TELEGRAM_API_BASE = "https://api.telegram.org/bot{token}"


@dataclass
class TelegramResponse:
    """Result of a Telegram API call."""
    success: bool
    message_id: Optional[int] = None
    error: Optional[str] = None
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class TelegramNotifier:
    """
    Sends Telegram notifications for the Matrix-to-0pnMatrx bridge.

    Used by: sanitizer, approval_gate, deployer, and other bridge modules.
    """

    def __init__(
        self,
        bot_token: Optional[str] = None,
        default_chat_id: int = DARDAN_TELEGRAM_ID,
    ) -> None:
        import os
        self.bot_token: Optional[str] = (
            bot_token
            or TELEGRAM_BOT_TOKEN
            or os.environ.get("MATRIX_BRIDGE_TELEGRAM_BOT_TOKEN")
        )
        self.default_chat_id: int = default_chat_id
        self._api_base: Optional[str] = (
            TELEGRAM_API_BASE.format(token=self.bot_token) if self.bot_token else None
        )

    # ── Core messaging ─────────────────────────────────────────────────────

    def send_message(self, chat_id: int, message: str) -> TelegramResponse:
        """Send a plain-text message to the specified chat."""
        if not self.bot_token or not self._api_base:
            logger.error("Telegram bot token not configured. Cannot send message.")
            return TelegramResponse(success=False, error="Bot token not configured")

        url = f"{self._api_base}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "Markdown",
        }

        try:
            resp = requests.post(url, json=payload, timeout=15)
            resp.raise_for_status()
            data = resp.json()
            if data.get("ok"):
                msg_id = data["result"]["message_id"]
                logger.info("Telegram message sent (id=%s) to chat %s", msg_id, chat_id)
                return TelegramResponse(success=True, message_id=msg_id)
            else:
                error_desc = data.get("description", "Unknown Telegram error")
                logger.error("Telegram API error: %s", error_desc)
                return TelegramResponse(success=False, error=error_desc)
        except requests.RequestException as exc:
            logger.exception("Failed to send Telegram message: %s", exc)
            return TelegramResponse(success=False, error=str(exc))

    def send_alert(self, message: str) -> TelegramResponse:
        """Send an alert to the default Dardan chat ID."""
        header = (
            "\U0001f6a8 *MATRIX BRIDGE ALERT*\n"
            f"Timestamp: {datetime.now(timezone.utc).isoformat()}\n"
            "─────────────────────────\n"
        )
        return self.send_message(self.default_chat_id, header + message)

    def send_approval_request(
        self,
        component_name: str,
        details: str,
    ) -> TelegramResponse:
        """Send a structured approval request for a bridge export."""
        message = (
            "\U0001f512 *EXPORT APPROVAL REQUIRED*\n\n"
            f"*Component:* `{component_name}`\n"
            f"*NeoSafe:* `{NEOSAFE_ADDRESS}`\n\n"
            f"{details}\n\n"
            "Reply with *APPROVE* or *REJECT* followed by component name.\n"
            "No automatic exports will proceed without explicit approval."
        )
        return self.send_message(self.default_chat_id, message)
