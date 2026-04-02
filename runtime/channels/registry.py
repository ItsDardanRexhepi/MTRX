"""
Channel Registry — manages all channel adapters.

Provides a unified interface for sending messages to any platform.
Automatically routes messages through the correct channel adapter.
"""

from __future__ import annotations

import logging
from typing import Dict, List, Optional

from runtime.channels.base.channel import Channel, ChannelMessage, ChannelType

logger = logging.getLogger(__name__)


class ChannelRegistry:
    """
    Unified registry for all channel adapters.

    Register channel adapters and send messages through any of them
    using a single interface. Handles routing, fallback, and multi-channel
    broadcasting.
    """

    def __init__(self) -> None:
        self._channels: Dict[ChannelType, Channel] = {}
        self._default_channel: Optional[ChannelType] = None
        logger.info("ChannelRegistry initialised.")

    def register(self, channel: Channel, default: bool = False) -> None:
        """Register a channel adapter."""
        self._channels[channel.channel_type] = channel
        if default or self._default_channel is None:
            self._default_channel = channel.channel_type
        logger.info("Channel registered | type=%s | default=%s",
                     channel.channel_type.value, default)

    def get_channel(self, channel_type: ChannelType) -> Optional[Channel]:
        return self._channels.get(channel_type)

    def get_default(self) -> Optional[Channel]:
        if self._default_channel:
            return self._channels.get(self._default_channel)
        return None

    async def send(
        self,
        channel_type: ChannelType,
        channel_id: str,
        text: str,
        **kwargs,
    ) -> ChannelMessage:
        """Send a message through a specific channel."""
        channel = self._channels.get(channel_type)
        if channel is None:
            raise ValueError(f"Channel {channel_type.value} not registered.")
        formatted = channel.format_for_platform(text)
        return await channel.send_message(channel_id, formatted, **kwargs)

    async def broadcast(
        self,
        text: str,
        targets: List[Dict[str, str]],
        **kwargs,
    ) -> List[ChannelMessage]:
        """Send to multiple channels. Each target: {"type": "...", "id": "..."}."""
        results = []
        for target in targets:
            ct = ChannelType(target["type"])
            channel = self._channels.get(ct)
            if channel:
                msg = await channel.send_message(target["id"], text, **kwargs)
                results.append(msg)
        return results

    def list_channels(self) -> List[dict]:
        return [
            {
                "type": ct.value,
                "default": ct == self._default_channel,
            }
            for ct in self._channels
        ]

    def get_stats(self) -> dict:
        return {
            "registered_channels": len(self._channels),
            "channel_types": [ct.value for ct in self._channels],
            "default": self._default_channel.value if self._default_channel else None,
        }
