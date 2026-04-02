"""
Task data types for the control plane.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional


class TaskStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    BLOCKED = "blocked"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    LOST = "lost"           # Detected as orphaned


class TaskType(str, Enum):
    AGENT = "agent"          # Agent-driven task (Neo, Trinity, Morpheus)
    CRON = "cron"            # Scheduled recurring task
    BACKGROUND = "background"  # Background execution
    SUBAGENT = "subagent"    # Child task spawned by another
    APPROVAL = "approval"    # Waiting for human approval
    FLOW = "flow"            # Multi-step flow


@dataclass
class Task:
    """A tracked background task."""
    task_id: str
    task_type: TaskType
    agent: str                     # neo, trinity, morpheus, system
    title: str                     # Human-readable title
    description: str               # Plain-language description
    status: TaskStatus = TaskStatus.QUEUED
    user_id: str = ""
    parent_id: str = ""            # For subtasks
    flow_id: str = ""              # For flow membership
    progress_pct: float = 0.0
    plain_status: str = ""         # Plain-language status for users
    result: str = ""
    error: str = ""
    created_at: float = field(default_factory=time.time)
    started_at: float = 0.0
    completed_at: float = 0.0
    updated_at: float = field(default_factory=time.time)
    timeout_seconds: int = 3600    # 1 hour default
    retry_count: int = 0
    max_retries: int = 2
    metadata: dict = field(default_factory=dict)
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "task_id": self.task_id,
            "task_type": self.task_type.value,
            "agent": self.agent,
            "title": self.title,
            "description": self.description,
            "status": self.status.value,
            "user_id": self.user_id,
            "parent_id": self.parent_id,
            "flow_id": self.flow_id,
            "progress_pct": round(self.progress_pct, 1),
            "plain_status": self.plain_status,
            "result": self.result,
            "error": self.error,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "updated_at": self.updated_at,
            "timeout_seconds": self.timeout_seconds,
            "retry_count": self.retry_count,
            "max_retries": self.max_retries,
            "metadata": self.metadata,
            "tags": self.tags,
        }

    @property
    def duration_seconds(self) -> float:
        if self.started_at <= 0:
            return 0.0
        end = self.completed_at if self.completed_at > 0 else time.time()
        return end - self.started_at

    @property
    def is_terminal(self) -> bool:
        return self.status in (
            TaskStatus.COMPLETED, TaskStatus.FAILED,
            TaskStatus.CANCELLED, TaskStatus.LOST,
        )


@dataclass
class TaskFlow:
    """A multi-step task flow (like OpenClaw's linear task flows)."""
    flow_id: str
    name: str
    description: str
    agent: str
    user_id: str = ""
    task_ids: List[str] = field(default_factory=list)
    status: TaskStatus = TaskStatus.QUEUED
    current_step: int = 0
    plain_status: str = ""
    created_at: float = field(default_factory=time.time)
    completed_at: float = 0.0

    def to_dict(self) -> dict:
        return {
            "flow_id": self.flow_id,
            "name": self.name,
            "description": self.description,
            "agent": self.agent,
            "user_id": self.user_id,
            "task_ids": self.task_ids,
            "status": self.status.value,
            "current_step": self.current_step,
            "plain_status": self.plain_status,
            "created_at": self.created_at,
            "completed_at": self.completed_at,
        }
