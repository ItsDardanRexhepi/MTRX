"""
APY Calculator — CANONICAL single source of truth for ALL APY display
across the entire MTRX platform.

Part of Component 16 (Staking).

NO other component, dashboard, or UI may compute APY independently.
All APY queries MUST route through this module.
"""

from __future__ import annotations

import logging
import math
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


class StakingTier(Enum):
    """Staking tiers with minimum lock durations."""
    FLEXIBLE = "flexible"       # No lock, lowest APY
    SHORT = "short"             # 30 days
    MEDIUM = "medium"           # 90 days
    LONG = "long"               # 180 days
    MAXIMUM = "maximum"         # 365 days, highest APY


@dataclass
class APYSnapshot:
    """Point-in-time APY reading for a tier."""
    tier: StakingTier
    base_rate_bps: int          # Base APY in basis points (100 = 1%)
    bonus_rate_bps: int         # Additional bonus from pool utilization
    effective_apy_bps: int      # Total effective APY
    computed_at: float = field(default_factory=time.time)
    total_staked_wei: int = 0
    pool_utilization_pct: float = 0.0


# Lock durations in seconds per tier
TIER_LOCK_SECONDS: Dict[StakingTier, int] = {
    StakingTier.FLEXIBLE: 0,
    StakingTier.SHORT: 30 * 86_400,
    StakingTier.MEDIUM: 90 * 86_400,
    StakingTier.LONG: 180 * 86_400,
    StakingTier.MAXIMUM: 365 * 86_400,
}

# Base APY rates in basis points per tier
TIER_BASE_RATES_BPS: Dict[StakingTier, int] = {
    StakingTier.FLEXIBLE: 200,   # 2%
    StakingTier.SHORT: 400,      # 4%
    StakingTier.MEDIUM: 600,     # 6%
    StakingTier.LONG: 900,       # 9%
    StakingTier.MAXIMUM: 1200,   # 12%
}


class APYCalculator:
    """
    CANONICAL single source of truth for ALL APY display in the MTRX platform.

    Every component, dashboard, and UI that needs to display APY MUST
    call this calculator. Direct APY computation elsewhere is prohibited.

    APY is computed from:
    - Base rate per staking tier (lock duration)
    - Bonus from pool utilization (higher utilization = lower bonus, scarcity reward)
    - Supply cap adjustment (diminishing returns as total staked approaches cap)
    """

    MAX_BONUS_BPS: int = 500     # Maximum 5% bonus
    SUPPLY_CAP_WEI: int = 100_000_000 * 10**18  # 100M token supply cap

    def __init__(self, reward_pool_wei: int = 0) -> None:
        """
        Args:
            reward_pool_wei: Total reward tokens available for distribution.
        """
        self._reward_pool_wei = reward_pool_wei
        # tier -> total staked
        self._staked_by_tier: Dict[StakingTier, int] = {t: 0 for t in StakingTier}
        self._total_staked_wei: int = 0
        # Cache of latest snapshots
        self._latest_snapshots: Dict[StakingTier, APYSnapshot] = {}
        self._last_recompute: float = 0.0

        logger.info("APYCalculator initialised (CANONICAL source of truth).")

    # ── Core APY Computation ──────────────────────────────────────────

    def get_apy(self, tier: StakingTier) -> APYSnapshot:
        """
        Get the current APY for a staking tier.

        This is the ONLY method any component should call to get APY values.
        The result includes base rate, bonus, and effective total.

        Args:
            tier: The staking tier to query.

        Returns:
            APYSnapshot with the current effective APY.
        """
        base_bps = TIER_BASE_RATES_BPS[tier]
        bonus_bps = self._compute_utilization_bonus(tier)
        supply_factor = self._compute_supply_factor()

        effective_bps = int((base_bps + bonus_bps) * supply_factor)
        # Ensure effective APY is non-negative
        effective_bps = max(effective_bps, 0)

        utilization = self._get_pool_utilization()

        snapshot = APYSnapshot(
            tier=tier,
            base_rate_bps=base_bps,
            bonus_rate_bps=bonus_bps,
            effective_apy_bps=effective_bps,
            total_staked_wei=self._staked_by_tier[tier],
            pool_utilization_pct=utilization,
        )
        self._latest_snapshots[tier] = snapshot
        return snapshot

    def get_all_apys(self) -> Dict[StakingTier, APYSnapshot]:
        """
        Get APY snapshots for ALL tiers. Used by dashboards and UI.

        Returns:
            Mapping of tier -> APYSnapshot for every tier.
        """
        return {tier: self.get_apy(tier) for tier in StakingTier}

    def get_effective_apy_percent(self, tier: StakingTier) -> float:
        """
        Convenience method returning effective APY as a percentage (e.g. 12.5).

        Args:
            tier: The staking tier.

        Returns:
            Effective APY as a float percentage.
        """
        snapshot = self.get_apy(tier)
        return snapshot.effective_apy_bps / 100.0

    # ── Staking State Updates ─────────────────────────────────────────

    def record_stake(self, tier: StakingTier, amount_wei: int) -> None:
        """
        Record a new stake, updating totals for APY recalculation.

        Args:
            tier: The tier being staked into.
            amount_wei: Amount staked in wei.

        Raises:
            ValueError: If amount is non-positive.
        """
        if amount_wei <= 0:
            raise ValueError("Stake amount must be positive.")
        self._staked_by_tier[tier] += amount_wei
        self._total_staked_wei += amount_wei
        logger.debug(
            "Stake recorded | tier=%s | amount=%d | total=%d",
            tier.value, amount_wei, self._total_staked_wei,
        )

    def record_unstake(self, tier: StakingTier, amount_wei: int) -> None:
        """
        Record an unstake, updating totals for APY recalculation.

        Args:
            tier: The tier being unstaked from.
            amount_wei: Amount unstaked in wei.

        Raises:
            ValueError: If amount exceeds staked balance.
        """
        if amount_wei > self._staked_by_tier[tier]:
            raise ValueError(
                f"Cannot unstake {amount_wei} — only {self._staked_by_tier[tier]} staked in {tier.value}."
            )
        self._staked_by_tier[tier] -= amount_wei
        self._total_staked_wei -= amount_wei
        logger.debug(
            "Unstake recorded | tier=%s | amount=%d | total=%d",
            tier.value, amount_wei, self._total_staked_wei,
        )

    def set_reward_pool(self, amount_wei: int) -> None:
        """Update the total reward pool available for distribution."""
        self._reward_pool_wei = amount_wei
        logger.info("Reward pool updated to %d wei.", amount_wei)

    # ── Reward Estimation ─────────────────────────────────────────────

    def estimate_rewards(
        self,
        tier: StakingTier,
        stake_amount_wei: int,
        duration_seconds: int,
    ) -> int:
        """
        Estimate rewards for a hypothetical stake.

        Args:
            tier: The staking tier.
            stake_amount_wei: Amount to stake.
            duration_seconds: How long to stake.

        Returns:
            Estimated reward in wei.
        """
        snapshot = self.get_apy(tier)
        annual_rate = snapshot.effective_apy_bps / 10_000
        duration_years = duration_seconds / (365.25 * 86_400)
        # Compound interest
        reward = int(stake_amount_wei * (math.exp(annual_rate * duration_years) - 1))
        return reward

    # ── Queries ───────────────────────────────────────────────────────

    def get_total_staked(self) -> int:
        """Return total staked across all tiers."""
        return self._total_staked_wei

    def get_staked_by_tier(self, tier: StakingTier) -> int:
        """Return total staked in a specific tier."""
        return self._staked_by_tier[tier]

    def get_lock_duration(self, tier: StakingTier) -> int:
        """Return lock duration in seconds for a tier."""
        return TIER_LOCK_SECONDS[tier]

    # ── Internal ──────────────────────────────────────────────────────

    def _compute_utilization_bonus(self, tier: StakingTier) -> int:
        """
        Compute bonus APY from pool utilization.

        Lower utilization = higher bonus (scarcity incentive).
        """
        utilization = self._get_pool_utilization()
        # Inverse relationship: less utilization = more bonus
        if utilization >= 1.0:
            return 0
        remaining = 1.0 - utilization
        return int(self.MAX_BONUS_BPS * remaining)

    def _compute_supply_factor(self) -> float:
        """
        Diminishing returns as total staked approaches supply cap.

        Returns a multiplier between 0.5 and 1.0.
        """
        if self._total_staked_wei <= 0:
            return 1.0
        ratio = self._total_staked_wei / self.SUPPLY_CAP_WEI
        # Logarithmic decay: starts at 1.0, approaches 0.5 at cap
        factor = 1.0 - (0.5 * ratio)
        return max(factor, 0.5)

    def _get_pool_utilization(self) -> float:
        """Return pool utilization as a fraction (0.0 to 1.0)."""
        if self._reward_pool_wei <= 0:
            return 1.0
        return min(self._total_staked_wei / self._reward_pool_wei, 1.0)
