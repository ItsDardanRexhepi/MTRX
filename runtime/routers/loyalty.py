"""C23 - Loyalty: loyalty programs, points, and tier management."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class ProgramCreateRequest(BaseModel):
    name: str
    brand: str
    tiers: list[dict]
    points_per_dollar: float = 1.0


class PointsRequest(BaseModel):
    program_id: str
    member_address: str
    points: int
    reason: str


@router.post("/program/create")
async def create_program(request: ProgramCreateRequest):
    """Create a new loyalty program."""
    return {"program_id": "", "name": request.name, "brand": request.brand, "status": "active"}


@router.get("/program/{program_id}")
async def get_program(program_id: str):
    """Get loyalty program details."""
    return {"program_id": program_id, "name": "", "members": 0, "total_points_issued": 0}


@router.post("/points/award")
async def award_points(request: PointsRequest):
    """Award loyalty points to a member."""
    return {"program_id": request.program_id, "member": request.member_address, "points": request.points, "status": "awarded"}


@router.post("/points/redeem")
async def redeem_points(request: PointsRequest):
    """Redeem loyalty points."""
    return {"program_id": request.program_id, "member": request.member_address, "points": request.points, "status": "redeemed"}


@router.get("/member/{address}/balance")
async def get_member_balance(address: str, program_id: str | None = None):
    """Get loyalty points balance for a member."""
    return {"address": address, "balances": [], "total_points": 0}
