"""
Approval Manager — manages exec approval requests across channels.

Sends plain-language approval requests to the designated approver.
Tracks responses with timeout. No developer jargon in user-facing messages.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID = "7161847911"
DEFAULT_TIMEOUT_SECONDS = 1800  # 30 minutes


class ApprovalStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXPIRED = "expired"
    CANCELLED = "cancelled"


@dataclass
class ApprovalRequest:
    """A request for human approval of an agent action."""
    request_id: str
    agent: str                     # Which agent is asking
    title: str                     # Plain-language title
    description: str               # What the agent wants to do and why
    risk_level: str = "normal"     # low, normal, high, critical
    approver_id: str = DARDAN_TELEGRAM_ID
    status: ApprovalStatus = ApprovalStatus.PENDING
    channel_type: str = "telegram"
    message_id: str = ""           # Channel message ID for the request
    response_note: str = ""        # Approver's note
    created_at: float = field(default_factory=time.time)
    responded_at: float = 0.0
    expires_at: float = 0.0
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "request_id": self.request_id,
            "agent": self.agent,
            "title": self.title,
            "description": self.description,
            "risk_level": self.risk_level,
            "approver_id": self.approver_id,
            "status": self.status.value,
            "channel_type": self.channel_type,
            "response_note": self.response_note,
            "created_at": self.created_at,
            "responded_at": self.responded_at,
            "expires_at": self.expires_at,
        }

    @property
    def is_expired(self) -> bool:
        return self.expires_at > 0 and time.time() > self.expires_at


_AGENT_LABELS = {"neo": "Neo", "trinity": "Trinity", "morpheus": "Morpheus"}

_RISK_ICONS = {
    "low": "🟢",
    "normal": "🟡",
    "high": "🟠",
    "critical": "🔴",
}


class ApprovalManager:
    """
    Manages approval requests with plain-language descriptions.

    When an agent needs approval:
    1. Creates a request with a clear, non-technical description
    2. Sends it to Dardan via the configured channel
    3. Waits up to 30 minutes for a response
    4. Returns the result to the requesting agent

    Better than OpenClaw: the approval request is readable by
    someone who is not a developer.
    """

    def __init__(
        self,
        send_fn: Optional[Callable] = None,
        storage_dir: str = "",
    ) -> None:
        """
        Args:
            send_fn: async callable(approver_id, text, reply_markup) to send approval messages.
            storage_dir: Directory for persistence.
        """
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "approvals"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._requests: Dict[str, ApprovalRequest] = {}
        self._send_fn = send_fn
        self._counter: int = 0
        self._load_all()
        logger.info("ApprovalManager initialised | pending=%d",
                     sum(1 for r in self._requests.values() if r.status == ApprovalStatus.PENDING))

    async def request_approval(
        self,
        agent: str,
        title: str,
        description: str,
        risk_level: str = "normal",
        timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
        metadata: Optional[dict] = None,
    ) -> ApprovalRequest:
        """
        Create and send an approval request.

        Args:
            agent: Which agent is requesting (neo, trinity, morpheus).
            title: Plain-language title of what the agent wants to do.
            description: Full description readable by a non-developer.
            risk_level: low, normal, high, critical.
            timeout_seconds: How long to wait (default 30 minutes).
            metadata: Extra context data.

        Returns:
            The created ApprovalRequest.
        """
        self._counter += 1
        req_id = f"APRV-{self._counter:08d}"

        request = ApprovalRequest(
            request_id=req_id,
            agent=agent,
            title=title,
            description=description,
            risk_level=risk_level,
            expires_at=time.time() + timeout_seconds,
            metadata=metadata or {},
        )
        self._requests[req_id] = request

        # Format the approval message in plain language
        agent_name = _AGENT_LABELS.get(agent, agent.title())
        risk_icon = _RISK_ICONS.get(risk_level, "🟡")
        msg = (
            f"{risk_icon} *{agent_name} needs your approval*\n\n"
            f"*What:* {title}\n\n"
            f"{description}\n\n"
            f"_This request expires in {timeout_seconds // 60} minutes._\n"
            f"_Request ID: {req_id}_"
        )

        # Send via channel
        if self._send_fn:
            try:
                await self._send_fn(
                    DARDAN_TELEGRAM_ID, msg,
                    {"inline_keyboard": [[
                        {"text": "✅ Yes, do it", "callback_data": f"approve:{req_id}"},
                        {"text": "❌ No", "callback_data": f"reject:{req_id}"},
                    ]]},
                )
            except Exception:
                logger.exception("Failed to send approval request | id=%s", req_id)

        self._persist(req_id)
        logger.info(
            "Approval requested | id=%s | agent=%s | title=%s",
            req_id, agent, title,
        )
        return request

    def respond(
        self, request_id: str, approved: bool, note: str = "",
    ) -> ApprovalRequest:
        """Record an approval response."""
        request = self._requests.get(request_id)
        if request is None:
            raise ValueError(f"Approval request {request_id} not found.")

        if request.status != ApprovalStatus.PENDING:
            raise ValueError(f"Request {request_id} already {request.status.value}.")

        if request.is_expired:
            request.status = ApprovalStatus.EXPIRED
            self._persist(request_id)
            raise ValueError(f"Request {request_id} has expired.")

        request.status = ApprovalStatus.APPROVED if approved else ApprovalStatus.REJECTED
        request.responded_at = time.time()
        request.response_note = note
        self._persist(request_id)

        logger.info(
            "Approval %s | id=%s | agent=%s",
            "granted" if approved else "denied", request_id, request.agent,
        )
        return request

    async def wait_for_approval(
        self, request_id: str, poll_interval: float = 2.0,
    ) -> ApprovalRequest:
        """Wait for an approval response, polling until resolved or expired."""
        while True:
            request = self._requests.get(request_id)
            if request is None:
                raise ValueError(f"Request {request_id} not found.")

            if request.status != ApprovalStatus.PENDING:
                return request

            if request.is_expired:
                request.status = ApprovalStatus.EXPIRED
                self._persist(request_id)
                return request

            await asyncio.sleep(poll_interval)

    def expire_stale(self) -> List[ApprovalRequest]:
        """Expire any pending requests past their timeout."""
        expired = []
        for request in self._requests.values():
            if request.status == ApprovalStatus.PENDING and request.is_expired:
                request.status = ApprovalStatus.EXPIRED
                self._persist(request.request_id)
                expired.append(request)
        return expired

    # ── Queries ──────────────────────────────────────────────────────

    def get_request(self, request_id: str) -> Optional[ApprovalRequest]:
        return self._requests.get(request_id)

    def get_pending(self) -> List[ApprovalRequest]:
        return [r for r in self._requests.values() if r.status == ApprovalStatus.PENDING]

    def get_history(self, limit: int = 20) -> List[ApprovalRequest]:
        reqs = sorted(self._requests.values(), key=lambda r: r.created_at, reverse=True)
        return reqs[:limit]

    def get_stats(self) -> dict:
        by_status = {}
        for r in self._requests.values():
            by_status[r.status.value] = by_status.get(r.status.value, 0) + 1
        return {
            "total": len(self._requests),
            "by_status": by_status,
        }

    # ── Persistence ──────────────────────────────────────────────────

    def _persist(self, request_id: str) -> None:
        request = self._requests.get(request_id)
        if request is None:
            return
        path = self._storage_dir / f"{request_id}.json"
        try:
            with open(path, "w") as f:
                json.dump(request.to_dict(), f, indent=2)
        except Exception:
            logger.exception("Failed to persist approval | id=%s", request_id)

    def _load_all(self) -> None:
        for path in self._storage_dir.glob("APRV-*.json"):
            try:
                with open(path) as f:
                    data = json.load(f)
                req = ApprovalRequest(
                    request_id=data["request_id"],
                    agent=data["agent"],
                    title=data["title"],
                    description=data["description"],
                    risk_level=data.get("risk_level", "normal"),
                    approver_id=data.get("approver_id", DARDAN_TELEGRAM_ID),
                    status=ApprovalStatus(data.get("status", "pending")),
                    channel_type=data.get("channel_type", "telegram"),
                    response_note=data.get("response_note", ""),
                    created_at=data.get("created_at", 0),
                    responded_at=data.get("responded_at", 0),
                    expires_at=data.get("expires_at", 0),
                )
                self._requests[req.request_id] = req
                num = int(req.request_id.split("-")[1])
                self._counter = max(self._counter, num)
            except Exception:
                logger.exception("Failed to load approval | file=%s", path)
