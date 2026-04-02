"""C25 - Cashback: annual power-user cashback rewards."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.cashback.cashback_engine import CashbackEngine

router = APIRouter()

_engine = CashbackEngine()


class RecordSpendRequest(BaseModel):
    recorder: str
    user: str
    year: int
    amount_usd: int


class RecordRevenueRequest(BaseModel):
    recorder: str
    user: str
    year: int
    amount_wei: int


class FundRequest(BaseModel):
    year: int
    amount_wei: int


class AllocateRequest(BaseModel):
    users: list[str]
    year: int


class ClaimRequest(BaseModel):
    user: str
    year: int


@router.post("/recorder/add")
async def add_recorder(address: str):
    """Add an authorized spend/revenue recorder."""
    try:
        _engine.add_recorder(address)
        return {"address": address, "status": "added"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/spend/record")
async def record_spend(request: RecordSpendRequest):
    """Record a user's spend for a year."""
    try:
        _engine.record_spend(request.recorder, request.user, request.year, request.amount_usd)
        return {"user": request.user, "year": request.year, "status": "recorded"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/revenue/record")
async def record_revenue(request: RecordRevenueRequest):
    """Record net revenue attributed to a user."""
    try:
        _engine.record_net_revenue(request.recorder, request.user, request.year, request.amount_wei)
        return {"user": request.user, "year": request.year, "status": "recorded"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/fund")
async def fund_distribution(request: FundRequest):
    """Fund the reward pool for a year."""
    try:
        dist = _engine.fund_distribution(request.year, request.amount_wei)
        return {"year": request.year, "pool_balance_wei": dist.reward_pool_balance_wei, "funded": dist.funded}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/enable/{year}")
async def enable_distribution(year: int):
    """Enable claiming for a year."""
    try:
        dist = _engine.enable_distribution(year)
        return {"year": year, "enabled": dist.enabled}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/allocate")
async def batch_allocate(request: AllocateRequest):
    """Batch allocate rewards to qualifying users."""
    results = _engine.batch_allocate_rewards(request.users, request.year)
    return {"year": request.year, "allocated": results, "count": len(results)}


@router.post("/claim")
async def claim_reward(request: ClaimRequest):
    """Claim cashback reward for a year."""
    try:
        amount = _engine.claim_reward(request.user, request.year)
        return {"user": request.user, "year": request.year, "claimed_wei": amount}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/qualified/{user}/{year}")
async def check_qualified(user: str, year: int):
    """Check if a user qualifies for cashback."""
    return {"user": user, "year": year, "qualified": _engine.is_qualified(user, year)}


@router.get("/reward/{user}/{year}")
async def get_reward(user: str, year: int):
    """Get allocated reward for a user and year."""
    return {"user": user, "year": year, "reward_wei": _engine.get_reward(user, year)}


@router.get("/distribution/{year}")
async def get_distribution(year: int):
    """Get distribution info for a year."""
    dist = _engine.get_distribution(year)
    if dist is None:
        raise HTTPException(status_code=404, detail="No distribution for this year.")
    return {
        "year": dist.year, "pool_balance_wei": dist.reward_pool_balance_wei,
        "total_claimed_wei": dist.total_claimed_wei, "funded": dist.funded, "enabled": dist.enabled,
    }
