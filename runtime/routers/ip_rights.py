"""C15 - IP Rights: intellectual property registration, licensing, and royalties."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class IPRegisterRequest(BaseModel):
    title: str
    ip_type: str  # patent, copyright, trademark
    description: str
    creator_address: str
    content_hash: str


class LicenseRequest(BaseModel):
    ip_id: str
    licensee_address: str
    terms: dict
    royalty_percent: float


@router.post("/register")
async def register_ip(request: IPRegisterRequest):
    """Register intellectual property on-chain."""
    return {"ip_id": "", "title": request.title, "type": request.ip_type, "status": "registered"}


@router.get("/{ip_id}")
async def get_ip(ip_id: str):
    """Get IP registration details."""
    return {"ip_id": ip_id, "title": "", "creator": "", "licenses": []}


@router.post("/license")
async def create_license(request: LicenseRequest):
    """Create a license for registered IP."""
    return {"license_id": "", "ip_id": request.ip_id, "licensee": request.licensee_address, "status": "active"}


@router.get("/{ip_id}/royalties")
async def get_royalties(ip_id: str):
    """Get royalty distribution history for an IP asset."""
    return {"ip_id": ip_id, "total_earned": 0, "distributions": []}


@router.get("/creator/{address}")
async def list_creator_ip(address: str):
    """List all IP registered by a creator."""
    return {"creator": address, "ip_assets": [], "total": 0}
