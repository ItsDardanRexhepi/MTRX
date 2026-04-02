"""
Pattern Tracker — learns user activity patterns for proactive outreach.

Tracks when users are active, what they talk about, and detects
deviations from their normal behavior to trigger check-ins.
"""

from __future__ import annotations

import json
import logging
import math
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class ActivityRecord:
    """A single user activity event."""
    timestamp: float
    hour: int
    day_of_week: int       # 0=Monday, 6=Sunday
    activity_type: str     # message, command, upload, etc.
    topics: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "timestamp": self.timestamp,
            "hour": self.hour,
            "day_of_week": self.day_of_week,
            "activity_type": self.activity_type,
            "topics": self.topics,
        }


@dataclass
class UserPattern:
    """Learned activity pattern for a user."""
    user_id: str
    active_hours: Dict[int, float] = field(default_factory=dict)  # hour -> frequency
    active_days: Dict[int, float] = field(default_factory=dict)   # day -> frequency
    avg_session_gap_hours: float = 24.0
    avg_messages_per_session: float = 5.0
    common_topics: List[str] = field(default_factory=list)
    last_activity: float = 0.0
    total_activities: int = 0
    streak_days: int = 0
    longest_streak: int = 0

    def to_dict(self) -> dict:
        return {
            "user_id": self.user_id,
            "active_hours": self.active_hours,
            "active_days": self.active_days,
            "avg_session_gap_hours": round(self.avg_session_gap_hours, 1),
            "avg_messages_per_session": round(self.avg_messages_per_session, 1),
            "common_topics": self.common_topics[:20],
            "last_activity": self.last_activity,
            "total_activities": self.total_activities,
            "streak_days": self.streak_days,
            "longest_streak": self.longest_streak,
        }

    @classmethod
    def from_dict(cls, data: dict) -> UserPattern:
        return cls(
            user_id=data["user_id"],
            active_hours={int(k): v for k, v in data.get("active_hours", {}).items()},
            active_days={int(k): v for k, v in data.get("active_days", {}).items()},
            avg_session_gap_hours=data.get("avg_session_gap_hours", 24.0),
            avg_messages_per_session=data.get("avg_messages_per_session", 5.0),
            common_topics=data.get("common_topics", []),
            last_activity=data.get("last_activity", 0.0),
            total_activities=data.get("total_activities", 0),
            streak_days=data.get("streak_days", 0),
            longest_streak=data.get("longest_streak", 0),
        )

    def is_typical_hour(self, hour: int) -> bool:
        """Check if user is typically active at this hour."""
        if not self.active_hours:
            return True
        threshold = max(self.active_hours.values()) * 0.3
        return self.active_hours.get(hour, 0) >= threshold

    def hours_since_last_activity(self) -> float:
        if self.last_activity <= 0:
            return 0.0
        return (time.time() - self.last_activity) / 3600


class PatternTracker:
    """
    Tracks and learns user activity patterns.

    Maintains per-user activity history, computes patterns,
    and detects anomalies (unusually long absence, etc.).
    """

    SESSION_GAP_SECONDS: int = 1800  # 30 min gap = new session

    def __init__(self, storage_dir: str = "") -> None:
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "patterns"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._patterns: Dict[str, UserPattern] = {}
        self._activities: Dict[str, List[ActivityRecord]] = defaultdict(list)
        self._session_starts: Dict[str, float] = {}
        self._session_counts: Dict[str, List[int]] = defaultdict(list)  # msgs per session
        self._current_session_msgs: Dict[str, int] = defaultdict(int)
        self._load_all()
        logger.info("PatternTracker initialised | users=%d", len(self._patterns))

    def record_activity(
        self,
        user_id: str,
        activity_type: str = "message",
        topics: Optional[List[str]] = None,
    ) -> UserPattern:
        """Record a user activity and update patterns."""
        now = time.time()
        lt = time.localtime(now)
        record = ActivityRecord(
            timestamp=now,
            hour=lt.tm_hour,
            day_of_week=lt.tm_wday,
            activity_type=activity_type,
            topics=topics or [],
        )

        activities = self._activities[user_id]
        activities.append(record)
        # Keep last 2000 activities
        if len(activities) > 2000:
            self._activities[user_id] = activities[-1000:]

        # Session tracking
        last = self._session_starts.get(user_id, 0)
        if now - last > self.SESSION_GAP_SECONDS:
            # End previous session
            if last > 0:
                self._session_counts[user_id].append(
                    self._current_session_msgs[user_id]
                )
            self._session_starts[user_id] = now
            self._current_session_msgs[user_id] = 0
        self._current_session_msgs[user_id] += 1

        # Update pattern
        pattern = self._get_or_create_pattern(user_id)
        pattern.total_activities += 1
        pattern.last_activity = now

        # Update hour frequencies
        pattern.active_hours[lt.tm_hour] = pattern.active_hours.get(lt.tm_hour, 0) + 1
        pattern.active_days[lt.tm_wday] = pattern.active_days.get(lt.tm_wday, 0) + 1

        # Update topics
        if topics:
            topic_counter = Counter(pattern.common_topics)
            topic_counter.update(topics)
            pattern.common_topics = [t for t, _ in topic_counter.most_common(20)]

        # Compute session gap average
        session_gaps = self._compute_session_gaps(user_id)
        if session_gaps:
            pattern.avg_session_gap_hours = sum(session_gaps) / len(session_gaps) / 3600

        # Compute avg messages per session
        counts = self._session_counts[user_id]
        if counts:
            pattern.avg_messages_per_session = sum(counts) / len(counts)

        # Streak tracking
        self._update_streak(pattern, now)

        self._persist(user_id)
        return pattern

    def get_pattern(self, user_id: str) -> Optional[UserPattern]:
        return self._patterns.get(user_id)

    def detect_absence(self, user_id: str) -> Tuple[bool, float]:
        """
        Detect if a user has been absent longer than their typical pattern.

        Returns:
            (is_absent, hours_overdue)
        """
        pattern = self._patterns.get(user_id)
        if pattern is None or pattern.total_activities < 5:
            return False, 0.0

        hours_since = pattern.hours_since_last_activity()
        expected_gap = pattern.avg_session_gap_hours

        # User is absent if they've been gone > 2x their average gap
        if hours_since > expected_gap * 2:
            return True, hours_since - expected_gap
        return False, 0.0

    def get_absent_users(self, min_activities: int = 5) -> List[Tuple[str, float]]:
        """Get all users who are absent longer than expected."""
        absent = []
        for uid, pattern in self._patterns.items():
            if pattern.total_activities < min_activities:
                continue
            is_absent, hours_over = self.detect_absence(uid)
            if is_absent:
                absent.append((uid, hours_over))
        absent.sort(key=lambda x: x[1], reverse=True)
        return absent

    def get_best_checkin_hour(self, user_id: str) -> int:
        """Get the hour when the user is most likely to be active."""
        pattern = self._patterns.get(user_id)
        if not pattern or not pattern.active_hours:
            return 9  # Default to 9 AM
        return max(pattern.active_hours, key=pattern.active_hours.get)

    def get_stats(self) -> dict:
        return {
            "tracked_users": len(self._patterns),
            "total_activities": sum(p.total_activities for p in self._patterns.values()),
        }

    # ── Internal ─────────────────────────────────────────────────────

    def _get_or_create_pattern(self, user_id: str) -> UserPattern:
        if user_id not in self._patterns:
            self._patterns[user_id] = UserPattern(user_id=user_id)
        return self._patterns[user_id]

    def _compute_session_gaps(self, user_id: str) -> List[float]:
        """Compute gaps between sessions."""
        activities = self._activities.get(user_id, [])
        if len(activities) < 2:
            return []
        gaps = []
        prev = activities[0].timestamp
        for act in activities[1:]:
            gap = act.timestamp - prev
            if gap > self.SESSION_GAP_SECONDS:
                gaps.append(gap)
            prev = act.timestamp
        return gaps[-50:]  # Last 50 session gaps

    def _update_streak(self, pattern: UserPattern, now: float) -> None:
        """Update consecutive day streak."""
        if pattern.last_activity <= 0:
            pattern.streak_days = 1
            return
        gap_hours = (now - pattern.last_activity) / 3600
        if gap_hours < 36:  # Allow up to 36 hours gap to maintain streak
            lt_now = time.localtime(now)
            lt_last = time.localtime(pattern.last_activity)
            if lt_now.tm_yday != lt_last.tm_yday or lt_now.tm_year != lt_last.tm_year:
                pattern.streak_days += 1
        else:
            pattern.streak_days = 1
        pattern.longest_streak = max(pattern.longest_streak, pattern.streak_days)

    def _persist(self, user_id: str) -> None:
        pattern = self._patterns.get(user_id)
        if pattern is None:
            return
        path = self._storage_dir / f"{user_id}.json"
        try:
            with open(path, "w") as f:
                json.dump(pattern.to_dict(), f, indent=2)
        except Exception:
            logger.exception("Failed to persist pattern | user=%s", user_id)

    def _load_all(self) -> None:
        for path in self._storage_dir.glob("*.json"):
            try:
                with open(path) as f:
                    data = json.load(f)
                pattern = UserPattern.from_dict(data)
                self._patterns[pattern.user_id] = pattern
            except Exception:
                logger.exception("Failed to load pattern | file=%s", path)
