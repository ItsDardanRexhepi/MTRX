"""
Component 21 — Decentralized Exchange (DEX)

Wraps Uniswap v3/v4 on Base network. Provides routing, liquidity management,
token registry, price feeds (via Component 11 oracle), EAS attestation hooks,
Trinity interface, and LP readiness checks.
"""

from runtime.blockchain.services.dex.router import DEXRouter
from runtime.blockchain.services.dex.liquidity_manager import LiquidityManager
from runtime.blockchain.services.dex.token_registry import TokenRegistry
from runtime.blockchain.services.dex.price_feed import DEXPriceFeed
from runtime.blockchain.services.dex.attestation_hook import DEXAttestationHook
from runtime.blockchain.services.dex.trinity_interface import DEXTrinityInterface
from runtime.blockchain.services.dex.lp_readiness import LPReadinessChecker

__all__ = [
    "DEXRouter",
    "LiquidityManager",
    "TokenRegistry",
    "DEXPriceFeed",
    "DEXAttestationHook",
    "DEXTrinityInterface",
    "LPReadinessChecker",
]
