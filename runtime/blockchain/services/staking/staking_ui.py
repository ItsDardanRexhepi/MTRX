"""
Staking UI — user-facing staking interface with plain English descriptions.

Part of Component 16 (Staking).
All APY values sourced exclusively from APYCalculator (canonical source).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from runtime.blockchain.services.staking.apy_calculator import (
    APYCalculator,
    StakingTier,
    TIER_LOCK_SECONDS,
)

logger = logging.getLogger(__name__)


@dataclass
class StakePosition:
    """A user's staking position."""
    position_id: str
    user_address: str
    tier: StakingTier
    amount_wei: int
    staked_at: float
    lock_until: float
    is_active: bool = True
    rewards_claimed_wei: int = 0


@dataclass
class StakingView:
    """Data structure for rendering the staking UI."""
    user_address: str
    positions: List[StakePosition]
    total_staked_wei: int
    total_rewards_earned_wei: int
    tier_details: List[Dict[str, Any]]
    plain_english_summary: str


class StakingUI:
    """
    User-facing staking interface providing plain English descriptions
    and clear tier comparisons.

    All APY values are fetched from APYCalculator — no local computation.
    """

    def __init__(self, apy_calculator: APYCalculator) -> None:
        """
        Args:
            apy_calculator: The canonical APY source (Component 16).
        """
        self._apy = apy_calculator
        self._positions: Dict[str, StakePosition] = {}
        self._user_positions: Dict[str, List[str]] = {}  # user -> [position_ids]
        self._counter: int = 0
        logger.info("StakingUI initialised.")

    # ── Staking Actions ───────────────────────────────────────────────

    def stake(
        self,
        user_address: str,
        tier: StakingTier,
        amount_wei: int,
    ) -> StakePosition:
        """
        Create a new staking position.

        Args:
            user_address: Address of the staker.
            tier: Staking tier to enter.
            amount_wei: Amount to stake in wei.

        Returns:
            The created StakePosition.

        Raises:
            ValueError: If amount is non-positive.
        """
        if amount_wei <= 0:
            raise ValueError("Stake amount must be positive.")
        if not user_address.startswith("0x"):
            raise ValueError(f"Invalid address: {user_address}")

        self._counter += 1
        position_id = f"STAKE-{self._counter:08d}"
        now = time.time()
        lock_duration = TIER_LOCK_SECONDS[tier]

        position = StakePosition(
            position_id=position_id,
            user_address=user_address,
            tier=tier,
            amount_wei=amount_wei,
            staked_at=now,
            lock_until=now + lock_duration,
        )

        self._positions[position_id] = position
        if user_address not in self._user_positions:
            self._user_positions[user_address] = []
        self._user_positions[user_address].append(position_id)

        # Update APY calculator totals
        self._apy.record_stake(tier, amount_wei)

        logger.info(
            "Stake created | id=%s | user=%s | tier=%s | amount=%d",
            position_id, user_address, tier.value, amount_wei,
        )
        return position

    def unstake(self, position_id: str, user_address: str) -> int:
        """
        Unstake a position if lock period has elapsed.

        Args:
            position_id: The position to unstake.
            user_address: Address of the staker (must match position owner).

        Returns:
            Amount unstaked in wei.

        Raises:
            ValueError: If position not found, not owned by user, or still locked.
        """
        position = self._positions.get(position_id)
        if position is None:
            raise ValueError(f"Position {position_id} not found.")
        if position.user_address != user_address:
            raise ValueError("Position does not belong to this user.")
        if not position.is_active:
            raise ValueError("Position is already unstaked.")

        now = time.time()
        if now < position.lock_until:
            remaining_days = (position.lock_until - now) / 86_400
            raise ValueError(
                f"Position is locked for {remaining_days:.1f} more days."
            )

        position.is_active = False
        self._apy.record_unstake(position.tier, position.amount_wei)

        logger.info(
            "Unstake completed | id=%s | amount=%d", position_id, position.amount_wei,
        )
        return position.amount_wei

    # ── View Generation ───────────────────────────────────────────────

    def get_staking_view(self, user_address: str) -> StakingView:
        """
        Generate the complete staking view for a user.

        Includes all positions, tier comparisons with APY from canonical source,
        and a plain English summary.

        Args:
            user_address: The user to generate the view for.

        Returns:
            StakingView ready for rendering.
        """
        position_ids = self._user_positions.get(user_address, [])
        positions = [
            self._positions[pid]
            for pid in position_ids
            if pid in self._positions
        ]

        active_positions = [p for p in positions if p.is_active]
        total_staked = sum(p.amount_wei for p in active_positions)
        total_rewards = sum(p.rewards_claimed_wei for p in positions)

        # Get tier details from canonical APY source
        all_apys = self._apy.get_all_apys()
        tier_details = []
        for tier in StakingTier:
            snapshot = all_apys[tier]
            lock_days = TIER_LOCK_SECONDS[tier] // 86_400
            tier_details.append({
                "tier": tier.value,
                "lock_days": lock_days,
                "apy_percent": snapshot.effective_apy_bps / 100.0,
                "base_apy_percent": snapshot.base_rate_bps / 100.0,
                "bonus_apy_percent": snapshot.bonus_rate_bps / 100.0,
                "total_staked_in_tier_wei": snapshot.total_staked_wei,
                "description": self._tier_description(tier, snapshot.effective_apy_bps, lock_days),
            })

        summary = self._build_summary(user_address, active_positions, total_staked, total_rewards)

        return StakingView(
            user_address=user_address,
            positions=positions,
            total_staked_wei=total_staked,
            total_rewards_earned_wei=total_rewards,
            tier_details=tier_details,
            plain_english_summary=summary,
        )

    def get_tier_comparison(self) -> List[Dict[str, Any]]:
        """
        Get a comparison of all tiers with current APYs for display.

        Returns:
            List of tier detail dicts sorted by lock duration.
        """
        view = self.get_staking_view("0x0000000000000000000000000000000000000000")
        return view.tier_details

    # ── Queries ───────────────────────────────────────────────────────

    def get_position(self, position_id: str) -> Optional[StakePosition]:
        """Retrieve a specific staking position."""
        return self._positions.get(position_id)

    def get_user_positions(self, user_address: str) -> List[StakePosition]:
        """Get all positions (active and inactive) for a user."""
        position_ids = self._user_positions.get(user_address, [])
        return [self._positions[pid] for pid in position_ids if pid in self._positions]

    def is_locked(self, position_id: str) -> bool:
        """Check if a position is still within its lock period."""
        position = self._positions.get(position_id)
        if position is None:
            return False
        return time.time() < position.lock_until

    # ── Internal ──────────────────────────────────────────────────────

    def _tier_description(self, tier: StakingTier, apy_bps: int, lock_days: int) -> str:
        """Generate a plain English description for a tier."""
        apy_pct = apy_bps / 100.0
        if tier == StakingTier.FLEXIBLE:
            return f"No lock-up required. Withdraw anytime. Currently earning {apy_pct:.1f}% APY."
        return (
            f"Lock your tokens for {lock_days} days to earn {apy_pct:.1f}% APY. "
            f"Tokens cannot be withdrawn until the lock period ends."
        )

    def _build_summary(
        self,
        user_address: str,
        active_positions: List[StakePosition],
        total_staked: int,
        total_rewards: int,
    ) -> str:
        """Build a plain English summary for the staking view."""
        if not active_positions:
            return (
                "You have no active staking positions. "
                "Choose a tier above to start earning rewards on your tokens."
            )

        count = len(active_positions)
        eth_staked = total_staked / 10**18
        eth_rewards = total_rewards / 10**18

        tiers_used = {p.tier.value for p in active_positions}
        tier_str = ", ".join(sorted(tiers_used))

        return (
            f"You have {count} active staking position{'s' if count > 1 else ''} "
            f"totalling {eth_staked:,.4f} tokens across {tier_str} tier{'s' if len(tiers_used) > 1 else ''}. "
            f"Total rewards earned so far: {eth_rewards:,.4f} tokens."
        )
