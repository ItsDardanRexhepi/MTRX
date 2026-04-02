"""
Dispute Manager — main orchestrator for on-chain dispute resolution.

Part of Component 30 (Dispute Resolution).
Coordinates the full dispute lifecycle: filing, evidence, jury selection,
commit-reveal voting, resolution, appeals, and contract freezing.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional, Set

from runtime.blockchain.services.disputes.juror_pool import JurorPool
from runtime.blockchain.services.disputes.voting import VotingEngine, Vote, TallyResult
from runtime.blockchain.services.disputes.evidence_tracker import EvidenceTracker

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

EVIDENCE_PERIOD_SECONDS: int = 3 * 86_400   # 3 days
VOTING_PERIOD_SECONDS: int = 2 * 86_400     # 2 days
REVEAL_PERIOD_SECONDS: int = 1 * 86_400     # 1 day


class DisputePhase(Enum):
    """Phases of a dispute lifecycle."""
    FILED = "filed"
    EVIDENCE = "evidence"
    JURY_SELECTION = "jury_selection"
    VOTING = "voting"
    REVEAL = "reveal"
    RESOLVED = "resolved"
    APPEALED = "appealed"
    APPEAL_RESOLVED = "appeal_resolved"
    DISMISSED = "dismissed"


@dataclass
class Dispute:
    """Full dispute record."""
    dispute_id: str
    claimant: str
    respondent: str
    stake_token: str
    claimant_bond_wei: int
    respondent_bond_wei: int
    juror_fee_wei: int
    claim_uri: str
    phase: DisputePhase = DisputePhase.FILED
    filed_at: float = field(default_factory=time.time)
    evidence_deadline: float = 0.0
    voting_deadline: float = 0.0
    reveal_deadline: float = 0.0
    resolved_at: float = 0.0
    outcome: Vote = Vote.NONE
    juror_count: int = 3
    appeal_round: int = 0
    frozen_contract: str = ""
    contract_frozen: bool = False
    jurors: List[str] = field(default_factory=list)
    respondent_bonded: bool = False


@dataclass
class AuditEntry:
    """Audit trail entry for dispute actions."""
    dispute_id: str
    action: str
    actor: str
    timestamp: float = field(default_factory=time.time)
    details: str = ""


class DisputeManager:
    """
    Orchestrates the full dispute resolution lifecycle.

    Architecture:
    - JurorPool: juror registration and selection
    - VotingEngine: commit-reveal voting
    - EvidenceTracker: evidence submissions
    - All blockchain calls delegated to injectable execute_fn
    """

    def __init__(
        self,
        juror_pool: Optional[JurorPool] = None,
        voting_engine: Optional[VotingEngine] = None,
        evidence_tracker: Optional[EvidenceTracker] = None,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._jurors = juror_pool or JurorPool()
        self._voting = voting_engine or VotingEngine()
        self._evidence = evidence_tracker or EvidenceTracker()
        self._execute = execute_fn
        self._disputes: Dict[str, Dispute] = {}
        self._audit: List[AuditEntry] = {}
        self._frozen_contracts: Dict[str, str] = {}  # contract_addr -> dispute_id
        self._counter: int = 0
        self._audit: List[AuditEntry] = []
        logger.info("DisputeManager initialised.")

    # ── Filing ────────────────────────────────────────────────────────

    def file_dispute(
        self,
        claimant: str,
        respondent: str,
        stake_token: str,
        bond_wei: int,
        juror_fee_wei: int,
        claim_uri: str,
        juror_count: int = 3,
        contract_to_freeze: str = "",
    ) -> Dispute:
        """
        File a new dispute.

        Args:
            claimant: Address of the claimant.
            respondent: Address of the respondent.
            stake_token: Token address used for bonds.
            bond_wei: Claimant's bond amount.
            juror_fee_wei: Fee offered to jurors.
            claim_uri: URI of the claim document.
            juror_count: Number of jurors (must be odd).
            contract_to_freeze: Optional contract to freeze during dispute.

        Returns:
            The created Dispute.
        """
        if not claimant.startswith("0x") or not respondent.startswith("0x"):
            raise ValueError("Invalid address format.")
        if claimant == respondent:
            raise ValueError("Claimant and respondent must differ.")
        if bond_wei <= 0:
            raise ValueError("Bond must be positive.")
        if juror_count < 1 or juror_count % 2 == 0:
            raise ValueError("Juror count must be odd and >= 1.")

        self._counter += 1
        did = f"DISP-{self._counter:08d}"
        now = time.time()

        dispute = Dispute(
            dispute_id=did,
            claimant=claimant,
            respondent=respondent,
            stake_token=stake_token,
            claimant_bond_wei=bond_wei,
            respondent_bond_wei=0,
            juror_fee_wei=juror_fee_wei,
            claim_uri=claim_uri,
            phase=DisputePhase.EVIDENCE,
            filed_at=now,
            evidence_deadline=now + EVIDENCE_PERIOD_SECONDS,
            juror_count=juror_count,
            frozen_contract=contract_to_freeze,
        )

        if contract_to_freeze:
            dispute.contract_frozen = True
            self._frozen_contracts[contract_to_freeze] = did

        self._disputes[did] = dispute
        self._log_audit(did, "file_dispute", claimant, f"bond={bond_wei}")
        logger.info(
            "Dispute filed | id=%s | claimant=%s | respondent=%s | bond=%d",
            did, claimant, respondent, bond_wei,
        )
        return dispute

    def respond_to_dispute(
        self, dispute_id: str, respondent: str, bond_wei: int,
    ) -> Dispute:
        """
        Respondent posts their bond to participate in the dispute.

        Args:
            dispute_id: The dispute to respond to.
            respondent: Respondent address (must match).
            bond_wei: Bond amount posted by respondent.
        """
        d = self._get_dispute(dispute_id)
        if d.respondent != respondent:
            raise ValueError("Only the respondent can respond.")
        if d.respondent_bonded:
            raise ValueError("Respondent already bonded.")
        if d.phase not in (DisputePhase.FILED, DisputePhase.EVIDENCE):
            raise ValueError(f"Cannot respond in phase {d.phase.value}.")
        if bond_wei <= 0:
            raise ValueError("Bond must be positive.")

        d.respondent_bond_wei = bond_wei
        d.respondent_bonded = True
        self._log_audit(dispute_id, "respond", respondent, f"bond={bond_wei}")
        logger.info(
            "Respondent bonded | dispute=%s | amount=%d", dispute_id, bond_wei,
        )
        return d

    # ── Evidence ──────────────────────────────────────────────────────

    def submit_evidence(
        self,
        dispute_id: str,
        submitter: str,
        evidence_uri: str,
        evidence_hash: str,
    ) -> None:
        """Submit evidence for a dispute. Must be in EVIDENCE phase."""
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.EVIDENCE:
            raise ValueError(f"Dispute not in evidence phase (current: {d.phase.value}).")
        if submitter not in (d.claimant, d.respondent):
            raise ValueError("Only dispute parties can submit evidence.")

        self._evidence.submit(
            dispute_id=dispute_id,
            submitter=submitter,
            evidence_uri=evidence_uri,
            evidence_hash=evidence_hash,
            deadline=d.evidence_deadline,
        )
        self._log_audit(dispute_id, "submit_evidence", submitter)

    def end_evidence_phase(self, dispute_id: str) -> Dispute:
        """
        End the evidence phase and move to jury selection.
        Can be called after evidence deadline passes.
        """
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.EVIDENCE:
            raise ValueError("Dispute not in evidence phase.")
        now = time.time()
        if now < d.evidence_deadline:
            raise ValueError("Evidence deadline has not passed yet.")

        d.phase = DisputePhase.JURY_SELECTION
        self._log_audit(dispute_id, "end_evidence_phase", "system")
        logger.info("Evidence phase ended | dispute=%s", dispute_id)
        return d

    # ── Jury Selection ────────────────────────────────────────────────

    def select_jury(self, dispute_id: str) -> List[str]:
        """
        Select jurors for this dispute from the pool.
        Excludes claimant and respondent.
        """
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.JURY_SELECTION:
            raise ValueError("Dispute not in jury selection phase.")

        exclude = {d.claimant, d.respondent}
        selected = self._jurors.select_jury(dispute_id, d.juror_count, exclude)
        d.jurors = selected

        # Initialize voting
        self._voting.init_voting(dispute_id, selected)

        now = time.time()
        d.phase = DisputePhase.VOTING
        d.voting_deadline = now + VOTING_PERIOD_SECONDS

        self._log_audit(dispute_id, "select_jury", "system", f"jurors={selected}")
        logger.info(
            "Jury selected | dispute=%s | jurors=%s", dispute_id, selected,
        )
        return selected

    # ── Voting ────────────────────────────────────────────────────────

    def commit_vote(
        self, dispute_id: str, juror: str, commit_hash: str,
    ) -> None:
        """Juror commits their vote hash."""
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.VOTING:
            raise ValueError("Dispute not in voting phase.")
        if juror not in d.jurors:
            raise ValueError(f"Juror {juror} not assigned to this dispute.")
        now = time.time()
        if now > d.voting_deadline:
            raise ValueError("Voting deadline has passed.")

        self._voting.commit_vote(dispute_id, juror, commit_hash)
        self._log_audit(dispute_id, "commit_vote", juror)

    def begin_reveal_phase(self, dispute_id: str) -> Dispute:
        """Transition from voting to reveal phase."""
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.VOTING:
            raise ValueError("Dispute not in voting phase.")

        now = time.time()
        d.phase = DisputePhase.REVEAL
        d.reveal_deadline = now + REVEAL_PERIOD_SECONDS
        self._log_audit(dispute_id, "begin_reveal", "system")
        logger.info("Reveal phase started | dispute=%s", dispute_id)
        return d

    def reveal_vote(
        self, dispute_id: str, juror: str, vote: Vote, salt: str,
    ) -> None:
        """Juror reveals their vote with the salt."""
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.REVEAL:
            raise ValueError("Dispute not in reveal phase.")
        if juror not in d.jurors:
            raise ValueError(f"Juror {juror} not assigned to this dispute.")
        now = time.time()
        if now > d.reveal_deadline:
            raise ValueError("Reveal deadline has passed.")

        self._voting.reveal_vote(dispute_id, juror, vote, salt)
        self._log_audit(dispute_id, "reveal_vote", juror, f"vote={vote.value}")

    # ── Resolution ────────────────────────────────────────────────────

    def resolve_dispute(self, dispute_id: str) -> Dispute:
        """
        Tally votes and resolve the dispute.

        Rewards majority jurors, slashes non-revealers.
        Unfreezes any frozen contracts.
        """
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.REVEAL:
            raise ValueError("Dispute not in reveal phase.")

        result = self._voting.tally(dispute_id)
        d.outcome = result.outcome
        d.phase = DisputePhase.RESOLVED
        d.resolved_at = time.time()

        # Reward/slash jurors
        non_revealers = self._voting.get_non_revealers(dispute_id)
        fee_per_juror = d.juror_fee_wei // max(len(d.jurors), 1)

        for juror_addr in d.jurors:
            if juror_addr in non_revealers:
                self._jurors.slash(juror_addr, fee_per_juror)
            else:
                self._jurors.reward(juror_addr, fee_per_juror)

        # Unfreeze contract
        if d.contract_frozen and d.frozen_contract:
            d.contract_frozen = False
            self._frozen_contracts.pop(d.frozen_contract, None)

        self._log_audit(
            dispute_id, "resolve", "system",
            f"outcome={result.outcome.value} | claimant={result.claimant_votes} | respondent={result.respondent_votes}",
        )
        logger.info(
            "Dispute resolved | id=%s | outcome=%s",
            dispute_id, result.outcome.value,
        )
        return d

    # ── Appeals ───────────────────────────────────────────────────────

    def appeal(
        self,
        dispute_id: str,
        appellant: str,
        extra_bond_wei: int,
        extra_fee_wei: int,
    ) -> Dispute:
        """
        Appeal a resolved dispute. Resets to evidence phase with new round.

        Args:
            appellant: Must be one of the dispute parties.
            extra_bond_wei: Additional bond for the appeal.
            extra_fee_wei: Additional juror fee for the appeal.
        """
        d = self._get_dispute(dispute_id)
        if d.phase != DisputePhase.RESOLVED:
            raise ValueError("Can only appeal a resolved dispute.")
        if appellant not in (d.claimant, d.respondent):
            raise ValueError("Only dispute parties can appeal.")
        if extra_bond_wei <= 0:
            raise ValueError("Appeal bond must be positive.")

        d.appeal_round += 1
        d.phase = DisputePhase.APPEALED
        d.juror_fee_wei += extra_fee_wei
        d.juror_count += 2  # Add 2 more jurors per appeal round

        if appellant == d.claimant:
            d.claimant_bond_wei += extra_bond_wei
        else:
            d.respondent_bond_wei += extra_bond_wei

        # Reset to evidence phase for new round
        now = time.time()
        d.evidence_deadline = now + EVIDENCE_PERIOD_SECONDS
        d.phase = DisputePhase.EVIDENCE
        d.outcome = Vote.NONE
        d.resolved_at = 0.0
        d.jurors = []

        self._log_audit(
            dispute_id, "appeal", appellant,
            f"round={d.appeal_round} | extra_bond={extra_bond_wei}",
        )
        logger.info(
            "Dispute appealed | id=%s | round=%d | appellant=%s",
            dispute_id, d.appeal_round, appellant,
        )
        return d

    # ── Dismissal ─────────────────────────────────────────────────────

    def dismiss_dispute(self, dispute_id: str, dismisser: str) -> Dispute:
        """
        Dismiss a dispute (owner/admin action).
        Returns bonds and unfreezes contracts.
        """
        d = self._get_dispute(dispute_id)
        if d.phase in (DisputePhase.RESOLVED, DisputePhase.DISMISSED):
            raise ValueError(f"Dispute already in {d.phase.value} phase.")

        d.phase = DisputePhase.DISMISSED
        d.resolved_at = time.time()

        if d.contract_frozen and d.frozen_contract:
            d.contract_frozen = False
            self._frozen_contracts.pop(d.frozen_contract, None)

        self._log_audit(dispute_id, "dismiss", dismisser)
        logger.info("Dispute dismissed | id=%s", dispute_id)
        return d

    # ── Queries ───────────────────────────────────────────────────────

    def get_dispute(self, dispute_id: str) -> Optional[Dispute]:
        """Get dispute by ID or None."""
        return self._disputes.get(dispute_id)

    def is_contract_frozen(self, contract_addr: str) -> bool:
        """Check if a contract is currently frozen by a dispute."""
        return contract_addr in self._frozen_contracts

    def get_freezing_dispute(self, contract_addr: str) -> Optional[str]:
        """Get the dispute ID that froze a contract."""
        return self._frozen_contracts.get(contract_addr)

    def get_evidence(self, dispute_id: str) -> list:
        """Get all evidence for a dispute."""
        return self._evidence.get_for_dispute(dispute_id)

    def get_audit_trail(self, dispute_id: str) -> List[AuditEntry]:
        """Get audit trail entries for a dispute."""
        return [e for e in self._audit if e.dispute_id == dispute_id]

    def list_disputes(
        self, phase: Optional[DisputePhase] = None,
    ) -> List[Dispute]:
        """List all disputes, optionally filtered by phase."""
        disputes = list(self._disputes.values())
        if phase is not None:
            disputes = [d for d in disputes if d.phase == phase]
        return disputes

    # ── Internal ──────────────────────────────────────────────────────

    def _get_dispute(self, dispute_id: str) -> Dispute:
        """Get dispute or raise."""
        d = self._disputes.get(dispute_id)
        if d is None:
            raise ValueError(f"Dispute {dispute_id} not found.")
        return d

    def _log_audit(
        self, dispute_id: str, action: str, actor: str, details: str = "",
    ) -> None:
        """Append to audit trail."""
        self._audit.append(AuditEntry(
            dispute_id=dispute_id,
            action=action,
            actor=actor,
            details=details,
        ))
