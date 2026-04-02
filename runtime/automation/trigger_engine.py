"""
Trigger Engine — evaluates events against registered triggers and executes actions.

Supports conditional logic, cooldowns, one-shot triggers, expiration,
and action chaining. All triggers persist to JSON files.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from runtime.automation.trigger_types import (
    ActionType, Event, EventType, Trigger, TriggerAction,
    TriggerCondition, TriggerExecution, TriggerStatus,
)

logger = logging.getLogger(__name__)


class TriggerEngine:
    """
    Event-driven automation engine.

    Users define triggers through conversation. When system events occur,
    the engine evaluates conditions and executes matching actions.
    """

    def __init__(
        self,
        storage_dir: str = "",
        action_handlers: Optional[Dict[ActionType, Callable]] = None,
    ) -> None:
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "triggers"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._triggers: Dict[str, Trigger] = {}
        self._by_user: Dict[str, List[str]] = {}
        self._by_event: Dict[EventType, List[str]] = {}
        self._action_handlers: Dict[ActionType, Callable] = action_handlers or {}
        self._lock = threading.Lock()
        self._counter: int = 0
        self._execution_counter: int = 0
        self._event_log: List[dict] = []
        self._load_all()

        # Register default action handlers
        self._action_handlers.setdefault(ActionType.LOG_EVENT, self._handle_log)

        logger.info(
            "TriggerEngine initialised | dir=%s | triggers=%d",
            self._storage_dir, len(self._triggers),
        )

    # ── Registration ─────────────────────────────────────────────────

    def register_handler(self, action_type: ActionType, handler: Callable) -> None:
        """Register an action handler for a specific action type."""
        self._action_handlers[action_type] = handler

    def create_trigger(
        self,
        user_id: str,
        name: str,
        description: str,
        event_type: EventType,
        conditions: Optional[List[TriggerCondition]] = None,
        actions: Optional[List[TriggerAction]] = None,
        one_shot: bool = False,
        cooldown_seconds: int = 0,
        max_fires: int = 0,
        expires_at: float = 0.0,
        tags: Optional[List[str]] = None,
    ) -> Trigger:
        """
        Create a new automation trigger.

        Args:
            user_id: Owner of the trigger.
            name: Short trigger name.
            description: What this trigger does (natural language).
            event_type: Type of event to listen for.
            conditions: Conditions that must all be true.
            actions: Actions to execute when triggered.
            one_shot: Fire only once then disable.
            cooldown_seconds: Minimum seconds between firings.
            max_fires: Maximum total firings (0 = unlimited).
            expires_at: Unix timestamp expiration (0 = never).
            tags: Categorization tags.

        Returns:
            The created Trigger.
        """
        if not name:
            raise ValueError("Trigger name must not be empty.")
        if not actions:
            raise ValueError("Trigger must have at least one action.")

        with self._lock:
            self._counter += 1
            tid = f"TRIG-{self._counter:08d}"

            trigger = Trigger(
                trigger_id=tid,
                user_id=user_id,
                name=name,
                description=description,
                event_type=event_type,
                conditions=conditions or [],
                actions=actions,
                one_shot=one_shot,
                cooldown_seconds=cooldown_seconds,
                max_fires=max_fires,
                expires_at=expires_at,
                tags=tags or [],
            )
            self._triggers[tid] = trigger
            self._by_user.setdefault(user_id, []).append(tid)
            self._by_event.setdefault(event_type, []).append(tid)
            self._persist(tid)

        logger.info(
            "Trigger created | id=%s | user=%s | event=%s | name=%s",
            tid, user_id, event_type.value, name,
        )
        return trigger

    # ── Event Processing ─────────────────────────────────────────────

    def fire_event(self, event: Event) -> List[TriggerExecution]:
        """
        Process an event against all registered triggers.

        Evaluates conditions for matching triggers and executes actions.
        Returns list of executions that occurred.
        """
        now = time.time()
        executions = []

        # Log the event
        self._event_log.append({
            "event_type": event.event_type.value,
            "source": event.source,
            "data": event.data,
            "timestamp": event.timestamp,
            "user_id": event.user_id,
        })
        # Keep last 1000 events
        if len(self._event_log) > 1000:
            self._event_log = self._event_log[-500:]

        trigger_ids = self._by_event.get(event.event_type, [])

        for tid in trigger_ids:
            trigger = self._triggers.get(tid)
            if trigger is None:
                continue

            # Skip non-active triggers
            if trigger.status != TriggerStatus.ACTIVE:
                continue

            # Check expiration
            if trigger.expires_at > 0 and now > trigger.expires_at:
                trigger.status = TriggerStatus.EXPIRED
                self._persist(tid)
                continue

            # Check cooldown
            if trigger.cooldown_seconds > 0 and trigger.last_fired_at > 0:
                if now - trigger.last_fired_at < trigger.cooldown_seconds:
                    continue

            # Check max fires
            if trigger.max_fires > 0 and trigger.fire_count >= trigger.max_fires:
                trigger.status = TriggerStatus.DISABLED
                self._persist(tid)
                continue

            # Filter by user if event has user_id
            if event.user_id and trigger.user_id != event.user_id:
                # Only user-scoped events filter by user
                if event.event_type in (
                    EventType.MESSAGE_RECEIVED,
                    EventType.DOCUMENT_UPLOADED,
                ):
                    continue

            # Evaluate conditions
            if not self._evaluate_conditions(trigger, event.data):
                continue

            # Execute actions
            execution = self._execute_trigger(trigger, event)
            executions.append(execution)

        return executions

    def fire_event_simple(
        self,
        event_type: str,
        source: str,
        data: Optional[dict] = None,
        user_id: str = "",
    ) -> List[TriggerExecution]:
        """Convenience method to fire an event from simple parameters."""
        event = Event(
            event_type=EventType(event_type),
            source=source,
            data=data or {},
            user_id=user_id,
        )
        return self.fire_event(event)

    # ── Trigger Management ───────────────────────────────────────────

    def pause_trigger(self, trigger_id: str) -> Trigger:
        """Pause a trigger."""
        trigger = self._get_trigger(trigger_id)
        with self._lock:
            trigger.status = TriggerStatus.PAUSED
            self._persist(trigger_id)
        return trigger

    def resume_trigger(self, trigger_id: str) -> Trigger:
        """Resume a paused trigger."""
        trigger = self._get_trigger(trigger_id)
        if trigger.status != TriggerStatus.PAUSED:
            raise ValueError(f"Trigger {trigger_id} is {trigger.status.value}, not paused.")
        with self._lock:
            trigger.status = TriggerStatus.ACTIVE
            self._persist(trigger_id)
        return trigger

    def delete_trigger(self, trigger_id: str) -> bool:
        """Delete a trigger permanently."""
        trigger = self._triggers.get(trigger_id)
        if trigger is None:
            return False
        with self._lock:
            del self._triggers[trigger_id]
            user_list = self._by_user.get(trigger.user_id, [])
            if trigger_id in user_list:
                user_list.remove(trigger_id)
            event_list = self._by_event.get(trigger.event_type, [])
            if trigger_id in event_list:
                event_list.remove(trigger_id)
            path = self._storage_dir / f"{trigger_id}.json"
            if path.exists():
                path.unlink()
        logger.info("Trigger deleted | id=%s", trigger_id)
        return True

    def update_trigger(
        self,
        trigger_id: str,
        name: Optional[str] = None,
        description: Optional[str] = None,
        conditions: Optional[List[TriggerCondition]] = None,
        actions: Optional[List[TriggerAction]] = None,
        cooldown_seconds: Optional[int] = None,
        max_fires: Optional[int] = None,
    ) -> Trigger:
        """Update trigger properties."""
        trigger = self._get_trigger(trigger_id)
        with self._lock:
            if name is not None:
                trigger.name = name
            if description is not None:
                trigger.description = description
            if conditions is not None:
                trigger.conditions = conditions
            if actions is not None:
                trigger.actions = actions
            if cooldown_seconds is not None:
                trigger.cooldown_seconds = cooldown_seconds
            if max_fires is not None:
                trigger.max_fires = max_fires
            self._persist(trigger_id)
        return trigger

    # ── Queries ───────────────────────────────────────────────────────

    def get_trigger(self, trigger_id: str) -> Optional[Trigger]:
        return self._triggers.get(trigger_id)

    def get_user_triggers(
        self, user_id: str, status: Optional[TriggerStatus] = None,
    ) -> List[Trigger]:
        ids = self._by_user.get(user_id, [])
        triggers = [self._triggers[tid] for tid in ids if tid in self._triggers]
        if status:
            triggers = [t for t in triggers if t.status == status]
        return triggers

    def get_trigger_history(self, trigger_id: str, limit: int = 20) -> List[TriggerExecution]:
        trigger = self._get_trigger(trigger_id)
        return trigger.executions[-limit:]

    def get_event_log(self, limit: int = 50) -> List[dict]:
        return self._event_log[-limit:]

    def get_stats(self) -> dict:
        by_status = {}
        for t in self._triggers.values():
            by_status[t.status.value] = by_status.get(t.status.value, 0) + 1
        total_fires = sum(t.fire_count for t in self._triggers.values())
        return {
            "total_triggers": len(self._triggers),
            "by_status": by_status,
            "total_fires": total_fires,
            "event_log_size": len(self._event_log),
        }

    # ── Internal ─────────────────────────────────────────────────────

    def _evaluate_conditions(self, trigger: Trigger, event_data: dict) -> bool:
        """All conditions must be true (AND logic)."""
        for condition in trigger.conditions:
            if not condition.evaluate(event_data):
                return False
        return True

    def _execute_trigger(self, trigger: Trigger, event: Event) -> TriggerExecution:
        """Execute all actions for a trigger."""
        self._execution_counter += 1
        exec_id = f"EXEC-{self._execution_counter:08d}"

        action_results = []
        success = True
        error = ""

        for action in trigger.actions:
            handler = self._action_handlers.get(action.action_type)
            if handler is None:
                result = {"action": action.action_type.value, "status": "skipped", "reason": "no handler"}
                action_results.append(result)
                continue
            try:
                result = handler(trigger, event, action)
                action_results.append({
                    "action": action.action_type.value,
                    "status": "success",
                    "result": result,
                })
            except Exception as exc:
                success = False
                error = str(exc)
                action_results.append({
                    "action": action.action_type.value,
                    "status": "error",
                    "error": str(exc),
                })
                logger.exception(
                    "Action failed | trigger=%s | action=%s",
                    trigger.trigger_id, action.action_type.value,
                )

        execution = TriggerExecution(
            execution_id=exec_id,
            trigger_id=trigger.trigger_id,
            event_type=event.event_type.value,
            event_data=event.data,
            action_results=action_results,
            success=success,
            error=error,
        )

        with self._lock:
            trigger.fire_count += 1
            trigger.last_fired_at = time.time()
            trigger.executions.append(execution)
            # Keep last 100 executions per trigger
            if len(trigger.executions) > 100:
                trigger.executions = trigger.executions[-50:]

            if trigger.one_shot:
                trigger.status = TriggerStatus.FIRED

            if not success:
                logger.warning(
                    "Trigger execution had errors | id=%s | exec=%s",
                    trigger.trigger_id, exec_id,
                )

            self._persist(trigger.trigger_id)

        logger.info(
            "Trigger fired | id=%s | event=%s | actions=%d | success=%s",
            trigger.trigger_id, event.event_type.value, len(action_results), success,
        )
        return execution

    def _handle_log(self, trigger: Trigger, event: Event, action: TriggerAction) -> dict:
        """Default log action handler."""
        msg = action.params.get("message", f"Trigger {trigger.name} fired")
        logger.info("AUTOMATION LOG | trigger=%s | msg=%s | event=%s", trigger.trigger_id, msg, event.data)
        return {"logged": msg}

    def _get_trigger(self, trigger_id: str) -> Trigger:
        trigger = self._triggers.get(trigger_id)
        if trigger is None:
            raise ValueError(f"Trigger {trigger_id} not found.")
        return trigger

    def _persist(self, trigger_id: str) -> None:
        trigger = self._triggers.get(trigger_id)
        if trigger is None:
            return
        path = self._storage_dir / f"{trigger_id}.json"
        try:
            with open(path, "w") as f:
                json.dump(trigger.to_dict(), f, indent=2)
        except Exception:
            logger.exception("Failed to persist trigger | id=%s", trigger_id)

    def _load_all(self) -> None:
        for path in self._storage_dir.glob("*.json"):
            try:
                with open(path) as f:
                    data = json.load(f)
                trigger = Trigger.from_dict(data)
                self._triggers[trigger.trigger_id] = trigger
                self._by_user.setdefault(trigger.user_id, []).append(trigger.trigger_id)
                self._by_event.setdefault(trigger.event_type, []).append(trigger.trigger_id)
                num = int(trigger.trigger_id.split("-")[1])
                self._counter = max(self._counter, num)
            except Exception:
                logger.exception("Failed to load trigger | file=%s", path)
