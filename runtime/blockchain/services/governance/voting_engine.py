"""
Component 19 — Voting Engine

Implements all three voting models:
  1. One-Person-One-Vote
  2. Token-Weighted
  3. Quadratic

Quorum: valid when all PARTICIPATING voters have cast.
Non-voters are NOT counted toward quorum. Result valid regardless of participation level.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


class VotingModel(Enum):
    """The three supported voting models. Once chosen, the selection is PERMANENT."""
    ONE_PERSON_ONE_VOTE = "one_person_one_vote"
    TOKEN_WEIGHTED = "token_weighted"
    QUADRATIC = "quadratic"


class VoteChoice(Enum):
    """Possible vote choices."""
    FOR = "for"
    AGAINST = "against"
    ABSTAIN = "abstain"


@dataclass
class VoteRecord:
    """Individual vote record."""
    voter: str
    proposal_id: str
    choice: VoteChoice
    weight: int
    model_used: VotingModel
    cast_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    eas_attestation_uid: Optional[str] = None


@dataclass
class VotingSession:
    """Tracks voting state for a single proposal."""
    proposal_id: str
    model: VotingModel
    votes: Dict[str, VoteRecord] = field(default_factory=dict)
    voters: Set[str] = field(default_factory=set)
    total_weight_for: int = 0
    total_weight_against: int = 0
    total_weight_abstain: int = 0
    closed: bool = False


class VotingEngine:
    """
    Manages vote casting across all three models with participation-based quorum.

    Quorum logic:
    - A vote is valid as long as at least 1 person participates.
    - Non-voters are never counted. Only those who actually vote matter.
    - Result is valid regardless of how many people chose to vote.
    """

    def __init__(
        self,
        active_model: VotingModel,
        token_balances: Optional[Dict[str, int]] = None,
    ) -> None:
        """
        Initialize the voting engine.

        Args:
            active_model: The permanently chosen voting model.
            token_balances: Mapping of address -> token balance (for weighted/quadratic).
        """
        self.active_model = active_model
        self._token_balances: Dict[str, int] = token_balances or {}
        self._sessions: Dict[str, VotingSession] = {}
        logger.info("VotingEngine initialized | model=%s", active_model.value)

    # ──────────────────── Session Management ──────────────

    def create_session(self, proposal_id: str) -> VotingSession:
        """Create a new voting session for a proposal."""
        if proposal_id in self._sessions:
            raise ValueError(f"Voting session already exists for proposal {proposal_id}.")

        session = VotingSession(proposal_id=proposal_id, model=self.active_model)
        self._sessions[proposal_id] = session
        logger.info("Voting session created | proposal=%s | model=%s", proposal_id, self.active_model.value)
        return session

    def get_session(self, proposal_id: str) -> Optional[VotingSession]:
        """Retrieve a voting session."""
        return self._sessions.get(proposal_id)

    # ──────────────────── Vote Casting ────────────────────

    def cast_vote(
        self,
        proposal_id: str,
        voter: str,
        choice: VoteChoice,
    ) -> VoteRecord:
        """
        Cast a vote on a proposal.

        Weight is calculated based on the active model:
        - OnePersonOneVote: weight = 1
        - TokenWeighted: weight = token balance
        - Quadratic: weight = floor(sqrt(token balance))

        Args:
            proposal_id: The proposal to vote on.
            voter: Address of the voter.
            choice: For, Against, or Abstain.

        Returns:
            The VoteRecord created.

        Raises:
            ValueError: If already voted, session not found, or session closed.
        """
        session = self._sessions.get(proposal_id)
        if session is None:
            raise ValueError(f"No voting session for proposal {proposal_id}.")
        if session.closed:
            raise ValueError(f"Voting session for proposal {proposal_id} is closed.")
        if voter in session.voters:
            raise ValueError(f"Voter {voter} has already voted on proposal {proposal_id}.")

        weight = self._calculate_weight(voter)

        record = VoteRecord(
            voter=voter,
            proposal_id=proposal_id,
            choice=choice,
            weight=weight,
            model_used=self.active_model,
        )

        # Record the vote
        session.votes[voter] = record
        session.voters.add(voter)

        if choice == VoteChoice.FOR:
            session.total_weight_for += weight
        elif choice == VoteChoice.AGAINST:
            session.total_weight_against += weight
        else:
            session.total_weight_abstain += weight

        logger.info(
            "Vote cast | proposal=%s | voter=%s | choice=%s | weight=%d | model=%s",
            proposal_id, voter, choice.value, weight, self.active_model.value,
        )
        return record

    # ──────────────────── Quorum & Results ────────────────

    def check_quorum(self, proposal_id: str) -> Dict[str, Any]:
        """
        Check quorum status. Quorum is MET as long as at least 1 voter participated.
        Non-voters are NOT counted.

        Returns:
            Dict with quorum status and participation details.
        """
        session = self._sessions.get(proposal_id)
        if session is None:
            raise ValueError(f"No voting session for proposal {proposal_id}.")

        participant_count = len(session.voters)
        quorum_met = participant_count > 0

        return {
            "proposal_id": proposal_id,
            "quorum_met": quorum_met,
            "total_participants": participant_count,
            "total_weight_for": session.total_weight_for,
            "total_weight_against": session.total_weight_against,
            "total_weight_abstain": session.total_weight_abstain,
            "note": "Quorum based on participating voters only. Non-voters not counted.",
        }

    def get_result(self, proposal_id: str) -> Dict[str, Any]:
        """
        Get the final result of a vote.

        Returns:
            Result dict including pass/fail, all tallies, and participation.
        """
        session = self._sessions.get(proposal_id)
        if session is None:
            raise ValueError(f"No voting session for proposal {proposal_id}.")

        participant_count = len(session.voters)
        passed = session.total_weight_for > session.total_weight_against

        return {
            "proposal_id": proposal_id,
            "model": self.active_model.value,
            "passed": passed,
            "votes_for": session.total_weight_for,
            "votes_against": session.total_weight_against,
            "votes_abstain": session.total_weight_abstain,
            "total_participants": participant_count,
            "quorum_met": participant_count > 0,
        }

    def close_session(self, proposal_id: str) -> Dict[str, Any]:
        """Close a voting session and return the final result."""
        session = self._sessions.get(proposal_id)
        if session is None:
            raise ValueError(f"No voting session for proposal {proposal_id}.")
        if session.closed:
            raise ValueError(f"Session for proposal {proposal_id} already closed.")

        session.closed = True
        result = self.get_result(proposal_id)
        logger.info(
            "Voting session closed | proposal=%s | passed=%s | participants=%d",
            proposal_id, result["passed"], result["total_participants"],
        )
        return result

    # ──────────────────── Token Balance Management ────────

    def set_token_balance(self, voter: str, balance: int) -> None:
        """Set governance token balance for a voter."""
        if balance < 0:
            raise ValueError("Token balance cannot be negative.")
        self._token_balances[voter] = balance
        logger.debug("Token balance set | voter=%s | balance=%d", voter, balance)

    def get_token_balance(self, voter: str) -> int:
        """Get governance token balance for a voter."""
        return self._token_balances.get(voter, 0)

    # ──────────────────── Queries ─────────────────────────

    def get_voter_record(self, proposal_id: str, voter: str) -> Optional[VoteRecord]:
        """Get a specific voter's record for a proposal."""
        session = self._sessions.get(proposal_id)
        if session is None:
            return None
        return session.votes.get(voter)

    def has_voted(self, proposal_id: str, voter: str) -> bool:
        """Check if a voter has already voted on a proposal."""
        session = self._sessions.get(proposal_id)
        if session is None:
            return False
        return voter in session.voters

    def list_voters(self, proposal_id: str) -> List[str]:
        """List all voters for a proposal."""
        session = self._sessions.get(proposal_id)
        if session is None:
            return []
        return list(session.voters)

    # ──────────────────── Internal ────────────────────────

    def _calculate_weight(self, voter: str) -> int:
        """
        Calculate vote weight based on the active model.

        - ONE_PERSON_ONE_VOTE: always 1
        - TOKEN_WEIGHTED: token balance
        - QUADRATIC: floor(sqrt(token balance))
        """
        if self.active_model == VotingModel.ONE_PERSON_ONE_VOTE:
            return 1

        balance = self._token_balances.get(voter, 0)
        if balance <= 0:
            raise ValueError(
                f"Voter {voter} has no governance tokens. "
                f"Token balance required for {self.active_model.value} voting."
            )

        if self.active_model == VotingModel.TOKEN_WEIGHTED:
            return balance

        # Quadratic: floor(sqrt(balance))
        return int(math.floor(math.sqrt(balance)))
