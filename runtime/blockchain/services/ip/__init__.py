"""
Component 15 — IP and Royalty Management Services.

Provides IP registration with blockchain timestamping, royalty enforcement,
revenue tracking, fee scheduling, proof generation, qualifying transaction
management, and dispute routing.
"""

from runtime.blockchain.services.ip.revenue_tracker import RevenueTracker
from runtime.blockchain.services.ip.fee_scheduler import FeeScheduler
from runtime.blockchain.services.ip.royalty_distributor import RoyaltyDistributor
from runtime.blockchain.services.ip.proof_generator import IPProofGenerator
from runtime.blockchain.services.ip.transaction_manager import QualifyingTransactionManager
from runtime.blockchain.services.ip.dispute_connector import IPDisputeConnector

__all__ = [
    "RevenueTracker",
    "FeeScheduler",
    "RoyaltyDistributor",
    "IPProofGenerator",
    "QualifyingTransactionManager",
    "IPDisputeConnector",
]
