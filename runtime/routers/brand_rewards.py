"""C26 - Brand Rewards: brand-specific reward campaigns and token incentives."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class CampaignRequest(BaseModel):
    brand: str
    name: str
    reward_token: str
    total_budget: float
    reward_per_action: float
    eligible_actions: list[str]


class RewardClaimRequest(BaseModel):
    campaign_id: str
    user_address: str
    action: str
    proof: dict


@router.post("/campaign/create")
async def create_campaign(request: CampaignRequest):
    """Create a brand reward campaign."""
    return {"campaign_id": "", "brand": request.brand, "name": request.name, "status": "active"}


@router.get("/campaign/{campaign_id}")
async def get_campaign(campaign_id: str):
    """Get campaign details and distribution stats."""
    return {"campaign_id": campaign_id, "distributed": 0, "remaining_budget": 0, "participants": 0}


@router.post("/claim")
async def claim_reward(request: RewardClaimRequest):
    """Claim a brand reward for completing an action."""
    return {"claim_id": "", "campaign_id": request.campaign_id, "reward_amount": 0, "status": "pending"}


@router.get("/user/{address}/rewards")
async def get_user_rewards(address: str):
    """Get all brand rewards earned by a user."""
    return {"address": address, "rewards": [], "total_value": 0}


@router.get("/campaigns")
async def list_campaigns(brand: str | None = None):
    """List active brand reward campaigns."""
    return {"campaigns": [], "total": 0}
