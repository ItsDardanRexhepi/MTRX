"""Router for inline code execution."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.execution import CodeSandbox, Language

router = APIRouter()
sandbox = CodeSandbox()


class ExecuteRequest(BaseModel):
    code: str
    language: str = "python"
    user_id: str = ""
    timeout: int = 0


@router.post("/run")
async def execute(req: ExecuteRequest):
    try:
        lang = Language(req.language)
    except ValueError:
        raise HTTPException(400, f"Unsupported language: {req.language}. Supported: python, javascript, shell")
    result = sandbox.execute(
        code=req.code, language=lang,
        user_id=req.user_id, timeout=req.timeout,
    )
    return result.to_dict()

@router.post("/python")
async def run_python(req: ExecuteRequest):
    result = sandbox.execute_python(req.code, req.user_id, req.timeout)
    return result.to_dict()

@router.get("/history")
async def history(user_id: str = "", limit: int = 20):
    return {"history": sandbox.get_history(user_id, limit)}

@router.get("/stats")
async def execution_stats():
    return sandbox.get_stats()
