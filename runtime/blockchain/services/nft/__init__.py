"""
OpenMatrix Component 3 — NFT Creation and Artist Services

This package provides the Python runtime for NFT lifecycle management including:
- NFT valuation engine with 90-day assessment cycles
- Valuation fallback logic for tokens with no secondary trading
- Royalty enforcement with NeoSafe 10% routing on every sale
- Dispute routing to Component 30 for bilateral NFT disputes

NeoSafe: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5

Architecture:
    OpenMatrixNFT.sol <-> valuation.py         (90-day assessment cycle)
    OpenMatrixNFT.sol <-> royalty_enforcer.py   (sale distribution)
    NFTRights.sol     <-> valuation.py          (rights reversion timer)
    valuation.py      <-> valuation_fallback.py (fallback when no trades)
    dispute_connector <-> Component 30          (bilateral dispute routing)
    valuation.py      <-> Component 11 oracle   (price feeds — NEVER direct Chainlink)
"""

from runtime.blockchain.services.nft.valuation import NFTValuationEngine, ValuationResult
from runtime.blockchain.services.nft.valuation_fallback import ValuationFallback, CollectionInfo
from runtime.blockchain.services.nft.royalty_enforcer import RoyaltyEnforcer
from runtime.blockchain.services.nft.dispute_connector import DisputeConnector

__all__ = [
    "NFTValuationEngine",
    "ValuationResult",
    "ValuationFallback",
    "CollectionInfo",
    "RoyaltyEnforcer",
    "DisputeConnector",
]

__version__ = "1.0.0"
__component__ = 3
