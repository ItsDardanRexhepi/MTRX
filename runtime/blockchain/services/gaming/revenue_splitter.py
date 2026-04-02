"""
Revenue Splitter — immutable 80/20 game revenue split.

Part of Component 14 (Gaming).
80% to developer, 20% to platform (NeoSafe). No admin functions.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
DEVELOPER_SHARE_BPS: int = 8000  # 80%
PLATFORM_SHARE_BPS: int = 2000   # 20%


@dataclass
class RevenueStats:
    """Revenue statistics for a game."""
    game_id: str
    developer: str
    total_revenue_wei: int = 0
    total_developer_paid_wei: int = 0
    total_platform_paid_wei: int = 0
    pending_balance_wei: int = 0


@dataclass
class DistributionRecord:
    """Record of a revenue distribution."""
    game_id: str
    total_wei: int
    developer_wei: int
    platform_wei: int
    timestamp: float = field(default_factory=time.time)


class RevenueSplitter:
    """
    Immutable 80/20 revenue split for games.

    Revenue flows in via deposit_revenue(). distribute_balance()
    splits the accumulated balance: 80% developer, 20% platform.
    No admin functions — the split is fixed at construction.
    """

    def __init__(
        self,
        game_id: str,
        developer: str,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        if not developer.startswith("0x"):
            raise ValueError("Invalid developer address.")

        self._game_id = game_id
        self._developer = developer
        self._execute = execute_fn
        self._total_revenue_wei: int = 0
        self._total_developer_paid_wei: int = 0
        self._total_platform_paid_wei: int = 0
        self._pending_balance_wei: int = 0
        self._distributions: list = []
        logger.info(
            "RevenueSplitter initialised | game=%s | dev=%s",
            game_id, developer,
        )

    def deposit_revenue(self, amount_wei: int) -> int:
        """
        Deposit revenue for later distribution.

        Args:
            amount_wei: Revenue amount in wei.

        Returns:
            New pending balance.
        """
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        self._total_revenue_wei += amount_wei
        self._pending_balance_wei += amount_wei

        logger.info(
            "Revenue deposited | game=%s | amount=%d | pending=%d",
            self._game_id, amount_wei, self._pending_balance_wei,
        )
        return self._pending_balance_wei

    def distribute_balance(self) -> DistributionRecord:
        """
        Distribute the pending balance: 80% to developer, 20% to platform.

        Returns:
            DistributionRecord with the split amounts.
        """
        if self._pending_balance_wei <= 0:
            raise ValueError("No pending balance to distribute.")

        total = self._pending_balance_wei
        developer_amount = (total * DEVELOPER_SHARE_BPS) // 10_000
        platform_amount = total - developer_amount  # Remainder to platform

        self._total_developer_paid_wei += developer_amount
        self._total_platform_paid_wei += platform_amount
        self._pending_balance_wei = 0

        record = DistributionRecord(
            game_id=self._game_id,
            total_wei=total,
            developer_wei=developer_amount,
            platform_wei=platform_amount,
        )
        self._distributions.append(record)

        logger.info(
            "Revenue distributed | game=%s | total=%d | dev=%d | platform=%d",
            self._game_id, total, developer_amount, platform_amount,
        )
        return record

    def get_stats(self) -> RevenueStats:
        """Get revenue statistics."""
        return RevenueStats(
            game_id=self._game_id,
            developer=self._developer,
            total_revenue_wei=self._total_revenue_wei,
            total_developer_paid_wei=self._total_developer_paid_wei,
            total_platform_paid_wei=self._total_platform_paid_wei,
            pending_balance_wei=self._pending_balance_wei,
        )
