"""
Governance Dashboard — plain English view of governance activity.

Part of Component 19 (Governance and Voting).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from runtime.blockchain.services.governance.voting_engine import VotingEngine, VotingModel
from runtime.blockchain.services.governance.proposal_manager import ProposalManager

logger = logging.getLogger(__name__)


@dataclass
class GovernanceOverview:
    """Complete governance overview for dashboard display."""
    dao_id: str
    voting_model: str
    active_proposals: List[Dict[str, Any]]
    recent_results: List[Dict[str, Any]]
    participation_stats: Dict[str, Any]
    plain_english_summary: str


class GovernanceDashboard:
    """
    Provides a unified governance dashboard with plain English summaries.

    Shows active proposals, recent results, and participation statistics.
    All data presented in non-technical language.
    """

    def __init__(
        self,
        voting_engine: VotingEngine,
        proposal_manager: ProposalManager,
    ) -> None:
        self._engine = voting_engine
        self._proposals = proposal_manager
        logger.info("GovernanceDashboard initialised.")

    def get_overview(self, dao_id: str) -> GovernanceOverview:
        """
        Generate a complete governance overview.

        Args:
            dao_id: The DAO to generate the overview for.

        Returns:
            GovernanceOverview with all dashboard data.
        """
        model = self._engine.active_model

        # Active proposals
        active = self._proposals.get_active_proposals()
        active_data = [
            {
                "proposal_id": p.proposal_id,
                "title": p.title,
                "description": p.description,
                "status": p.status.value if hasattr(p, 'status') else "active",
                "created_by": p.proposer if hasattr(p, 'proposer') else "",
            }
            for p in active
        ] if active else []

        # Recent results
        completed = self._proposals.get_completed_proposals() if hasattr(self._proposals, 'get_completed_proposals') else []
        results_data = []
        for p in (completed[-10:] if completed else []):
            session = self._engine.get_session(p.proposal_id)
            if session:
                result = self._engine.get_result(p.proposal_id)
                results_data.append({
                    "proposal_id": p.proposal_id,
                    "title": p.title if hasattr(p, 'title') else p.proposal_id,
                    "passed": result["passed"],
                    "votes_for": result["votes_for"],
                    "votes_against": result["votes_against"],
                    "participants": result["total_participants"],
                })

        # Participation stats
        stats = self._compute_participation_stats(results_data)

        summary = self._build_summary(model, len(active_data), len(results_data), stats)

        return GovernanceOverview(
            dao_id=dao_id,
            voting_model=model.value,
            active_proposals=active_data,
            recent_results=results_data,
            participation_stats=stats,
            plain_english_summary=summary,
        )

    def get_proposal_detail(self, proposal_id: str) -> Dict[str, Any]:
        """Get detailed view of a single proposal."""
        session = self._engine.get_session(proposal_id)
        if session is None:
            return {"error": f"No voting session found for {proposal_id}."}

        quorum = self._engine.check_quorum(proposal_id)
        return {
            "proposal_id": proposal_id,
            "model": session.model.value,
            "votes_for": session.total_weight_for,
            "votes_against": session.total_weight_against,
            "votes_abstain": session.total_weight_abstain,
            "participants": len(session.voters),
            "quorum_met": quorum["quorum_met"],
            "closed": session.closed,
            "note": "Quorum is based on participating voters only. Non-voters are not counted.",
        }

    def _compute_participation_stats(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Compute aggregate participation statistics."""
        if not results:
            return {"total_votes": 0, "proposals_passed": 0, "proposals_failed": 0, "avg_participants": 0}

        total_participants = sum(r.get("participants", 0) for r in results)
        passed = sum(1 for r in results if r.get("passed"))
        return {
            "total_votes": len(results),
            "proposals_passed": passed,
            "proposals_failed": len(results) - passed,
            "avg_participants": total_participants / len(results) if results else 0,
        }

    def _build_summary(
        self,
        model: VotingModel,
        active_count: int,
        completed_count: int,
        stats: Dict[str, Any],
    ) -> str:
        """Build a plain English governance summary."""
        model_names = {
            VotingModel.ONE_PERSON_ONE_VOTE: "one-person-one-vote",
            VotingModel.TOKEN_WEIGHTED: "token-weighted",
            VotingModel.QUADRATIC: "quadratic",
        }
        model_name = model_names.get(model, model.value)

        parts = [f"Your governance uses {model_name} voting (permanent choice)."]
        if active_count > 0:
            parts.append(f"{active_count} proposal(s) are currently open for voting.")
        else:
            parts.append("No proposals are currently open.")
        if completed_count > 0:
            parts.append(
                f"{stats['proposals_passed']} of {completed_count} recent proposals passed."
            )
        parts.append("All governance votes are free. Results are recorded on-chain via EAS attestation.")
        return " ".join(parts)
