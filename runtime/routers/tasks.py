"""Router for background task control plane."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from runtime.tasks import TaskLedger, TaskStatus, TaskType

router = APIRouter()
ledger = TaskLedger()


class CreateTaskRequest(BaseModel):
    task_type: str = "agent"
    agent: str = "neo"
    title: str
    description: str
    user_id: str = ""
    timeout_seconds: int = 3600
    tags: List[str] = []

class CreateFlowRequest(BaseModel):
    name: str
    description: str
    agent: str = "neo"
    task_descriptions: List[str]
    user_id: str = ""

class UpdateProgressRequest(BaseModel):
    progress_pct: float
    plain_status: str = ""


@router.post("/create")
async def create_task(req: CreateTaskRequest):
    task = ledger.create_task(
        task_type=TaskType(req.task_type), agent=req.agent,
        title=req.title, description=req.description,
        user_id=req.user_id, timeout_seconds=req.timeout_seconds, tags=req.tags,
    )
    return task.to_dict()

@router.post("/{task_id}/start")
async def start_task(task_id: str):
    try:
        return ledger.start_task(task_id).to_dict()
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.post("/{task_id}/progress")
async def update_progress(task_id: str, req: UpdateProgressRequest):
    try:
        return ledger.update_progress(task_id, req.progress_pct, req.plain_status).to_dict()
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.post("/{task_id}/complete")
async def complete_task(task_id: str, result: str = ""):
    try:
        return ledger.complete_task(task_id, result).to_dict()
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.post("/{task_id}/fail")
async def fail_task(task_id: str, error: str = ""):
    try:
        return ledger.fail_task(task_id, error).to_dict()
    except ValueError as e:
        raise HTTPException(404, str(e))

@router.post("/{task_id}/cancel")
async def cancel_task(task_id: str):
    try:
        return ledger.cancel_task(task_id).to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.get("/summary")
async def task_summary():
    return ledger.get_summary()

@router.get("/active")
async def active_tasks():
    return {"tasks": [t.to_dict() for t in ledger.list_active_tasks()]}

@router.get("/list")
async def list_tasks(agent: str = "", status: Optional[str] = None, limit: int = 50):
    s = TaskStatus(status) if status else None
    return {"tasks": [t.to_dict() for t in ledger.list_tasks(agent, s, limit=limit)]}

@router.get("/{task_id}")
async def get_task(task_id: str):
    task = ledger.get_task(task_id)
    if task is None:
        raise HTTPException(404, "Task not found.")
    return task.to_dict()

@router.post("/flows/create")
async def create_flow(req: CreateFlowRequest):
    flow = ledger.create_flow(
        name=req.name, description=req.description, agent=req.agent,
        task_descriptions=req.task_descriptions, user_id=req.user_id,
    )
    return flow.to_dict()

@router.get("/flows/list")
async def list_flows():
    return {"flows": [f.to_dict() for f in ledger.list_flows()]}

@router.get("/flows/{flow_id}")
async def get_flow(flow_id: str):
    flow = ledger.get_flow(flow_id)
    if flow is None:
        raise HTTPException(404, "Flow not found.")
    return flow.to_dict()

@router.post("/maintenance/cleanup")
async def cleanup():
    count = ledger.cleanup_old_tasks()
    return {"cleaned": count}

@router.post("/maintenance/detect-lost")
async def detect_lost():
    lost = ledger.detect_lost_tasks()
    return {"lost_tasks": [t.to_dict() for t in lost]}

@router.get("/stats/summary")
async def task_stats():
    return ledger.get_stats()
