"""
ERC-8004 On-Chain Reputation Tracking
=======================================

Tracks and calculates reputation scores for agents using their ERC-8004
on-chain identity. Reputation is derived from on-chain activity history
and is publicly verifiable.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class ReputationEventType(Enum):
    """Categories of events that affect reputation."""
    TASK_COMPLETED = "task_completed"
    TASK_FAILED = "task_failed"
    PAYMENT_PROCESSED = "payment_processed"
    PAYMENT_DISPUTED = "payment_disputed"
    USER_UPVOTE = "user_upvote"
    USER_DOWNVOTE = "user_downvote"
    SECURITY_VIOLATION = "security_violation"
    SLA_MET = "sla_met"
    SLA_BREACHED = "sla_breached"


# Weights applied to each event type when computing the aggregate score.
EVENT_WEIGHTS: Dict[ReputationEventType, float] = {
    ReputationEventType.TASK_COMPLETED: 1.0,
    ReputationEventType.TASK_FAILED: -2.0,
    ReputationEventType.PAYMENT_PROCESSED: 0.5,
    ReputationEventType.PAYMENT_DISPUTED: -3.0,
    ReputationEventType.USER_UPVOTE: 0.8,
    ReputationEventType.USER_DOWNVOTE: -1.5,
    ReputationEventType.SECURITY_VIOLATION: -10.0,
    ReputationEventType.SLA_MET: 1.2,
    ReputationEventType.SLA_BREACHED: -2.5,
}


@dataclass
class ReputationEvent:
    """A single event that contributes to an agent's reputation."""
    event_type: ReputationEventType
    timestamp: datetime
    weight: float
    details: Dict[str, Any] = field(default_factory=dict)
    tx_hash: Optional[str] = None


@dataclass
class ReputationScore:
    """Aggregate reputation state for an agent."""
    agent_id: str
    score: Decimal
    total_events: int
    positive_events: int
    negative_events: int
    calculated_at: datetime
    confidence: float  # 0.0 – 1.0, rises with more events
    history_summary: Dict[str, int] = field(default_factory=dict)


class AgentReputation:
    """ERC-8004 on-chain reputation tracking for 0pnMatrx agents.

    Reputation scores are derived from on-chain event histories and are
    publicly verifiable.  The scoring algorithm applies event-type-specific
    weights and a time-decay factor so recent behaviour is emphasised.
    """

    # Reputation is clamped to [MIN_SCORE, MAX_SCORE].
    MIN_SCORE: Decimal = Decimal("0")
    MAX_SCORE: Decimal = Decimal("1000")
    INITIAL_SCORE: Decimal = Decimal("500")
    # Half-life (in days) for time-decay weighting.
    DECAY_HALF_LIFE_DAYS: float = 90.0

    def __init__(self) -> None:
        self._events: Dict[str, List[ReputationEvent]] = {}
        self._scores: Dict[str, ReputationScore] = {}
        logger.info("AgentReputation service initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_reputation(self, agent_id: str) -> ReputationScore:
        """Return the current reputation score for *agent_id*.

        If no score has been calculated yet a fresh one is computed from
        stored event history.

        Args:
            agent_id: ERC-8004 agent identifier.

        Returns:
            Current ``ReputationScore``.
        """
        if agent_id not in self._scores:
            history = self._events.get(agent_id, [])
            self._scores[agent_id] = self.calculate_score(history, agent_id)
        return self._scores[agent_id]

    def update_reputation(self, agent_id: str, event: ReputationEvent) -> ReputationScore:
        """Record a new event and recalculate the reputation score.

        Args:
            agent_id: ERC-8004 agent identifier.
            event: The reputation-relevant event to record.

        Returns:
            Updated ``ReputationScore``.

        Raises:
            ValueError: If the event is malformed.
        """
        self._validate_event(event)

        if agent_id not in self._events:
            self._events[agent_id] = []
        self._events[agent_id].append(event)

        self._record_event_on_chain(agent_id, event)

        score = self.calculate_score(self._events[agent_id], agent_id)
        self._scores[agent_id] = score
        logger.info(
            "Reputation updated for %s: score=%s (event=%s)",
            agent_id, score.score, event.event_type.value,
        )
        return score

    def calculate_score(
        self,
        agent_history: List[ReputationEvent],
        agent_id: str = "unknown",
    ) -> ReputationScore:
        """Calculate a reputation score from a list of historical events.

        The algorithm:
        1. Start from ``INITIAL_SCORE``.
        2. For each event, apply its weight scaled by a time-decay factor.
        3. Clamp the result to [MIN_SCORE, MAX_SCORE].
        4. Compute a confidence value in [0, 1] based on event volume.

        Args:
            agent_history: Ordered list of reputation events.
            agent_id: Agent identifier (used in the returned dataclass).

        Returns:
            Freshly computed ``ReputationScore``.
        """
        now = datetime.now(timezone.utc)
        running = float(self.INITIAL_SCORE)
        positive = 0
        negative = 0
        summary: Dict[str, int] = {}

        for event in agent_history:
            base_weight = EVENT_WEIGHTS.get(event.event_type, 0.0)
            age_days = max((now - event.timestamp).total_seconds() / 86400.0, 0.0)
            decay = math.exp(-math.log(2) * age_days / self.DECAY_HALF_LIFE_DAYS)
            delta = base_weight * event.weight * decay
            running += delta

            key = event.event_type.value
            summary[key] = summary.get(key, 0) + 1
            if base_weight >= 0:
                positive += 1
            else:
                negative += 1

        clamped = max(float(self.MIN_SCORE), min(running, float(self.MAX_SCORE)))
        total = len(agent_history)
        confidence = min(1.0, total / 100.0)  # saturates at 100 events

        return ReputationScore(
            agent_id=agent_id,
            score=Decimal(str(round(clamped, 2))),
            total_events=total,
            positive_events=positive,
            negative_events=negative,
            calculated_at=now,
            confidence=round(confidence, 4),
            history_summary=summary,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _validate_event(event: ReputationEvent) -> None:
        if event.weight <= 0:
            raise ValueError("ReputationEvent.weight must be positive")
        if not isinstance(event.event_type, ReputationEventType):
            raise ValueError(f"Invalid event type: {event.event_type}")

    @staticmethod
    def _record_event_on_chain(agent_id: str, event: ReputationEvent) -> None:
        """Persist the reputation event to the on-chain ERC-8004 record.

        Raises:
            RuntimeError: If the transaction fails.
        """
        try:
            # TODO: Replace with actual Web3 call to record reputation event
            logger.debug(
                "On-chain reputation event recorded for %s: %s",
                agent_id, event.event_type.value,
            )
        except Exception as exc:
            logger.error("Failed to record reputation event on-chain for %s: %s", agent_id, exc)
            raise RuntimeError(f"On-chain reputation recording failed for {agent_id}") from exc
