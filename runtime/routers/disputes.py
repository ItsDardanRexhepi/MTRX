"""C30 - Disputes: on-chain dispute resolution, arbitration, and escrow release."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class DisputeRequest(BaseModel):
    transaction_id: str
    claimant_address: str
    respondent_address: str
    description: str
    evidence: list[dict]
    amount_in_dispute: float


class ResolutionRequest(BaseModel):
    dispute_id: str
    decision: str  # "claimant", "respondent", "split"
    reasoning: str
    split_percent: float | None = None


@router.post("/create")
async def create_dispute(request: DisputeRequest):
    """Open a new dispute for arbitration."""
    return {
        "dispute_id": "", "transaction_id": request.transaction_id,
        "amount": request.amount_in_dispute, "status": "open",
    }


@router.get("/{dispute_id}")
async def get_dispute(dispute_id: str):
    """Get dispute details and status."""
    return {"dispute_id": dispute_id, "status": "open", "evidence_count": 0, "arbitrator": None}


@router.post("/{dispute_id}/evidence")
async def submit_evidence(dispute_id: str, description: str, document_hash: str):
    """Submit additional evidence for a dispute."""
    return {"dispute_id": dispute_id, "evidence_id": "", "status": "submitted"}


@router.post("/resolve")
async def resolve_dispute(request: ResolutionRequest):
    """Resolve a dispute with an arbitration decision."""
    return {"dispute_id": request.dispute_id, "decision": request.decision, "status": "resolved"}


@router.get("/")
async def list_disputes(status: str | None = None):
    """List all disputes, optionally filtered by status."""
    return {"disputes": [], "total": 0, "filter": status}
