"""Router for persistent user memory."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from runtime.memory import UserMemoryStore
from runtime.memory.memory_types import MemoryCategory

router = APIRouter()
store = UserMemoryStore()


class RememberRequest(BaseModel):
    user_id: str
    key: str
    value: str
    category: str = "fact"
    confidence: float = 1.0
    tags: List[str] = []

class RecallRequest(BaseModel):
    user_id: str
    key: Optional[str] = None
    category: Optional[str] = None
    min_confidence: float = 0.0
    tags: Optional[List[str]] = None

class ContextRequest(BaseModel):
    user_id: str
    max_entries: int = 10

class SessionRequest(BaseModel):
    user_id: str
    topics: List[str] = []
    sentiment: str = "neutral"
    summary: str = ""
    message_count: int = 0
    key_decisions: List[str] = []


@router.post("/remember")
async def remember(req: RememberRequest):
    entry = store.remember(
        user_id=req.user_id, key=req.key, value=req.value,
        category=MemoryCategory(req.category), confidence=req.confidence, tags=req.tags,
    )
    return {"status": "remembered", "entry": entry.to_dict()}

@router.post("/recall")
async def recall(req: RecallRequest):
    cat = MemoryCategory(req.category) if req.category else None
    entries = store.recall(
        user_id=req.user_id, key=req.key, category=cat,
        min_confidence=req.min_confidence, tags=req.tags,
    )
    return {"entries": [e.to_dict() for e in entries]}

@router.post("/forget")
async def forget(user_id: str, key: str):
    ok = store.forget(user_id, key)
    if not ok:
        raise HTTPException(404, "Memory not found.")
    return {"status": "forgotten"}

@router.post("/context")
async def context(req: ContextRequest):
    ctx = store.get_context_summary(req.user_id, max_items=req.max_entries)
    return {"context": ctx}

@router.post("/session/start")
async def start_session(user_id: str):
    store.start_session(user_id)
    return {"status": "session_started"}

@router.post("/session/end")
async def end_session(req: SessionRequest):
    store.end_session(
        user_id=req.user_id, topics=req.topics, sentiment=req.sentiment,
        summary=req.summary, message_count=req.message_count,
        key_decisions=req.key_decisions,
    )
    return {"status": "session_ended"}

@router.get("/profile/{user_id}")
async def get_profile(user_id: str):
    profile = store.get_profile(user_id)
    if profile is None:
        raise HTTPException(404, "User not found.")
    return profile.to_dict()

@router.post("/decay")
async def decay(user_id: str):
    store.decay_confidence(user_id)
    return {"status": "decay_applied"}

@router.get("/stats")
async def stats():
    return store.get_stats()
