"""
Vesting Engine — calculates releasable funds based on vesting type.

Part of Component 22 (Community Fundraising).
Supports immediate, time-based, milestone-based, and hybrid vesting.
"""

from __future__ import annotations

import logging
import time
from enum import Enum
from typing import Optional

logger = logging.getLogger(__name__)


class VestingType(Enum):
    """How campaign funds are released."""
    IMMEDIATE = "immediate"
    MILESTONE_BASED = "milestone_based"
    TIME_BASED = "time_based"
    HYBRID = "hybrid"


class VestingEngine:
    """
    Calculates how much of a campaign's raised funds are releasable.

    - Immediate: 100% released as soon as campaign is funded.
    - TimeBased: Linear release over vesting_duration after cliff.
    - MilestoneBased: Released per verified milestone amount.
    - Hybrid: 50% time-based + 50% milestone-based.
    """

    def __init__(self) -> None:
        logger.info("VestingEngine initialised.")

    def compute_releasable(
        self,
        vesting_type: VestingType,
        total_raised_wei: int,
        total_released_wei: int,
        vesting_start: float,
        vesting_duration: int,
        vesting_cliff: int,
        milestone_released_wei: int = 0,
    ) -> int:
        """
        Compute how much can be released right now.

        Args:
            vesting_type: The vesting schedule type.
            total_raised_wei: Total funds raised.
            total_released_wei: Funds already released.
            vesting_start: Unix timestamp when vesting begins.
            vesting_duration: Total vesting duration in seconds.
            vesting_cliff: Cliff period in seconds (no release before).
            milestone_released_wei: Funds unlocked by verified milestones.

        Returns:
            Amount in wei that can be released now.
        """
        if vesting_type == VestingType.IMMEDIATE:
            return self._immediate(total_raised_wei, total_released_wei)
        elif vesting_type == VestingType.TIME_BASED:
            return self._time_based(
                total_raised_wei, total_released_wei,
                vesting_start, vesting_duration, vesting_cliff,
            )
        elif vesting_type == VestingType.MILESTONE_BASED:
            return self._milestone_based(
                milestone_released_wei, total_released_wei,
            )
        elif vesting_type == VestingType.HYBRID:
            return self._hybrid(
                total_raised_wei, total_released_wei,
                vesting_start, vesting_duration, vesting_cliff,
                milestone_released_wei,
            )
        else:
            raise ValueError(f"Unknown vesting type: {vesting_type}")

    def _immediate(
        self, total_raised_wei: int, total_released_wei: int,
    ) -> int:
        """100% available immediately."""
        return max(0, total_raised_wei - total_released_wei)

    def _time_based(
        self,
        total_raised_wei: int,
        total_released_wei: int,
        vesting_start: float,
        vesting_duration: int,
        vesting_cliff: int,
    ) -> int:
        """Linear vesting after cliff."""
        now = time.time()
        elapsed = now - vesting_start

        if elapsed < vesting_cliff:
            return 0

        if vesting_duration <= 0:
            vested = total_raised_wei
        else:
            fraction = min(elapsed / vesting_duration, 1.0)
            vested = int(total_raised_wei * fraction)

        return max(0, vested - total_released_wei)

    def _milestone_based(
        self, milestone_released_wei: int, total_released_wei: int,
    ) -> int:
        """Release only what milestones have unlocked."""
        return max(0, milestone_released_wei - total_released_wei)

    def _hybrid(
        self,
        total_raised_wei: int,
        total_released_wei: int,
        vesting_start: float,
        vesting_duration: int,
        vesting_cliff: int,
        milestone_released_wei: int,
    ) -> int:
        """50% time-based + 50% milestone-based."""
        half = total_raised_wei // 2

        time_vested = self._time_based(
            half, 0, vesting_start, vesting_duration, vesting_cliff,
        )
        milestone_vested = min(milestone_released_wei, half)

        total_vested = time_vested + milestone_vested
        return max(0, total_vested - total_released_wei)
