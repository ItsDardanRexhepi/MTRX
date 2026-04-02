"""
Component 14 — Gaming

Full game lifecycle: vetting/registry, milestone-based funding,
ERC-1155 asset management, and 80/20 revenue splitting.
"""

from runtime.blockchain.services.gaming.game_registry import GameRegistryService
from runtime.blockchain.services.gaming.game_funding import GameFundingService
from runtime.blockchain.services.gaming.asset_manager import GameAssetManager
from runtime.blockchain.services.gaming.revenue_splitter import RevenueSplitter

__all__ = [
    "GameRegistryService",
    "GameFundingService",
    "GameAssetManager",
    "RevenueSplitter",
]
