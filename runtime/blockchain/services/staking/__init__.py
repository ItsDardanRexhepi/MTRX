"""
Component 16 — Staking Services

Token staking with APY calculation, staking UI, and reward distribution.
APYCalculator is the CANONICAL single source of truth for ALL APY display
across the entire platform. No other component computes or caches APY independently.
"""

from runtime.blockchain.services.staking.apy_calculator import APYCalculator
from runtime.blockchain.services.staking.staking_ui import StakingUI
from runtime.blockchain.services.staking.rewards_distributor import RewardsDistributor

__all__ = [
    "APYCalculator",
    "StakingUI",
    "RewardsDistributor",
]
