"""
Liquidity Manager — manages LP positions on Uniswap v3/v4.

Part of Component 21 (DEX).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from runtime.blockchain.services.dex.router import UniswapVersion

logger = logging.getLogger(__name__)


@dataclass
class LPPosition:
    """A liquidity provider position."""
    position_id: str
    provider: str
    token_a: str
    token_b: str
    fee_tier: int
    amount_a_wei: int
    amount_b_wei: int
    tick_lower: int
    tick_upper: int
    liquidity: int
    version: UniswapVersion
    created_at: float = field(default_factory=time.time)
    is_active: bool = True
    fees_earned_a_wei: int = 0
    fees_earned_b_wei: int = 0


class LiquidityManager:
    """
    Manages liquidity provider positions on Uniswap v3/v4 via Base.

    Supports concentrated liquidity (v3) and hook-enabled pools (v4).
    Tracks positions, fee accrual, and provides rebalancing signals.
    """

    def __init__(self) -> None:
        self._positions: Dict[str, LPPosition] = {}
        self._user_positions: Dict[str, List[str]] = {}
        self._counter: int = 0
        logger.info("LiquidityManager initialised.")

    def add_liquidity(
        self,
        provider: str,
        token_a: str,
        token_b: str,
        amount_a_wei: int,
        amount_b_wei: int,
        fee_tier: int = 3000,
        tick_lower: int = -887272,
        tick_upper: int = 887272,
        version: UniswapVersion = UniswapVersion.V3,
    ) -> LPPosition:
        """
        Add liquidity to a pool.

        Args:
            provider: LP address.
            token_a: First token address.
            token_b: Second token address.
            amount_a_wei: Amount of token A.
            amount_b_wei: Amount of token B.
            fee_tier: Pool fee tier.
            tick_lower: Lower tick bound (concentrated liquidity).
            tick_upper: Upper tick bound (concentrated liquidity).
            version: Uniswap version.

        Returns:
            The created LPPosition.
        """
        if amount_a_wei <= 0 or amount_b_wei <= 0:
            raise ValueError("Both token amounts must be positive.")
        if tick_lower >= tick_upper:
            raise ValueError("tick_lower must be less than tick_upper.")

        self._counter += 1
        pos_id = f"LP-{self._counter:08d}"

        liquidity = int((amount_a_wei * amount_b_wei) ** 0.5)

        position = LPPosition(
            position_id=pos_id,
            provider=provider,
            token_a=token_a,
            token_b=token_b,
            fee_tier=fee_tier,
            amount_a_wei=amount_a_wei,
            amount_b_wei=amount_b_wei,
            tick_lower=tick_lower,
            tick_upper=tick_upper,
            liquidity=liquidity,
            version=version,
        )

        self._positions[pos_id] = position
        if provider not in self._user_positions:
            self._user_positions[provider] = []
        self._user_positions[provider].append(pos_id)

        logger.info(
            "Liquidity added | id=%s | %s/%s | liquidity=%d",
            pos_id, token_a, token_b, liquidity,
        )
        return position

    def remove_liquidity(self, position_id: str, provider: str) -> LPPosition:
        """
        Remove a liquidity position.

        Args:
            position_id: The position to remove.
            provider: Must match the position owner.

        Returns:
            The deactivated position with final fee tallies.
        """
        position = self._positions.get(position_id)
        if position is None:
            raise ValueError(f"Position {position_id} not found.")
        if position.provider != provider:
            raise ValueError("Only the position owner can remove liquidity.")
        if not position.is_active:
            raise ValueError("Position is already removed.")

        position.is_active = False
        logger.info("Liquidity removed | id=%s", position_id)
        return position

    def collect_fees(self, position_id: str) -> Dict[str, int]:
        """
        Collect accumulated fees for a position.

        Returns:
            Dict with 'token_a_fees' and 'token_b_fees' in wei.
        """
        position = self._positions.get(position_id)
        if position is None:
            raise ValueError(f"Position {position_id} not found.")

        fees = {
            "token_a_fees": position.fees_earned_a_wei,
            "token_b_fees": position.fees_earned_b_wei,
        }
        position.fees_earned_a_wei = 0
        position.fees_earned_b_wei = 0
        return fees

    def accrue_fees(
        self, position_id: str, fee_a_wei: int, fee_b_wei: int,
    ) -> None:
        """Record fee accrual for a position."""
        position = self._positions.get(position_id)
        if position is None:
            return
        position.fees_earned_a_wei += fee_a_wei
        position.fees_earned_b_wei += fee_b_wei

    def get_position(self, position_id: str) -> Optional[LPPosition]:
        """Get a position by ID."""
        return self._positions.get(position_id)

    def get_user_positions(self, provider: str) -> List[LPPosition]:
        """Get all positions for a provider."""
        pos_ids = self._user_positions.get(provider, [])
        return [self._positions[pid] for pid in pos_ids if pid in self._positions]

    def get_active_positions(self) -> List[LPPosition]:
        """Get all active positions."""
        return [p for p in self._positions.values() if p.is_active]
