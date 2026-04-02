"""Router for skills marketplace."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from runtime.skills import SkillsRegistry

router = APIRouter()
registry = SkillsRegistry()


class ExecuteSkillRequest(BaseModel):
    name: str
    context: dict = {}
    agent: str = ""


@router.get("/list")
async def list_skills(agent: str = ""):
    return {"skills": registry.list_skills(agent)}

@router.post("/execute")
async def execute_skill(req: ExecuteSkillRequest):
    result = await registry.execute_skill(req.name, req.context, req.agent)
    if not result.get("success"):
        raise HTTPException(400, result.get("error", "Skill execution failed."))
    return result

@router.post("/reload")
async def reload_skills():
    count = registry.reload()
    return {"reloaded": count}

@router.get("/stats")
async def skills_stats():
    return registry.get_stats()
