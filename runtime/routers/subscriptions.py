"""C27 - Subscriptions: recurring on-chain payment subscriptions."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.subscriptions.subscription_manager import SubscriptionManager
from runtime.blockchain.services.subscriptions.tier_registry import Frequency

router = APIRouter()

_manager = SubscriptionManager()


class TierCreateRequest(BaseModel):
    creator: str
    payment_token: str
    price_wei: int
    frequency: str  # "daily", "weekly", "monthly", "quarterly", "annually", "custom"
    name: str
    metadata_uri: str = ""
    custom_period: int = 0


class SubscribeRequest(BaseModel):
    subscriber_address: str
    tier_id: str
    auto_renew: bool = True


class CancelRequest(BaseModel):
    caller: str


@router.post("/tier/create")
async def create_tier(request: TierCreateRequest):
    """Create a subscription tier."""
    try:
        freq = Frequency(request.frequency)
        tier = _manager.create_tier(
            creator=request.creator, payment_token=request.payment_token,
            price_wei=request.price_wei, frequency=freq, name=request.name,
            metadata_uri=request.metadata_uri, custom_period=request.custom_period,
        )
        return {
            "tier_id": tier.tier_id, "name": tier.name, "price_wei": tier.price_wei,
            "frequency": tier.frequency.value, "active": tier.active,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/tier/{tier_id}")
async def get_tier(tier_id: str):
    """Get subscription tier details."""
    tier = _manager._tiers.get_tier(tier_id)
    if tier is None:
        raise HTTPException(status_code=404, detail="Tier not found.")
    return {
        "tier_id": tier.tier_id, "creator": tier.creator, "name": tier.name,
        "price_wei": tier.price_wei, "frequency": tier.frequency.value,
        "subscriber_count": tier.subscriber_count, "active": tier.active,
    }


@router.post("/subscribe")
async def subscribe(request: SubscribeRequest):
    """Subscribe to a tier."""
    try:
        sub = _manager.subscribe(request.subscriber_address, request.tier_id, request.auto_renew)
        return {
            "subscription_id": sub.subscription_id, "tier_id": sub.tier_id,
            "subscriber": sub.subscriber, "expires_at": sub.expires_at,
            "auto_renew": sub.auto_renew, "status": "active",
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/subscription/{subscription_id}/renew")
async def renew_subscription(subscription_id: str):
    """Renew a subscription."""
    try:
        sub = _manager.renew(subscription_id)
        return {
            "subscription_id": sub.subscription_id, "expires_at": sub.expires_at,
            "renewal_count": sub.renewal_count, "total_paid_wei": sub.total_paid_wei,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/subscription/{subscription_id}/cancel")
async def cancel_subscription(subscription_id: str, request: CancelRequest):
    """Cancel a subscription."""
    try:
        sub = _manager.cancel_subscription(subscription_id, request.caller)
        return {"subscription_id": sub.subscription_id, "status": "cancelled"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/subscription/{subscription_id}")
async def get_subscription(subscription_id: str):
    """Get subscription details."""
    sub = _manager.get_subscription(subscription_id)
    if sub is None:
        raise HTTPException(status_code=404, detail="Subscription not found.")
    status = _manager.get_status(subscription_id)
    return {
        "subscription_id": sub.subscription_id, "tier_id": sub.tier_id,
        "subscriber": sub.subscriber, "expires_at": sub.expires_at,
        "auto_renew": sub.auto_renew, "status": status.value,
        "total_paid_wei": sub.total_paid_wei, "renewal_count": sub.renewal_count,
    }


@router.get("/subscriber/{address}")
async def list_subscriptions(address: str):
    """List all subscriptions for a subscriber."""
    subs = _manager.get_subscriber_history(address)
    return {
        "address": address,
        "subscriptions": [
            {"subscription_id": s.subscription_id, "tier_id": s.tier_id, "status": _manager.get_status(s.subscription_id).value}
            for s in subs
        ],
        "total": len(subs),
    }
