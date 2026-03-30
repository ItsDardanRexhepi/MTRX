"""
Component 19 — Governance and Voting

Platform-wide policy votes ONLY. Bilateral disputes rejected and redirected to Component 30.
Three voting models: one-person-one-vote, token-weighted, quadratic. Choice is PERMANENT.
Quorum: valid when all PARTICIPATING voters have cast. Non-voters not counted.
Free always — no fees. EAS attestation on every result.
"""

from runtime.blockchain.services.governance.proposal_manager import ProposalManager
from runtime.blockchain.services.governance.voting_engine import VotingEngine
from runtime.blockchain.services.governance.model_selector import ModelSelector
from runtime.blockchain.services.governance.results_executor import ResultsExecutor
from runtime.blockchain.services.governance.dashboard import GovernanceDashboard
from runtime.blockchain.services.governance.anti_manipulation import AntiManipulation

__all__ = [
    "ProposalManager",
    "VotingEngine",
    "ModelSelector",
    "ResultsExecutor",
    "GovernanceDashboard",
    "AntiManipulation",
]
