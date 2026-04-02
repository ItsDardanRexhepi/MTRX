"""Router for autonomous goals engine."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from runtime.goals import GoalEngine, GoalStatus

router = APIRouter()
engine = GoalEngine()


class CreateGoalRequest(BaseModel):
    user_id: str
    title: str
    description: str
    agent_name: str = "neo"
    steps: Optional[List[str]] = None
    priority: str = "medium"
    deadline: float = 0.0
    check_interval: int = 3600
    tags: List[str] = []

class AddStepRequest(BaseModel):
    description: str
    depends_on: List[str] = []

class StepResultRequest(BaseModel):
    result: str = ""

class StepErrorRequest(BaseModel):
    error: str = ""

class UpdateRequest(BaseModel):
    update_text: str


@router.post("/create")
async def create_goal(req: CreateGoalRequest):
    goal = engine.create_goal(
        user_id=req.user_id, title=req.title, description=req.description,
        agent_name=req.agent_name, steps=req.steps, priority=req.priority,
        deadline=req.deadline, check_interval=req.check_interval, tags=req.tags,
    )
    return goal.to_dict()

@router.post("/{goal_id}/steps")
async def add_step(goal_id: str, req: AddStepRequest):
    try:
        step = engine.add_step(goal_id, req.description, req.depends_on)
        return step.to_dict()
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.post("/{goal_id}/steps/{step_id}/start")
async def start_step(goal_id: str, step_id: str):
    try:
        step = engine.start_step(goal_id, step_id)
        return step.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/steps/{step_id}/complete")
async def complete_step(goal_id: str, step_id: str, req: StepResultRequest):
    try:
        step = engine.complete_step(goal_id, step_id, req.result)
        return step.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/steps/{step_id}/fail")
async def fail_step(goal_id: str, step_id: str, req: StepErrorRequest):
    try:
        step = engine.fail_step(goal_id, step_id, req.error)
        return step.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/steps/{step_id}/skip")
async def skip_step(goal_id: str, step_id: str, reason: str = ""):
    try:
        step = engine.skip_step(goal_id, step_id, reason)
        return step.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/pause")
async def pause_goal(goal_id: str):
    try:
        goal = engine.pause_goal(goal_id)
        return goal.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/resume")
async def resume_goal(goal_id: str):
    try:
        goal = engine.resume_goal(goal_id)
        return goal.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/cancel")
async def cancel_goal(goal_id: str, reason: str = ""):
    try:
        goal = engine.cancel_goal(goal_id, reason)
        return goal.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/{goal_id}/update")
async def update_goal(goal_id: str, req: UpdateRequest):
    try:
        goal = engine.update_goal(goal_id, req.update_text)
        return goal.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.get("/{goal_id}")
async def get_goal(goal_id: str):
    goal = engine.get_goal(goal_id)
    if goal is None:
        raise HTTPException(404, "Goal not found.")
    return goal.to_dict()

@router.get("/{goal_id}/next-step")
async def next_step(goal_id: str):
    try:
        step = engine.get_next_step(goal_id)
        return step.to_dict() if step else {"step": None}
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.get("/user/{user_id}")
async def user_goals(user_id: str, status: Optional[str] = None):
    s = GoalStatus(status) if status else None
    goals = engine.get_user_goals(user_id, s)
    return {"goals": [g.to_dict() for g in goals]}

@router.get("/active/all")
async def active_goals():
    return {"goals": [g.to_dict() for g in engine.get_active_goals()]}

@router.get("/due/all")
async def due_goals():
    return {"goals": [g.to_dict() for g in engine.get_due_goals()]}

@router.get("/overdue/all")
async def overdue_goals():
    return {"goals": [g.to_dict() for g in engine.get_overdue_goals()]}

@router.get("/stats/summary")
async def goal_stats():
    return engine.get_stats()
