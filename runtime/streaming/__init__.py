"""
Streaming Responses — partial replies update in place instead of new messages.

Better than OpenClaw: typing indicators that show the message being
composed in real time. Works across all channels that support editing.
"""

from runtime.streaming.streamer import MessageStreamer, StreamConfig

__all__ = ["MessageStreamer", "StreamConfig"]
