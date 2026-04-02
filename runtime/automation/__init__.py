"""
Event-Based Automation — when X happens do Y, defined through conversation.

Users define triggers via natural language. The engine matches events
against registered triggers and executes actions automatically.
"""

from runtime.automation.trigger_engine import TriggerEngine
from runtime.automation.trigger_types import (
    Trigger, TriggerCondition, TriggerAction, TriggerStatus,
    EventType, ActionType, Event,
)

__all__ = [
    "TriggerEngine", "Trigger", "TriggerCondition", "TriggerAction",
    "TriggerStatus", "EventType", "ActionType", "Event",
]
