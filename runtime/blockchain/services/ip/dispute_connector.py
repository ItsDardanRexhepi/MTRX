"""
IP Dispute Connector — routes IP-related disputes to Component 30 (Disputes).

Part of Component 15 (IP and Royalty Management).
Handles IP infringement claims, royalty disputes, and ownership challenges.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class IPDisputeType(Enum):
    """Types of IP disputes that can be filed."""
    INFRINGEMENT = "infringement"
    ROYALTY_UNDERPAYMENT = "royalty_underpayment"
    OWNERSHIP_CHALLENGE = "ownership_challenge"
    LICENSING_VIOLATION = "licensing_violation"
    UNAUTHORIZED_DERIVATIVE = "unauthorized_derivative"


class DisputeStatus(Enum):
    """Status of a dispute routed to Component 30."""
    PENDING = "pending"
    SUBMITTED = "submitted"
    ACKNOWLEDGED = "acknowledged"
    IN_REVIEW = "in_review"
    RESOLVED = "resolved"
    DISMISSED = "dismissed"


@dataclass
class IPDisputeRequest:
    """A dispute request originating from IP management."""
    dispute_id: str
    ip_id: str
    dispute_type: IPDisputeType
    claimant_address: str
    respondent_address: str
    description: str
    evidence_hashes: List[str] = field(default_factory=list)
    amount_in_dispute_wei: int = 0
    status: DisputeStatus = DisputeStatus.PENDING
    created_at: float = field(default_factory=time.time)
    component_30_ref: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class IPDisputeConnector:
    """
    Routes IP disputes to the Component 30 dispute resolution system.

    Provides a standardized interface for filing IP-related disputes,
    tracking their status, and receiving resolution callbacks. All disputes
    are submitted through the Component 30 connector interface.
    """

    COMPONENT_ID: int = 15
    TARGET_COMPONENT: int = 30

    def __init__(self, dispute_system: Optional[Any] = None) -> None:
        """
        Args:
            dispute_system: Reference to Component 30 dispute system.
                            Accepts any object implementing submit_dispute().
        """
        self._dispute_system = dispute_system
        self._disputes: Dict[str, IPDisputeRequest] = {}
        self._counter: int = 0
        logger.info("IPDisputeConnector initialised (Component 15 -> 30).")

    # ── Filing ────────────────────────────────────────────────────────

    def file_dispute(
        self,
        ip_id: str,
        dispute_type: IPDisputeType,
        claimant_address: str,
        respondent_address: str,
        description: str,
        evidence_hashes: Optional[List[str]] = None,
        amount_in_dispute_wei: int = 0,
    ) -> IPDisputeRequest:
        """
        File an IP dispute and route it to Component 30.

        Args:
            ip_id: The IP work at the center of the dispute.
            dispute_type: Category of the IP dispute.
            claimant_address: Address of the party filing the dispute.
            respondent_address: Address of the party being disputed.
            description: Detailed description of the dispute.
            evidence_hashes: List of IPFS/on-chain hashes for evidence.
            amount_in_dispute_wei: Monetary amount in dispute (if applicable).

        Returns:
            The created IPDisputeRequest with routing information.

        Raises:
            ValueError: If required fields are missing or addresses are invalid.
        """
        if not claimant_address.startswith("0x") or not respondent_address.startswith("0x"):
            raise ValueError("Both claimant and respondent must be valid Ethereum addresses.")
        if claimant_address == respondent_address:
            raise ValueError("Claimant and respondent cannot be the same address.")
        if not description.strip():
            raise ValueError("Dispute description cannot be empty.")

        self._counter += 1
        dispute_id = f"IP-DISP-{self._counter:06d}"

        request = IPDisputeRequest(
            dispute_id=dispute_id,
            ip_id=ip_id,
            dispute_type=dispute_type,
            claimant_address=claimant_address,
            respondent_address=respondent_address,
            description=description,
            evidence_hashes=evidence_hashes or [],
            amount_in_dispute_wei=amount_in_dispute_wei,
        )

        self._disputes[dispute_id] = request

        # Route to Component 30
        self._submit_to_dispute_system(request)

        logger.info(
            "IP dispute filed | id=%s | type=%s | ip=%s | claimant=%s",
            dispute_id, dispute_type.value, ip_id, claimant_address,
        )
        return request

    def add_evidence(self, dispute_id: str, evidence_hash: str) -> None:
        """
        Add additional evidence to an existing dispute.

        Args:
            dispute_id: The dispute to add evidence to.
            evidence_hash: IPFS or on-chain hash of the evidence.

        Raises:
            ValueError: If dispute not found or already resolved.
        """
        request = self._get_dispute(dispute_id)
        if request.status in (DisputeStatus.RESOLVED, DisputeStatus.DISMISSED):
            raise ValueError(f"Cannot add evidence to {request.status.value} dispute.")

        request.evidence_hashes.append(evidence_hash)
        logger.info("Evidence added to dispute %s: %s", dispute_id, evidence_hash)

    # ── Status ────────────────────────────────────────────────────────

    def get_dispute(self, dispute_id: str) -> Optional[IPDisputeRequest]:
        """Retrieve a dispute by ID."""
        return self._disputes.get(dispute_id)

    def get_disputes_for_ip(self, ip_id: str) -> List[IPDisputeRequest]:
        """Get all disputes related to a specific IP work."""
        return [d for d in self._disputes.values() if d.ip_id == ip_id]

    def get_disputes_by_claimant(self, address: str) -> List[IPDisputeRequest]:
        """Get all disputes filed by a specific claimant."""
        return [d for d in self._disputes.values() if d.claimant_address == address]

    def get_active_disputes(self) -> List[IPDisputeRequest]:
        """Return all disputes that are not yet resolved or dismissed."""
        terminal = {DisputeStatus.RESOLVED, DisputeStatus.DISMISSED}
        return [d for d in self._disputes.values() if d.status not in terminal]

    # ── Callbacks ─────────────────────────────────────────────────────

    def on_resolution(self, dispute_id: str, resolution: Dict[str, Any]) -> None:
        """
        Callback invoked by Component 30 when a dispute is resolved.

        Args:
            dispute_id: The resolved dispute ID.
            resolution: Resolution details from Component 30.
        """
        request = self._get_dispute(dispute_id)
        request.status = DisputeStatus.RESOLVED
        request.metadata["resolution"] = resolution
        request.metadata["resolved_at"] = time.time()
        logger.info(
            "Dispute %s resolved | outcome=%s",
            dispute_id, resolution.get("outcome", "unknown"),
        )

    def on_dismissal(self, dispute_id: str, reason: str) -> None:
        """
        Callback invoked by Component 30 when a dispute is dismissed.

        Args:
            dispute_id: The dismissed dispute ID.
            reason: Reason for dismissal.
        """
        request = self._get_dispute(dispute_id)
        request.status = DisputeStatus.DISMISSED
        request.metadata["dismissal_reason"] = reason
        request.metadata["dismissed_at"] = time.time()
        logger.info("Dispute %s dismissed | reason=%s", dispute_id, reason)

    # ── Internal ──────────────────────────────────────────────────────

    def _submit_to_dispute_system(self, request: IPDisputeRequest) -> None:
        """Submit a dispute to Component 30."""
        if self._dispute_system is None:
            request.status = DisputeStatus.PENDING
            logger.warning(
                "Component 30 not connected — dispute %s queued as PENDING.",
                request.dispute_id,
            )
            return

        try:
            ref = self._dispute_system.submit_dispute(
                source_component=self.COMPONENT_ID,
                dispute_id=request.dispute_id,
                dispute_type=request.dispute_type.value,
                claimant=request.claimant_address,
                respondent=request.respondent_address,
                description=request.description,
                evidence=request.evidence_hashes,
                amount_wei=request.amount_in_dispute_wei,
            )
            request.component_30_ref = ref
            request.status = DisputeStatus.SUBMITTED
        except Exception:
            logger.exception("Failed to submit dispute %s to Component 30.", request.dispute_id)
            request.status = DisputeStatus.PENDING

    def _get_dispute(self, dispute_id: str) -> IPDisputeRequest:
        """Get a dispute or raise ValueError."""
        request = self._disputes.get(dispute_id)
        if request is None:
            raise ValueError(f"Dispute {dispute_id} not found.")
        return request
