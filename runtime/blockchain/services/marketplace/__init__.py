"""
Component 24 — Marketplace

Peer-to-peer NFT/asset marketplace supporting ERC721 and ERC1155,
with escrow, compliance filtering, EAS attestations, and 5% platform fee.
"""

from runtime.blockchain.services.marketplace.marketplace_service import MarketplaceService

__all__ = [
    "MarketplaceService",
]
