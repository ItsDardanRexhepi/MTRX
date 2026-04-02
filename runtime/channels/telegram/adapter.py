"""
Telegram Channel Adapter — native Telegram messaging with streaming support.

Features beyond OpenClaw:
- Real-time typing indicators during response generation
- In-place message editing for streaming responses
- Inline keyboard buttons for approval flows
- Markdown V2 formatting that looks native
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

import httpx

from runtime.channels.base.channel import Channel, ChannelMessage, ChannelType

logger = logging.getLogger(__name__)

TELEGRAM_API = "https://api.telegram.org/bot{token}"


class TelegramChannel(Channel):
    """
    Telegram bot adapter with streaming and approval support.

    Uses direct HTTP API calls (no python-telegram-bot dependency).
    Supports in-place message editing for streaming responses.
    """

    channel_type = ChannelType.TELEGRAM

    def __init__(self, bot_token: str = "") -> None:
        self._token = bot_token or os.environ.get("MATRIX_TELEGRAM_BOT_TOKEN", "")
        self._base_url = TELEGRAM_API.format(token=self._token)
        self._client: Optional[httpx.AsyncClient] = None
        logger.info("TelegramChannel initialised | token=%s", "set" if self._token else "missing")

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=30.0)
        return self._client

    async def send_message(
        self, channel_id: str, text: str, reply_to: str = "",
        parse_mode: str = "Markdown", **kwargs,
    ) -> ChannelMessage:
        client = await self._get_client()
        payload = {
            "chat_id": channel_id,
            "text": text,
            "parse_mode": parse_mode,
        }
        if reply_to:
            payload["reply_to_message_id"] = reply_to
        if kwargs.get("reply_markup"):
            payload["reply_markup"] = kwargs["reply_markup"]

        resp = await client.post(f"{self._base_url}/sendMessage", json=payload)
        data = resp.json()

        if not data.get("ok"):
            # Retry without parse mode if formatting failed
            if "parse" in str(data.get("description", "")).lower():
                payload["parse_mode"] = ""
                resp = await client.post(f"{self._base_url}/sendMessage", json=payload)
                data = resp.json()

            if not data.get("ok"):
                logger.error("Telegram send failed: %s", data.get("description"))
                return ChannelMessage(channel_type=ChannelType.TELEGRAM, channel_id=channel_id, text=text)

        result = data["result"]
        return ChannelMessage(
            message_id=str(result["message_id"]),
            channel_type=ChannelType.TELEGRAM,
            channel_id=channel_id,
            text=text,
        )

    async def edit_message(
        self, channel_id: str, message_id: str, text: str, **kwargs,
    ) -> bool:
        """Edit a message in-place — used for streaming responses."""
        client = await self._get_client()
        payload = {
            "chat_id": channel_id,
            "message_id": int(message_id),
            "text": text,
            "parse_mode": kwargs.get("parse_mode", "Markdown"),
        }
        resp = await client.post(f"{self._base_url}/editMessageText", json=payload)
        data = resp.json()
        if not data.get("ok"):
            # Common: message not modified (same text)
            desc = data.get("description", "")
            if "not modified" not in desc.lower():
                logger.warning("Telegram edit failed: %s", desc)
            return False
        return True

    async def react(self, channel_id: str, message_id: str, emoji: str) -> bool:
        """React to a message (Telegram supports reactions since API 7.0)."""
        client = await self._get_client()
        payload = {
            "chat_id": channel_id,
            "message_id": int(message_id),
            "reaction": [{"type": "emoji", "emoji": emoji}],
        }
        resp = await client.post(f"{self._base_url}/setMessageReaction", json=payload)
        return resp.json().get("ok", False)

    async def send_typing(self, channel_id: str) -> None:
        """Show typing indicator — call this repeatedly during generation."""
        client = await self._get_client()
        await client.post(
            f"{self._base_url}/sendChatAction",
            json={"chat_id": channel_id, "action": "typing"},
        )

    async def delete_message(self, channel_id: str, message_id: str) -> bool:
        client = await self._get_client()
        resp = await client.post(
            f"{self._base_url}/deleteMessage",
            json={"chat_id": channel_id, "message_id": int(message_id)},
        )
        return resp.json().get("ok", False)

    async def send_approval_request(
        self,
        channel_id: str,
        title: str,
        description: str,
        approve_data: str = "",
        reject_data: str = "",
    ) -> ChannelMessage:
        """Send approval with inline keyboard buttons."""
        text = f"*Approval Needed*\n\n{title}\n\n{description}"
        reply_markup = {
            "inline_keyboard": [[
                {"text": "✅ Approve", "callback_data": approve_data or "approve"},
                {"text": "❌ Reject", "callback_data": reject_data or "reject"},
            ]]
        }
        return await self.send_message(
            channel_id, text, reply_markup=reply_markup,
        )

    def format_for_platform(self, text: str) -> str:
        """Telegram uses Markdown formatting."""
        return text

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None
