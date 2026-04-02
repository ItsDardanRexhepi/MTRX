"""
User Memory Store — persistent cross-session memory for all agents.

Trinity's primary memory backend. Stores user profiles, memories,
and conversation summaries to JSON files. Thread-safe, auto-persists.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

from runtime.memory.memory_types import (
    MemoryCategory, MemoryEntry, ConversationSummary, UserProfile,
)

logger = logging.getLogger(__name__)

CONFIDENCE_DECAY_RATE: float = 0.01  # Per day
MIN_CONFIDENCE: float = 0.1


class UserMemoryStore:
    """
    Persistent user memory with JSON file backing.

    Each user gets a JSON file: {storage_dir}/{user_id}.json
    Memory is loaded lazily on first access and flushed on write.

    Thread-safe for concurrent agent access.
    """

    def __init__(self, storage_dir: str = "") -> None:
        if not storage_dir:
            storage_dir = os.path.join(
                os.path.dirname(__file__), "..", "..", "data", "memory",
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._profiles: Dict[str, UserProfile] = {}
        self._lock = threading.Lock()
        self._counter: int = 0
        logger.info("UserMemoryStore initialised | dir=%s", self._storage_dir)

    # ── Profile Management ────────────────────────────────────────────

    def get_or_create_profile(
        self,
        user_id: str,
        display_name: str = "",
        username: str = "",
    ) -> UserProfile:
        """Get existing profile or create a new one."""
        with self._lock:
            if user_id not in self._profiles:
                self._load_profile(user_id)
            if user_id not in self._profiles:
                profile = UserProfile(
                    user_id=user_id,
                    display_name=display_name,
                    username=username,
                )
                self._profiles[user_id] = profile
                self._persist(user_id)
                logger.info("New profile created | user=%s", user_id)
            else:
                profile = self._profiles[user_id]
                if display_name and not profile.display_name:
                    profile.display_name = display_name
                if username and not profile.username:
                    profile.username = username
            profile.last_seen = time.time()
            return profile

    def get_profile(self, user_id: str) -> Optional[UserProfile]:
        """Get profile if it exists."""
        with self._lock:
            if user_id not in self._profiles:
                self._load_profile(user_id)
            return self._profiles.get(user_id)

    def update_profile(self, user_id: str, **kwargs) -> UserProfile:
        """Update profile fields."""
        profile = self.get_or_create_profile(user_id)
        with self._lock:
            for key, value in kwargs.items():
                if hasattr(profile, key):
                    setattr(profile, key, value)
            self._persist(user_id)
        return profile

    # ── Memory CRUD ───────────────────────────────────────────────────

    def remember(
        self,
        user_id: str,
        category: MemoryCategory,
        key: str,
        value: str,
        source: str = "explicit",
        confidence: float = 1.0,
        tags: Optional[List[str]] = None,
    ) -> MemoryEntry:
        """
        Store a memory about a user. Updates existing if same key exists.

        Args:
            user_id: The user this memory is about.
            category: Type of memory.
            key: Short identifier (e.g. "timezone", "favorite_color").
            value: The remembered content.
            source: How it was learned.
            confidence: Initial confidence (0.0-1.0).
            tags: Optional categorization tags.

        Returns:
            The created or updated MemoryEntry.
        """
        profile = self.get_or_create_profile(user_id)
        with self._lock:
            # Check for existing memory with same key
            existing = next(
                (m for m in profile.memories if m.key == key and m.category == category),
                None,
            )
            if existing:
                existing.value = value
                existing.confidence = min(existing.confidence + 0.1, 1.0)
                existing.last_accessed = time.time()
                existing.access_count += 1
                existing.source = source
                if tags:
                    existing.tags = list(set(existing.tags + tags))
                self._persist(user_id)
                logger.debug("Memory updated | user=%s | key=%s", user_id, key)
                return existing

            self._counter += 1
            mid = f"MEM-{self._counter:08d}"
            entry = MemoryEntry(
                memory_id=mid,
                user_id=user_id,
                category=category,
                key=key,
                value=value,
                confidence=confidence,
                source=source,
                tags=tags or [],
            )
            profile.memories.append(entry)
            self._persist(user_id)
            logger.info(
                "Memory stored | user=%s | key=%s | cat=%s",
                user_id, key, category.value,
            )
            return entry

    def recall(
        self,
        user_id: str,
        key: Optional[str] = None,
        category: Optional[MemoryCategory] = None,
        min_confidence: float = 0.0,
        tags: Optional[List[str]] = None,
    ) -> List[MemoryEntry]:
        """
        Recall memories about a user with optional filters.

        Args:
            user_id: The user.
            key: Filter by key.
            category: Filter by category.
            min_confidence: Minimum confidence threshold.
            tags: Filter by tags (any match).

        Returns:
            Matching memories sorted by confidence (highest first).
        """
        profile = self.get_profile(user_id)
        if profile is None:
            return []

        with self._lock:
            results = list(profile.memories)
            if key:
                results = [m for m in results if m.key == key]
            if category:
                results = [m for m in results if m.category == category]
            if min_confidence > 0:
                results = [m for m in results if m.confidence >= min_confidence]
            if tags:
                tag_set = set(tags)
                results = [m for m in results if tag_set & set(m.tags)]

            # Update access metadata
            for m in results:
                m.last_accessed = time.time()
                m.access_count += 1

            results.sort(key=lambda m: m.confidence, reverse=True)
            return results

    def forget(self, user_id: str, key: str, category: Optional[MemoryCategory] = None) -> bool:
        """Remove a specific memory."""
        profile = self.get_profile(user_id)
        if profile is None:
            return False
        with self._lock:
            before = len(profile.memories)
            profile.memories = [
                m for m in profile.memories
                if not (m.key == key and (category is None or m.category == category))
            ]
            removed = len(profile.memories) < before
            if removed:
                self._persist(user_id)
                logger.info("Memory forgotten | user=%s | key=%s", user_id, key)
            return removed

    def get_context_summary(self, user_id: str, max_items: int = 20) -> str:
        """
        Build a concise context string for injecting into agent system prompts.
        Prioritizes high-confidence, recently-accessed memories.

        Returns:
            A formatted string summarizing what is known about the user.
        """
        profile = self.get_profile(user_id)
        if profile is None:
            return ""

        memories = sorted(
            profile.memories,
            key=lambda m: (m.confidence * 0.7 + (1.0 / max(1, time.time() - m.last_accessed + 1)) * 0.3),
            reverse=True,
        )[:max_items]

        if not memories:
            name = profile.display_name or profile.username or user_id
            return f"User: {name}. No prior memories recorded."

        lines = []
        name = profile.display_name or profile.username or user_id
        lines.append(f"User: {name}")
        if profile.timezone:
            lines.append(f"Timezone: {profile.timezone}")
        if profile.total_sessions > 0:
            lines.append(f"Sessions: {profile.total_sessions}")

        by_cat: Dict[str, List[str]] = {}
        for m in memories:
            cat = m.category.value
            by_cat.setdefault(cat, []).append(f"{m.key}: {m.value}")

        for cat, items in by_cat.items():
            lines.append(f"[{cat}] " + "; ".join(items[:5]))

        # Last conversation summary
        if profile.conversation_history:
            last = profile.conversation_history[-1]
            if last.summary:
                lines.append(f"Last conversation: {last.summary[:150]}")

        return "\n".join(lines)

    # ── Conversation History ──────────────────────────────────────────

    def start_session(
        self, user_id: str, session_id: str, agent_name: str,
    ) -> ConversationSummary:
        """Record the start of a new conversation session."""
        profile = self.get_or_create_profile(user_id)
        with self._lock:
            summary = ConversationSummary(
                session_id=session_id,
                user_id=user_id,
                agent_name=agent_name,
                started_at=time.time(),
            )
            profile.conversation_history.append(summary)
            profile.total_sessions += 1
            # Keep only last 50 sessions
            if len(profile.conversation_history) > 50:
                profile.conversation_history = profile.conversation_history[-50:]
            self._persist(user_id)
            return summary

    def end_session(
        self,
        user_id: str,
        session_id: str,
        summary: str = "",
        topics: Optional[List[str]] = None,
        sentiment: str = "neutral",
        key_decisions: Optional[List[str]] = None,
    ) -> Optional[ConversationSummary]:
        """Record the end of a conversation session with summary."""
        profile = self.get_profile(user_id)
        if profile is None:
            return None
        with self._lock:
            for cs in reversed(profile.conversation_history):
                if cs.session_id == session_id:
                    cs.ended_at = time.time()
                    cs.summary = summary
                    cs.topics = topics or []
                    cs.sentiment = sentiment
                    cs.key_decisions = key_decisions or []
                    self._persist(user_id)
                    return cs
        return None

    def record_message(self, user_id: str, session_id: str) -> None:
        """Increment message count for current session and profile."""
        profile = self.get_profile(user_id)
        if profile is None:
            return
        with self._lock:
            profile.total_messages += 1
            for cs in reversed(profile.conversation_history):
                if cs.session_id == session_id:
                    cs.message_count += 1
                    break
            self._persist(user_id)

    # ── Confidence Decay ──────────────────────────────────────────────

    def decay_confidence(self, user_id: str) -> int:
        """
        Apply time-based confidence decay to all memories.
        Called periodically. Returns number of memories pruned.
        """
        profile = self.get_profile(user_id)
        if profile is None:
            return 0
        with self._lock:
            pruned = 0
            now = time.time()
            surviving = []
            for m in profile.memories:
                days_since_access = (now - m.last_accessed) / 86_400
                m.confidence -= CONFIDENCE_DECAY_RATE * days_since_access
                if m.confidence < MIN_CONFIDENCE:
                    pruned += 1
                else:
                    surviving.append(m)
            profile.memories = surviving
            if pruned > 0:
                self._persist(user_id)
                logger.info(
                    "Confidence decay | user=%s | pruned=%d", user_id, pruned,
                )
            return pruned

    # ── Cross-Agent Search ────────────────────────────────────────────

    def cross_agent_search(
        self,
        query: str,
        requesting_agent: str = "",
        max_results: int = 10,
    ) -> List[dict]:
        """
        Search across all users' memories — used by agents to find
        relevant context from other agents' memory spaces.

        Neo, Trinity, and Morpheus can search across each other's
        memories while still maintaining distinct memory spaces.
        """
        query_lower = query.lower()
        results = []

        # Load all profiles
        for uid in self.list_users():
            profile = self.get_profile(uid)
            if profile is None:
                continue
            for mem in profile.memories:
                score = 0.0
                key_lower = mem.key.lower()
                val_lower = mem.value.lower()
                if query_lower in key_lower:
                    score += 2.0
                if query_lower in val_lower:
                    score += 1.0
                # Partial word matching
                for word in query_lower.split():
                    if word in key_lower or word in val_lower:
                        score += 0.5
                    if any(word in tag.lower() for tag in mem.tags):
                        score += 0.3

                if score > 0:
                    score *= mem.confidence
                    results.append({
                        "user_id": uid,
                        "key": mem.key,
                        "value": mem.value,
                        "category": mem.category.value if hasattr(mem.category, 'value') else str(mem.category),
                        "confidence": mem.confidence,
                        "score": round(score, 3),
                        "source_agent": mem.source,
                        "requesting_agent": requesting_agent,
                    })

        results.sort(key=lambda x: x["score"], reverse=True)
        return results[:max_results]

    # ── Queries ───────────────────────────────────────────────────────

    def list_users(self) -> List[str]:
        """List all user IDs with stored profiles."""
        user_ids = set(self._profiles.keys())
        for f in self._storage_dir.glob("*.json"):
            user_ids.add(f.stem)
        return sorted(user_ids)

    def get_stats(self) -> dict:
        """Get aggregate memory statistics."""
        total_users = len(self.list_users())
        total_memories = sum(
            len(p.memories) for p in self._profiles.values()
        )
        return {
            "total_users": total_users,
            "loaded_profiles": len(self._profiles),
            "total_memories": total_memories,
            "storage_dir": str(self._storage_dir),
        }

    # ── Persistence ───────────────────────────────────────────────────

    def _persist(self, user_id: str) -> None:
        """Write user profile to disk."""
        profile = self._profiles.get(user_id)
        if profile is None:
            return
        path = self._storage_dir / f"{user_id}.json"
        try:
            with open(path, "w") as f:
                json.dump(profile.to_dict(), f, indent=2)
        except Exception:
            logger.exception("Failed to persist profile | user=%s", user_id)

    def _load_profile(self, user_id: str) -> None:
        """Load user profile from disk if it exists."""
        path = self._storage_dir / f"{user_id}.json"
        if not path.exists():
            return
        try:
            with open(path) as f:
                data = json.load(f)
            self._profiles[user_id] = UserProfile.from_dict(data)
            # Restore counter
            for m in self._profiles[user_id].memories:
                num = int(m.memory_id.split("-")[1]) if "-" in m.memory_id else 0
                self._counter = max(self._counter, num)
        except Exception:
            logger.exception("Failed to load profile | user=%s", user_id)
