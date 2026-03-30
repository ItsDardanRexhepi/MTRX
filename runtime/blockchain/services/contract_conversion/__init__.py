"""
Component 1 — Smart Contract Conversion Service
=================================================

Converts natural-language contracts into enforceable, deployable Solidity
smart contracts with tiered revenue sharing routed to the NeoSafe wallet.

Sub-modules
-----------
parser            : NLP-based document parsing into structured contract data.
generator         : Solidity code generation from parsed contracts.
revenue_enforcer  : Real-time revenue monitoring and NeoSafe routing.
tier_manager      : Permanent tier tracking based on rolling 12-month revenue.
artist_classifier : Broad creative-worker classification engine.
dispute_connector : Routes bilateral disputes to Component 30.
templates         : Pre-built contract templates (rental, employment, etc.).
"""

from runtime.blockchain.services.contract_conversion.parser import (
    ContractParser,
    ParsedContract,
    Party,
    Condition,
    PaymentTerms,
    Trigger,
    DisputeResolution,
)
from runtime.blockchain.services.contract_conversion.generator import SolidityGenerator
from runtime.blockchain.services.contract_conversion.revenue_enforcer import RevenueEnforcer
from runtime.blockchain.services.contract_conversion.tier_manager import TierManager
from runtime.blockchain.services.contract_conversion.artist_classifier import ArtistClassifier
from runtime.blockchain.services.contract_conversion.dispute_connector import DisputeConnector

__all__ = [
    "ContractParser",
    "ParsedContract",
    "Party",
    "Condition",
    "PaymentTerms",
    "Trigger",
    "DisputeResolution",
    "SolidityGenerator",
    "RevenueEnforcer",
    "TierManager",
    "ArtistClassifier",
    "DisputeConnector",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 1
COMPONENT_NAME: str = "Smart Contract Conversion Service"
