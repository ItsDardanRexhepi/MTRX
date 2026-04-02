"""Router for event-based automation triggers."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from runtime.automation import TriggerEngine, EventType, ActionType, TriggerStatus
from runtime.automation.trigger_types import TriggerCondition, TriggerAction, ConditionOperator

router = APIRouter()
trigger_engine = TriggerEngine()


class ConditionModel(BaseModel):
    field: str
    operator: str
    value: object
    description: str = ""

class ActionModel(BaseModel):
    action_type: str
    params: dict = {}
    description: str = ""

class CreateTriggerRequest(BaseModel):
    user_id: str
    name: str
    description: str
    event_type: str
    conditions: List[ConditionModel] = []
    actions: List[ActionModel]
    one_shot: bool = False
    cooldown_seconds: int = 0
    max_fires: int = 0
    expires_at: float = 0.0
    tags: List[str] = []

class FireEventRequest(BaseModel):
    event_type: str
    source: str
    data: dict = {}
    user_id: str = ""


@router.post("/create")
async def create_trigger(req: CreateTriggerRequest):
    conditions = [
        TriggerCondition(
            field=c.field, operator=ConditionOperator(c.operator),
            value=c.value, description=c.description,
        )
        for c in req.conditions
    ]
    actions = [
        TriggerAction(
            action_type=ActionType(a.action_type),
            params=a.params, description=a.description,
        )
        for a in req.actions
    ]
    trigger = trigger_engine.create_trigger(
        user_id=req.user_id, name=req.name, description=req.description,
        event_type=EventType(req.event_type), conditions=conditions,
        actions=actions, one_shot=req.one_shot,
        cooldown_seconds=req.cooldown_seconds, max_fires=req.max_fires,
        expires_at=req.expires_at, tags=req.tags,
    )
    return trigger.to_dict()

@router.post("/fire")
async def fire_event(req: FireEventRequest):
    execs = trigger_engine.fire_event_simple(
        event_type=req.event_type, source=req.source,
        data=req.data, user_id=req.user_id,
    )
    return {"executions": [e.to_dict() for e in execs]}

@router.post("/{trigger_id}/pause")
async def pause_trigger(trigger_id: str):
    try:
        t = trigger_engine.pause_trigger(trigger_id)
        return t.to_dict()
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.post("/{trigger_id}/resume")
async def resume_trigger(trigger_id: str):
    try:
        t = trigger_engine.resume_trigger(trigger_id)
        return t.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.delete("/{trigger_id}")
async def delete_trigger(trigger_id: str):
    ok = trigger_engine.delete_trigger(trigger_id)
    if not ok:
        raise HTTPException(404, "Trigger not found.")
    return {"status": "deleted"}

@router.get("/{trigger_id}")
async def get_trigger(trigger_id: str):
    t = trigger_engine.get_trigger(trigger_id)
    if t is None:
        raise HTTPException(404, "Trigger not found.")
    return t.to_dict()

@router.get("/{trigger_id}/history")
async def trigger_history(trigger_id: str, limit: int = 20):
    try:
        execs = trigger_engine.get_trigger_history(trigger_id, limit)
        return {"executions": [e.to_dict() for e in execs]}
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.get("/user/{user_id}")
async def user_triggers(user_id: str, status: Optional[str] = None):
    s = TriggerStatus(status) if status else None
    triggers = trigger_engine.get_user_triggers(user_id, s)
    return {"triggers": [t.to_dict() for t in triggers]}

@router.get("/events/log")
async def event_log(limit: int = 50):
    return {"events": trigger_engine.get_event_log(limit)}

@router.get("/stats/summary")
async def trigger_stats():
    return trigger_engine.get_stats()
