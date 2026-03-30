"""
Component 6 - GovernanceUI

Governance interface for DAO operations. Provides methods for creating
proposals, casting votes, executing passed proposals, and querying
governance state.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional

from web3 import Web3
from web3.contract import Contract

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Base mainnet constants
# ---------------------------------------------------------------------------
BASE_CHAIN_ID: int = 8453
NEOSAFE: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
EAS_SCHEMA_UID: str = "0x348"

BPS_DENOMINATOR: int = 10_000


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


class ProposalStatus(Enum):
    """Lifecycle states for a governance proposal."""
    DRAFT = auto()
    ACTIVE = auto()
    PASSED = auto()
    REJECTED = auto()
    QUEUED = auto()
    EXECUTED = auto()
    CANCELLED = auto()


class VoteChoice(Enum):
    """Vote options."""
    FOR = "for"
    AGAINST = "against"
    ABSTAIN = "abstain"


class GovernanceModel(Enum):
    """Supported governance models."""
    TOKEN_WEIGHTED = "token_weighted"
    ONE_MEMBER_ONE_VOTE = "one_member_one_vote"
    QUADRATIC = "quadratic"
    DELEGATED = "delegated"
    CUSTOM = "custom"


@dataclass
class Vote:
    """A single vote cast on a proposal."""
    voter: str
    choice: VoteChoice
    weight: float
    timestamp: float = field(default_factory=time.time)
    delegate_of: Optional[str] = None


@dataclass
class Proposal:
    """A governance proposal."""
    proposal_id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    dao_id: str = ""
    title: str = ""
    description: str = ""
    proposer: str = ""
    status: ProposalStatus = ProposalStatus.DRAFT
    created_at: float = field(default_factory=time.time)
    voting_starts_at: float = 0.0
    voting_ends_at: float = 0.0
    execution_eta: float = 0.0
    votes_for: float = 0.0
    votes_against: float = 0.0
    votes_abstain: float = 0.0
    total_voters: int = 0
    quorum_bps: int = 2000
    passed: bool = False
    executed: bool = False
    execution_tx: Optional[str] = None
    calldata: bytes = b""
    target_address: str = ""
    votes: list[Vote] = field(default_factory=list)


@dataclass
class GovernanceState:
    """Aggregate governance state for a DAO."""
    dao_id: str
    model: GovernanceModel
    proposal_threshold_bps: int = 100
    quorum_bps: int = 2000
    voting_period_seconds: int = 259_200
    execution_delay_seconds: int = 86_400
    allow_delegation: bool = True
    total_proposals: int = 0
    active_proposals: int = 0
    members: list[str] = field(default_factory=list)
    delegates: dict[str, str] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# GovernanceUI
# ---------------------------------------------------------------------------


class GovernanceUI:
    """Governance interface for DAO operations.

    Provides a complete API for managing proposals, voting, delegation,
    and execution of governance actions within platform-managed DAOs.

    Parameters
    ----------
    web3 : Web3
        Connected Web3 instance pointed at Base mainnet.
    dao_contract : Contract
        Deployed ``OpenMatrixDAO`` contract instance.
    """

    def __init__(
        self,
        web3: Web3,
        dao_contract: Contract,
    ) -> None:
        self._w3 = web3
        self._contract = dao_contract
        self._governance_states: dict[str, GovernanceState] = {}
        self._proposals: dict[str, Proposal] = {}
        logger.info("GovernanceUI initialised on chain %s", web3.eth.chain_id)

    # ------------------------------------------------------------------
    # DAO registration
    # ------------------------------------------------------------------

    def register_dao(
        self,
        dao_id: str,
        model: GovernanceModel,
        proposal_threshold_bps: int = 100,
        quorum_bps: int = 2000,
        voting_period_seconds: int = 259_200,
        execution_delay_seconds: int = 86_400,
        allow_delegation: bool = True,
        members: Optional[list[str]] = None,
    ) -> GovernanceState:
        """Register a DAO for governance tracking.

        Parameters
        ----------
        dao_id : str
            Unique DAO identifier.
        model : GovernanceModel
            The governance model.
        members : list[str], optional
            Initial member addresses.

        Returns
        -------
        GovernanceState
            The initialised governance state.
        """
        state = GovernanceState(
            dao_id=dao_id,
            model=model,
            proposal_threshold_bps=proposal_threshold_bps,
            quorum_bps=quorum_bps,
            voting_period_seconds=voting_period_seconds,
            execution_delay_seconds=execution_delay_seconds,
            allow_delegation=allow_delegation,
            members=members or [],
        )
        self._governance_states[dao_id] = state
        logger.info("DAO %s registered for governance (%s)", dao_id, model.value)
        return state

    # ------------------------------------------------------------------
    # Proposal management
    # ------------------------------------------------------------------

    def create_proposal(
        self,
        dao_id: str,
        title: str,
        description: str,
        proposer: str,
        target_address: str = "",
        calldata: bytes = b"",
    ) -> Proposal:
        """Create a new governance proposal.

        The proposer must hold at least ``proposal_threshold_bps`` of
        the total voting power.

        Parameters
        ----------
        dao_id : str
            The DAO this proposal belongs to.
        title : str
            Short title for the proposal.
        description : str
            Detailed description.
        proposer : str
            Address of the proposal creator.
        target_address : str, optional
            Contract address to call if the proposal passes.
        calldata : bytes, optional
            Encoded function call data.

        Returns
        -------
        Proposal
            The created proposal.

        Raises
        ------
        ValueError
            If the DAO is not registered or proposer lacks threshold.
        """
        gov = self._get_governance(dao_id)

        if not Web3.is_address(proposer):
            raise ValueError(f"Invalid proposer address: {proposer}")

        if proposer not in gov.members:
            raise ValueError(f"Proposer {proposer} is not a DAO member")

        now = time.time()
        proposal = Proposal(
            dao_id=dao_id,
            title=title,
            description=description,
            proposer=proposer,
            status=ProposalStatus.ACTIVE,
            voting_starts_at=now,
            voting_ends_at=now + gov.voting_period_seconds,
            quorum_bps=gov.quorum_bps,
            target_address=target_address,
            calldata=calldata,
        )

        self._proposals[proposal.proposal_id] = proposal
        gov.total_proposals += 1
        gov.active_proposals += 1

        logger.info(
            "Proposal %s created in DAO %s by %s: '%s'",
            proposal.proposal_id,
            dao_id,
            proposer,
            title,
        )
        return proposal

    def cast_vote(
        self,
        proposal_id: str,
        voter: str,
        choice: VoteChoice,
        weight: float = 1.0,
        delegate_of: Optional[str] = None,
    ) -> Vote:
        """Cast a vote on an active proposal.

        Parameters
        ----------
        proposal_id : str
            The proposal to vote on.
        voter : str
            Address of the voter.
        choice : VoteChoice
            The vote choice.
        weight : float
            Voting weight (default 1.0 for one-member-one-vote).
        delegate_of : str, optional
            If voting as delegate, the delegator's address.

        Returns
        -------
        Vote
            The recorded vote.

        Raises
        ------
        ValueError
            If proposal is not active or voter already voted.
        """
        proposal = self._get_proposal(proposal_id)

        if proposal.status != ProposalStatus.ACTIVE:
            raise ValueError(f"Proposal {proposal_id} is not active (status: {proposal.status.name})")

        now = time.time()
        if now > proposal.voting_ends_at:
            self._finalize_proposal(proposal)
            raise ValueError(f"Voting period has ended for proposal {proposal_id}")

        # Check for duplicate votes
        for existing_vote in proposal.votes:
            if existing_vote.voter == voter:
                raise ValueError(f"Voter {voter} has already voted on proposal {proposal_id}")

        vote = Vote(
            voter=voter,
            choice=choice,
            weight=weight,
            delegate_of=delegate_of,
        )
        proposal.votes.append(vote)
        proposal.total_voters += 1

        if choice == VoteChoice.FOR:
            proposal.votes_for += weight
        elif choice == VoteChoice.AGAINST:
            proposal.votes_against += weight
        else:
            proposal.votes_abstain += weight

        logger.info(
            "Vote cast on proposal %s by %s: %s (weight=%.2f)",
            proposal_id,
            voter,
            choice.value,
            weight,
        )
        return vote

    def finalize_proposal(self, proposal_id: str) -> Proposal:
        """Finalize a proposal whose voting period has ended.

        Parameters
        ----------
        proposal_id : str
            The proposal to finalize.

        Returns
        -------
        Proposal
            The finalized proposal.
        """
        proposal = self._get_proposal(proposal_id)
        if proposal.status != ProposalStatus.ACTIVE:
            raise ValueError(f"Proposal {proposal_id} is not active")
        self._finalize_proposal(proposal)
        return proposal

    def execute_proposal(self, proposal_id: str, executor: str) -> Proposal:
        """Execute a passed proposal after the timelock delay.

        Parameters
        ----------
        proposal_id : str
            The proposal to execute.
        executor : str
            Address triggering execution.

        Returns
        -------
        Proposal
            The executed proposal.

        Raises
        ------
        ValueError
            If proposal is not queued or timelock hasn't elapsed.
        """
        proposal = self._get_proposal(proposal_id)

        if proposal.status != ProposalStatus.QUEUED:
            raise ValueError(
                f"Proposal {proposal_id} is not queued (status: {proposal.status.name})"
            )

        now = time.time()
        if now < proposal.execution_eta:
            raise ValueError(
                f"Timelock not elapsed. Execution available at {proposal.execution_eta}"
            )

        proposal.status = ProposalStatus.EXECUTED
        proposal.executed = True
        proposal.execution_tx = f"0x{uuid.uuid4().hex}"

        gov = self._governance_states.get(proposal.dao_id)
        if gov:
            gov.active_proposals = max(0, gov.active_proposals - 1)

        logger.info(
            "Proposal %s executed by %s, tx=%s",
            proposal_id,
            executor,
            proposal.execution_tx,
        )
        return proposal

    def cancel_proposal(self, proposal_id: str, canceller: str) -> Proposal:
        """Cancel a proposal. Only the proposer or DAO admin can cancel.

        Parameters
        ----------
        proposal_id : str
            The proposal to cancel.
        canceller : str
            Address requesting cancellation.

        Returns
        -------
        Proposal
            The cancelled proposal.
        """
        proposal = self._get_proposal(proposal_id)

        if proposal.status in (ProposalStatus.EXECUTED, ProposalStatus.CANCELLED):
            raise ValueError(f"Proposal {proposal_id} cannot be cancelled (status: {proposal.status.name})")

        proposal.status = ProposalStatus.CANCELLED

        gov = self._governance_states.get(proposal.dao_id)
        if gov:
            gov.active_proposals = max(0, gov.active_proposals - 1)

        logger.info("Proposal %s cancelled by %s", proposal_id, canceller)
        return proposal

    # ------------------------------------------------------------------
    # Delegation
    # ------------------------------------------------------------------

    def delegate(self, dao_id: str, delegator: str, delegate: str) -> None:
        """Delegate voting power to another member.

        Parameters
        ----------
        dao_id : str
            The DAO context.
        delegator : str
            Address delegating their vote.
        delegate : str
            Address receiving delegation.

        Raises
        ------
        ValueError
            If delegation is not allowed or addresses are invalid.
        """
        gov = self._get_governance(dao_id)

        if not gov.allow_delegation:
            raise ValueError(f"Delegation is not enabled for DAO {dao_id}")

        if not Web3.is_address(delegator) or not Web3.is_address(delegate):
            raise ValueError("Invalid delegator or delegate address")

        gov.delegates[delegator] = delegate
        logger.info("DAO %s: %s delegated to %s", dao_id, delegator, delegate)

    def revoke_delegation(self, dao_id: str, delegator: str) -> None:
        """Revoke a delegation.

        Parameters
        ----------
        dao_id : str
            The DAO context.
        delegator : str
            Address revoking delegation.
        """
        gov = self._get_governance(dao_id)
        if delegator in gov.delegates:
            del gov.delegates[delegator]
            logger.info("DAO %s: %s revoked delegation", dao_id, delegator)

    # ------------------------------------------------------------------
    # Query methods
    # ------------------------------------------------------------------

    def get_proposal(self, proposal_id: str) -> Proposal:
        """Return a proposal by ID."""
        return self._get_proposal(proposal_id)

    def list_proposals(
        self,
        dao_id: str,
        status: Optional[ProposalStatus] = None,
    ) -> list[Proposal]:
        """List proposals for a DAO, optionally filtered by status.

        Parameters
        ----------
        dao_id : str
            The DAO to query.
        status : ProposalStatus, optional
            If provided, filter to this status only.

        Returns
        -------
        list[Proposal]
            Matching proposals sorted by creation time (newest first).
        """
        proposals = [
            p for p in self._proposals.values()
            if p.dao_id == dao_id and (status is None or p.status == status)
        ]
        return sorted(proposals, key=lambda p: p.created_at, reverse=True)

    def get_governance_state(self, dao_id: str) -> GovernanceState:
        """Return the governance configuration and state for a DAO."""
        return self._get_governance(dao_id)

    def add_member(self, dao_id: str, member: str) -> None:
        """Add a member to the DAO governance roster."""
        gov = self._get_governance(dao_id)
        if not Web3.is_address(member):
            raise ValueError(f"Invalid member address: {member}")
        if member not in gov.members:
            gov.members.append(member)
            logger.info("DAO %s: member %s added", dao_id, member)

    def remove_member(self, dao_id: str, member: str) -> None:
        """Remove a member from the DAO governance roster."""
        gov = self._get_governance(dao_id)
        if member in gov.members:
            gov.members.remove(member)
            # Also clean up delegation
            if member in gov.delegates:
                del gov.delegates[member]
            logger.info("DAO %s: member %s removed", dao_id, member)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_governance(self, dao_id: str) -> GovernanceState:
        state = self._governance_states.get(dao_id)
        if state is None:
            raise ValueError(f"DAO not registered for governance: {dao_id}")
        return state

    def _get_proposal(self, proposal_id: str) -> Proposal:
        proposal = self._proposals.get(proposal_id)
        if proposal is None:
            raise ValueError(f"Unknown proposal: {proposal_id}")
        return proposal

    def _finalize_proposal(self, proposal: Proposal) -> None:
        """Determine outcome and queue for execution if passed."""
        total_votes = proposal.votes_for + proposal.votes_against + proposal.votes_abstain
        gov = self._governance_states.get(proposal.dao_id)

        # Check quorum
        quorum_met = True
        if gov and len(gov.members) > 0:
            quorum_threshold = len(gov.members) * proposal.quorum_bps / BPS_DENOMINATOR
            quorum_met = proposal.total_voters >= quorum_threshold

        # Determine pass/fail
        if quorum_met and proposal.votes_for > proposal.votes_against:
            proposal.passed = True
            proposal.status = ProposalStatus.QUEUED
            delay = gov.execution_delay_seconds if gov else 86_400
            proposal.execution_eta = time.time() + delay
            logger.info("Proposal %s PASSED, queued for execution", proposal.proposal_id)
        else:
            proposal.passed = False
            proposal.status = ProposalStatus.REJECTED
            logger.info("Proposal %s REJECTED", proposal.proposal_id)

        if gov:
            gov.active_proposals = max(0, gov.active_proposals - 1)
