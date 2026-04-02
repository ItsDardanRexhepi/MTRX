"""
Trigger data types for the automation engine.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class EventType(str, Enum):
    """Types of events that can fire triggers."""
    PRICE_CHANGE = "price_change"
    WALLET_TRANSFER = "wallet_transfer"
    CONTRACT_EVENT = "contract_event"
    SCHEDULE = "schedule"
    MESSAGE_RECEIVED = "message_received"
    GOAL_COMPLETED = "goal_completed"
    GOAL_FAILED = "goal_failed"
    DOCUMENT_UPLOADED = "document_uploaded"
    THRESHOLD_CROSSED = "threshold_crossed"
    CUSTOM = "custom"


class ActionType(str, Enum):
    """Types of actions a trigger can execute."""
    SEND_MESSAGE = "send_message"
    EXECUTE_CODE = "execute_code"
    CALL_API = "call_api"
    CREATE_GOAL = "create_goal"
    TRANSFER_TOKEN = "transfer_token"
    LOG_EVENT = "log_event"
    WEBHOOK = "webhook"
    AGENT_TASK = "agent_task"
    CUSTOM = "custom"


class TriggerStatus(str, Enum):
    ACTIVE = "active"
    PAUSED = "paused"
    FIRED = "fired"          # One-shot trigger that has fired
    EXPIRED = "expired"
    DISABLED = "disabled"
    ERROR = "error"


class ConditionOperator(str, Enum):
    EQUALS = "eq"
    NOT_EQUALS = "neq"
    GREATER_THAN = "gt"
    LESS_THAN = "lt"
    GREATER_EQUAL = "gte"
    LESS_EQUAL = "lte"
    CONTAINS = "contains"
    NOT_CONTAINS = "not_contains"
    REGEX = "regex"
    IN = "in"
    EXISTS = "exists"


@dataclass
class TriggerCondition:
    """A condition that must be met for a trigger to fire."""
    field: str
    operator: ConditionOperator
    value: Any
    description: str = ""

    def evaluate(self, event_data: dict) -> bool:
        """Evaluate this condition against event data."""
        actual = event_data
        for key in self.field.split("."):
            if isinstance(actual, dict):
                actual = actual.get(key)
            else:
                return False
            if actual is None:
                return self.operator == ConditionOperator.EXISTS and not self.value

        op = self.operator
        if op == ConditionOperator.EQUALS:
            return actual == self.value
        elif op == ConditionOperator.NOT_EQUALS:
            return actual != self.value
        elif op == ConditionOperator.GREATER_THAN:
            return float(actual) > float(self.value)
        elif op == ConditionOperator.LESS_THAN:
            return float(actual) < float(self.value)
        elif op == ConditionOperator.GREATER_EQUAL:
            return float(actual) >= float(self.value)
        elif op == ConditionOperator.LESS_EQUAL:
            return float(actual) <= float(self.value)
        elif op == ConditionOperator.CONTAINS:
            return str(self.value) in str(actual)
        elif op == ConditionOperator.NOT_CONTAINS:
            return str(self.value) not in str(actual)
        elif op == ConditionOperator.IN:
            return actual in self.value
        elif op == ConditionOperator.EXISTS:
            return (actual is not None) == bool(self.value)
        elif op == ConditionOperator.REGEX:
            import re
            return bool(re.search(str(self.value), str(actual)))
        return False

    def to_dict(self) -> dict:
        return {
            "field": self.field,
            "operator": self.operator.value,
            "value": self.value,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: dict) -> TriggerCondition:
        return cls(
            field=data["field"],
            operator=ConditionOperator(data["operator"]),
            value=data["value"],
            description=data.get("description", ""),
        )


@dataclass
class TriggerAction:
    """An action to execute when a trigger fires."""
    action_type: ActionType
    params: dict = field(default_factory=dict)
    description: str = ""

    def to_dict(self) -> dict:
        return {
            "action_type": self.action_type.value,
            "params": self.params,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: dict) -> TriggerAction:
        return cls(
            action_type=ActionType(data["action_type"]),
            params=data.get("params", {}),
            description=data.get("description", ""),
        )


@dataclass
class Event:
    """An event that occurred in the system."""
    event_type: EventType
    source: str
    data: dict = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    user_id: str = ""


@dataclass
class TriggerExecution:
    """Record of a trigger firing."""
    execution_id: str
    trigger_id: str
    event_type: str
    event_data: dict
    action_results: List[dict] = field(default_factory=list)
    success: bool = True
    error: str = ""
    executed_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        return {
            "execution_id": self.execution_id,
            "trigger_id": self.trigger_id,
            "event_type": self.event_type,
            "event_data": self.event_data,
            "action_results": self.action_results,
            "success": self.success,
            "error": self.error,
            "executed_at": self.executed_at,
        }


@dataclass
class Trigger:
    """A user-defined automation trigger."""
    trigger_id: str
    user_id: str
    name: str
    description: str
    event_type: EventType
    conditions: List[TriggerCondition] = field(default_factory=list)
    actions: List[TriggerAction] = field(default_factory=list)
    status: TriggerStatus = TriggerStatus.ACTIVE
    one_shot: bool = False
    cooldown_seconds: int = 0
    max_fires: int = 0           # 0 = unlimited
    fire_count: int = 0
    last_fired_at: float = 0.0
    created_at: float = field(default_factory=time.time)
    expires_at: float = 0.0      # 0 = never
    tags: List[str] = field(default_factory=list)
    executions: List[TriggerExecution] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "trigger_id": self.trigger_id,
            "user_id": self.user_id,
            "name": self.name,
            "description": self.description,
            "event_type": self.event_type.value,
            "conditions": [c.to_dict() for c in self.conditions],
            "actions": [a.to_dict() for a in self.actions],
            "status": self.status.value,
            "one_shot": self.one_shot,
            "cooldown_seconds": self.cooldown_seconds,
            "max_fires": self.max_fires,
            "fire_count": self.fire_count,
            "last_fired_at": self.last_fired_at,
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "tags": self.tags,
            "executions": [e.to_dict() for e in self.executions[-50:]],
        }

    @classmethod
    def from_dict(cls, data: dict) -> Trigger:
        return cls(
            trigger_id=data["trigger_id"],
            user_id=data["user_id"],
            name=data["name"],
            description=data.get("description", ""),
            event_type=EventType(data["event_type"]),
            conditions=[TriggerCondition.from_dict(c) for c in data.get("conditions", [])],
            actions=[TriggerAction.from_dict(a) for a in data.get("actions", [])],
            status=TriggerStatus(data.get("status", "active")),
            one_shot=data.get("one_shot", False),
            cooldown_seconds=data.get("cooldown_seconds", 0),
            max_fires=data.get("max_fires", 0),
            fire_count=data.get("fire_count", 0),
            last_fired_at=data.get("last_fired_at", 0.0),
            created_at=data.get("created_at", time.time()),
            expires_at=data.get("expires_at", 0.0),
            tags=data.get("tags", []),
            executions=[],  # Don't reload full history
        )
