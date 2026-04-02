"""
Persistent User Memory — Trinity remembers each user across sessions.

Stores user preferences, conversation summaries, learned facts,
and interaction patterns. Backed by JSON files for persistence.
"""

from runtime.memory.user_memory import UserMemoryStore
from runtime.memory.memory_types import UserProfile, MemoryEntry, ConversationSummary

__all__ = [
    "UserMemoryStore",
    "UserProfile",
    "MemoryEntry",
    "ConversationSummary",
]
