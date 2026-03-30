"""
Rewards Distributor — distributes staking rewards based on APY from canonical source.

Part of Component 16 (Staking).
All APY values sourced exclusively from APYCalculator.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from runtime.blockchain.services.staking.apy_calculator import APYCalculator, StakingTier

logger = logging.getLogger(__name__)


NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class RewardDistribution:
    """Record of a reward distribution event."""
    distribution_id: str
    recipient: str
    tier: StakingTier
    staked_amount_wei: int
    reward_amount_wei: int
    apy_bps_at_distribution: int
    period_start: float
    period_end: float
    tx_hash: Optional[str] = None


@dataclass
class DistributionCycle:
    """A complete distribution cycle across all stakers."""
    cycle_id: str
    started_at: float
    completed_at: Optional[float] = None
    total_distributed_wei: int = 0
    recipient_count: int = 0
    distributions: List[RewardDistribution] = field(default_factory=list)


class RewardsDistributor:
    """
    Distributes staking rewards to all active stakers.

    Reward amounts are calculated using the canonical APYCalculator.
    Distribution runs periodically (configurable interval).
    All reward tokens come from the platform reward pool.
    """

    DEFAULT_INTERVAL_SECONDS: int = 86_400  # 24 hours

    def __init__(
        self,
        apy_calculator: APYCalculator,
        distribution_interval: int = DEFAULT_INTERVAL_SECONDS,
        send_reward_fn: Optional[Callable[[str, int], Optional[str]]] = None,
    ) -> None:
        """
        Args:
            apy_calculator: Canonical APY source.
            distribution_interval: Seconds between distribution cycles.
            send_reward_fn: Callable(to_address, amount_wei) -> tx_hash.
        """
        self._apy = apy_calculator
        self._interval = distribution_interval
        self._send_reward = send_reward_fn

        self._cycles: List[DistributionCycle] = []
        self._last_distribution: float = 0.0
        self._cycle_counter: int = 0

        # Accumulated rewards per user (claimable balance)
        self._pending_rewards: Dict[str, int] = {}
        # Total distributed lifetime
        self._total_distributed_wei: int = 0

        logger.info(
            "RewardsDistributor initialised | interval=%ds", distribution_interval,
        )

    # ── Distribution ──────────────────────────────────────────────────

    def distribute_rewards(
        self,
        active_stakes: List[Dict[str, Any]],
    ) -> DistributionCycle:
        """
        Run a distribution cycle for all active stakers.

        Each stake is evaluated using the canonical APY for its tier,
        prorated for the time since last distribution.

        Args:
            active_stakes: List of dicts with keys:
                - user_address (str)
                - tier (StakingTier)
                - amount_wei (int)
                - staked_at (float)

        Returns:
            DistributionCycle with all individual distributions.

        Raises:
            ValueError: If distribution is called too soon.
        """
        now = time.time()
        if self._last_distribution > 0:
            elapsed = now - self._last_distribution
            if elapsed < self._interval * 0.9:
                raise ValueError(
                    f"Distribution interval not met. {self._interval - elapsed:.0f}s remaining."
                )

        self._cycle_counter += 1
        cycle_id = f"DIST-CYCLE-{self._cycle_counter:06d}"
        period_start = self._last_distribution if self._last_distribution > 0 else now - self._interval
        period_end = now

        cycle = DistributionCycle(
            cycle_id=cycle_id,
            started_at=now,
        )

        for stake in active_stakes:
            distribution = self._compute_and_distribute(
                user_address=stake["user_address"],
                tier=stake["tier"],
                amount_wei=stake["amount_wei"],
                period_start=period_start,
                period_end=period_end,
                cycle_id=cycle_id,
            )
            if distribution is not None:
                cycle.distributions.append(distribution)
                cycle.total_distributed_wei += distribution.reward_amount_wei
                cycle.recipient_count += 1

        cycle.completed_at = time.time()
        self._cycles.append(cycle)
        self._last_distribution = now
        self._total_distributed_wei += cycle.total_distributed_wei

        logger.info(
            "Distribution cycle %s completed | recipients=%d | total=%d wei",
            cycle_id, cycle.recipient_count, cycle.total_distributed_wei,
        )
        return cycle

    def claim_rewards(self, user_address: str) -> int:
        """
        Claim accumulated pending rewards for a user.

        Args:
            user_address: Address of the claiming user.

        Returns:
            Amount claimed in wei.
        """
        amount = self._pending_rewards.get(user_address, 0)
        if amount <= 0:
            return 0

        tx_hash: Optional[str] = None
        if self._send_reward is not None:
            try:
                tx_hash = self._send_reward(user_address, amount)
            except Exception:
                logger.exception("Failed to send reward to %s.", user_address)
                raise

        self._pending_rewards[user_address] = 0
        logger.info(
            "Rewards claimed | user=%s | amount=%d wei | tx=%s",
            user_address, amount, tx_hash,
        )
        return amount

    # ── Queries ───────────────────────────────────────────────────────

    def get_pending_rewards(self, user_address: str) -> int:
        """Return pending unclaimed rewards for a user."""
        return self._pending_rewards.get(user_address, 0)

    def get_total_distributed(self) -> int:
        """Return lifetime total distributed rewards."""
        return self._total_distributed_wei

    def get_cycle_history(self, limit: int = 10) -> List[DistributionCycle]:
        """Return recent distribution cycles."""
        return list(reversed(self._cycles[-limit:]))

    def get_last_distribution_time(self) -> float:
        """Return timestamp of last distribution."""
        return self._last_distribution

    def get_next_distribution_time(self) -> float:
        """Return estimated timestamp of next distribution."""
        if self._last_distribution <= 0:
            return time.time()
        return self._last_distribution + self._interval

    # ── Internal ──────────────────────────────────────────────────────

    def _compute_and_distribute(
        self,
        user_address: str,
        tier: StakingTier,
        amount_wei: int,
        period_start: float,
        period_end: float,
        cycle_id: str,
    ) -> Optional[RewardDistribution]:
        """Compute and record a single reward distribution."""
        duration = period_end - period_start
        if duration <= 0 or amount_wei <= 0:
            return None

        # Get APY from canonical source
        snapshot = self._apy.get_apy(tier)
        annual_rate = snapshot.effective_apy_bps / 10_000
        duration_years = duration / (365.25 * 86_400)

        reward = int(amount_wei * annual_rate * duration_years)
        if reward <= 0:
            return None

        # Accumulate pending rewards
        self._pending_rewards[user_address] = (
            self._pending_rewards.get(user_address, 0) + reward
        )

        dist_counter = len(self._cycles) * 1000 + len(
            self._cycles[-1].distributions if self._cycles else []
        )
        distribution = RewardDistribution(
            distribution_id=f"{cycle_id}-{dist_counter:04d}",
            recipient=user_address,
            tier=tier,
            staked_amount_wei=amount_wei,
            reward_amount_wei=reward,
            apy_bps_at_distribution=snapshot.effective_apy_bps,
            period_start=period_start,
            period_end=period_end,
        )

        logger.debug(
            "Reward computed | user=%s | tier=%s | reward=%d wei | apy=%d bps",
            user_address, tier.value, reward, snapshot.effective_apy_bps,
        )
        return distribution
