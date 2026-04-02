"""Router for multi-channel management."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List

from runtime.channels import ChannelRegistry, ChannelType

router = APIRouter()
channel_registry = ChannelRegistry()


class SendMessageRequest(BaseModel):
    channel_type: str
    channel_id: str
    text: str
    reply_to: str = ""

class BroadcastRequest(BaseModel):
    text: str
    targets: List[dict]  # [{"type": "telegram", "id": "123"}, ...]


@router.get("/list")
async def list_channels():
    return {"channels": channel_registry.list_channels()}

@router.post("/send")
async def send_message(req: SendMessageRequest):
    try:
        msg = await channel_registry.send(
            ChannelType(req.channel_type), req.channel_id,
            req.text, reply_to=req.reply_to,
        )
        return msg.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.post("/broadcast")
async def broadcast(req: BroadcastRequest):
    results = await channel_registry.broadcast(req.text, req.targets)
    return {"sent": [m.to_dict() for m in results]}

@router.get("/stats")
async def channel_stats():
    return channel_registry.get_stats()
