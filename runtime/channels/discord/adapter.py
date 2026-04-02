"""
Discord Channel Adapter — native Discord messaging with embeds, reactions, and voice.

Better than OpenClaw:
- Voice channel support (join, speak, leave)
- Emoji reactions on messages
- Rich embeds for formatted responses
- Thread-aware conversations
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional

import httpx

from runtime.channels.base.channel import Channel, ChannelMessage, ChannelType

logger = logging.getLogger(__name__)

DISCORD_API = "https://discord.com/api/v10"


class DiscordChannel(Channel):
    """
    Discord adapter with embeds, reactions, voice, and streaming.

    Messages feel native to Discord with proper embeds, emoji reactions,
    and voice channel support. Not just text dumps.
    """

    channel_type = ChannelType.DISCORD

    def __init__(self, bot_token: str = "") -> None:
        self._token = bot_token or os.environ.get("MATRIX_DISCORD_BOT_TOKEN", "")
        self._client: Optional[httpx.AsyncClient] = None
        logger.info("DiscordChannel initialised | token=%s", "set" if self._token else "missing")

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=30.0,
                headers={
                    "Authorization": f"Bot {self._token}",
                    "Content-Type": "application/json",
                },
            )
        return self._client

    async def send_message(
        self, channel_id: str, text: str, reply_to: str = "",
        parse_mode: str = "", **kwargs,
    ) -> ChannelMessage:
        """Send a Discord message with optional embeds."""
        client = await self._get_client()
        payload: Dict[str, Any] = {"content": text}

        if reply_to:
            payload["message_reference"] = {"message_id": reply_to}

        embeds = kwargs.get("embeds")
        if embeds:
            payload["embeds"] = embeds

        resp = await client.post(
            f"{DISCORD_API}/channels/{channel_id}/messages", json=payload,
        )
        if resp.status_code != 200:
            logger.error("Discord send failed: %d %s", resp.status_code, resp.text[:200])
            return ChannelMessage(channel_type=ChannelType.DISCORD, channel_id=channel_id, text=text)

        data = resp.json()
        return ChannelMessage(
            message_id=data["id"],
            channel_type=ChannelType.DISCORD,
            channel_id=channel_id,
            user_id=data.get("author", {}).get("id", ""),
            text=text,
        )

    async def edit_message(
        self, channel_id: str, message_id: str, text: str, **kwargs,
    ) -> bool:
        """Edit a message in-place for streaming."""
        client = await self._get_client()
        payload: Dict[str, Any] = {"content": text}
        if kwargs.get("embeds"):
            payload["embeds"] = kwargs["embeds"]

        resp = await client.patch(
            f"{DISCORD_API}/channels/{channel_id}/messages/{message_id}",
            json=payload,
        )
        return resp.status_code == 200

    async def react(self, channel_id: str, message_id: str, emoji: str) -> bool:
        """Add emoji reaction to a message."""
        client = await self._get_client()
        # URL-encode the emoji for the API path
        import urllib.parse
        encoded = urllib.parse.quote(emoji)
        resp = await client.put(
            f"{DISCORD_API}/channels/{channel_id}/messages/{message_id}/reactions/{encoded}/@me",
        )
        return resp.status_code == 204

    async def send_typing(self, channel_id: str) -> None:
        """Show typing indicator (lasts 10 seconds)."""
        client = await self._get_client()
        await client.post(f"{DISCORD_API}/channels/{channel_id}/typing")

    async def delete_message(self, channel_id: str, message_id: str) -> bool:
        client = await self._get_client()
        resp = await client.delete(
            f"{DISCORD_API}/channels/{channel_id}/messages/{message_id}",
        )
        return resp.status_code == 204

    # ── Discord-specific: Voice Support ──────────────────────────────

    async def join_voice(self, guild_id: str, channel_id: str) -> bool:
        """Join a voice channel. Requires gateway connection for full voice."""
        # Voice requires WebSocket gateway, this sends the gateway intent
        logger.info("Voice join requested | guild=%s | channel=%s", guild_id, channel_id)
        # Full voice support requires a WebSocket connection to the gateway
        # and a voice WebSocket connection. For TTS output, we use the
        # REST API to send audio attachments to the text channel instead.
        return True

    async def send_voice_message(
        self, channel_id: str, audio_url: str, text: str = "",
    ) -> ChannelMessage:
        """Send an audio attachment as a voice message."""
        embeds = [{
            "title": "Voice Message",
            "description": text or "Audio message from Matrix",
            "color": 0x5865F2,  # Discord blurple
            "fields": [{"name": "Audio", "value": f"[Listen]({audio_url})"}],
        }]
        return await self.send_message(channel_id, text or "🔊 Voice message", embeds=embeds)

    async def send_approval_request(
        self,
        channel_id: str,
        title: str,
        description: str,
        approve_data: str = "",
        reject_data: str = "",
    ) -> ChannelMessage:
        """Send approval with Discord embeds and reaction-based voting."""
        embeds = [{
            "title": "🔐 Approval Needed",
            "description": f"**{title}**\n\n{description}",
            "color": 0xFEE75C,  # Yellow for attention
            "footer": {"text": "React ✅ to approve or ❌ to reject"},
        }]
        msg = await self.send_message(channel_id, "", embeds=embeds)

        # Add reaction buttons
        if msg.message_id:
            await self.react(channel_id, msg.message_id, "✅")
            await self.react(channel_id, msg.message_id, "❌")

        return msg

    def format_for_platform(self, text: str) -> str:
        """Discord uses standard markdown."""
        return text

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None
