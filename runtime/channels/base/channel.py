"""
Base Channel — abstract interface all channel adapters implement.

Every channel must handle: send, edit, react, typing, and receive.
"""

from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional


class ChannelType(str, Enum):
    TELEGRAM = "telegram"
    SLACK = "slack"
    DISCORD = "discord"
    WHATSAPP = "whatsapp"
    WEBHOOK = "webhook"
    API = "api"


@dataclass
class ChannelMessage:
    """A message received from or sent to a channel."""
    message_id: str = ""
    channel_type: ChannelType = ChannelType.API
    channel_id: str = ""          # Chat/channel/room ID
    user_id: str = ""
    user_name: str = ""
    text: str = ""
    reply_to: str = ""            # ID of message being replied to
    attachments: List[dict] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        return {
            "message_id": self.message_id,
            "channel_type": self.channel_type.value,
            "channel_id": self.channel_id,
            "user_id": self.user_id,
            "user_name": self.user_name,
            "text": self.text,
            "reply_to": self.reply_to,
            "attachments": self.attachments,
            "metadata": self.metadata,
            "timestamp": self.timestamp,
        }


class Channel(ABC):
    """
    Abstract base for all channel adapters.

    Each channel must implement these methods to provide
    platform-native messaging that feels right on each platform.
    """

    channel_type: ChannelType = ChannelType.API

    @abstractmethod
    async def send_message(
        self, channel_id: str, text: str, reply_to: str = "",
        parse_mode: str = "", **kwargs,
    ) -> ChannelMessage:
        """Send a message. Returns the sent message."""
        ...

    @abstractmethod
    async def edit_message(
        self, channel_id: str, message_id: str, text: str, **kwargs,
    ) -> bool:
        """Edit an existing message in-place (for streaming)."""
        ...

    @abstractmethod
    async def react(
        self, channel_id: str, message_id: str, emoji: str,
    ) -> bool:
        """React to a message with an emoji."""
        ...

    @abstractmethod
    async def send_typing(self, channel_id: str) -> None:
        """Show typing indicator."""
        ...

    @abstractmethod
    async def delete_message(self, channel_id: str, message_id: str) -> bool:
        """Delete a message."""
        ...

    async def send_approval_request(
        self,
        channel_id: str,
        title: str,
        description: str,
        approve_data: str = "",
        reject_data: str = "",
    ) -> ChannelMessage:
        """Send an approval request with yes/no buttons. Override for platform-native buttons."""
        text = f"🔐 *Approval Required*\n\n{title}\n\n{description}\n\nReply YES to approve or NO to reject."
        return await self.send_message(channel_id, text)

    def format_for_platform(self, text: str) -> str:
        """Format text for this platform's conventions. Override per channel."""
        return text
