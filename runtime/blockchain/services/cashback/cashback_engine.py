"""
Cashback Engine — annual power-user cashback rewards.

Part of Component 26 (Power User Cashback).
Tracks user spending, calculates qualification, allocates and distributes
annual cashback from a funded reward pool.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Qualification thresholds
MIN_SPEND_USD: int = 10_000         # Minimum annual spend to qualify
CASHBACK_RATE_BPS: int = 100        # 1% of net revenue


@dataclass
class YearlyDistribution:
    """Annual reward pool state."""
    year: int
    reward_pool_balance_wei: int = 0
    total_claimed_wei: int = 0
    distribution_timestamp: float = 0.0
    funded: bool = False
    enabled: bool = False


@dataclass
class UserYearlyRecord:
    """User's spending and revenue record for a year."""
    user: str
    year: int
    total_spend_usd: int = 0
    net_revenue_wei: int = 0
    reward_allocated_wei: int = 0
    reward_claimed: bool = False


class CashbackEngine:
    """
    Manages the annual power-user cashback programme.

    Lifecycle per year:
    1. Record spends and net revenue throughout the year.
    2. Fund the distribution pool.
    3. Allocate rewards to qualifying users.
    4. Enable distribution so users can claim.
    5. Sweep unclaimed after deadline.
    """

    SWEEP_DELAY_SECONDS: int = 90 * 86_400  # 90 days after enable

    def __init__(
        self,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._execute = execute_fn
        self._distributions: Dict[int, YearlyDistribution] = {}
        # (user, year) -> UserYearlyRecord
        self._records: Dict[tuple, UserYearlyRecord] = {}
        self._recorders: Set[str] = set()
        logger.info("CashbackEngine initialised.")

    # ── Recorder Management ───────────────────────────────────────────

    def add_recorder(self, address: str) -> None:
        """Add an authorized spend/revenue recorder."""
        if not address.startswith("0x"):
            raise ValueError("Invalid address.")
        self._recorders.add(address)
        logger.info("Recorder added | addr=%s", address)

    def remove_recorder(self, address: str) -> None:
        """Remove a recorder."""
        self._recorders.discard(address)
        logger.info("Recorder removed | addr=%s", address)

    # ── Recording ─────────────────────────────────────────────────────

    def record_spend(
        self, recorder: str, user: str, year: int, amount_usd: int,
    ) -> None:
        """
        Record a user's spend for a year.

        Args:
            recorder: Authorized recorder address.
            user: User's address.
            year: The fiscal year.
            amount_usd: Spend amount in USD (integer).
        """
        self._check_recorder(recorder)
        if amount_usd <= 0:
            raise ValueError("Amount must be positive.")

        key = (user, year)
        if key not in self._records:
            self._records[key] = UserYearlyRecord(user=user, year=year)
        self._records[key].total_spend_usd += amount_usd

        logger.debug(
            "Spend recorded | user=%s | year=%d | amount=%d | total=%d",
            user, year, amount_usd, self._records[key].total_spend_usd,
        )

    def record_net_revenue(
        self, recorder: str, user: str, year: int, amount_wei: int,
    ) -> None:
        """Record net revenue attributed to a user for a year."""
        self._check_recorder(recorder)
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        key = (user, year)
        if key not in self._records:
            self._records[key] = UserYearlyRecord(user=user, year=year)
        self._records[key].net_revenue_wei += amount_wei

        logger.debug(
            "Revenue recorded | user=%s | year=%d | amount=%d",
            user, year, amount_wei,
        )

    # ── Allocation ────────────────────────────────────────────────────

    def allocate_reward(self, user: str, year: int) -> int:
        """
        Allocate cashback reward for a qualifying user.

        Returns:
            Allocated reward in wei.

        Raises:
            ValueError: If user doesn't qualify or already allocated.
        """
        key = (user, year)
        record = self._records.get(key)
        if record is None:
            raise ValueError(f"No records for user {user} in year {year}.")
        if record.reward_allocated_wei > 0:
            raise ValueError(f"Reward already allocated for {user} in {year}.")
        if not self.is_qualified(user, year):
            raise ValueError(f"User {user} does not qualify for year {year}.")

        # 1% of net revenue
        reward = (record.net_revenue_wei * CASHBACK_RATE_BPS) // 10_000
        if reward <= 0:
            raise ValueError("Calculated reward is zero.")

        record.reward_allocated_wei = reward
        logger.info(
            "Reward allocated | user=%s | year=%d | amount=%d",
            user, year, reward,
        )
        return reward

    def batch_allocate_rewards(
        self, users: List[str], year: int,
    ) -> Dict[str, int]:
        """Allocate rewards for multiple users. Returns user -> amount."""
        results = {}
        for user in users:
            try:
                amount = self.allocate_reward(user, year)
                results[user] = amount
            except ValueError as exc:
                logger.warning("Skip allocation | user=%s | reason=%s", user, exc)
        return results

    # ── Distribution Pool ─────────────────────────────────────────────

    def fund_distribution(self, year: int, amount_wei: int) -> YearlyDistribution:
        """Fund the reward pool for a year."""
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        dist = self._get_or_create_dist(year)
        dist.reward_pool_balance_wei += amount_wei
        dist.funded = True

        logger.info(
            "Distribution funded | year=%d | amount=%d | pool=%d",
            year, amount_wei, dist.reward_pool_balance_wei,
        )
        return dist

    def enable_distribution(self, year: int) -> YearlyDistribution:
        """Enable claiming for a year."""
        dist = self._get_or_create_dist(year)
        if not dist.funded:
            raise ValueError(f"Year {year} distribution not funded.")
        dist.enabled = True
        dist.distribution_timestamp = time.time()
        logger.info("Distribution enabled | year=%d", year)
        return dist

    # ── Claiming ──────────────────────────────────────────────────────

    def claim_reward(self, user: str, year: int) -> int:
        """
        Claim cashback reward for a year.

        Returns:
            Claimed amount in wei.
        """
        dist = self._distributions.get(year)
        if dist is None or not dist.enabled:
            raise ValueError(f"Distribution for year {year} not enabled.")

        key = (user, year)
        record = self._records.get(key)
        if record is None:
            raise ValueError(f"No record for user {user} in year {year}.")
        if record.reward_allocated_wei <= 0:
            raise ValueError("No reward allocated.")
        if record.reward_claimed:
            raise ValueError("Already claimed.")
        if record.reward_allocated_wei > dist.reward_pool_balance_wei:
            raise ValueError("Insufficient pool balance.")

        record.reward_claimed = True
        dist.total_claimed_wei += record.reward_allocated_wei
        dist.reward_pool_balance_wei -= record.reward_allocated_wei

        logger.info(
            "Reward claimed | user=%s | year=%d | amount=%d",
            user, year, record.reward_allocated_wei,
        )
        return record.reward_allocated_wei

    def sweep_unclaimed(self, year: int) -> int:
        """
        Sweep unclaimed rewards back to platform after deadline.

        Returns:
            Amount swept in wei.
        """
        dist = self._distributions.get(year)
        if dist is None:
            raise ValueError(f"No distribution for year {year}.")
        if not dist.enabled:
            raise ValueError("Distribution not enabled.")

        elapsed = time.time() - dist.distribution_timestamp
        if elapsed < self.SWEEP_DELAY_SECONDS:
            raise ValueError("Sweep deadline not reached.")

        swept = dist.reward_pool_balance_wei
        dist.reward_pool_balance_wei = 0

        logger.info("Unclaimed swept | year=%d | amount=%d", year, swept)
        return swept

    # ── Queries ───────────────────────────────────────────────────────

    def is_qualified(self, user: str, year: int) -> bool:
        """Check if a user qualifies for cashback."""
        key = (user, year)
        record = self._records.get(key)
        if record is None:
            return False
        return record.total_spend_usd >= MIN_SPEND_USD

    def get_reward(self, user: str, year: int) -> int:
        """Get allocated reward for a user and year."""
        key = (user, year)
        record = self._records.get(key)
        return record.reward_allocated_wei if record else 0

    def get_distribution(self, year: int) -> Optional[YearlyDistribution]:
        """Get distribution info for a year."""
        return self._distributions.get(year)

    # ── Internal ──────────────────────────────────────────────────────

    def _check_recorder(self, address: str) -> None:
        """Verify address is an authorized recorder."""
        if address not in self._recorders:
            raise ValueError(f"Address {address} is not an authorized recorder.")

    def _get_or_create_dist(self, year: int) -> YearlyDistribution:
        """Get or create yearly distribution."""
        if year not in self._distributions:
            self._distributions[year] = YearlyDistribution(year=year)
        return self._distributions[year]
