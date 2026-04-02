"""C22 - Fundraising: milestone-based community fundraising campaigns."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.fundraising.campaign_manager import CampaignManager, CampaignStatus
from runtime.blockchain.services.fundraising.vesting_engine import VestingType
from runtime.blockchain.services.fundraising.milestone_tracker import VerificationMethod

router = APIRouter()

_manager = CampaignManager()


class CampaignRequest(BaseModel):
    recipient: str
    goal_wei: int
    deadline: float
    vesting_type: str = "immediate"  # immediate, milestone_based, time_based, hybrid
    verification_method: str = "oracle"  # oracle, contributor_vote
    vesting_duration: int = 0
    vesting_cliff: int = 0


class MilestoneRequest(BaseModel):
    description: str
    release_amount_wei: int
    vote_deadline: float = 0.0


class ContributionRequest(BaseModel):
    contributor: str
    amount_wei: int


@router.post("/campaign/create")
async def create_campaign(request: CampaignRequest):
    """Create a fundraising campaign."""
    try:
        c = _manager.create_campaign(
            recipient=request.recipient, goal_wei=request.goal_wei,
            deadline=request.deadline, vesting_type=VestingType(request.vesting_type),
            verification_method=VerificationMethod(request.verification_method),
            vesting_duration=request.vesting_duration, vesting_cliff=request.vesting_cliff,
        )
        return {
            "campaign_id": c.campaign_id, "recipient": c.recipient,
            "goal_wei": c.goal_wei, "status": c.status.value,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/milestone")
async def add_milestone(campaign_id: str, request: MilestoneRequest):
    """Add a milestone to a campaign."""
    try:
        _manager.add_milestone(campaign_id, request.description, request.release_amount_wei, request.vote_deadline)
        return {"campaign_id": campaign_id, "status": "milestone_added"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/contribute")
async def contribute(request: ContributionRequest):
    """Contribute to a fundraising campaign."""
    try:
        # campaign_id from query param
        raise HTTPException(status_code=400, detail="Use /campaign/{id}/contribute")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/contribute")
async def contribute_to_campaign(campaign_id: str, request: ContributionRequest):
    """Contribute to a specific campaign."""
    try:
        c = _manager.contribute(campaign_id, request.contributor, request.amount_wei)
        return {
            "campaign_id": c.campaign_id, "total_raised_wei": c.total_raised_wei,
            "goal_wei": c.goal_wei, "status": c.status.value,
            "contributor_count": c.contributor_count,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/release")
async def release_funds(campaign_id: str):
    """Release vested funds to the recipient."""
    try:
        amount = _manager.release_funds(campaign_id)
        return {"campaign_id": campaign_id, "released_wei": amount}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/refund")
async def claim_refund(campaign_id: str, contributor: str):
    """Claim a refund from a failed campaign."""
    try:
        amount = _manager.claim_refund(campaign_id, contributor)
        return {"campaign_id": campaign_id, "contributor": contributor, "refund_wei": amount}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/campaign/{campaign_id}")
async def get_campaign(campaign_id: str):
    """Get campaign details and progress."""
    c = _manager.get_campaign(campaign_id)
    if c is None:
        raise HTTPException(status_code=404, detail="Campaign not found.")
    return {
        "campaign_id": c.campaign_id, "recipient": c.recipient,
        "goal_wei": c.goal_wei, "total_raised_wei": c.total_raised_wei,
        "total_released_wei": c.total_released_wei, "status": c.status.value,
        "contributor_count": c.contributor_count,
        "vesting_type": c.vesting_type.value,
    }


@router.get("/campaigns")
async def list_campaigns(status: Optional[str] = None):
    """List all fundraising campaigns."""
    s = CampaignStatus(status) if status else None
    campaigns = _manager.list_campaigns(status=s)
    return {
        "campaigns": [
            {"campaign_id": c.campaign_id, "goal_wei": c.goal_wei, "raised_wei": c.total_raised_wei, "status": c.status.value}
            for c in campaigns
        ],
        "total": len(campaigns),
    }
