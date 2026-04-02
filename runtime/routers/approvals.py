"""Router for exec approval system."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.approvals import ApprovalManager, ApprovalStatus

router = APIRouter()
approval_mgr = ApprovalManager()


class RequestApprovalRequest(BaseModel):
    agent: str = "neo"
    title: str
    description: str
    risk_level: str = "normal"
    timeout_seconds: int = 1800

class RespondRequest(BaseModel):
    approved: bool
    note: str = ""


@router.post("/request")
async def request_approval(req: RequestApprovalRequest):
    approval = await approval_mgr.request_approval(
        agent=req.agent, title=req.title, description=req.description,
        risk_level=req.risk_level, timeout_seconds=req.timeout_seconds,
    )
    return approval.to_dict()

@router.post("/{request_id}/respond")
async def respond(request_id: str, req: RespondRequest):
    try:
        approval = approval_mgr.respond(request_id, req.approved, req.note)
        return approval.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.get("/pending")
async def pending_approvals():
    return {"pending": [r.to_dict() for r in approval_mgr.get_pending()]}

@router.get("/history")
async def approval_history(limit: int = 20):
    return {"approvals": [r.to_dict() for r in approval_mgr.get_history(limit)]}

@router.get("/{request_id}")
async def get_approval(request_id: str):
    r = approval_mgr.get_request(request_id)
    if r is None:
        raise HTTPException(404, "Approval request not found.")
    return r.to_dict()

@router.post("/expire-stale")
async def expire_stale():
    expired = approval_mgr.expire_stale()
    return {"expired": len(expired)}

@router.get("/stats")
async def approval_stats():
    return approval_mgr.get_stats()
