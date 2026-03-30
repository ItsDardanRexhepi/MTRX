"""C19 - Governance: protocol-level governance, voting, and parameter updates."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class ParameterChangeRequest(BaseModel):
    parameter: str
    current_value: str
    proposed_value: str
    justification: str


class GovernanceVoteRequest(BaseModel):
    proposal_id: str
    vote: str  # "yes", "no", "abstain"
    voter_address: str


@router.post("/proposal/create")
async def create_proposal(request: ParameterChangeRequest):
    """Create a protocol governance proposal."""
    return {"proposal_id": "", "parameter": request.parameter, "status": "voting"}


@router.get("/proposal/{proposal_id}")
async def get_proposal(proposal_id: str):
    """Get governance proposal details and vote tally."""
    return {"proposal_id": proposal_id, "status": "voting", "yes_votes": 0, "no_votes": 0}


@router.post("/vote")
async def vote_on_proposal(request: GovernanceVoteRequest):
    """Cast a governance vote."""
    return {"proposal_id": request.proposal_id, "voter": request.voter_address, "vote": request.vote, "status": "recorded"}


@router.get("/parameters")
async def list_parameters():
    """List all governable protocol parameters."""
    return {"parameters": [], "total": 0}


@router.get("/proposals")
async def list_proposals(status: str | None = None):
    """List governance proposals, optionally filtered by status."""
    return {"proposals": [], "total": 0, "filter": status}
