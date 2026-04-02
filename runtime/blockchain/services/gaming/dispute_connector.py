"""
Gaming Dispute Connector
=========================

Routes ALL gaming disputes to Component 30 (DisputeResolution),
NOT Component 19 (Governance). Handles disputes about game fairness,
asset ownership, revenue distribution, and refund requests.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# CRITICAL: Gaming disputes go to Component 30, NOT Component 19
DISPUTE_COMPONENT: int = 30
GOVERNANCE_COMPONENT: int = 19  # NOT used for gaming disputes


class GamingDisputeType(Enum):
    GAME_FAIRNESS = "game_fairness"
    ASSET_OWNERSHIP = "asset_ownership"
    REVENUE_DISTRIBUTION = "revenue_distribution"
    REFUND_REQUEST = "refund_request"
    DEVELOPER_MISCONDUCT = "developer_misconduct"
    ASSET_FRAUD = "asset_fraud"


class DisputeUrgency(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class GamingDispute:
    """A gaming dispute to be routed to Component 30."""
    dispute_id: str = field(default_factory=lambda: f"gd-{uuid.uuid4().hex[:12]}")
    dispute_type: GamingDisputeType = GamingDisputeType.GAME_FAIRNESS
    urgency: DisputeUrgency = DisputeUrgency.MEDIUM
    claimant_wallet: str = ""
    respondent_wallet: str = ""
    game_deployment_id: str = ""
    game_name: str = ""
    description: str = ""
    evidence: List[Dict[str, Any]] = field(default_factory=list)
    amount_eth: float = 0.0
    routed_to_component: int = DISPUTE_COMPONENT
    component_30_dispute_id: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    routed_at: Optional[float] = None
    resolved_at: Optional[float] = None
    resolution: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class GamingDisputeConnector:
    """Routes gaming disputes to Component 30 DisputeResolution.

    IMPORTANT: Gaming disputes ALWAYS go to Component 30 (bilateral
    dispute resolution with jurors), NEVER to Component 19 (governance).
    Component 19 is for DAO governance only.

    Parameters
    ----------
    dispute_manager : Any
        Component 30 DisputeManager.
    attestation_service : Any
        Component 8 for dispute attestations.
    """

    def __init__(
        self,
        dispute_manager: Any = None,
        attestation_service: Any = None,
    ) -> None:
        self._dispute_manager = dispute_manager
        self._attestation = attestation_service
        self._disputes: Dict[str, GamingDispute] = {}
        self._by_game: Dict[str, List[str]] = {}
        self._by_wallet: Dict[str, List[str]] = {}
        logger.info(
            "GamingDisputeConnector initialised (routes to Component %d, NOT Component %d)",
            DISPUTE_COMPONENT, GOVERNANCE_COMPONENT,
        )

    def file_dispute(
        self,
        dispute_type: GamingDisputeType,
        claimant_wallet: str,
        respondent_wallet: str,
        game_deployment_id: str,
        game_name: str,
        description: str,
        evidence: Optional[List[Dict[str, Any]]] = None,
        amount_eth: float = 0.0,
        urgency: DisputeUrgency = DisputeUrgency.MEDIUM,
    ) -> GamingDispute:
        """File a gaming dispute and route to Component 30.

        Args:
            dispute_type: Type of gaming dispute.
            claimant_wallet: Who is filing the dispute.
            respondent_wallet: Who the dispute is against.
            game_deployment_id: The game deployment ID.
            game_name: Name of the game.
            description: Description of the dispute.
            evidence: Supporting evidence.
            amount_eth: Amount in dispute.
            urgency: Dispute urgency level.

        Returns:
            GamingDispute with Component 30 routing.
        """
        dispute = GamingDispute(
            dispute_type=dispute_type,
            urgency=urgency,
            claimant_wallet=claimant_wallet,
            respondent_wallet=respondent_wallet,
            game_deployment_id=game_deployment_id,
            game_name=game_name,
            description=description,
            evidence=evidence or [],
            amount_eth=amount_eth,
            routed_to_component=DISPUTE_COMPONENT,
        )

        self._disputes[dispute.dispute_id] = dispute
        self._by_game.setdefault(game_deployment_id, []).append(dispute.dispute_id)
        self._by_wallet.setdefault(claimant_wallet, []).append(dispute.dispute_id)

        # Route to Component 30
        self._route_to_component_30(dispute)

        logger.info(
            "Gaming dispute filed: %s (type=%s, game=%s) -> Component %d",
            dispute.dispute_id, dispute_type.value, game_name, DISPUTE_COMPONENT,
        )
        return dispute

    def get_dispute(self, dispute_id: str) -> Optional[GamingDispute]:
        return self._disputes.get(dispute_id)

    def get_game_disputes(self, game_deployment_id: str) -> List[GamingDispute]:
        ids = self._by_game.get(game_deployment_id, [])
        return [self._disputes[did] for did in ids if did in self._disputes]

    def get_wallet_disputes(self, wallet_address: str) -> List[GamingDispute]:
        ids = self._by_wallet.get(wallet_address, [])
        return [self._disputes[did] for did in ids if did in self._disputes]

    def update_resolution(self, dispute_id: str, resolution: str) -> bool:
        """Update a dispute with its resolution from Component 30."""
        dispute = self._disputes.get(dispute_id)
        if not dispute:
            return False
        dispute.resolution = resolution
        dispute.resolved_at = time.time()
        logger.info("Gaming dispute %s resolved: %s", dispute_id, resolution)
        return True

    def get_stats(self) -> Dict[str, Any]:
        by_type: Dict[str, int] = {}
        resolved = 0
        pending = 0
        for d in self._disputes.values():
            by_type[d.dispute_type.value] = by_type.get(d.dispute_type.value, 0) + 1
            if d.resolved_at:
                resolved += 1
            else:
                pending += 1
        return {
            "total_disputes": len(self._disputes),
            "resolved": resolved,
            "pending": pending,
            "by_type": by_type,
            "routing_component": DISPUTE_COMPONENT,
        }

    def _route_to_component_30(self, dispute: GamingDispute) -> None:
        """Route the dispute to Component 30 DisputeResolution."""
        if self._dispute_manager:
            try:
                c30_id = self._dispute_manager.create_dispute(
                    claimant=dispute.claimant_wallet,
                    respondent=dispute.respondent_wallet,
                    description=f"[Gaming: {dispute.game_name}] {dispute.description}",
                    evidence=dispute.evidence,
                    amount_eth=dispute.amount_eth,
                    category="gaming",
                    source_component=14,
                )
                dispute.component_30_dispute_id = c30_id
                dispute.routed_at = time.time()
                logger.info(
                    "Dispute %s routed to Component 30 as %s",
                    dispute.dispute_id, c30_id,
                )
            except Exception as exc:
                logger.error("Failed to route to Component 30: %s", exc)
        else:
            dispute.routed_at = time.time()
            logger.warning("No DisputeManager available, dispute %s queued", dispute.dispute_id)

        if self._attestation:
            try:
                self._attestation.create_attestation(
                    schema="gaming_dispute_filed",
                    data={
                        "dispute_id": dispute.dispute_id,
                        "type": dispute.dispute_type.value,
                        "game": dispute.game_name,
                        "routed_to": DISPUTE_COMPONENT,
                    },
                )
            except Exception as exc:
                logger.warning("Dispute attestation failed: %s", exc)
