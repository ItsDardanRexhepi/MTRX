"""
Multi-Channel Support — Telegram, Slack, Discord, WhatsApp, and more.

Each channel adapter feels native to its platform.
Better than OpenClaw: messages look and feel like they belong on each platform.
"""

from runtime.channels.base.channel import Channel, ChannelMessage, ChannelType
from runtime.channels.registry import ChannelRegistry

__all__ = ["Channel", "ChannelMessage", "ChannelType", "ChannelRegistry"]
