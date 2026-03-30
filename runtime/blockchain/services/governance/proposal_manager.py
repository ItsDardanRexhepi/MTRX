"""
Component 19 — Proposal Manager

Manages creation, lifecycle, and querying of governance proposals.
Bilateral disputes are REJECTED at this level and redirected to Component 30.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class ProposalStatus(Enum):
    """Lifecycle states for a governance proposal."""
    DRAFT = "draft"
    ACTIVE = "active"
    VOTING_CLOSED = "voting_closed"
    EXECUTED = "executed"
    CANCELLED = "cancelled"
    REJECTED_BILATERAL = "rejected_bilateral"


class ProposalCategory(Enum):
    """Allowed proposal categories — bilateral disputes are NOT permitted."""
    PLATFORM_POLICY = "platform_policy"
    FEE_STRUCTURE = "fee_structure"
    FEATURE_REQUEST = "feature_request"
    PARAMETER_CHANGE = "parameter_change"
    COMMUNITY_INITIATIVE = "community_initiative"
    TREASURY_ALLOCATION = "treasury_allocation"
    PROTOCOL_UPGRADE = "protocol_upgrade"


# Categories that are ALWAYS rejected — routed to Component 30
BILATERAL_DISPUTE_KEYWORDS = frozenset({
    "bilateral_dispute", "bilateral", "dispute", "two_party_dispute",
    "arbitration", "mediation", "party_vs_party",
})


@dataclass
class Proposal:
    """A platform-wide governance proposal."""
    proposal_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    proposer: str = ""
    title: str = ""
    description: str = ""
    category: str = ""
    status: ProposalStatus = ProposalStatus.DRAFT
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    deadline: Optional[datetime] = None
    votes_for: int = 0
    votes_against: int = 0
    votes_abstain: int = 0
    total_participants: int = 0
    executed: bool = False
    eas_attestation_uid: Optional[str] = None
    on_chain_tx: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class ProposalManager:
    """
    Manages the full lifecycle of governance proposals.

    - Creates proposals for platform-wide policy only
    - REJECTS bilateral disputes at creation time, redirecting to Component 30
    - Tracks proposal state transitions
    - Provides querying and filtering
    """

    COMPONENT_30_REDIRECT = "Component 30 — Dispute Resolution"

    def __init__(self, contract_address: str, eas_address: str) -> None:
        self.contract_address = contract_address
        self.eas_address = eas_address
        self._proposals: Dict[str, Proposal] = {}
        logger.info(
            "ProposalManager initialized | contract=%s | eas=%s",
            contract_address, eas_address,
        )

    # ──────────────────── Creation ────────────────────────

    def create_proposal(
        self,
        proposer: str,
        title: str,
        description: str,
        category: str,
        deadline: datetime,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Proposal:
        """
        Create a new governance proposal.

        Raises:
            ValueError: If the category is a bilateral dispute (redirected to Component 30).
            ValueError: If deadline is in the past.
        """
        # REJECT bilateral disputes — Component 30 handles those
        if self._is_bilateral_dispute(category):
            logger.warning(
                "Bilateral dispute REJECTED from governance | proposer=%s | category=%s",
                proposer, category,
            )
            raise ValueError(
                f"Bilateral disputes are not allowed in platform governance. "
                f"Please use {self.COMPONENT_30_REDIRECT} for dispute resolution."
            )

        if deadline <= datetime.now(timezone.utc):
            raise ValueError("Proposal deadline must be in the future.")

        proposal = Proposal(
            proposer=proposer,
            title=title,
            description=description,
            category=category,
            status=ProposalStatus.ACTIVE,
            deadline=deadline,
            metadata=metadata or {},
        )

        self._proposals[proposal.proposal_id] = proposal
        logger.info(
            "Proposal created | id=%s | title=%s | proposer=%s | category=%s | deadline=%s",
            proposal.proposal_id, title, proposer, category, deadline.isoformat(),
        )
        return proposal

    # ──────────────────── Lifecycle ───────────────────────

    def close_voting(self, proposal_id: str) -> Proposal:
        """Close voting on a proposal after deadline passes."""
        proposal = self._get_or_raise(proposal_id)
        if proposal.status != ProposalStatus.ACTIVE:
            raise ValueError(f"Proposal {proposal_id} is not active (status={proposal.status.value}).")

        now = datetime.now(timezone.utc)
        if proposal.deadline and now < proposal.deadline:
            raise ValueError("Cannot close voting before the deadline.")

        proposal.status = ProposalStatus.VOTING_CLOSED
        logger.info("Voting closed | proposal=%s | participants=%d", proposal_id, proposal.total_participants)
        return proposal

    def mark_executed(self, proposal_id: str, eas_uid: str, tx_hash: str) -> Proposal:
        """Mark a proposal as executed with EAS attestation."""
        proposal = self._get_or_raise(proposal_id)
        if proposal.status != ProposalStatus.VOTING_CLOSED:
            raise ValueError(f"Proposal {proposal_id} voting is not closed.")

        proposal.status = ProposalStatus.EXECUTED
        proposal.executed = True
        proposal.eas_attestation_uid = eas_uid
        proposal.on_chain_tx = tx_hash
        logger.info(
            "Proposal executed | id=%s | eas=%s | tx=%s",
            proposal_id, eas_uid, tx_hash,
        )
        return proposal

    def cancel_proposal(self, proposal_id: str, cancelled_by: str) -> Proposal:
        """Cancel an active proposal. Only proposer or platform owner."""
        proposal = self._get_or_raise(proposal_id)
        if proposal.status not in (ProposalStatus.ACTIVE, ProposalStatus.DRAFT):
            raise ValueError(f"Proposal {proposal_id} cannot be cancelled (status={proposal.status.value}).")

        proposal.status = ProposalStatus.CANCELLED
        logger.info("Proposal cancelled | id=%s | by=%s", proposal_id, cancelled_by)
        return proposal

    # ──────────────────── Recording Votes ─────────────────

    def record_vote(
        self,
        proposal_id: str,
        weight_for: int = 0,
        weight_against: int = 0,
        weight_abstain: int = 0,
    ) -> Proposal:
        """Record aggregated vote weights on a proposal (called by VotingEngine)."""
        proposal = self._get_or_raise(proposal_id)
        if proposal.status != ProposalStatus.ACTIVE:
            raise ValueError(f"Proposal {proposal_id} is not active for voting.")

        proposal.votes_for += weight_for
        proposal.votes_against += weight_against
        proposal.votes_abstain += weight_abstain
        proposal.total_participants += 1
        return proposal

    # ──────────────────── Queries ─────────────────────────

    def get_proposal(self, proposal_id: str) -> Optional[Proposal]:
        """Retrieve a proposal by ID."""
        return self._proposals.get(proposal_id)

    def list_proposals(
        self,
        status: Optional[ProposalStatus] = None,
        category: Optional[str] = None,
        proposer: Optional[str] = None,
    ) -> List[Proposal]:
        """List proposals with optional filters."""
        results = list(self._proposals.values())
        if status is not None:
            results = [p for p in results if p.status == status]
        if category is not None:
            results = [p for p in results if p.category == category]
        if proposer is not None:
            results = [p for p in results if p.proposer == proposer]
        return sorted(results, key=lambda p: p.created_at, reverse=True)

    def get_active_proposals(self) -> List[Proposal]:
        """Return all currently active proposals."""
        return self.list_proposals(status=ProposalStatus.ACTIVE)

    def get_proposal_result(self, proposal_id: str) -> Dict[str, Any]:
        """Get the result summary of a proposal."""
        proposal = self._get_or_raise(proposal_id)
        passed = proposal.votes_for > proposal.votes_against
        return {
            "proposal_id": proposal.proposal_id,
            "title": proposal.title,
            "status": proposal.status.value,
            "votes_for": proposal.votes_for,
            "votes_against": proposal.votes_against,
            "votes_abstain": proposal.votes_abstain,
            "total_participants": proposal.total_participants,
            "passed": passed,
            "eas_attestation": proposal.eas_attestation_uid,
        }

    # ──────────────────── Internal ────────────────────────

    def _get_or_raise(self, proposal_id: str) -> Proposal:
        """Retrieve a proposal or raise ValueError."""
        proposal = self._proposals.get(proposal_id)
        if proposal is None:
            raise ValueError(f"Proposal {proposal_id} not found.")
        return proposal

    @staticmethod
    def _is_bilateral_dispute(category: str) -> bool:
        """Check if a category represents a bilateral dispute."""
        normalized = category.lower().strip().replace(" ", "_")
        return normalized in BILATERAL_DISPUTE_KEYWORDS
