"""Router for proactive check-in system."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Tuple

from runtime.proactive import CheckInEngine, PatternTracker

router = APIRouter()
tracker = PatternTracker()
checkin_engine = CheckInEngine(pattern_tracker=tracker)


class RecordActivityRequest(BaseModel):
    user_id: str
    activity_type: str = "message"
    topics: List[str] = []

class CreateCheckInRequest(BaseModel):
    user_id: str
    checkin_type: str
    message: str
    context: dict = {}
    priority: int = 5
    expires_in: int = 0

class FollowUpRequest(BaseModel):
    user_id: str
    message: str
    delay_seconds: int = 3600
    context: dict = {}

class PreferencesRequest(BaseModel):
    user_id: str
    enabled: bool = True
    min_interval_hours: int = 4
    quiet_start: int = 22
    quiet_end: int = 7


@router.post("/activity")
async def record_activity(req: RecordActivityRequest):
    pattern = tracker.record_activity(req.user_id, req.activity_type, req.topics)
    return pattern.to_dict()

@router.get("/pattern/{user_id}")
async def get_pattern(user_id: str):
    pattern = tracker.get_pattern(user_id)
    if pattern is None:
        raise HTTPException(404, "No pattern data for user.")
    return pattern.to_dict()

@router.get("/absent")
async def get_absent_users():
    absent = tracker.get_absent_users()
    return {"absent_users": [{"user_id": uid, "hours_overdue": round(h, 1)} for uid, h in absent]}

@router.get("/best-hour/{user_id}")
async def best_checkin_hour(user_id: str):
    hour = tracker.get_best_checkin_hour(user_id)
    return {"user_id": user_id, "best_hour": hour}

@router.post("/create")
async def create_checkin(req: CreateCheckInRequest):
    from runtime.proactive.checkin_engine import CheckInType
    checkin = checkin_engine.create_checkin(
        user_id=req.user_id, checkin_type=CheckInType(req.checkin_type),
        message=req.message, context=req.context,
        priority=req.priority, expires_in=req.expires_in,
    )
    return checkin.to_dict()

@router.post("/followup")
async def schedule_followup(req: FollowUpRequest):
    checkin = checkin_engine.schedule_followup(
        user_id=req.user_id, message=req.message,
        delay_seconds=req.delay_seconds, context=req.context,
    )
    return checkin.to_dict()

@router.post("/scan")
async def scan():
    new = checkin_engine.scan_for_checkins()
    return {"new_checkins": [c.to_dict() for c in new]}

@router.post("/process")
async def process():
    sent = checkin_engine.process_pending()
    return {"sent": [c.to_dict() for c in sent]}

@router.post("/{checkin_id}/acknowledge")
async def acknowledge(checkin_id: str):
    c = checkin_engine.acknowledge(checkin_id)
    if c is None:
        raise HTTPException(404, "Check-in not found.")
    return c.to_dict()

@router.post("/{checkin_id}/dismiss")
async def dismiss(checkin_id: str):
    c = checkin_engine.dismiss(checkin_id)
    if c is None:
        raise HTTPException(404, "Check-in not found.")
    return c.to_dict()

@router.post("/preferences")
async def set_preferences(req: PreferencesRequest):
    prefs = checkin_engine.set_preferences(
        user_id=req.user_id, enabled=req.enabled,
        min_interval_hours=req.min_interval_hours,
        quiet_hours=(req.quiet_start, req.quiet_end),
    )
    return prefs

@router.get("/preferences/{user_id}")
async def get_preferences(user_id: str):
    return checkin_engine.get_preferences(user_id)

@router.get("/user/{user_id}")
async def user_checkins(user_id: str, status: Optional[str] = None, limit: int = 20):
    from runtime.proactive.checkin_engine import CheckInStatus
    s = CheckInStatus(status) if status else None
    checkins = checkin_engine.get_user_checkins(user_id, s, limit)
    return {"checkins": [c.to_dict() for c in checkins]}

@router.get("/stats/summary")
async def checkin_stats():
    return {
        "checkins": checkin_engine.get_stats(),
        "patterns": tracker.get_stats(),
    }
