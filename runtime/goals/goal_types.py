"""Goal data types."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class GoalStatus(Enum):
    PENDING = "pending"
    ACTIVE = "active"
    PAUSED = "paused"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class StepStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class GoalPriority(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class GoalStep:
    """A discrete step within a goal."""
    step_id: str
    description: str
    status: StepStatus = StepStatus.PENDING
    result: str = ""
    error: str = ""
    started_at: float = 0.0
    completed_at: float = 0.0
    retry_count: int = 0
    max_retries: int = 3
    depends_on: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "step_id": self.step_id, "description": self.description,
            "status": self.status.value, "result": self.result,
            "error": self.error, "started_at": self.started_at,
            "completed_at": self.completed_at, "retry_count": self.retry_count,
            "max_retries": self.max_retries, "depends_on": self.depends_on,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, d: dict) -> GoalStep:
        return cls(
            step_id=d["step_id"], description=d["description"],
            status=StepStatus(d.get("status", "pending")),
            result=d.get("result", ""), error=d.get("error", ""),
            started_at=d.get("started_at", 0.0),
            completed_at=d.get("completed_at", 0.0),
            retry_count=d.get("retry_count", 0),
            max_retries=d.get("max_retries", 3),
            depends_on=d.get("depends_on", []),
            metadata=d.get("metadata", {}),
        )


@dataclass
class Goal:
    """A long-running autonomous goal."""
    goal_id: str
    user_id: str
    agent_name: str
    title: str
    description: str
    status: GoalStatus = GoalStatus.PENDING
    priority: GoalPriority = GoalPriority.MEDIUM
    steps: List[GoalStep] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    started_at: float = 0.0
    completed_at: float = 0.0
    deadline: float = 0.0
    progress_pct: float = 0.0
    last_update: str = ""
    last_checked_at: float = 0.0
    check_interval_seconds: int = 3600  # Default 1 hour
    notify_on_completion: bool = True
    notify_on_failure: bool = True
    notify_on_progress: bool = False
    tags: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "goal_id": self.goal_id, "user_id": self.user_id,
            "agent_name": self.agent_name, "title": self.title,
            "description": self.description, "status": self.status.value,
            "priority": self.priority.value,
            "steps": [s.to_dict() for s in self.steps],
            "created_at": self.created_at, "started_at": self.started_at,
            "completed_at": self.completed_at, "deadline": self.deadline,
            "progress_pct": self.progress_pct, "last_update": self.last_update,
            "last_checked_at": self.last_checked_at,
            "check_interval_seconds": self.check_interval_seconds,
            "notify_on_completion": self.notify_on_completion,
            "notify_on_failure": self.notify_on_failure,
            "notify_on_progress": self.notify_on_progress,
            "tags": self.tags, "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, d: dict) -> Goal:
        g = cls(
            goal_id=d["goal_id"], user_id=d["user_id"],
            agent_name=d.get("agent_name", "neo"), title=d["title"],
            description=d.get("description", ""),
            status=GoalStatus(d.get("status", "pending")),
            priority=GoalPriority(d.get("priority", "medium")),
            created_at=d.get("created_at", time.time()),
            started_at=d.get("started_at", 0.0),
            completed_at=d.get("completed_at", 0.0),
            deadline=d.get("deadline", 0.0),
            progress_pct=d.get("progress_pct", 0.0),
            last_update=d.get("last_update", ""),
            last_checked_at=d.get("last_checked_at", 0.0),
            check_interval_seconds=d.get("check_interval_seconds", 3600),
            notify_on_completion=d.get("notify_on_completion", True),
            notify_on_failure=d.get("notify_on_failure", True),
            notify_on_progress=d.get("notify_on_progress", False),
            tags=d.get("tags", []), metadata=d.get("metadata", {}),
        )
        g.steps = [GoalStep.from_dict(s) for s in d.get("steps", [])]
        return g
