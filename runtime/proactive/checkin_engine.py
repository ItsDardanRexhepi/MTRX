"""
Check-In Engine — proactive outreach based on user patterns.

Uses PatternTracker data to determine when and how to reach out
to users. Supports various check-in types and cooldowns.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

from runtime.proactive.pattern_tracker import PatternTracker

logger = logging.getLogger(__name__)


class CheckInType(str, Enum):
    ABSENCE = "absence"               # User hasn't been around
    GOAL_REMINDER = "goal_reminder"   # Pending goal needs attention
    STREAK = "streak"                 # Celebrate activity streak
    FOLLOW_UP = "follow_up"           # Follow up on previous conversation
    SCHEDULED = "scheduled"           # User-requested check-in
    INSIGHT = "insight"               # Proactive insight to share


class CheckInStatus(str, Enum):
    PENDING = "pending"
    SENT = "sent"
    ACKNOWLEDGED = "acknowledged"
    DISMISSED = "dismissed"
    EXPIRED = "expired"


@dataclass
class CheckIn:
    """A proactive check-in to send to a user."""
    checkin_id: str
    user_id: str
    checkin_type: CheckInType
    message: str
    context: dict = field(default_factory=dict)
    status: CheckInStatus = CheckInStatus.PENDING
    priority: int = 5                 # 1-10, higher = more important
    created_at: float = field(default_factory=time.time)
    sent_at: float = 0.0
    expires_at: float = 0.0

    def to_dict(self) -> dict:
        return {
            "checkin_id": self.checkin_id,
            "user_id": self.user_id,
            "checkin_type": self.checkin_type.value,
            "message": self.message,
            "context": self.context,
            "status": self.status.value,
            "priority": self.priority,
            "created_at": self.created_at,
            "sent_at": self.sent_at,
            "expires_at": self.expires_at,
        }

    @classmethod
    def from_dict(cls, data: dict) -> CheckIn:
        return cls(
            checkin_id=data["checkin_id"],
            user_id=data["user_id"],
            checkin_type=CheckInType(data["checkin_type"]),
            message=data["message"],
            context=data.get("context", {}),
            status=CheckInStatus(data.get("status", "pending")),
            priority=data.get("priority", 5),
            created_at=data.get("created_at", time.time()),
            sent_at=data.get("sent_at", 0.0),
            expires_at=data.get("expires_at", 0.0),
        )


class CheckInEngine:
    """
    Manages proactive check-ins with users.

    Works with PatternTracker to detect absence, and provides
    scheduling for follow-ups and reminders. A send function
    is injected for actual message delivery (e.g., Telegram).
    """

    DEFAULT_ABSENCE_THRESHOLD: float = 2.0    # 2x normal gap
    DEFAULT_CHECKIN_COOLDOWN: int = 14400      # 4 hours between check-ins
    MAX_PENDING_PER_USER: int = 5

    def __init__(
        self,
        pattern_tracker: Optional[PatternTracker] = None,
        send_fn: Optional[Callable[[str, str], None]] = None,
        storage_dir: str = "",
    ) -> None:
        """
        Args:
            pattern_tracker: Tracker for user activity patterns.
            send_fn: Callable(user_id, message) to deliver check-ins.
            storage_dir: Directory for check-in persistence.
        """
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "checkins"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._tracker = pattern_tracker or PatternTracker()
        self._send_fn = send_fn
        self._checkins: Dict[str, CheckIn] = {}
        self._by_user: Dict[str, List[str]] = {}
        self._last_checkin_time: Dict[str, float] = {}
        self._counter: int = 0
        self._user_preferences: Dict[str, dict] = {}
        self._load_all()
        logger.info("CheckInEngine initialised | pending=%d",
                     sum(1 for c in self._checkins.values() if c.status == CheckInStatus.PENDING))

    # ── Check-In Creation ────────────────────────────────────────────

    def create_checkin(
        self,
        user_id: str,
        checkin_type: CheckInType,
        message: str,
        context: Optional[dict] = None,
        priority: int = 5,
        expires_in: int = 0,
    ) -> CheckIn:
        """Create a pending check-in for a user."""
        # Respect per-user limits
        pending = self._get_pending(user_id)
        if len(pending) >= self.MAX_PENDING_PER_USER:
            # Remove lowest priority pending
            lowest = min(pending, key=lambda c: c.priority)
            lowest.status = CheckInStatus.EXPIRED
            self._persist_checkin(lowest.checkin_id)

        self._counter += 1
        cid = f"CHK-{self._counter:08d}"

        checkin = CheckIn(
            checkin_id=cid,
            user_id=user_id,
            checkin_type=checkin_type,
            message=message,
            context=context or {},
            priority=priority,
            expires_at=time.time() + expires_in if expires_in > 0 else 0.0,
        )
        self._checkins[cid] = checkin
        self._by_user.setdefault(user_id, []).append(cid)
        self._persist_checkin(cid)

        logger.info("Check-in created | id=%s | user=%s | type=%s",
                     cid, user_id, checkin_type.value)
        return checkin

    def schedule_followup(
        self,
        user_id: str,
        message: str,
        delay_seconds: int = 3600,
        context: Optional[dict] = None,
    ) -> CheckIn:
        """Schedule a follow-up check-in after a delay."""
        return self.create_checkin(
            user_id=user_id,
            checkin_type=CheckInType.FOLLOW_UP,
            message=message,
            context={**(context or {}), "send_after": time.time() + delay_seconds},
            priority=6,
            expires_in=delay_seconds + 86400,  # Expire 1 day after send time
        )

    # ── Processing ───────────────────────────────────────────────────

    def scan_for_checkins(self) -> List[CheckIn]:
        """
        Scan all users and generate check-ins for detected patterns.
        Called periodically by the scheduler.

        Returns:
            List of newly created check-ins.
        """
        new_checkins = []
        now = time.time()

        # Check for absent users
        absent_users = self._tracker.get_absent_users()
        for user_id, hours_over in absent_users:
            if not self._should_checkin(user_id, CheckInType.ABSENCE):
                continue
            pattern = self._tracker.get_pattern(user_id)
            if pattern is None:
                continue

            hours_gone = pattern.hours_since_last_activity()
            msg = self._generate_absence_message(user_id, hours_gone, pattern)
            checkin = self.create_checkin(
                user_id=user_id,
                checkin_type=CheckInType.ABSENCE,
                message=msg,
                context={"hours_absent": round(hours_gone, 1)},
                priority=4,
                expires_in=86400,
            )
            new_checkins.append(checkin)

        # Check for streak milestones
        for user_id, pattern in self._tracker._patterns.items():
            if pattern.streak_days in (7, 14, 30, 60, 100, 365):
                if not self._should_checkin(user_id, CheckInType.STREAK):
                    continue
                msg = f"Amazing — you've been active for {pattern.streak_days} days in a row! Keep it up."
                checkin = self.create_checkin(
                    user_id=user_id,
                    checkin_type=CheckInType.STREAK,
                    message=msg,
                    context={"streak_days": pattern.streak_days},
                    priority=3,
                    expires_in=86400,
                )
                new_checkins.append(checkin)

        return new_checkins

    def process_pending(self) -> List[CheckIn]:
        """
        Process and send pending check-ins.
        Returns list of check-ins that were sent.
        """
        now = time.time()
        sent = []

        for checkin in list(self._checkins.values()):
            if checkin.status != CheckInStatus.PENDING:
                continue

            # Check expiration
            if checkin.expires_at > 0 and now > checkin.expires_at:
                checkin.status = CheckInStatus.EXPIRED
                self._persist_checkin(checkin.checkin_id)
                continue

            # Check if scheduled for later
            send_after = checkin.context.get("send_after", 0)
            if send_after > now:
                continue

            # Check cooldown
            last = self._last_checkin_time.get(checkin.user_id, 0)
            if now - last < self.DEFAULT_CHECKIN_COOLDOWN:
                continue

            # Send it
            if self._send_fn:
                try:
                    self._send_fn(checkin.user_id, checkin.message)
                    checkin.status = CheckInStatus.SENT
                    checkin.sent_at = now
                    self._last_checkin_time[checkin.user_id] = now
                    sent.append(checkin)
                    logger.info("Check-in sent | id=%s | user=%s", checkin.checkin_id, checkin.user_id)
                except Exception:
                    logger.exception("Failed to send check-in | id=%s", checkin.checkin_id)
            else:
                # No send function — just mark as sent for processing
                checkin.status = CheckInStatus.SENT
                checkin.sent_at = now
                self._last_checkin_time[checkin.user_id] = now
                sent.append(checkin)

            self._persist_checkin(checkin.checkin_id)

        return sent

    def acknowledge(self, checkin_id: str) -> Optional[CheckIn]:
        """Mark a check-in as acknowledged by the user."""
        checkin = self._checkins.get(checkin_id)
        if checkin and checkin.status == CheckInStatus.SENT:
            checkin.status = CheckInStatus.ACKNOWLEDGED
            self._persist_checkin(checkin_id)
        return checkin

    def dismiss(self, checkin_id: str) -> Optional[CheckIn]:
        """Dismiss a check-in."""
        checkin = self._checkins.get(checkin_id)
        if checkin:
            checkin.status = CheckInStatus.DISMISSED
            self._persist_checkin(checkin_id)
        return checkin

    # ── User Preferences ─────────────────────────────────────────────

    def set_preferences(
        self,
        user_id: str,
        enabled: bool = True,
        min_interval_hours: int = 4,
        allowed_types: Optional[List[CheckInType]] = None,
        quiet_hours: Optional[Tuple[int, int]] = None,
    ) -> dict:
        """Set user check-in preferences."""
        prefs = {
            "enabled": enabled,
            "min_interval_hours": min_interval_hours,
            "allowed_types": [t.value for t in (allowed_types or list(CheckInType))],
            "quiet_start": quiet_hours[0] if quiet_hours else 22,
            "quiet_end": quiet_hours[1] if quiet_hours else 7,
        }
        self._user_preferences[user_id] = prefs
        self._persist_preferences()
        return prefs

    def get_preferences(self, user_id: str) -> dict:
        return self._user_preferences.get(user_id, {
            "enabled": True,
            "min_interval_hours": 4,
            "allowed_types": [t.value for t in CheckInType],
            "quiet_start": 22,
            "quiet_end": 7,
        })

    # ── Queries ───────────────────────────────────────────────────────

    def get_checkin(self, checkin_id: str) -> Optional[CheckIn]:
        return self._checkins.get(checkin_id)

    def get_user_checkins(
        self, user_id: str, status: Optional[CheckInStatus] = None, limit: int = 20,
    ) -> List[CheckIn]:
        ids = self._by_user.get(user_id, [])
        checkins = [self._checkins[cid] for cid in ids if cid in self._checkins]
        if status:
            checkins = [c for c in checkins if c.status == status]
        return checkins[-limit:]

    def get_stats(self) -> dict:
        by_status = {}
        by_type = {}
        for c in self._checkins.values():
            by_status[c.status.value] = by_status.get(c.status.value, 0) + 1
            by_type[c.checkin_type.value] = by_type.get(c.checkin_type.value, 0) + 1
        return {
            "total_checkins": len(self._checkins),
            "by_status": by_status,
            "by_type": by_type,
            "tracked_users": len(self._by_user),
        }

    # ── Internal ─────────────────────────────────────────────────────

    def _should_checkin(self, user_id: str, checkin_type: CheckInType) -> bool:
        """Check preferences and cooldown before creating a check-in."""
        prefs = self.get_preferences(user_id)
        if not prefs.get("enabled", True):
            return False
        allowed = prefs.get("allowed_types", [])
        if allowed and checkin_type.value not in allowed:
            return False

        # Quiet hours
        current_hour = time.localtime().tm_hour
        quiet_start = prefs.get("quiet_start", 22)
        quiet_end = prefs.get("quiet_end", 7)
        if quiet_start > quiet_end:
            if current_hour >= quiet_start or current_hour < quiet_end:
                return False
        elif quiet_start <= current_hour < quiet_end:
            return False

        # Already have pending of same type?
        pending = self._get_pending(user_id)
        if any(c.checkin_type == checkin_type for c in pending):
            return False

        return True

    def _get_pending(self, user_id: str) -> List[CheckIn]:
        ids = self._by_user.get(user_id, [])
        return [
            self._checkins[cid] for cid in ids
            if cid in self._checkins and self._checkins[cid].status == CheckInStatus.PENDING
        ]

    def _generate_absence_message(self, user_id: str, hours: float, pattern) -> str:
        """Generate a contextual absence check-in message."""
        if hours < 48:
            return f"Hey! Haven't heard from you in about {int(hours)} hours. Everything going well?"
        days = int(hours / 24)
        topics = pattern.common_topics[:3]
        if topics:
            topic_str = ", ".join(topics)
            return (
                f"It's been {days} days since we last chatted. "
                f"Last time we were talking about {topic_str}. Want to pick up where we left off?"
            )
        return f"It's been {days} days — just checking in. Let me know if you need anything!"

    def _persist_checkin(self, checkin_id: str) -> None:
        checkin = self._checkins.get(checkin_id)
        if checkin is None:
            return
        path = self._storage_dir / f"{checkin_id}.json"
        try:
            with open(path, "w") as f:
                json.dump(checkin.to_dict(), f, indent=2)
        except Exception:
            logger.exception("Failed to persist check-in | id=%s", checkin_id)

    def _persist_preferences(self) -> None:
        path = self._storage_dir / "preferences.json"
        try:
            with open(path, "w") as f:
                json.dump(self._user_preferences, f, indent=2)
        except Exception:
            logger.exception("Failed to persist preferences.")

    def _load_all(self) -> None:
        # Load preferences
        prefs_path = self._storage_dir / "preferences.json"
        if prefs_path.exists():
            try:
                with open(prefs_path) as f:
                    self._user_preferences = json.load(f)
            except Exception:
                logger.exception("Failed to load preferences.")

        # Load check-ins
        for path in self._storage_dir.glob("CHK-*.json"):
            try:
                with open(path) as f:
                    data = json.load(f)
                checkin = CheckIn.from_dict(data)
                self._checkins[checkin.checkin_id] = checkin
                self._by_user.setdefault(checkin.user_id, []).append(checkin.checkin_id)
                num = int(checkin.checkin_id.split("-")[1])
                self._counter = max(self._counter, num)
            except Exception:
                logger.exception("Failed to load check-in | file=%s", path)
