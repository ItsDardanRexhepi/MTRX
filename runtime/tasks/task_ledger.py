"""
Task Ledger — SQLite-backed unified task control plane.

All agents (Neo, Trinity, Morpheus) register their background work here.
Provides audit trail, lost-run recovery, and plain-language status.
Better than OpenClaw: every status is human-readable, not technical jargon.
"""

from __future__ import annotations

import json
import logging
import sqlite3
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

from runtime.tasks.task_types import Task, TaskFlow, TaskStatus, TaskType

logger = logging.getLogger(__name__)

# Plain-language templates for status summaries
_STATUS_TEMPLATES = {
    TaskStatus.QUEUED: "{agent} is about to {action}. Waiting in line.",
    TaskStatus.RUNNING: "{agent} is {action} right now. {progress}",
    TaskStatus.BLOCKED: "{agent} needs your help before continuing — {reason}.",
    TaskStatus.COMPLETED: "{agent} finished {action}. {result}",
    TaskStatus.FAILED: "{agent} ran into a problem while {action}. {error}",
    TaskStatus.CANCELLED: "You cancelled this task. {agent} has stopped.",
    TaskStatus.LOST: "This task seems to have stopped unexpectedly. {agent} can retry if needed.",
}

_AGENT_NAMES = {
    "neo": "Neo",
    "trinity": "Trinity",
    "morpheus": "Morpheus",
    "system": "Matrix",
}


def _humanize_duration(seconds: float) -> str:
    if seconds < 60:
        return f"{int(seconds)} seconds"
    elif seconds < 3600:
        mins = int(seconds / 60)
        return f"{mins} minute{'s' if mins != 1 else ''}"
    else:
        hours = int(seconds / 3600)
        mins = int((seconds % 3600) / 60)
        if mins:
            return f"{hours}h {mins}m"
        return f"{hours} hour{'s' if hours != 1 else ''}"


class TaskLedger:
    """
    SQLite-backed task registry with plain-language status.

    Every background operation across all agents is tracked here.
    Supports task flows (multi-step), subtasks, auto-cleanup,
    and lost-run detection.
    """

    LOST_THRESHOLD_SECONDS: int = 7200   # 2 hours without update = lost
    CLEANUP_AGE_SECONDS: int = 604800    # 7 days

    def __init__(self, db_path: str = "") -> None:
        if not db_path:
            db_dir = Path(__file__).resolve().parent.parent.parent / "data" / "tasks"
            db_dir.mkdir(parents=True, exist_ok=True)
            db_path = str(db_dir / "tasks.db")
        self._db_path = db_path
        self._lock = threading.Lock()
        self._task_counter: int = 0
        self._flow_counter: int = 0
        self._init_db()
        logger.info("TaskLedger initialised | db=%s", self._db_path)

    # ── Task Lifecycle ───────────────────────────────────────────────

    def create_task(
        self,
        task_type: TaskType,
        agent: str,
        title: str,
        description: str,
        user_id: str = "",
        parent_id: str = "",
        flow_id: str = "",
        timeout_seconds: int = 3600,
        metadata: Optional[dict] = None,
        tags: Optional[List[str]] = None,
    ) -> Task:
        """Create and register a new background task."""
        with self._lock:
            self._task_counter += 1
            task_id = f"TASK-{self._task_counter:08d}"

        agent_name = _AGENT_NAMES.get(agent, agent.title())
        plain = _STATUS_TEMPLATES[TaskStatus.QUEUED].format(
            agent=agent_name, action=description.lower(),
        )

        task = Task(
            task_id=task_id,
            task_type=task_type,
            agent=agent,
            title=title,
            description=description,
            user_id=user_id,
            parent_id=parent_id,
            flow_id=flow_id,
            timeout_seconds=timeout_seconds,
            plain_status=plain,
            metadata=metadata or {},
            tags=tags or [],
        )
        self._insert_task(task)
        logger.info("Task created | id=%s | agent=%s | title=%s", task_id, agent, title)
        return task

    def start_task(self, task_id: str) -> Task:
        """Mark a task as running."""
        task = self._get_task(task_id)
        task.status = TaskStatus.RUNNING
        task.started_at = time.time()
        task.updated_at = time.time()
        agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())
        task.plain_status = _STATUS_TEMPLATES[TaskStatus.RUNNING].format(
            agent=agent_name, action=task.description.lower(),
            progress="Just getting started.",
        )
        self._update_task(task)
        return task

    def update_progress(
        self, task_id: str, progress_pct: float, plain_status: str = "",
    ) -> Task:
        """Update task progress with plain-language status."""
        task = self._get_task(task_id)
        task.progress_pct = min(100.0, max(0.0, progress_pct))
        task.updated_at = time.time()
        if plain_status:
            task.plain_status = plain_status
        else:
            agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())
            elapsed = _humanize_duration(task.duration_seconds)
            task.plain_status = _STATUS_TEMPLATES[TaskStatus.RUNNING].format(
                agent=agent_name, action=task.description.lower(),
                progress=f"{int(task.progress_pct)}% done, running for {elapsed}.",
            )
        self._update_task(task)
        return task

    def complete_task(self, task_id: str, result: str = "") -> Task:
        """Mark task as completed."""
        task = self._get_task(task_id)
        task.status = TaskStatus.COMPLETED
        task.progress_pct = 100.0
        task.completed_at = time.time()
        task.updated_at = time.time()
        task.result = result
        agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())
        elapsed = _humanize_duration(task.duration_seconds)
        result_summary = f"Took {elapsed}." + (f" {result}" if result else "")
        task.plain_status = _STATUS_TEMPLATES[TaskStatus.COMPLETED].format(
            agent=agent_name, action=task.description.lower(),
            result=result_summary,
        )
        self._update_task(task)
        logger.info("Task completed | id=%s | duration=%.1fs", task_id, task.duration_seconds)
        return task

    def fail_task(self, task_id: str, error: str = "") -> Task:
        """Mark task as failed. Retries if within limit."""
        task = self._get_task(task_id)
        agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())

        task.retry_count += 1
        if task.retry_count <= task.max_retries:
            task.status = TaskStatus.QUEUED
            task.error = error
            task.updated_at = time.time()
            task.plain_status = (
                f"{agent_name} hit a snag — retrying "
                f"(attempt {task.retry_count + 1} of {task.max_retries + 1})."
            )
        else:
            task.status = TaskStatus.FAILED
            task.error = error
            task.completed_at = time.time()
            task.updated_at = time.time()
            friendly_error = self._friendly_error(error)
            task.plain_status = _STATUS_TEMPLATES[TaskStatus.FAILED].format(
                agent=agent_name, action=task.description.lower(),
                error=friendly_error,
            )
        self._update_task(task)
        return task

    def cancel_task(self, task_id: str) -> Task:
        """Cancel a task."""
        task = self._get_task(task_id)
        if task.is_terminal:
            raise ValueError(f"Task {task_id} is already {task.status.value}.")
        agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())
        task.status = TaskStatus.CANCELLED
        task.completed_at = time.time()
        task.updated_at = time.time()
        task.plain_status = _STATUS_TEMPLATES[TaskStatus.CANCELLED].format(agent=agent_name)
        self._update_task(task)
        logger.info("Task cancelled | id=%s", task_id)
        return task

    def block_task(self, task_id: str, reason: str) -> Task:
        """Mark a task as blocked, waiting for something."""
        task = self._get_task(task_id)
        task.status = TaskStatus.BLOCKED
        task.updated_at = time.time()
        agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())
        task.plain_status = _STATUS_TEMPLATES[TaskStatus.BLOCKED].format(
            agent=agent_name, reason=reason,
        )
        self._update_task(task)
        return task

    # ── Task Flows ───────────────────────────────────────────────────

    def create_flow(
        self,
        name: str,
        description: str,
        agent: str,
        task_descriptions: List[str],
        user_id: str = "",
    ) -> TaskFlow:
        """Create a multi-step task flow."""
        with self._lock:
            self._flow_counter += 1
            flow_id = f"FLOW-{self._flow_counter:08d}"

        task_ids = []
        for i, desc in enumerate(task_descriptions):
            task = self.create_task(
                task_type=TaskType.FLOW,
                agent=agent,
                title=f"Step {i+1}: {desc[:60]}",
                description=desc,
                user_id=user_id,
                flow_id=flow_id,
            )
            task_ids.append(task.task_id)

        flow = TaskFlow(
            flow_id=flow_id,
            name=name,
            description=description,
            agent=agent,
            user_id=user_id,
            task_ids=task_ids,
            status=TaskStatus.QUEUED,
            plain_status=f"Flow ready with {len(task_ids)} steps.",
        )
        self._insert_flow(flow)
        logger.info("Flow created | id=%s | steps=%d", flow_id, len(task_ids))
        return flow

    def advance_flow(self, flow_id: str) -> Optional[Task]:
        """Advance to the next step in a flow. Returns next task or None if done."""
        flow = self._get_flow(flow_id)
        if flow.current_step >= len(flow.task_ids):
            flow.status = TaskStatus.COMPLETED
            flow.completed_at = time.time()
            flow.plain_status = f"All {len(flow.task_ids)} steps completed."
            self._update_flow(flow)
            return None

        task_id = flow.task_ids[flow.current_step]
        task = self._get_task(task_id)
        if task.status == TaskStatus.COMPLETED:
            flow.current_step += 1
            flow.plain_status = (
                f"Step {flow.current_step} of {len(flow.task_ids)} done. "
                f"Moving to the next step."
            )
            self._update_flow(flow)
            return self.advance_flow(flow_id)

        if task.status == TaskStatus.QUEUED:
            self.start_task(task_id)
            flow.status = TaskStatus.RUNNING
            flow.plain_status = (
                f"Working on step {flow.current_step + 1} of {len(flow.task_ids)}: "
                f"{task.description}"
            )
            self._update_flow(flow)

        return self._get_task(task_id)

    # ── Queries ──────────────────────────────────────────────────────

    def get_task(self, task_id: str) -> Optional[Task]:
        try:
            return self._get_task(task_id)
        except ValueError:
            return None

    def list_tasks(
        self,
        agent: str = "",
        status: Optional[TaskStatus] = None,
        user_id: str = "",
        limit: int = 50,
    ) -> List[Task]:
        """List tasks with optional filters."""
        conn = self._connect()
        query = "SELECT data FROM tasks WHERE 1=1"
        params: list = []
        if agent:
            query += " AND agent = ?"
            params.append(agent)
        if status:
            query += " AND status = ?"
            params.append(status.value)
        if user_id:
            query += " AND user_id = ?"
            params.append(user_id)
        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        rows = conn.execute(query, params).fetchall()
        conn.close()
        return [self._row_to_task(r[0]) for r in rows]

    def list_active_tasks(self) -> List[Task]:
        """Get all non-terminal tasks."""
        conn = self._connect()
        rows = conn.execute(
            "SELECT data FROM tasks WHERE status IN ('queued', 'running', 'blocked') "
            "ORDER BY created_at DESC"
        ).fetchall()
        conn.close()
        return [self._row_to_task(r[0]) for r in rows]

    def list_flows(self, limit: int = 20) -> List[TaskFlow]:
        conn = self._connect()
        rows = conn.execute(
            "SELECT data FROM flows ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
        conn.close()
        return [self._row_to_flow(r[0]) for r in rows]

    def get_flow(self, flow_id: str) -> Optional[TaskFlow]:
        try:
            return self._get_flow(flow_id)
        except ValueError:
            return None

    def get_summary(self) -> dict:
        """Get a plain-language summary of all active work."""
        active = self.list_active_tasks()
        if not active:
            return {
                "summary": "All clear — no tasks running right now.",
                "active_count": 0,
                "tasks": [],
            }

        lines = []
        by_agent: Dict[str, list] = {}
        for t in active:
            by_agent.setdefault(t.agent, []).append(t)

        for agent, tasks in by_agent.items():
            agent_name = _AGENT_NAMES.get(agent, agent.title())
            if len(tasks) == 1:
                lines.append(f"{agent_name}: {tasks[0].plain_status}")
            else:
                lines.append(f"{agent_name} is working on {len(tasks)} things:")
                for t in tasks:
                    lines.append(f"  - {t.title}: {t.plain_status}")

        return {
            "summary": "\n".join(lines),
            "active_count": len(active),
            "tasks": [t.to_dict() for t in active],
        }

    # ── Maintenance ──────────────────────────────────────────────────

    def detect_lost_tasks(self) -> List[Task]:
        """Find tasks that appear to have stalled."""
        now = time.time()
        active = self.list_active_tasks()
        lost = []
        for task in active:
            if task.status == TaskStatus.RUNNING:
                if now - task.updated_at > self.LOST_THRESHOLD_SECONDS:
                    task.status = TaskStatus.LOST
                    agent_name = _AGENT_NAMES.get(task.agent, task.agent.title())
                    task.plain_status = (
                        f"This task stopped responding after "
                        f"{_humanize_duration(now - task.updated_at)}. "
                        f"{agent_name} can restart it if you'd like."
                    )
                    self._update_task(task)
                    lost.append(task)
        if lost:
            logger.warning("Detected %d lost tasks.", len(lost))
        return lost

    def cleanup_old_tasks(self) -> int:
        """Remove completed tasks older than cleanup threshold."""
        cutoff = time.time() - self.CLEANUP_AGE_SECONDS
        conn = self._connect()
        cursor = conn.execute(
            "DELETE FROM tasks WHERE status IN ('completed', 'failed', 'cancelled', 'lost') "
            "AND completed_at > 0 AND completed_at < ?",
            (cutoff,),
        )
        count = cursor.rowcount
        conn.commit()
        conn.close()
        if count:
            logger.info("Cleaned up %d old tasks.", count)
        return count

    def get_stats(self) -> dict:
        conn = self._connect()
        rows = conn.execute(
            "SELECT status, COUNT(*) FROM tasks GROUP BY status"
        ).fetchall()
        conn.close()
        by_status = {r[0]: r[1] for r in rows}
        return {
            "total": sum(by_status.values()),
            "by_status": by_status,
        }

    # ── Internal DB ──────────────────────────────────────────────────

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self._db_path)

    def _init_db(self) -> None:
        conn = self._connect()
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                task_id TEXT PRIMARY KEY,
                task_type TEXT NOT NULL,
                agent TEXT NOT NULL,
                status TEXT NOT NULL,
                user_id TEXT DEFAULT '',
                flow_id TEXT DEFAULT '',
                created_at REAL NOT NULL,
                completed_at REAL DEFAULT 0,
                data TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS flows (
                flow_id TEXT PRIMARY KEY,
                agent TEXT NOT NULL,
                status TEXT NOT NULL,
                user_id TEXT DEFAULT '',
                created_at REAL NOT NULL,
                completed_at REAL DEFAULT 0,
                data TEXT NOT NULL
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_agent ON tasks(agent)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_user ON tasks(user_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_flow ON tasks(flow_id)")
        conn.commit()

        # Load counter
        row = conn.execute("SELECT MAX(CAST(SUBSTR(task_id, 6) AS INTEGER)) FROM tasks").fetchone()
        if row and row[0]:
            self._task_counter = row[0]
        row = conn.execute("SELECT MAX(CAST(SUBSTR(flow_id, 6) AS INTEGER)) FROM flows").fetchone()
        if row and row[0]:
            self._flow_counter = row[0]

        conn.close()

    def _insert_task(self, task: Task) -> None:
        conn = self._connect()
        conn.execute(
            "INSERT INTO tasks (task_id, task_type, agent, status, user_id, flow_id, created_at, completed_at, data) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (task.task_id, task.task_type.value, task.agent, task.status.value,
             task.user_id, task.flow_id, task.created_at, task.completed_at,
             json.dumps(task.to_dict())),
        )
        conn.commit()
        conn.close()

    def _update_task(self, task: Task) -> None:
        conn = self._connect()
        conn.execute(
            "UPDATE tasks SET status=?, completed_at=?, data=? WHERE task_id=?",
            (task.status.value, task.completed_at, json.dumps(task.to_dict()), task.task_id),
        )
        conn.commit()
        conn.close()

    def _get_task(self, task_id: str) -> Task:
        conn = self._connect()
        row = conn.execute("SELECT data FROM tasks WHERE task_id=?", (task_id,)).fetchone()
        conn.close()
        if row is None:
            raise ValueError(f"Task {task_id} not found.")
        return self._row_to_task(row[0])

    def _insert_flow(self, flow: TaskFlow) -> None:
        conn = self._connect()
        conn.execute(
            "INSERT INTO flows (flow_id, agent, status, user_id, created_at, completed_at, data) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (flow.flow_id, flow.agent, flow.status.value,
             flow.user_id, flow.created_at, flow.completed_at,
             json.dumps(flow.to_dict())),
        )
        conn.commit()
        conn.close()

    def _update_flow(self, flow: TaskFlow) -> None:
        conn = self._connect()
        conn.execute(
            "UPDATE flows SET status=?, completed_at=?, data=? WHERE flow_id=?",
            (flow.status.value, flow.completed_at, json.dumps(flow.to_dict()), flow.flow_id),
        )
        conn.commit()
        conn.close()

    def _get_flow(self, flow_id: str) -> TaskFlow:
        conn = self._connect()
        row = conn.execute("SELECT data FROM flows WHERE flow_id=?", (flow_id,)).fetchone()
        conn.close()
        if row is None:
            raise ValueError(f"Flow {flow_id} not found.")
        return self._row_to_flow(row[0])

    def _row_to_task(self, data_str: str) -> Task:
        d = json.loads(data_str)
        return Task(
            task_id=d["task_id"], task_type=TaskType(d["task_type"]),
            agent=d["agent"], title=d["title"], description=d["description"],
            status=TaskStatus(d["status"]), user_id=d.get("user_id", ""),
            parent_id=d.get("parent_id", ""), flow_id=d.get("flow_id", ""),
            progress_pct=d.get("progress_pct", 0), plain_status=d.get("plain_status", ""),
            result=d.get("result", ""), error=d.get("error", ""),
            created_at=d["created_at"], started_at=d.get("started_at", 0),
            completed_at=d.get("completed_at", 0), updated_at=d.get("updated_at", 0),
            timeout_seconds=d.get("timeout_seconds", 3600),
            retry_count=d.get("retry_count", 0), max_retries=d.get("max_retries", 2),
            metadata=d.get("metadata", {}), tags=d.get("tags", []),
        )

    def _row_to_flow(self, data_str: str) -> TaskFlow:
        d = json.loads(data_str)
        return TaskFlow(
            flow_id=d["flow_id"], name=d["name"], description=d["description"],
            agent=d["agent"], user_id=d.get("user_id", ""),
            task_ids=d.get("task_ids", []), status=TaskStatus(d["status"]),
            current_step=d.get("current_step", 0),
            plain_status=d.get("plain_status", ""),
            created_at=d["created_at"], completed_at=d.get("completed_at", 0),
        )

    def _friendly_error(self, error: str) -> str:
        """Convert technical errors to friendly messages."""
        lower = error.lower()
        if "timeout" in lower:
            return "It took too long and had to stop. You can try again."
        if "connection" in lower or "network" in lower:
            return "There was a network issue. Check your connection and try again."
        if "permission" in lower or "auth" in lower:
            return "It doesn't have permission to do that. You may need to grant access."
        if "not found" in lower or "404" in lower:
            return "It couldn't find what it was looking for."
        if "rate limit" in lower or "429" in lower:
            return "Too many requests — waiting a moment before trying again."
        if len(error) > 200:
            return error[:200] + "..."
        return error if error else "Something unexpected happened."
