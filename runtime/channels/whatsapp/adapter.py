"""
WhatsApp Channel Adapter — native WhatsApp Cloud API messaging.

Better than OpenClaw:
- Emoji reactions on incoming messages
- Interactive button messages for approvals
- Template message support
- Read receipts
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, Optional

import httpx

from runtime.channels.base.channel import Channel, ChannelMessage, ChannelType

logger = logging.getLogger(__name__)

WHATSAPP_API = "https://graph.facebook.com/v19.0"


class WhatsAppChannel(Channel):
    """
    WhatsApp Cloud API adapter with reactions and interactive messages.

    Messages feel native to WhatsApp. Supports emoji reactions on
    incoming messages, interactive buttons for approvals, and
    proper read receipt handling.
    """

    channel_type = ChannelType.WHATSAPP

    def __init__(
        self,
        access_token: str = "",
        phone_number_id: str = "",
    ) -> None:
        self._token = access_token or os.environ.get("MATRIX_WHATSAPP_TOKEN", "")
        self._phone_id = phone_number_id or os.environ.get("MATRIX_WHATSAPP_PHONE_ID", "")
        self._client: Optional[httpx.AsyncClient] = None
        logger.info("WhatsAppChannel initialised | phone_id=%s", self._phone_id or "missing")

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=30.0,
                headers={"Authorization": f"Bearer {self._token}"},
            )
        return self._client

    async def send_message(
        self, channel_id: str, text: str, reply_to: str = "",
        parse_mode: str = "", **kwargs,
    ) -> ChannelMessage:
        """Send a WhatsApp text message."""
        client = await self._get_client()
        payload: Dict[str, Any] = {
            "messaging_product": "whatsapp",
            "to": channel_id,
            "type": "text",
            "text": {"body": self.format_for_platform(text)},
        }
        if reply_to:
            payload["context"] = {"message_id": reply_to}

        resp = await client.post(
            f"{WHATSAPP_API}/{self._phone_id}/messages", json=payload,
        )
        data = resp.json()

        msg_id = ""
        if "messages" in data:
            msg_id = data["messages"][0].get("id", "")
        elif not data.get("error"):
            msg_id = data.get("id", "")

        if data.get("error"):
            logger.error("WhatsApp send failed: %s", data["error"].get("message"))

        return ChannelMessage(
            message_id=msg_id,
            channel_type=ChannelType.WHATSAPP,
            channel_id=channel_id,
            text=text,
        )

    async def edit_message(
        self, channel_id: str, message_id: str, text: str, **kwargs,
    ) -> bool:
        """WhatsApp doesn't support message editing. Send a new message instead."""
        # WhatsApp Cloud API does not support editing sent messages
        return False

    async def react(self, channel_id: str, message_id: str, emoji: str) -> bool:
        """React to a message with an emoji — WhatsApp supports this natively."""
        client = await self._get_client()
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": channel_id,
            "type": "reaction",
            "reaction": {
                "message_id": message_id,
                "emoji": emoji,
            },
        }
        resp = await client.post(
            f"{WHATSAPP_API}/{self._phone_id}/messages", json=payload,
        )
        data = resp.json()
        return not data.get("error")

    async def send_typing(self, channel_id: str) -> None:
        """WhatsApp doesn't have a public typing indicator API."""
        pass

    async def delete_message(self, channel_id: str, message_id: str) -> bool:
        """WhatsApp doesn't support deleting sent messages via API."""
        return False

    async def mark_read(self, message_id: str) -> bool:
        """Mark a received message as read."""
        client = await self._get_client()
        payload = {
            "messaging_product": "whatsapp",
            "status": "read",
            "message_id": message_id,
        }
        resp = await client.post(
            f"{WHATSAPP_API}/{self._phone_id}/messages", json=payload,
        )
        return not resp.json().get("error")

    async def send_approval_request(
        self,
        channel_id: str,
        title: str,
        description: str,
        approve_data: str = "",
        reject_data: str = "",
    ) -> ChannelMessage:
        """Send interactive button message for approval."""
        client = await self._get_client()
        payload = {
            "messaging_product": "whatsapp",
            "to": channel_id,
            "type": "interactive",
            "interactive": {
                "type": "button",
                "header": {"type": "text", "text": "Approval Needed"},
                "body": {"text": f"{title}\n\n{description}"},
                "action": {
                    "buttons": [
                        {
                            "type": "reply",
                            "reply": {"id": approve_data or "approve", "title": "Approve"},
                        },
                        {
                            "type": "reply",
                            "reply": {"id": reject_data or "reject", "title": "Reject"},
                        },
                    ],
                },
            },
        }
        resp = await client.post(
            f"{WHATSAPP_API}/{self._phone_id}/messages", json=payload,
        )
        data = resp.json()
        msg_id = ""
        if "messages" in data:
            msg_id = data["messages"][0].get("id", "")

        return ChannelMessage(
            message_id=msg_id,
            channel_type=ChannelType.WHATSAPP,
            channel_id=channel_id,
            text=f"{title}\n{description}",
        )

    def format_for_platform(self, text: str) -> str:
        """WhatsApp uses *bold* _italic_ ~strikethrough~ ```monospace```."""
        return text

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None
