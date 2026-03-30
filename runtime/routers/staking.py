"""C16 - Staking: token staking, delegation, and reward distribution."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class StakeRequest(BaseModel):
    amount: float
    validator: str | None = None
    lock_period_days: int = 30


class UnstakeRequest(BaseModel):
    stake_id: str
    amount: float


@router.post("/stake")
async def stake_tokens(request: StakeRequest):
    """Stake tokens for rewards."""
    return {"stake_id": "", "amount": request.amount, "validator": request.validator, "status": "staked"}


@router.post("/unstake")
async def unstake_tokens(request: UnstakeRequest):
    """Unstake tokens (subject to unbonding period)."""
    return {"stake_id": request.stake_id, "amount": request.amount, "status": "unbonding"}


@router.get("/rewards/{address}")
async def get_rewards(address: str):
    """Get pending staking rewards for an address."""
    return {"address": address, "pending_rewards": 0, "claimed_rewards": 0}


@router.post("/rewards/{address}/claim")
async def claim_rewards(address: str):
    """Claim accumulated staking rewards."""
    return {"address": address, "claimed_amount": 0, "status": "claimed"}


@router.get("/validators")
async def list_validators():
    """List all active validators and their stats."""
    return {"validators": [], "total_staked": 0}
