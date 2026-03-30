"""
Component 4 -- Real-World Asset Tokenization
=============================================

Tokenizes real-world assets (property, vehicles, general assets) as on-chain
representations with joint ownership, pooled purchases, legal bridging, and
full chain-of-custody event emission for Component 12.

Sub-modules
-----------
legal_bridge       : Bidirectional hash link between smart contracts and legal documents.
property_tokenizer : Tokenization engine for real-estate assets.
vehicle_tokenizer  : Tokenization engine for vehicle assets.
asset_tokenizer    : General-purpose tokenization for any asset class.
asset_verifier     : Oracle-backed asset valuation via Component 11.
pooled_purchase    : Multi-party pooled fund coordinator with escrow.
custody_emitter    : Ownership transfer event emitter for Component 12.
dispute_connector  : Routes bilateral co-owner disputes to Component 30.
"""

from runtime.blockchain.services.rwa.legal_bridge import LegalBridge
from runtime.blockchain.services.rwa.property_tokenizer import PropertyTokenizer
from runtime.blockchain.services.rwa.vehicle_tokenizer import VehicleTokenizer
from runtime.blockchain.services.rwa.asset_tokenizer import AssetTokenizer
from runtime.blockchain.services.rwa.asset_verifier import AssetVerifier
from runtime.blockchain.services.rwa.pooled_purchase import PooledPurchaseCoordinator
from runtime.blockchain.services.rwa.custody_emitter import CustodyEmitter
from runtime.blockchain.services.rwa.dispute_connector import DisputeConnector

__all__ = [
    "LegalBridge",
    "PropertyTokenizer",
    "VehicleTokenizer",
    "AssetTokenizer",
    "AssetVerifier",
    "PooledPurchaseCoordinator",
    "CustodyEmitter",
    "DisputeConnector",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 4
COMPONENT_NAME: str = "Real-World Asset Tokenization"
