"""
Juror Pool — manages juror registration, staking, and jury selection.

Part of Component 30 (Dispute Resolution).
Jurors register by staking tokens. Juries are selected randomly from the pool.
"""

from __future__ import annotations

import hashlib
import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


@dataclass
class Juror:
    """A registered juror in the pool."""
    address: str
    staked_wei: int
    registered_at: float = field(default_factory=time.time)
    active: bool = True
    disputes_served: int = 0


class JurorPool:
    """
    Manages the juror pool for dispute resolution.

    Jurors register by staking tokens above the minimum threshold.
    Jury selection uses deterministic pseudo-random selection from the pool
    based on dispute ID as seed.
    """

    DEFAULT_MIN_STAKE_WEI: int = 100 * 10**18  # 100 tokens

    def __init__(
        self,
        min_stake_wei: int = DEFAULT_MIN_STAKE_WEI,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._min_stake_wei = min_stake_wei
        self._execute = execute_fn
        self._jurors: Dict[str, Juror] = {}
        logger.info(
            "JurorPool initialised | min_stake=%d wei.", min_stake_wei,
        )

    def register(self, address: str, amount_wei: int) -> Juror:
        """
        Register a juror by staking tokens.

        Args:
            address: Juror's wallet address.
            amount_wei: Amount to stake.

        Returns:
            The registered Juror.

        Raises:
            ValueError: If stake is below minimum or address invalid.
        """
        if not address.startswith("0x"):
            raise ValueError("Invalid juror address.")
        if amount_wei < self._min_stake_wei:
            raise ValueError(
                f"Stake {amount_wei} below minimum {self._min_stake_wei}."
            )
        if address in self._jurors:
            juror = self._jurors[address]
            juror.staked_wei += amount_wei
            juror.active = True
            logger.info(
                "Juror topped up | addr=%s | added=%d | total=%d",
                address, amount_wei, juror.staked_wei,
            )
            return juror

        juror = Juror(address=address, staked_wei=amount_wei)
        self._jurors[address] = juror
        logger.info(
            "Juror registered | addr=%s | stake=%d", address, amount_wei,
        )
        return juror

    def withdraw(self, address: str, amount_wei: int) -> int:
        """
        Withdraw stake from the juror pool.

        Args:
            address: Juror's wallet address.
            amount_wei: Amount to withdraw.

        Returns:
            Remaining stake in wei.

        Raises:
            ValueError: If juror not found or amount exceeds stake.
        """
        juror = self._get_juror(address)
        if amount_wei > juror.staked_wei:
            raise ValueError(
                f"Cannot withdraw {amount_wei} — only {juror.staked_wei} staked."
            )
        juror.staked_wei -= amount_wei
        if juror.staked_wei < self._min_stake_wei:
            juror.active = False
        logger.info(
            "Juror withdrew | addr=%s | amount=%d | remaining=%d",
            address, amount_wei, juror.staked_wei,
        )
        return juror.staked_wei

    def select_jury(
        self,
        dispute_id: str,
        count: int,
        exclude: Optional[Set[str]] = None,
    ) -> List[str]:
        """
        Select a jury from the active pool using deterministic pseudo-random.

        Args:
            dispute_id: Dispute ID used as random seed.
            count: Number of jurors to select.
            exclude: Addresses to exclude (e.g. dispute parties).

        Returns:
            List of selected juror addresses.

        Raises:
            ValueError: If not enough eligible jurors in pool.
        """
        exclude = exclude or set()
        eligible = [
            addr for addr, j in self._jurors.items()
            if j.active and addr not in exclude
        ]
        if len(eligible) < count:
            raise ValueError(
                f"Need {count} jurors but only {len(eligible)} eligible."
            )

        # Deterministic shuffle using dispute_id as seed
        seed = hashlib.sha256(dispute_id.encode()).digest()
        seed_int = int.from_bytes(seed[:8], "big")

        scored = []
        for addr in eligible:
            h = hashlib.sha256(f"{seed_int}:{addr}".encode()).digest()
            score = int.from_bytes(h[:8], "big")
            scored.append((score, addr))
        scored.sort()

        selected = [addr for _, addr in scored[:count]]
        for addr in selected:
            self._jurors[addr].disputes_served += 1

        logger.info(
            "Jury selected | dispute=%s | count=%d | jurors=%s",
            dispute_id, count, selected,
        )
        return selected

    def slash(self, address: str, amount_wei: int) -> None:
        """Slash a juror's stake as penalty for dishonest voting."""
        juror = self._get_juror(address)
        slash_amount = min(amount_wei, juror.staked_wei)
        juror.staked_wei -= slash_amount
        if juror.staked_wei < self._min_stake_wei:
            juror.active = False
        logger.info(
            "Juror slashed | addr=%s | amount=%d | remaining=%d",
            address, slash_amount, juror.staked_wei,
        )

    def reward(self, address: str, amount_wei: int) -> None:
        """Reward a juror for honest participation."""
        juror = self._get_juror(address)
        juror.staked_wei += amount_wei
        logger.info(
            "Juror rewarded | addr=%s | amount=%d | total=%d",
            address, amount_wei, juror.staked_wei,
        )

    def get_pool_size(self) -> int:
        """Return number of active jurors in the pool."""
        return sum(1 for j in self._jurors.values() if j.active)

    def get_juror(self, address: str) -> Optional[Juror]:
        """Get juror info or None."""
        return self._jurors.get(address)

    def set_min_stake(self, amount_wei: int) -> None:
        """Update the minimum stake requirement."""
        self._min_stake_wei = amount_wei
        # Deactivate jurors below new minimum
        for j in self._jurors.values():
            if j.staked_wei < amount_wei:
                j.active = False
        logger.info("Min juror stake updated to %d wei.", amount_wei)

    def _get_juror(self, address: str) -> Juror:
        """Get juror or raise."""
        juror = self._jurors.get(address)
        if juror is None:
            raise ValueError(f"Juror {address} not found.")
        return juror
