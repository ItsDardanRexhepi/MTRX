"""
Voting Engine — commit-reveal voting for dispute resolution.

Part of Component 30 (Dispute Resolution).
Jurors commit vote hashes, then reveal their votes. Tallying determines outcome.
"""

from __future__ import annotations

import hashlib
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Set, Tuple

logger = logging.getLogger(__name__)


class Vote(Enum):
    """Possible votes in a dispute."""
    NONE = "none"
    CLAIMANT = "claimant"
    RESPONDENT = "respondent"


@dataclass
class JurorVote:
    """A juror's vote record for a dispute."""
    juror: str
    commit_hash: str = ""
    revealed_vote: Vote = Vote.NONE
    committed: bool = False
    revealed: bool = False
    committed_at: float = 0.0
    revealed_at: float = 0.0


@dataclass
class TallyResult:
    """Result of tallying votes for a dispute."""
    dispute_id: str
    claimant_votes: int
    respondent_votes: int
    total_votes: int
    outcome: Vote
    tallied_at: float = field(default_factory=time.time)


class VotingEngine:
    """
    Commit-reveal voting system for disputes.

    Phase 1 (Commit): Jurors submit hash(vote + salt).
    Phase 2 (Reveal): Jurors reveal vote and salt; engine verifies hash.
    Phase 3 (Tally): Count revealed votes, determine outcome by majority.
    """

    def __init__(self) -> None:
        # dispute_id -> { juror_address -> JurorVote }
        self._votes: Dict[str, Dict[str, JurorVote]] = {}
        self._tallies: Dict[str, TallyResult] = {}
        logger.info("VotingEngine initialised.")

    def init_voting(self, dispute_id: str, jurors: List[str]) -> None:
        """
        Initialize voting for a dispute with selected jurors.

        Args:
            dispute_id: The dispute being voted on.
            jurors: List of juror addresses selected for this dispute.
        """
        self._votes[dispute_id] = {
            addr: JurorVote(juror=addr) for addr in jurors
        }
        logger.info(
            "Voting initialised | dispute=%s | jurors=%d",
            dispute_id, len(jurors),
        )

    def commit_vote(
        self,
        dispute_id: str,
        juror: str,
        commit_hash: str,
    ) -> None:
        """
        Record a juror's vote commitment.

        Args:
            dispute_id: The dispute.
            juror: Juror address.
            commit_hash: Hash of (vote + salt).

        Raises:
            ValueError: If juror not assigned or already committed.
        """
        vote_record = self._get_vote(dispute_id, juror)
        if vote_record.committed:
            raise ValueError(
                f"Juror {juror} already committed for dispute {dispute_id}."
            )
        vote_record.commit_hash = commit_hash
        vote_record.committed = True
        vote_record.committed_at = time.time()
        logger.info(
            "Vote committed | dispute=%s | juror=%s", dispute_id, juror,
        )

    def reveal_vote(
        self,
        dispute_id: str,
        juror: str,
        vote: Vote,
        salt: str,
    ) -> None:
        """
        Reveal a juror's vote and verify against commitment.

        Args:
            dispute_id: The dispute.
            juror: Juror address.
            vote: The actual vote.
            salt: The salt used in the commitment.

        Raises:
            ValueError: If not committed, already revealed, or hash mismatch.
        """
        vote_record = self._get_vote(dispute_id, juror)
        if not vote_record.committed:
            raise ValueError(f"Juror {juror} has not committed a vote.")
        if vote_record.revealed:
            raise ValueError(f"Juror {juror} already revealed.")
        if vote == Vote.NONE:
            raise ValueError("Cannot reveal a NONE vote.")

        # Verify commitment hash
        expected_hash = self._compute_hash(vote, salt)
        if expected_hash != vote_record.commit_hash:
            raise ValueError(
                f"Reveal hash mismatch for juror {juror}. "
                f"Commitment does not match vote + salt."
            )

        vote_record.revealed_vote = vote
        vote_record.revealed = True
        vote_record.revealed_at = time.time()
        logger.info(
            "Vote revealed | dispute=%s | juror=%s | vote=%s",
            dispute_id, juror, vote.value,
        )

    def tally(self, dispute_id: str) -> TallyResult:
        """
        Tally all revealed votes for a dispute.

        Args:
            dispute_id: The dispute to tally.

        Returns:
            TallyResult with vote counts and outcome.

        Raises:
            ValueError: If no votes exist for dispute.
        """
        votes = self._votes.get(dispute_id)
        if votes is None:
            raise ValueError(f"No voting record for dispute {dispute_id}.")

        claimant_count = 0
        respondent_count = 0
        for vr in votes.values():
            if vr.revealed:
                if vr.revealed_vote == Vote.CLAIMANT:
                    claimant_count += 1
                elif vr.revealed_vote == Vote.RESPONDENT:
                    respondent_count += 1

        total = claimant_count + respondent_count
        if claimant_count > respondent_count:
            outcome = Vote.CLAIMANT
        elif respondent_count > claimant_count:
            outcome = Vote.RESPONDENT
        else:
            # Tie defaults to respondent (status quo)
            outcome = Vote.RESPONDENT

        result = TallyResult(
            dispute_id=dispute_id,
            claimant_votes=claimant_count,
            respondent_votes=respondent_count,
            total_votes=total,
            outcome=outcome,
        )
        self._tallies[dispute_id] = result
        logger.info(
            "Votes tallied | dispute=%s | claimant=%d | respondent=%d | outcome=%s",
            dispute_id, claimant_count, respondent_count, outcome.value,
        )
        return result

    def get_committed_jurors(self, dispute_id: str) -> List[str]:
        """Return addresses of jurors who have committed."""
        votes = self._votes.get(dispute_id, {})
        return [addr for addr, vr in votes.items() if vr.committed]

    def get_revealed_jurors(self, dispute_id: str) -> List[str]:
        """Return addresses of jurors who have revealed."""
        votes = self._votes.get(dispute_id, {})
        return [addr for addr, vr in votes.items() if vr.revealed]

    def get_non_revealers(self, dispute_id: str) -> List[str]:
        """Return addresses of jurors who committed but did not reveal."""
        votes = self._votes.get(dispute_id, {})
        return [
            addr for addr, vr in votes.items()
            if vr.committed and not vr.revealed
        ]

    def get_tally(self, dispute_id: str) -> Optional[TallyResult]:
        """Get tally result if available."""
        return self._tallies.get(dispute_id)

    @staticmethod
    def compute_commit_hash(vote: Vote, salt: str) -> str:
        """
        Compute the commitment hash for a vote.
        Public utility so jurors can generate their commitment.
        """
        return VotingEngine._compute_hash(vote, salt)

    @staticmethod
    def _compute_hash(vote: Vote, salt: str) -> str:
        """Compute keccak-style hash of vote + salt."""
        payload = f"{vote.value}:{salt}"
        return hashlib.sha256(payload.encode()).hexdigest()

    def _get_vote(self, dispute_id: str, juror: str) -> JurorVote:
        """Get a juror's vote record or raise."""
        votes = self._votes.get(dispute_id)
        if votes is None:
            raise ValueError(f"No voting record for dispute {dispute_id}.")
        vr = votes.get(juror)
        if vr is None:
            raise ValueError(
                f"Juror {juror} not assigned to dispute {dispute_id}."
            )
        return vr
