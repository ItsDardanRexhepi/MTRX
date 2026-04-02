"""
Slack Channel Adapter — native Slack messaging with Block Kit and approval routing.

Better than OpenClaw:
- Native exec approval routing stays in Slack (no context switching)
- Block Kit formatting for rich, interactive messages
- Thread-aware conversations
- Emoji reactions on messages
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional

import httpx

from runtime.channels.base.channel import Channel, ChannelMessage, ChannelType

logger = logging.getLogger(__name__)

SLACK_API = "https://slack.com/api"


class SlackChannel(Channel):
    """
    Slack adapter with Block Kit, threading, and native approval routing.

    Uses Slack Web API directly. Messages feel like native Slack messages
    with proper Block Kit formatting, not just plain text dumps.
    """

    channel_type = ChannelType.SLACK

    def __init__(self, bot_token: str = "", app_token: str = "") -> None:
        self._bot_token = bot_token or os.environ.get("MATRIX_SLACK_BOT_TOKEN", "")
        self._app_token = app_token or os.environ.get("MATRIX_SLACK_APP_TOKEN", "")
        self._client: Optional[httpx.AsyncClient] = None
        logger.info("SlackChannel initialised | token=%s", "set" if self._bot_token else "missing")

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=30.0,
                headers={"Authorization": f"Bearer {self._bot_token}"},
            )
        return self._client

    async def send_message(
        self, channel_id: str, text: str, reply_to: str = "",
        parse_mode: str = "", **kwargs,
    ) -> ChannelMessage:
        """Send a Slack message with optional Block Kit blocks."""
        client = await self._get_client()
        payload: Dict[str, Any] = {
            "channel": channel_id,
            "text": text,  # Fallback text
        }
        if reply_to:
            payload["thread_ts"] = reply_to

        # Convert markdown to Slack Block Kit
        blocks = kwargs.get("blocks")
        if blocks:
            payload["blocks"] = blocks
        else:
            payload["blocks"] = self._text_to_blocks(text)

        resp = await client.post(f"{SLACK_API}/chat.postMessage", json=payload)
        data = resp.json()

        if not data.get("ok"):
            logger.error("Slack send failed: %s", data.get("error"))
            return ChannelMessage(channel_type=ChannelType.SLACK, channel_id=channel_id, text=text)

        return ChannelMessage(
            message_id=data.get("ts", ""),
            channel_type=ChannelType.SLACK,
            channel_id=channel_id,
            text=text,
            metadata={"thread_ts": data.get("ts", "")},
        )

    async def edit_message(
        self, channel_id: str, message_id: str, text: str, **kwargs,
    ) -> bool:
        """Edit a message in-place for streaming."""
        client = await self._get_client()
        payload = {
            "channel": channel_id,
            "ts": message_id,
            "text": text,
            "blocks": kwargs.get("blocks") or self._text_to_blocks(text),
        }
        resp = await client.post(f"{SLACK_API}/chat.update", json=payload)
        data = resp.json()
        if not data.get("ok"):
            logger.warning("Slack edit failed: %s", data.get("error"))
            return False
        return True

    async def react(self, channel_id: str, message_id: str, emoji: str) -> bool:
        """Add emoji reaction to a message."""
        client = await self._get_client()
        # Slack uses emoji names without colons
        emoji_name = emoji.strip(":")
        resp = await client.post(
            f"{SLACK_API}/reactions.add",
            json={"channel": channel_id, "timestamp": message_id, "name": emoji_name},
        )
        return resp.json().get("ok", False)

    async def send_typing(self, channel_id: str) -> None:
        """Slack doesn't have a typing API, but we can use a status indicator."""
        pass  # Slack Bot API does not support typing indicators

    async def delete_message(self, channel_id: str, message_id: str) -> bool:
        client = await self._get_client()
        resp = await client.post(
            f"{SLACK_API}/chat.delete",
            json={"channel": channel_id, "ts": message_id},
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
        """
        Native Slack approval routing with interactive buttons.

        Approvals stay in Slack — no context switching to Telegram.
        Uses Block Kit interactive components for clean UX.
        """
        blocks = [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": "Approval Needed", "emoji": True},
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": f"*{title}*\n\n{description}"},
            },
            {"type": "divider"},
            {
                "type": "actions",
                "elements": [
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "Approve"},
                        "style": "primary",
                        "action_id": "approval_approve",
                        "value": approve_data or "approve",
                    },
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "Reject"},
                        "style": "danger",
                        "action_id": "approval_reject",
                        "value": reject_data or "reject",
                    },
                ],
            },
        ]
        return await self.send_message(
            channel_id, f"Approval: {title}", blocks=blocks,
        )

    def format_for_platform(self, text: str) -> str:
        """Convert generic markdown to Slack mrkdwn."""
        # Slack uses *bold* and _italic_ (same as generic markdown for basics)
        # Links: <url|text> instead of [text](url)
        import re
        text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<\2|\1>', text)
        return text

    def _text_to_blocks(self, text: str) -> List[dict]:
        """Convert text to Slack Block Kit blocks."""
        # Split into sections at double newlines
        sections = text.split("\n\n")
        blocks = []
        for section in sections:
            section = section.strip()
            if not section:
                continue
            if section.startswith("# "):
                blocks.append({
                    "type": "header",
                    "text": {"type": "plain_text", "text": section[2:].strip()},
                })
            else:
                blocks.append({
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": self.format_for_platform(section)},
                })
        return blocks or [{"type": "section", "text": {"type": "mrkdwn", "text": text}}]

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None
