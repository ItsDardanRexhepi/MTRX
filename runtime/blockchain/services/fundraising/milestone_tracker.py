"""
Milestone Tracker — manages campaign milestones with verification.

Part of Component 22 (Community Fundraising).
Supports oracle verification and contributor voting for milestone approval.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Set

logger = logging.getLogger(__name__)


class MilestoneStatus(Enum):
    """Status of a campaign milestone."""
    PENDING = "pending"
    VERIFIED = "verified"
    REJECTED = "rejected"


class VerificationMethod(Enum):
    """How milestones are verified."""
    ORACLE = "oracle"
    CONTRIBUTOR_VOTE = "contributor_vote"


@dataclass
class Milestone:
    """A campaign milestone with release amount."""
    milestone_id: str
    campaign_id: str
    description: str
    release_amount_wei: int
    status: MilestoneStatus = MilestoneStatus.PENDING
    vote_deadline: float = 0.0
    votes_for: int = 0
    votes_against: int = 0
    created_at: float = field(default_factory=time.time)
    resolved_at: float = 0.0


class MilestoneTracker:
    """
    Tracks milestones per campaign and handles verification.

    Verification modes:
    - Oracle: A trusted oracle address verifies or rejects.
    - ContributorVote: Contributors vote, majority decides.
    """

    DEFAULT_VOTE_QUORUM_PCT: int = 50
    DEFAULT_VOTE_PERIOD_SECONDS: int = 5 * 86_400  # 5 days

    def __init__(self, vote_quorum_pct: int = DEFAULT_VOTE_QUORUM_PCT) -> None:
        self._milestones: Dict[str, Milestone] = {}
        self._by_campaign: Dict[str, List[str]] = {}
        self._voters: Dict[str, Set[str]] = {}  # milestone_id -> set of voter addrs
        self._vote_quorum_pct = vote_quorum_pct
        self._counter: int = 0
        logger.info("MilestoneTracker initialised | quorum=%d%%.", vote_quorum_pct)

    def add_milestone(
        self,
        campaign_id: str,
        description: str,
        release_amount_wei: int,
        vote_deadline: float = 0.0,
    ) -> Milestone:
        """
        Add a milestone to a campaign.

        Args:
            campaign_id: The campaign this milestone belongs to.
            description: Description of the milestone.
            release_amount_wei: Funds released on verification.
            vote_deadline: Deadline for contributor voting (0 = default).

        Returns:
            The created Milestone.
        """
        if not description:
            raise ValueError("Milestone description must not be empty.")
        if release_amount_wei <= 0:
            raise ValueError("Release amount must be positive.")

        self._counter += 1
        mid = f"MS-{self._counter:08d}"
        now = time.time()

        if vote_deadline <= 0:
            vote_deadline = now + self.DEFAULT_VOTE_PERIOD_SECONDS

        milestone = Milestone(
            milestone_id=mid,
            campaign_id=campaign_id,
            description=description,
            release_amount_wei=release_amount_wei,
            vote_deadline=vote_deadline,
        )
        self._milestones[mid] = milestone
        self._by_campaign.setdefault(campaign_id, []).append(mid)
        self._voters[mid] = set()

        logger.info(
            "Milestone added | id=%s | campaign=%s | release=%d",
            mid, campaign_id, release_amount_wei,
        )
        return milestone

    def oracle_verify(self, milestone_id: str) -> Milestone:
        """Verify a milestone via oracle (trusted call)."""
        ms = self._get_milestone(milestone_id)
        if ms.status != MilestoneStatus.PENDING:
            raise ValueError(f"Milestone {milestone_id} is not pending.")
        ms.status = MilestoneStatus.VERIFIED
        ms.resolved_at = time.time()
        logger.info("Milestone oracle-verified | id=%s", milestone_id)
        return ms

    def oracle_reject(self, milestone_id: str) -> Milestone:
        """Reject a milestone via oracle."""
        ms = self._get_milestone(milestone_id)
        if ms.status != MilestoneStatus.PENDING:
            raise ValueError(f"Milestone {milestone_id} is not pending.")
        ms.status = MilestoneStatus.REJECTED
        ms.resolved_at = time.time()
        logger.info("Milestone oracle-rejected | id=%s", milestone_id)
        return ms

    def vote(
        self, milestone_id: str, voter: str, in_favor: bool,
    ) -> Milestone:
        """
        Cast a contributor vote on a milestone.

        Args:
            milestone_id: The milestone to vote on.
            voter: Contributor's address.
            in_favor: True for approve, False for reject.
        """
        ms = self._get_milestone(milestone_id)
        if ms.status != MilestoneStatus.PENDING:
            raise ValueError(f"Milestone {milestone_id} is not pending.")
        now = time.time()
        if now > ms.vote_deadline:
            raise ValueError("Voting deadline has passed.")
        if voter in self._voters[milestone_id]:
            raise ValueError(f"Voter {voter} already voted on {milestone_id}.")

        self._voters[milestone_id].add(voter)
        if in_favor:
            ms.votes_for += 1
        else:
            ms.votes_against += 1

        logger.info(
            "Vote cast | milestone=%s | voter=%s | favor=%s",
            milestone_id, voter, in_favor,
        )
        return ms

    def tally_vote(
        self, milestone_id: str, total_contributors: int,
    ) -> Milestone:
        """
        Tally votes and determine milestone status.

        Args:
            milestone_id: The milestone to tally.
            total_contributors: Total number of eligible voters.
        """
        ms = self._get_milestone(milestone_id)
        if ms.status != MilestoneStatus.PENDING:
            raise ValueError(f"Milestone {milestone_id} already resolved.")

        total_votes = ms.votes_for + ms.votes_against
        quorum_needed = (total_contributors * self._vote_quorum_pct) // 100

        if total_votes < quorum_needed:
            logger.warning(
                "Quorum not met | milestone=%s | votes=%d | needed=%d",
                milestone_id, total_votes, quorum_needed,
            )
            ms.status = MilestoneStatus.REJECTED
        elif ms.votes_for > ms.votes_against:
            ms.status = MilestoneStatus.VERIFIED
        else:
            ms.status = MilestoneStatus.REJECTED

        ms.resolved_at = time.time()
        logger.info(
            "Vote tallied | milestone=%s | for=%d | against=%d | status=%s",
            milestone_id, ms.votes_for, ms.votes_against, ms.status.value,
        )
        return ms

    def get_milestone(self, milestone_id: str) -> Optional[Milestone]:
        """Get milestone or None."""
        return self._milestones.get(milestone_id)

    def get_for_campaign(self, campaign_id: str) -> List[Milestone]:
        """Get all milestones for a campaign."""
        ids = self._by_campaign.get(campaign_id, [])
        return [self._milestones[mid] for mid in ids]

    def get_verified_release_total(self, campaign_id: str) -> int:
        """Sum of release amounts for all verified milestones in a campaign."""
        total = 0
        for ms in self.get_for_campaign(campaign_id):
            if ms.status == MilestoneStatus.VERIFIED:
                total += ms.release_amount_wei
        return total

    def set_vote_quorum(self, pct: int) -> None:
        """Update the vote quorum percentage."""
        if not 1 <= pct <= 100:
            raise ValueError("Quorum must be between 1 and 100.")
        self._vote_quorum_pct = pct
        logger.info("Vote quorum updated to %d%%.", pct)

    def _get_milestone(self, milestone_id: str) -> Milestone:
        """Get milestone or raise."""
        ms = self._milestones.get(milestone_id)
        if ms is None:
            raise ValueError(f"Milestone {milestone_id} not found.")
        return ms
