"""C26 - Brand Rewards: brand-specific reward campaigns and token incentives."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.brand_rewards.campaign_manager import (
    BrandCampaignManager, CampaignStatus, EligibilityMode,
)

router = APIRouter()

_manager = BrandCampaignManager()


class CampaignRequest(BaseModel):
    brand: str
    reward_token: str
    reward_per_user_wei: int
    max_claims: int
    start_time: float
    end_time: float
    eligibility_mode: str = "open"  # open, allowlist, zkp
    zkp_verifier: str = ""
    terms_uri: str = ""
    metadata_uri: str = ""
    initial_funding_wei: int = 0


class FundRequest(BaseModel):
    caller: str
    amount_wei: int


class AllowlistRequest(BaseModel):
    caller: str
    users: list[str]
    eligible: list[bool]


class ClaimRequest(BaseModel):
    user: str


@router.post("/campaign/create")
async def create_campaign(request: CampaignRequest):
    """Create a brand reward campaign."""
    try:
        c = _manager.create_campaign(
            brand=request.brand, reward_token=request.reward_token,
            reward_per_user_wei=request.reward_per_user_wei, max_claims=request.max_claims,
            start_time=request.start_time, end_time=request.end_time,
            eligibility_mode=EligibilityMode(request.eligibility_mode),
            zkp_verifier=request.zkp_verifier, terms_uri=request.terms_uri,
            metadata_uri=request.metadata_uri, initial_funding_wei=request.initial_funding_wei,
        )
        return {
            "campaign_id": c.campaign_id, "brand": c.brand,
            "reward_per_user_wei": c.reward_per_user_wei, "status": c.status.value,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/fund")
async def fund_campaign(campaign_id: str, request: FundRequest):
    """Add funds to a campaign."""
    try:
        c = _manager.fund_campaign(campaign_id, request.caller, request.amount_wei)
        return {"campaign_id": c.campaign_id, "total_budget_wei": c.total_budget_wei}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/allowlist")
async def update_allowlist(campaign_id: str, request: AllowlistRequest):
    """Update the campaign allowlist."""
    try:
        _manager.update_allowlist(campaign_id, request.caller, request.users, request.eligible)
        return {"campaign_id": campaign_id, "status": "updated"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/claim")
async def claim_reward(campaign_id: str, request: ClaimRequest):
    """Claim a brand reward."""
    try:
        amount = _manager.claim_reward(campaign_id, request.user)
        return {"campaign_id": campaign_id, "user": request.user, "reward_wei": amount}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/pause")
async def pause_campaign(campaign_id: str, caller: str):
    """Pause a campaign."""
    try:
        c = _manager.pause_campaign(campaign_id, caller)
        return {"campaign_id": c.campaign_id, "status": c.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/resume")
async def resume_campaign(campaign_id: str, caller: str):
    """Resume a paused campaign."""
    try:
        c = _manager.resume_campaign(campaign_id, caller)
        return {"campaign_id": c.campaign_id, "status": c.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/campaign/{campaign_id}/cancel")
async def cancel_campaign(campaign_id: str, caller: str):
    """Cancel a campaign."""
    try:
        c = _manager.cancel_campaign(campaign_id, caller)
        return {"campaign_id": c.campaign_id, "status": c.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/campaign/{campaign_id}")
async def get_campaign(campaign_id: str):
    """Get campaign details and distribution stats."""
    c = _manager.get_campaign(campaign_id)
    if c is None:
        raise HTTPException(status_code=404, detail="Campaign not found.")
    return {
        "campaign_id": c.campaign_id, "brand": c.brand,
        "total_budget_wei": c.total_budget_wei, "distributed_wei": c.distributed_wei,
        "total_claims": c.total_claims, "max_claims": c.max_claims,
        "status": c.status.value, "eligibility_mode": c.eligibility_mode.value,
    }


@router.get("/campaign/{campaign_id}/eligible/{user}")
async def check_eligibility(campaign_id: str, user: str):
    """Check if a user is eligible for a campaign."""
    return {"campaign_id": campaign_id, "user": user, "eligible": _manager.is_eligible(campaign_id, user)}
