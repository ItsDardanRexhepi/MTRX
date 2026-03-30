"""
Component 23 — Smart Loyalty and Rewards

Platform-native rewards from treasury based on verifiable on-chain activity.
Business-deployed reward programs where platform takes NOTHING.
Zero card linking, zero spending data shared.
ZKP eligibility validation confirms without revealing identity or behavior.
"""

from runtime.blockchain.services.loyalty.platform_rewards import PlatformRewards
from runtime.blockchain.services.loyalty.business_rewards import BusinessRewardsDeployer
from runtime.blockchain.services.loyalty.dashboard import LoyaltyDashboard
from runtime.blockchain.services.loyalty.zkp_validator import ZKPEligibilityValidator

__all__ = [
    "PlatformRewards",
    "BusinessRewardsDeployer",
    "LoyaltyDashboard",
    "ZKPEligibilityValidator",
]
