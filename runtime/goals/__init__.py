"""
Autonomous Goals Engine — long-running goals that Neo works on over hours or days.

Users define goals in conversation. The engine tracks progress, schedules
work steps, and reports back asynchronously.
"""

from runtime.goals.goal_engine import GoalEngine
from runtime.goals.goal_types import Goal, GoalStatus, GoalStep, StepStatus

__all__ = ["GoalEngine", "Goal", "GoalStatus", "GoalStep", "StepStatus"]
