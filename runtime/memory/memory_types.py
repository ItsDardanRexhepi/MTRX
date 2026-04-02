"""
Memory data types — structured representations of user memory.

Part of the Persistent User Memory system.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class MemoryCategory(Enum):
    """Categories of remembered information."""
    PREFERENCE = "preference"       # User likes/dislikes, settings
    FACT = "fact"                    # Factual info about the user
    CONTEXT = "context"             # Situational context (project, role)
    BEHAVIOR = "behavior"           # Observed interaction patterns
    RELATIONSHIP = "relationship"   # How user relates to other users/entities
    GOAL = "goal"                   # User's stated objectives
    FEEDBACK = "feedback"           # User corrections and guidance


@dataclass
class MemoryEntry:
    """A single piece of remembered information."""
    memory_id: str
    user_id: str
    category: MemoryCategory
    key: str                        # Short identifier (e.g. "timezone", "name")
    value: str                      # The remembered content
    confidence: float = 1.0         # 0.0-1.0, decays over time if not reinforced
    source: str = ""                # How it was learned (explicit, inferred, observed)
    created_at: float = field(default_factory=time.time)
    last_accessed: float = field(default_factory=time.time)
    access_count: int = 0
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "memory_id": self.memory_id,
            "user_id": self.user_id,
            "category": self.category.value,
            "key": self.key,
            "value": self.value,
            "confidence": self.confidence,
            "source": self.source,
            "created_at": self.created_at,
            "last_accessed": self.last_accessed,
            "access_count": self.access_count,
            "tags": self.tags,
        }

    @classmethod
    def from_dict(cls, d: dict) -> MemoryEntry:
        return cls(
            memory_id=d["memory_id"],
            user_id=d["user_id"],
            category=MemoryCategory(d["category"]),
            key=d["key"],
            value=d["value"],
            confidence=d.get("confidence", 1.0),
            source=d.get("source", ""),
            created_at=d.get("created_at", time.time()),
            last_accessed=d.get("last_accessed", time.time()),
            access_count=d.get("access_count", 0),
            tags=d.get("tags", []),
        )


@dataclass
class ConversationSummary:
    """Summary of a conversation session."""
    session_id: str
    user_id: str
    agent_name: str
    started_at: float
    ended_at: float = 0.0
    message_count: int = 0
    summary: str = ""
    topics: List[str] = field(default_factory=list)
    sentiment: str = "neutral"      # positive, neutral, negative
    key_decisions: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "user_id": self.user_id,
            "agent_name": self.agent_name,
            "started_at": self.started_at,
            "ended_at": self.ended_at,
            "message_count": self.message_count,
            "summary": self.summary,
            "topics": self.topics,
            "sentiment": self.sentiment,
            "key_decisions": self.key_decisions,
        }

    @classmethod
    def from_dict(cls, d: dict) -> ConversationSummary:
        return cls(
            session_id=d["session_id"],
            user_id=d["user_id"],
            agent_name=d["agent_name"],
            started_at=d["started_at"],
            ended_at=d.get("ended_at", 0.0),
            message_count=d.get("message_count", 0),
            summary=d.get("summary", ""),
            topics=d.get("topics", []),
            sentiment=d.get("sentiment", "neutral"),
            key_decisions=d.get("key_decisions", []),
        )


@dataclass
class UserProfile:
    """Complete user profile aggregated from memory entries."""
    user_id: str
    display_name: str = ""
    username: str = ""
    first_seen: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)
    total_messages: int = 0
    total_sessions: int = 0
    preferred_agent: str = ""
    timezone: str = ""
    language: str = "en"
    memories: List[MemoryEntry] = field(default_factory=list)
    conversation_history: List[ConversationSummary] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "user_id": self.user_id,
            "display_name": self.display_name,
            "username": self.username,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
            "total_messages": self.total_messages,
            "total_sessions": self.total_sessions,
            "preferred_agent": self.preferred_agent,
            "timezone": self.timezone,
            "language": self.language,
            "memories": [m.to_dict() for m in self.memories],
            "conversation_history": [c.to_dict() for c in self.conversation_history],
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, d: dict) -> UserProfile:
        profile = cls(
            user_id=d["user_id"],
            display_name=d.get("display_name", ""),
            username=d.get("username", ""),
            first_seen=d.get("first_seen", time.time()),
            last_seen=d.get("last_seen", time.time()),
            total_messages=d.get("total_messages", 0),
            total_sessions=d.get("total_sessions", 0),
            preferred_agent=d.get("preferred_agent", ""),
            timezone=d.get("timezone", ""),
            language=d.get("language", "en"),
            metadata=d.get("metadata", {}),
        )
        profile.memories = [MemoryEntry.from_dict(m) for m in d.get("memories", [])]
        profile.conversation_history = [ConversationSummary.from_dict(c) for c in d.get("conversation_history", [])]
        return profile
