"""
Goal Engine — manages long-running autonomous goals.

Users define goals via conversation. The engine decomposes them into steps,
tracks progress, schedules periodic checks, and reports back.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional

from runtime.goals.goal_types import (
    Goal, GoalStatus, GoalStep, StepStatus, GoalPriority,
)

logger = logging.getLogger(__name__)


class GoalEngine:
    """
    Manages autonomous goals with step decomposition and progress tracking.

    Goals persist to JSON files. The engine provides:
    - Goal creation with automatic step decomposition
    - Step execution tracking with retries
    - Progress calculation and status updates
    - Deadline monitoring
    - Notification hooks for completion/failure
    """

    def __init__(
        self,
        storage_dir: str = "",
        notify_fn: Optional[Callable[[str, str, str], None]] = None,
    ) -> None:
        """
        Args:
            storage_dir: Directory for goal persistence.
            notify_fn: Callable(user_id, title, message) for notifications.
        """
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "goals"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._goals: Dict[str, Goal] = {}
        self._by_user: Dict[str, List[str]] = {}
        self._notify_fn = notify_fn
        self._lock = threading.Lock()
        self._counter: int = 0
        self._load_all()
        logger.info("GoalEngine initialised | dir=%s | goals=%d", self._storage_dir, len(self._goals))

    # ── Goal Lifecycle ────────────────────────────────────────────────

    def create_goal(
        self,
        user_id: str,
        title: str,
        description: str,
        agent_name: str = "neo",
        steps: Optional[List[str]] = None,
        priority: str = "medium",
        deadline: float = 0.0,
        check_interval: int = 3600,
        tags: Optional[List[str]] = None,
    ) -> Goal:
        """
        Create a new autonomous goal.

        Args:
            user_id: The user who set this goal.
            title: Short goal title.
            description: Full description of what to achieve.
            agent_name: Which agent is responsible.
            steps: Optional list of step descriptions. Auto-generated if None.
            priority: low/medium/high/critical.
            deadline: Unix timestamp deadline (0 = no deadline).
            check_interval: Seconds between progress checks.
            tags: Categorization tags.

        Returns:
            The created Goal.
        """
        if not title:
            raise ValueError("Goal title must not be empty.")

        with self._lock:
            self._counter += 1
            gid = f"GOAL-{self._counter:08d}"

            goal_steps = []
            if steps:
                for i, desc in enumerate(steps):
                    step = GoalStep(
                        step_id=f"{gid}-S{i+1:03d}",
                        description=desc,
                        depends_on=[f"{gid}-S{i:03d}"] if i > 0 else [],
                    )
                    goal_steps.append(step)

            goal = Goal(
                goal_id=gid,
                user_id=user_id,
                agent_name=agent_name,
                title=title,
                description=description,
                status=GoalStatus.ACTIVE,
                priority=GoalPriority(priority),
                steps=goal_steps,
                started_at=time.time(),
                deadline=deadline,
                check_interval_seconds=check_interval,
                tags=tags or [],
            )
            self._goals[gid] = goal
            self._by_user.setdefault(user_id, []).append(gid)
            self._persist(gid)

        logger.info(
            "Goal created | id=%s | user=%s | title=%s | steps=%d",
            gid, user_id, title, len(goal_steps),
        )
        return goal

    def add_step(
        self, goal_id: str, description: str, depends_on: Optional[List[str]] = None,
    ) -> GoalStep:
        """Add a step to an existing goal."""
        goal = self._get_goal(goal_id)
        with self._lock:
            idx = len(goal.steps) + 1
            step = GoalStep(
                step_id=f"{goal_id}-S{idx:03d}",
                description=description,
                depends_on=depends_on or [],
            )
            goal.steps.append(step)
            self._persist(goal_id)
        return step

    # ── Step Execution ────────────────────────────────────────────────

    def start_step(self, goal_id: str, step_id: str) -> GoalStep:
        """Mark a step as running."""
        goal = self._get_goal(goal_id)
        step = self._get_step(goal, step_id)
        with self._lock:
            # Check dependencies
            for dep_id in step.depends_on:
                dep = self._get_step(goal, dep_id)
                if dep.status != StepStatus.COMPLETED:
                    raise ValueError(f"Dependency {dep_id} not completed.")
            step.status = StepStatus.RUNNING
            step.started_at = time.time()
            self._persist(goal_id)
        return step

    def complete_step(
        self, goal_id: str, step_id: str, result: str = "",
    ) -> GoalStep:
        """Mark a step as completed with result."""
        goal = self._get_goal(goal_id)
        step = self._get_step(goal, step_id)
        with self._lock:
            step.status = StepStatus.COMPLETED
            step.result = result
            step.completed_at = time.time()
            self._update_progress(goal)
            self._persist(goal_id)

        # Check if all steps complete
        if all(s.status in (StepStatus.COMPLETED, StepStatus.SKIPPED) for s in goal.steps):
            self._complete_goal(goal)

        return step

    def fail_step(
        self, goal_id: str, step_id: str, error: str = "",
    ) -> GoalStep:
        """Mark a step as failed. Retries if within limit."""
        goal = self._get_goal(goal_id)
        step = self._get_step(goal, step_id)
        with self._lock:
            step.retry_count += 1
            if step.retry_count <= step.max_retries:
                step.status = StepStatus.PENDING
                step.error = error
                logger.info(
                    "Step retry | goal=%s | step=%s | attempt=%d/%d",
                    goal_id, step_id, step.retry_count, step.max_retries,
                )
            else:
                step.status = StepStatus.FAILED
                step.error = error
                step.completed_at = time.time()
                logger.warning(
                    "Step failed permanently | goal=%s | step=%s | error=%s",
                    goal_id, step_id, error,
                )
                if goal.notify_on_failure and self._notify_fn:
                    self._notify_fn(
                        goal.user_id,
                        f"Goal step failed: {goal.title}",
                        f"Step '{step.description}' failed after {step.max_retries} retries: {error}",
                    )
            self._update_progress(goal)
            self._persist(goal_id)
        return step

    def skip_step(self, goal_id: str, step_id: str, reason: str = "") -> GoalStep:
        """Skip a step."""
        goal = self._get_goal(goal_id)
        step = self._get_step(goal, step_id)
        with self._lock:
            step.status = StepStatus.SKIPPED
            step.result = f"Skipped: {reason}" if reason else "Skipped"
            step.completed_at = time.time()
            self._update_progress(goal)
            self._persist(goal_id)
        return step

    # ── Goal Status ───────────────────────────────────────────────────

    def pause_goal(self, goal_id: str) -> Goal:
        """Pause an active goal."""
        goal = self._get_goal(goal_id)
        if goal.status != GoalStatus.ACTIVE:
            raise ValueError(f"Goal is {goal.status.value}, not active.")
        with self._lock:
            goal.status = GoalStatus.PAUSED
            goal.last_update = "Paused by user."
            self._persist(goal_id)
        return goal

    def resume_goal(self, goal_id: str) -> Goal:
        """Resume a paused goal."""
        goal = self._get_goal(goal_id)
        if goal.status != GoalStatus.PAUSED:
            raise ValueError(f"Goal is {goal.status.value}, not paused.")
        with self._lock:
            goal.status = GoalStatus.ACTIVE
            goal.last_update = "Resumed."
            self._persist(goal_id)
        return goal

    def cancel_goal(self, goal_id: str, reason: str = "") -> Goal:
        """Cancel a goal."""
        goal = self._get_goal(goal_id)
        with self._lock:
            goal.status = GoalStatus.CANCELLED
            goal.completed_at = time.time()
            goal.last_update = f"Cancelled: {reason}" if reason else "Cancelled"
            self._persist(goal_id)
        return goal

    def update_goal(self, goal_id: str, update_text: str) -> Goal:
        """Record a progress update on a goal."""
        goal = self._get_goal(goal_id)
        with self._lock:
            goal.last_update = update_text
            goal.last_checked_at = time.time()
            self._persist(goal_id)

        if goal.notify_on_progress and self._notify_fn:
            self._notify_fn(goal.user_id, f"Goal update: {goal.title}", update_text)
        return goal

    # ── Scheduling ────────────────────────────────────────────────────

    def get_due_goals(self) -> List[Goal]:
        """Get goals that are due for a progress check."""
        now = time.time()
        due = []
        for goal in self._goals.values():
            if goal.status != GoalStatus.ACTIVE:
                continue
            if now - goal.last_checked_at >= goal.check_interval_seconds:
                due.append(goal)
        return due

    def get_overdue_goals(self) -> List[Goal]:
        """Get active goals past their deadline."""
        now = time.time()
        return [
            g for g in self._goals.values()
            if g.status == GoalStatus.ACTIVE and g.deadline > 0 and now > g.deadline
        ]

    def get_next_step(self, goal_id: str) -> Optional[GoalStep]:
        """Get the next actionable step (pending with all deps met)."""
        goal = self._get_goal(goal_id)
        completed_ids = {s.step_id for s in goal.steps if s.status in (StepStatus.COMPLETED, StepStatus.SKIPPED)}
        for step in goal.steps:
            if step.status == StepStatus.PENDING:
                if all(dep in completed_ids for dep in step.depends_on):
                    return step
        return None

    # ── Queries ───────────────────────────────────────────────────────

    def get_goal(self, goal_id: str) -> Optional[Goal]:
        """Get goal or None."""
        return self._goals.get(goal_id)

    def get_user_goals(
        self, user_id: str, status: Optional[GoalStatus] = None,
    ) -> List[Goal]:
        """Get all goals for a user."""
        ids = self._by_user.get(user_id, [])
        goals = [self._goals[gid] for gid in ids if gid in self._goals]
        if status:
            goals = [g for g in goals if g.status == status]
        return goals

    def get_active_goals(self) -> List[Goal]:
        """Get all active goals across all users."""
        return [g for g in self._goals.values() if g.status == GoalStatus.ACTIVE]

    def get_stats(self) -> dict:
        """Get aggregate statistics."""
        by_status = {}
        for g in self._goals.values():
            by_status[g.status.value] = by_status.get(g.status.value, 0) + 1
        return {"total": len(self._goals), "by_status": by_status}

    # ── Internal ──────────────────────────────────────────────────────

    def _complete_goal(self, goal: Goal) -> None:
        """Mark a goal as completed."""
        goal.status = GoalStatus.COMPLETED
        goal.completed_at = time.time()
        goal.progress_pct = 100.0
        goal.last_update = "All steps completed."
        self._persist(goal.goal_id)
        logger.info("Goal completed | id=%s | title=%s", goal.goal_id, goal.title)
        if goal.notify_on_completion and self._notify_fn:
            self._notify_fn(
                goal.user_id, f"Goal completed: {goal.title}",
                f"All {len(goal.steps)} steps finished successfully.",
            )

    def _update_progress(self, goal: Goal) -> None:
        """Recalculate goal progress percentage."""
        if not goal.steps:
            return
        done = sum(1 for s in goal.steps if s.status in (StepStatus.COMPLETED, StepStatus.SKIPPED))
        goal.progress_pct = round((done / len(goal.steps)) * 100, 1)

    def _get_goal(self, goal_id: str) -> Goal:
        goal = self._goals.get(goal_id)
        if goal is None:
            raise ValueError(f"Goal {goal_id} not found.")
        return goal

    def _get_step(self, goal: Goal, step_id: str) -> GoalStep:
        for s in goal.steps:
            if s.step_id == step_id:
                return s
        raise ValueError(f"Step {step_id} not found in goal {goal.goal_id}.")

    def _persist(self, goal_id: str) -> None:
        goal = self._goals.get(goal_id)
        if goal is None:
            return
        path = self._storage_dir / f"{goal_id}.json"
        try:
            with open(path, "w") as f:
                json.dump(goal.to_dict(), f, indent=2)
        except Exception:
            logger.exception("Failed to persist goal | id=%s", goal_id)

    def _load_all(self) -> None:
        """Load all goals from disk."""
        for path in self._storage_dir.glob("*.json"):
            try:
                with open(path) as f:
                    data = json.load(f)
                goal = Goal.from_dict(data)
                self._goals[goal.goal_id] = goal
                self._by_user.setdefault(goal.user_id, []).append(goal.goal_id)
                num = int(goal.goal_id.split("-")[1])
                self._counter = max(self._counter, num)
            except Exception:
                logger.exception("Failed to load goal | file=%s", path)
