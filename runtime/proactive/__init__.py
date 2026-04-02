"""
Proactive Check-Ins — Trinity reaches out to users based on learned patterns.

Learns user activity patterns, detects absence or routine changes,
and initiates contextual check-ins via the agent system.
"""

from runtime.proactive.checkin_engine import CheckInEngine
from runtime.proactive.pattern_tracker import PatternTracker, UserPattern

__all__ = ["CheckInEngine", "PatternTracker", "UserPattern"]
