"""C27 - Subscriptions: recurring on-chain payment subscriptions."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class SubscriptionCreateRequest(BaseModel):
    plan_name: str
    price: float
    asset: str = "USDC"
    interval_days: int = 30
    merchant_address: str


class SubscribeRequest(BaseModel):
    plan_id: str
    subscriber_address: str


@router.post("/plan/create")
async def create_plan(request: SubscriptionCreateRequest):
    """Create a subscription plan."""
    return {"plan_id": "", "name": request.plan_name, "price": request.price, "interval": request.interval_days, "status": "active"}


@router.get("/plan/{plan_id}")
async def get_plan(plan_id: str):
    """Get subscription plan details."""
    return {"plan_id": plan_id, "name": "", "price": 0, "subscribers": 0}


@router.post("/subscribe")
async def subscribe(request: SubscribeRequest):
    """Subscribe to a plan."""
    return {"subscription_id": "", "plan_id": request.plan_id, "subscriber": request.subscriber_address, "status": "active"}


@router.post("/subscription/{subscription_id}/cancel")
async def cancel_subscription(subscription_id: str):
    """Cancel a subscription."""
    return {"subscription_id": subscription_id, "status": "cancelled"}


@router.get("/subscriber/{address}")
async def list_subscriptions(address: str):
    """List all subscriptions for a subscriber."""
    return {"address": address, "subscriptions": [], "total": 0}
