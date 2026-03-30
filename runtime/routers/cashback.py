"""C25 - Cashback: transaction-based cashback rewards and distribution."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class CashbackProgramRequest(BaseModel):
    name: str
    merchant: str
    cashback_percent: float
    max_per_transaction: float
    asset: str = "USDC"


class CashbackClaimRequest(BaseModel):
    program_id: str
    transaction_hash: str
    amount: float


@router.post("/program/create")
async def create_program(request: CashbackProgramRequest):
    """Create a cashback rewards program."""
    return {"program_id": "", "name": request.name, "cashback_percent": request.cashback_percent, "status": "active"}


@router.get("/program/{program_id}")
async def get_program(program_id: str):
    """Get cashback program details."""
    return {"program_id": program_id, "name": "", "total_distributed": 0, "status": "active"}


@router.post("/claim")
async def claim_cashback(request: CashbackClaimRequest):
    """Claim cashback for a qualifying transaction."""
    return {"claim_id": "", "program_id": request.program_id, "cashback_amount": 0, "status": "pending"}


@router.get("/balance/{address}")
async def get_cashback_balance(address: str):
    """Get accumulated cashback balance for an address."""
    return {"address": address, "pending": 0, "claimed": 0, "total_earned": 0}
