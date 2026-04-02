"""C24 - Marketplace: peer-to-peer listings, offers, and escrow."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.marketplace.marketplace_service import (
    MarketplaceService, ListingStatus,
)

router = APIRouter()

_service = MarketplaceService()


class ListERC721Request(BaseModel):
    seller: str
    asset_contract: str
    token_id: int
    price_wei: int


class ListERC1155Request(BaseModel):
    seller: str
    asset_contract: str
    token_id: int
    amount: int
    price_per_unit_wei: int


class PurchaseRequest(BaseModel):
    buyer: str


class AttestationRequest(BaseModel):
    caller: str
    attestation_uid: str


@router.post("/listing/erc721")
async def list_erc721(request: ListERC721Request):
    """List an ERC721 asset for sale."""
    try:
        l = _service.list_erc721(request.seller, request.asset_contract, request.token_id, request.price_wei)
        return {"listing_id": l.listing_id, "seller": l.seller, "price_wei": l.price_per_unit_wei, "status": l.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/listing/erc1155")
async def list_erc1155(request: ListERC1155Request):
    """List ERC1155 assets for sale."""
    try:
        l = _service.list_erc1155(request.seller, request.asset_contract, request.token_id, request.amount, request.price_per_unit_wei)
        return {"listing_id": l.listing_id, "seller": l.seller, "amount": l.amount, "price_per_unit_wei": l.price_per_unit_wei, "status": l.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/listing/{listing_id}/purchase")
async def purchase(listing_id: str, request: PurchaseRequest):
    """Purchase a listed asset."""
    try:
        p = _service.purchase(listing_id, request.buyer)
        return {
            "listing_id": p.listing_id, "buyer": p.buyer,
            "total_price_wei": p.total_price_wei, "platform_fee_wei": p.platform_fee_wei,
            "seller_proceeds_wei": p.seller_proceeds_wei,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/listing/{listing_id}/cancel")
async def cancel_listing(listing_id: str, caller: str):
    """Cancel a listing."""
    try:
        l = _service.cancel_listing(listing_id, caller)
        return {"listing_id": l.listing_id, "status": l.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/listing/{listing_id}/attestation")
async def attach_attestation(listing_id: str, request: AttestationRequest):
    """Attach an EAS attestation to a listing."""
    try:
        l = _service.attach_attestation(listing_id, request.caller, request.attestation_uid)
        return {"listing_id": l.listing_id, "eas_attestation": l.eas_attestation}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/listing/{listing_id}")
async def get_listing(listing_id: str):
    """Get listing details."""
    l = _service.get_listing(listing_id)
    if l is None:
        raise HTTPException(status_code=404, detail="Listing not found.")
    return {
        "listing_id": l.listing_id, "seller": l.seller,
        "asset_contract": l.asset_contract, "token_id": l.token_id,
        "amount": l.amount, "price_per_unit_wei": l.price_per_unit_wei,
        "standard": l.standard.value, "status": l.status.value,
        "eas_attestation": l.eas_attestation,
    }


@router.get("/listings")
async def list_listings(status: Optional[str] = None):
    """Browse marketplace listings."""
    s = ListingStatus(status) if status else None
    listings = _service.list_listings(status=s)
    return {
        "listings": [
            {"listing_id": l.listing_id, "seller": l.seller, "price_per_unit_wei": l.price_per_unit_wei, "status": l.status.value}
            for l in listings
        ],
        "total": len(listings),
    }


@router.get("/stats")
async def marketplace_stats():
    """Get marketplace trading statistics."""
    return {"total_volume_wei": _service.get_total_volume_wei(), "total_fees_wei": _service.get_total_fees_wei()}
