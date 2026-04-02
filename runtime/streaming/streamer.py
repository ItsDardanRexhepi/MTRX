"""
Message Streamer — sends partial responses by editing messages in-place.

Handles the complexity of rate-limiting edits, chunking updates,
and maintaining typing indicators across different channel platforms.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import AsyncIterator, Optional

from runtime.channels.base.channel import Channel, ChannelMessage

logger = logging.getLogger(__name__)


@dataclass
class StreamConfig:
    """Configuration for streaming behavior."""
    edit_interval_ms: int = 800     # Min ms between edits (rate limiting)
    typing_interval_ms: int = 4000  # How often to send typing indicator
    min_chunk_chars: int = 20       # Min chars before first edit
    max_message_length: int = 4000  # Platform-specific max length
    show_cursor: bool = True        # Show ▌ cursor while streaming
    cursor_char: str = " ▌"


class MessageStreamer:
    """
    Streams partial responses to a channel by editing a message in place.

    Usage:
        streamer = MessageStreamer(channel)
        async with streamer.stream(channel_id) as stream:
            for token in generate_tokens():
                await stream.push(token)
    """

    def __init__(self, channel: Channel) -> None:
        self._channel = channel

    def stream(self, channel_id: str, config: Optional[StreamConfig] = None) -> _StreamSession:
        """Start a streaming session."""
        return _StreamSession(self._channel, channel_id, config or StreamConfig())


class _StreamSession:
    """
    Manages a single streaming response.

    Sends an initial placeholder message, then edits it in-place
    as tokens arrive. Handles typing indicators and rate limiting.
    """

    def __init__(
        self, channel: Channel, channel_id: str, config: StreamConfig,
    ) -> None:
        self._channel = channel
        self._channel_id = channel_id
        self._config = config
        self._message: Optional[ChannelMessage] = None
        self._buffer: str = ""
        self._last_edit: float = 0.0
        self._last_typing: float = 0.0
        self._typing_task: Optional[asyncio.Task] = None
        self._done: bool = False

    async def __aenter__(self) -> _StreamSession:
        # Send typing indicator immediately
        await self._send_typing()
        # Start background typing indicator
        self._typing_task = asyncio.create_task(self._typing_loop())
        return self

    async def __aexit__(self, *exc) -> None:
        self._done = True
        if self._typing_task:
            self._typing_task.cancel()
            try:
                await self._typing_task
            except asyncio.CancelledError:
                pass

        # Final edit to remove cursor and show complete message
        if self._message and self._buffer:
            await self._channel.edit_message(
                self._channel_id, self._message.message_id, self._buffer,
            )

    async def push(self, token: str) -> None:
        """Push a token to the stream."""
        self._buffer += token

        # Send initial message once we have enough content
        if self._message is None:
            if len(self._buffer) >= self._config.min_chunk_chars:
                display = self._buffer
                if self._config.show_cursor:
                    display += self._config.cursor_char
                self._message = await self._channel.send_message(
                    self._channel_id, display,
                )
                self._last_edit = time.monotonic()
                return
            return

        # Rate-limit edits
        now = time.monotonic()
        elapsed_ms = (now - self._last_edit) * 1000
        if elapsed_ms < self._config.edit_interval_ms:
            return

        # Edit the message with current buffer
        display = self._buffer
        if self._config.show_cursor:
            display += self._config.cursor_char

        # Truncate if too long for platform
        if len(display) > self._config.max_message_length:
            display = display[:self._config.max_message_length - 20] + "\n... (continuing)"

        await self._channel.edit_message(
            self._channel_id, self._message.message_id, display,
        )
        self._last_edit = now

    async def push_all(self, tokens: AsyncIterator[str]) -> str:
        """Push all tokens from an async iterator. Returns full text."""
        async for token in tokens:
            await self.push(token)
        return self._buffer

    async def _send_typing(self) -> None:
        try:
            await self._channel.send_typing(self._channel_id)
            self._last_typing = time.monotonic()
        except Exception:
            pass  # Typing indicators are best-effort

    async def _typing_loop(self) -> None:
        """Continuously send typing indicator while streaming."""
        while not self._done:
            await asyncio.sleep(self._config.typing_interval_ms / 1000)
            if not self._done:
                await self._send_typing()
