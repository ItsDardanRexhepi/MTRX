"""
Session Manager — tracks active sessions and handles token rotation.

Immediately disconnects active device sessions after token rotation,
preventing stale tokens from being used.
"""

from __future__ import annotations

import hashlib
import logging
import secrets
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class Session:
    """An active authenticated session."""
    session_id: str
    user_id: str
    token_hash: str               # SHA256 of the session token
    device_info: str = ""
    channel: str = ""             # telegram, slack, discord, etc.
    created_at: float = field(default_factory=time.time)
    last_active: float = field(default_factory=time.time)
    expires_at: float = 0.0
    revoked: bool = False

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "user_id": self.user_id,
            "device_info": self.device_info,
            "channel": self.channel,
            "created_at": self.created_at,
            "last_active": self.last_active,
            "revoked": self.revoked,
        }


class SessionManager:
    """
    Manages active sessions with immediate revocation on token rotation.

    When a token is rotated, ALL existing sessions for that user
    are immediately revoked — not just the one being replaced.
    This prevents the window where an old token could still be used.
    """

    SESSION_TIMEOUT: int = 86400      # 24 hours
    MAX_SESSIONS_PER_USER: int = 10

    def __init__(self) -> None:
        self._sessions: Dict[str, Session] = {}
        self._by_user: Dict[str, List[str]] = {}
        self._by_token: Dict[str, str] = {}  # token_hash -> session_id
        self._counter: int = 0
        logger.info("SessionManager initialised.")

    def create_session(
        self,
        user_id: str,
        token: str,
        device_info: str = "",
        channel: str = "",
        ttl: int = 0,
    ) -> Session:
        """Create a new authenticated session."""
        self._counter += 1
        session_id = f"SESS-{self._counter:08d}"
        token_hash = hashlib.sha256(token.encode()).hexdigest()

        # Enforce per-user limit
        user_sessions = self._by_user.get(user_id, [])
        if len(user_sessions) >= self.MAX_SESSIONS_PER_USER:
            # Revoke oldest session
            oldest_id = user_sessions[0]
            self.revoke_session(oldest_id)

        session = Session(
            session_id=session_id,
            user_id=user_id,
            token_hash=token_hash,
            device_info=device_info,
            channel=channel,
            expires_at=time.time() + (ttl or self.SESSION_TIMEOUT),
        )
        self._sessions[session_id] = session
        self._by_user.setdefault(user_id, []).append(session_id)
        self._by_token[token_hash] = session_id

        logger.info("Session created | id=%s | user=%s | channel=%s",
                     session_id, user_id, channel)
        return session

    def validate_token(self, token: str) -> Optional[Session]:
        """Validate a token and return its session, or None if invalid."""
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        session_id = self._by_token.get(token_hash)
        if session_id is None:
            return None

        session = self._sessions.get(session_id)
        if session is None or session.revoked:
            return None

        if session.expires_at > 0 and time.time() > session.expires_at:
            self.revoke_session(session_id)
            return None

        session.last_active = time.time()
        return session

    def rotate_token(self, user_id: str, new_token: str) -> Session:
        """
        Rotate a user's token — IMMEDIATELY revoke ALL existing sessions
        and create a new one with the new token.

        This is the key security improvement: no window where old tokens work.
        """
        # Revoke all existing sessions for this user
        revoked = self.revoke_all_user_sessions(user_id)
        if revoked:
            logger.info(
                "Token rotation: revoked %d active sessions for user %s",
                revoked, user_id,
            )

        # Create new session with the new token
        return self.create_session(user_id, new_token)

    def revoke_session(self, session_id: str) -> bool:
        """Revoke a single session immediately."""
        session = self._sessions.get(session_id)
        if session is None:
            return False
        session.revoked = True
        self._by_token.pop(session.token_hash, None)
        logger.info("Session revoked | id=%s | user=%s", session_id, session.user_id)
        return True

    def revoke_all_user_sessions(self, user_id: str) -> int:
        """Revoke ALL sessions for a user. Returns count revoked."""
        session_ids = self._by_user.get(user_id, [])
        count = 0
        for sid in list(session_ids):
            if self.revoke_session(sid):
                count += 1
        return count

    def get_user_sessions(self, user_id: str) -> List[Session]:
        """Get all active (non-revoked) sessions for a user."""
        session_ids = self._by_user.get(user_id, [])
        return [
            self._sessions[sid] for sid in session_ids
            if sid in self._sessions and not self._sessions[sid].revoked
        ]

    def cleanup_expired(self) -> int:
        """Remove expired and revoked sessions."""
        now = time.time()
        to_remove = []
        for sid, session in self._sessions.items():
            if session.revoked or (session.expires_at > 0 and now > session.expires_at):
                to_remove.append(sid)

        for sid in to_remove:
            session = self._sessions.pop(sid, None)
            if session:
                self._by_token.pop(session.token_hash, None)
                user_list = self._by_user.get(session.user_id, [])
                if sid in user_list:
                    user_list.remove(sid)

        return len(to_remove)

    def get_stats(self) -> dict:
        active = sum(1 for s in self._sessions.values() if not s.revoked)
        return {
            "total_sessions": len(self._sessions),
            "active_sessions": active,
            "unique_users": len(self._by_user),
        }
