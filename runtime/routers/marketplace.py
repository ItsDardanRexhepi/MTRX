"""C24 - Marketplace: peer-to-peer listings, offers, and escrow."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class ListingRequest(BaseModel):
    title: str
    description: str
    price: float
    asset: str = "USDC"
    category: str
    seller_address: str


class OfferRequest(BaseModel):
    listing_id: str
    buyer_address: str
    amount: float


@router.post("/listing/create")
async def create_listing(request: ListingRequest):
    """Create a marketplace listing."""
    return {"listing_id": "", "title": request.title, "price": request.price, "status": "active"}


@router.get("/listing/{listing_id}")
async def get_listing(listing_id: str):
    """Get listing details."""
    return {"listing_id": listing_id, "title": "", "price": 0, "seller": "", "status": "active"}


@router.post("/offer")
async def make_offer(request: OfferRequest):
    """Make an offer on a listing."""
    return {"offer_id": "", "listing_id": request.listing_id, "amount": request.amount, "status": "pending"}


@router.post("/offer/{offer_id}/accept")
async def accept_offer(offer_id: str):
    """Accept an offer and initiate escrow."""
    return {"offer_id": offer_id, "escrow_id": "", "status": "in_escrow"}


@router.get("/listings")
async def list_listings(category: str | None = None):
    """Browse marketplace listings."""
    return {"listings": [], "total": 0, "category": category}
