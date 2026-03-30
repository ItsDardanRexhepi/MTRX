"""C22 - Fundraising: token launches, IDOs, and crowdfunding campaigns."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class CampaignRequest(BaseModel):
    name: str
    description: str
    goal_amount: float
    token_symbol: str
    token_price: float
    duration_days: int


class ContributionRequest(BaseModel):
    campaign_id: str
    amount: float
    contributor_address: str


@router.post("/campaign/create")
async def create_campaign(request: CampaignRequest):
    """Create a fundraising campaign."""
    return {"campaign_id": "", "name": request.name, "goal": request.goal_amount, "status": "active"}


@router.get("/campaign/{campaign_id}")
async def get_campaign(campaign_id: str):
    """Get campaign details and progress."""
    return {"campaign_id": campaign_id, "raised": 0, "goal": 0, "contributors": 0, "status": "active"}


@router.post("/contribute")
async def contribute(request: ContributionRequest):
    """Contribute to a fundraising campaign."""
    return {"campaign_id": request.campaign_id, "amount": request.amount, "tokens_allocated": 0, "status": "confirmed"}


@router.get("/campaigns")
async def list_campaigns(status: str | None = None):
    """List all fundraising campaigns."""
    return {"campaigns": [], "total": 0}
