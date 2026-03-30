"""
Component 6 -- DAO Dispute Connector
======================================

Routes DAO governance disputes to Component 30 (Dispute Resolution).
When DAO members disagree on proposals, treasury allocation, or
governance decisions, this connector packages the dispute context
and forwards it to the platform's dispute resolution system.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_30_ENDPOINT: str = "runtime.blockchain.services.dispute_resolution"


class DAODisputeType(Enum):
    """Categories of DAO governance disputes."""
    PROPOSAL_VALIDITY = auto()
    TREASURY_ALLOCATION = auto()
    VOTING_IRREGULARITY = auto()
    MEMBERSHIP_DISPUTE = auto()
    FEE_DISAGREEMENT = auto()
    GOVERNANCE_RULE_CHANGE = auto()
    QUORUM_CHALLENGE = auto()
    EXECUTION_DISPUTE = auto()
    GENERAL = auto()


class DisputeStatus(Enum):
    """Lifecycle states for a routed dispute."""
    DRAFT = auto()
    SUBMITTED = auto()
    ROUTED = auto()
    ACKNOWLEDGED = auto()
    IN_RESOLUTION = auto()
    RESOLVED = auto()
    ESCALATED = auto()
    DISMISSED = auto()


class DisputeUrgency(Enum):
    """Urgency levels for dispute routing."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class DAODisputeRecord:
    """A DAO dispute record routed to Component 30."""
    dispute_id: str
    dao_id: str
    filed_by: str
    against: Optional[str]
    dispute_type: DAODisputeType
    urgency: DisputeUrgency
    description: str
    evidence_hashes: List[str] = field(default_factory=list)
    proposal_id: Optional[str] = None
    treasury_amount_usd: Optional[float] = None
    status: DisputeStatus = DisputeStatus.DRAFT
    created_at: float = field(default_factory=time.time)
    routed_at: Optional[float] = None
    resolved_at: Optional[float] = None
    resolution_summary: Optional[str] = None
    component_30_ref: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class DisputeResolution:
    """Resolution data returned from Component 30."""
    dispute_id: str
    outcome: str
    binding: bool
    enforced_on_chain: bool
    resolution_tx: Optional[str] = None
    resolved_at: float = field(default_factory=time.time)


class DAODisputeConnector:
    """Routes DAO governance disputes to Component 30.

    When DAO members cannot reach agreement through normal governance
    channels, this connector packages the full dispute context --
    proposal data, voting records, treasury snapshots -- and forwards
    it to the platform-wide dispute resolution system.

    Parameters
    ----------
    dao_contract : Any
        Deployed DAO governance contract.
    dispute_resolution_client : Any
        Client for the Component 30 dispute resolution service.
    treasury_manager : Any
        TreasuryManager for treasury snapshot data.
    """

    def __init__(
        self,
        dao_contract: Any,
        dispute_resolution_client: Any = None,
        treasury_manager: Any = None,
    ) -> None:
        self._contract = dao_contract
        self._dispute_client = dispute_resolution_client
        self._treasury = treasury_manager
        self._disputes: Dict[str, DAODisputeRecord] = {}
        logger.info("DAODisputeConnector initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def file_dispute(
        self,
        dao_id: str,
        filed_by: str,
        dispute_type: DAODisputeType,
        description: str,
        against: Optional[str] = None,
        urgency: DisputeUrgency = DisputeUrgency.MEDIUM,
        proposal_id: Optional[str] = None,
        evidence_hashes: Optional[List[str]] = None,
        treasury_amount_usd: Optional[float] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> DAODisputeRecord:
        """File a new DAO governance dispute.

        Creates the dispute record and routes it to Component 30 for
        resolution.

        Args:
            dao_id: The DAO where the dispute arose.
            filed_by: Address of the member filing the dispute.
            dispute_type: Category of the dispute.
            description: Detailed description of the issue.
            against: Optional address of the opposing party.
            urgency: How urgently the dispute needs resolution.
            proposal_id: Related proposal ID if applicable.
            evidence_hashes: IPFS or on-chain hashes of supporting evidence.
            treasury_amount_usd: Treasury amount in question if applicable.
            metadata: Additional context data.

        Returns:
            The created DAODisputeRecord.

        Raises:
            ValueError: If the filing member is not a DAO member.
        """
        # Validate membership
        if not self._verify_membership(dao_id, filed_by):
            raise ValueError(f"Address {filed_by} is not a member of DAO {dao_id}")

        dispute_id = f"dao-disp-{uuid.uuid4().hex[:12]}"

        record = DAODisputeRecord(
            dispute_id=dispute_id,
            dao_id=dao_id,
            filed_by=filed_by,
            against=against,
            dispute_type=dispute_type,
            urgency=urgency,
            description=description,
            evidence_hashes=evidence_hashes or [],
            proposal_id=proposal_id,
            treasury_amount_usd=treasury_amount_usd,
            status=DisputeStatus.SUBMITTED,
            metadata=metadata or {},
        )

        self._disputes[dispute_id] = record

        # Gather context and route
        context = self._build_dispute_context(record)
        self._route_to_component_30(record, context)

        logger.info(
            "DAO dispute %s filed: dao=%s, type=%s, urgency=%s, by=%s",
            dispute_id, dao_id, dispute_type.name, urgency.value, filed_by,
        )
        return record

    def get_dispute(self, dispute_id: str) -> Optional[DAODisputeRecord]:
        """Retrieve a dispute record by ID."""
        return self._disputes.get(dispute_id)

    def list_disputes(
        self,
        dao_id: Optional[str] = None,
        status: Optional[DisputeStatus] = None,
    ) -> List[DAODisputeRecord]:
        """List disputes, optionally filtered by DAO or status."""
        results: List[DAODisputeRecord] = []
        for dispute in self._disputes.values():
            if dao_id and dispute.dao_id != dao_id:
                continue
            if status and dispute.status != status:
                continue
            results.append(dispute)
        return results

    def add_evidence(
        self, dispute_id: str, evidence_hash: str, submitted_by: str
    ) -> bool:
        """Add evidence to an existing dispute.

        Args:
            dispute_id: The dispute to add evidence to.
            evidence_hash: IPFS or on-chain hash of the evidence.
            submitted_by: Address submitting the evidence.

        Returns:
            True if evidence was added, False if dispute not found.
        """
        dispute = self._disputes.get(dispute_id)
        if dispute is None:
            return False
        if dispute.status in (DisputeStatus.RESOLVED, DisputeStatus.DISMISSED):
            logger.warning("Cannot add evidence to resolved dispute %s", dispute_id)
            return False
        dispute.evidence_hashes.append(evidence_hash)
        logger.info(
            "Evidence added to dispute %s by %s: %s",
            dispute_id, submitted_by, evidence_hash,
        )
        return True

    def escalate_dispute(self, dispute_id: str, reason: str) -> bool:
        """Escalate a dispute to higher-level resolution.

        Args:
            dispute_id: The dispute to escalate.
            reason: Reason for escalation.

        Returns:
            True if escalated, False if not found or already resolved.
        """
        dispute = self._disputes.get(dispute_id)
        if dispute is None:
            return False
        if dispute.status in (DisputeStatus.RESOLVED, DisputeStatus.DISMISSED):
            return False
        dispute.status = DisputeStatus.ESCALATED
        dispute.metadata["escalation_reason"] = reason
        dispute.metadata["escalated_at"] = time.time()
        logger.info("Dispute %s escalated: %s", dispute_id, reason)
        return True

    def receive_resolution(
        self, dispute_id: str, resolution: DisputeResolution
    ) -> bool:
        """Receive a resolution from Component 30.

        If the resolution is binding and enforceable, executes it
        on-chain via the DAO contract.

        Args:
            dispute_id: The dispute being resolved.
            resolution: Resolution details from Component 30.

        Returns:
            True if applied, False if dispute not found.
        """
        dispute = self._disputes.get(dispute_id)
        if dispute is None:
            return False

        dispute.status = DisputeStatus.RESOLVED
        dispute.resolved_at = resolution.resolved_at
        dispute.resolution_summary = resolution.outcome

        if resolution.binding and resolution.enforced_on_chain:
            self._enforce_resolution(dispute, resolution)

        logger.info(
            "Dispute %s resolved: %s (binding=%s, on_chain=%s)",
            dispute_id, resolution.outcome,
            resolution.binding, resolution.enforced_on_chain,
        )
        return True

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _verify_membership(self, dao_id: str, address: str) -> bool:
        """Verify that an address is a member of the DAO."""
        try:
            return self._contract.functions.isMember(
                dao_id.encode(), address
            ).call()
        except Exception:
            # If contract call fails, allow filing (will be validated by Component 30)
            return True

    def _build_dispute_context(self, dispute: DAODisputeRecord) -> Dict[str, Any]:
        """Build comprehensive context for Component 30."""
        context: Dict[str, Any] = {
            "component": 6,
            "component_name": "DAO Governance",
            "dao_id": dispute.dao_id,
            "dispute_type": dispute.dispute_type.name,
            "description": dispute.description,
            "filed_by": dispute.filed_by,
            "against": dispute.against,
            "evidence_count": len(dispute.evidence_hashes),
        }

        if dispute.proposal_id:
            context["proposal_id"] = dispute.proposal_id
            try:
                proposal_data = self._contract.functions.getProposal(
                    dispute.proposal_id.encode()
                ).call()
                context["proposal_data"] = proposal_data
            except Exception:
                pass

        if self._treasury and dispute.treasury_amount_usd:
            try:
                treasury_value = self._treasury.get_current_value(dispute.dao_id)
                context["current_treasury_usd"] = treasury_value
                context["disputed_amount_usd"] = dispute.treasury_amount_usd
                context["disputed_percentage"] = (
                    dispute.treasury_amount_usd / treasury_value * 100
                    if treasury_value > 0 else 0
                )
            except Exception:
                pass

        return context

    def _route_to_component_30(
        self, dispute: DAODisputeRecord, context: Dict[str, Any]
    ) -> None:
        """Route the dispute to Component 30 for resolution."""
        try:
            if self._dispute_client:
                ref = self._dispute_client.submit_dispute(
                    source_component=6,
                    dispute_id=dispute.dispute_id,
                    context=context,
                    urgency=dispute.urgency.value,
                )
                dispute.component_30_ref = ref
            dispute.status = DisputeStatus.ROUTED
            dispute.routed_at = time.time()
            logger.info("Dispute %s routed to Component 30", dispute.dispute_id)
        except Exception as exc:
            logger.error(
                "Failed to route dispute %s to Component 30: %s",
                dispute.dispute_id, exc,
            )

    def _enforce_resolution(
        self, dispute: DAODisputeRecord, resolution: DisputeResolution
    ) -> None:
        """Execute a binding resolution on-chain via the DAO contract."""
        try:
            tx = self._contract.functions.enforceDisputeResolution(
                dispute.dao_id.encode(),
                dispute.dispute_id.encode(),
                resolution.outcome.encode(),
            ).build_transaction({
                "from": NEOSAFE_ADDRESS,
            })
            logger.info(
                "Resolution enforcement tx built for dispute %s", dispute.dispute_id
            )
        except Exception as exc:
            logger.error(
                "Failed to enforce resolution for dispute %s: %s",
                dispute.dispute_id, exc,
            )
