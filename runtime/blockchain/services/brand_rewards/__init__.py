"""
Component 25 — Brand Rewards

Brand reward campaigns with open/allowlist/ZKP eligibility modes,
campaign funding, reward claiming, and lifecycle management.
"""

from runtime.blockchain.services.brand_rewards.campaign_manager import BrandCampaignManager

__all__ = [
    "BrandCampaignManager",
]
