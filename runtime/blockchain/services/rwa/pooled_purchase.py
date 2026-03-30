"""
Component 4 -- Pooled Purchase Coordinator
============================================

Enables multiple users to pool funds to purchase an asset together.  Funds are
held in escrow until all parties contribute their share.  Once the pool is
fully funded the purchase executes automatically.  Ownership is split
proportional to each party's contribution.

If the pool fails to fill, every contributor receives a full refund.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class PoolStatus(Enum):
    OPEN = auto()
    FUNDED = auto()
    EXECUTED = auto()
    REFUNDED = auto()
    EXPIRED = auto()


@dataclass
class Contribution:
    """A single party's contribution to a pool."""

    party: str
    amount: float
    contributed_at: float


@dataclass
class PurchasePool:
    """A pooled-purchase escrow pool."""

    pool_id: str
    asset: Dict[str, Any]
    required_amount: float
    parties: List[str]
    status: PoolStatus
    contributions: Dict[str, Contribution]
    total_contributed: float
    created_at: float
    executed_at: Optional[float] = None
    ownership_splits: Dict[str, float] = field(default_factory=dict)


# ------------------------------------------------------------------ service


class PooledPurchaseCoordinator:
    """
    Coordinates multi-party pooled asset purchases with escrow, proportional
    ownership splits, and automatic refunds on failure.
    """

    def __init__(self) -> None:
        self._pools: Dict[str, PurchasePool] = {}

    def create_pool(
        self,
        asset: Dict[str, Any],
        required_amount: float,
        parties: List[str],
    ) -> PurchasePool:
        """
        Create a new pooled-purchase escrow pool.

        Parameters
        ----------
        asset : dict
            Description of the asset to be purchased.
        required_amount : float
            Total amount required to complete the purchase.
        parties : list[str]
            Identifiers of all parties invited to contribute.

        Returns
        -------
        PurchasePool
        """
        if required_amount <= 0:
            raise ValueError("Required amount must be positive.")
        if len(parties) < 2:
            raise ValueError("A pooled purchase requires at least 2 parties.")

        pool_id = str(uuid.uuid4())

        pool = PurchasePool(
            pool_id=pool_id,
            asset=asset,
            required_amount=required_amount,
            parties=list(parties),
            status=PoolStatus.OPEN,
            contributions={},
            total_contributed=0.0,
            created_at=time.time(),
        )

        self._pools[pool_id] = pool
        return pool

    def contribute(
        self, pool_id: str, party: str, amount: float
    ) -> PurchasePool:
        """
        Record a contribution from a party.

        Parameters
        ----------
        pool_id : str
            The pool to contribute to.
        party : str
            The contributing party.
        amount : float
            The contribution amount.

        Returns
        -------
        PurchasePool
            The updated pool state.

        Raises
        ------
        ValueError
            If the pool is not open or the party is not listed.
        """
        pool = self._get_pool(pool_id)

        if pool.status != PoolStatus.OPEN:
            raise ValueError(f"Pool {pool_id} is not open for contributions.")
        if party not in pool.parties:
            raise ValueError(f"Party {party} is not a member of pool {pool_id}.")
        if amount <= 0:
            raise ValueError("Contribution must be positive.")

        if party in pool.contributions:
            pool.contributions[party].amount += amount
        else:
            pool.contributions[party] = Contribution(
                party=party, amount=amount, contributed_at=time.time()
            )

        pool.total_contributed += amount

        # Auto-fund check
        if pool.total_contributed >= pool.required_amount:
            pool.status = PoolStatus.FUNDED

        return pool

    def check_pool_status(self, pool_id: str) -> Dict[str, Any]:
        """
        Return the current status of a pool.

        Returns
        -------
        dict
            ``pool_id``, ``status``, ``total_contributed``,
            ``required_amount``, ``remaining``, ``contributors``.
        """
        pool = self._get_pool(pool_id)
        remaining = max(0.0, pool.required_amount - pool.total_contributed)

        return {
            "pool_id": pool.pool_id,
            "status": pool.status.name,
            "total_contributed": pool.total_contributed,
            "required_amount": pool.required_amount,
            "remaining": remaining,
            "contributors": {
                party: c.amount for party, c in pool.contributions.items()
            },
        }

    def execute_purchase(self, pool_id: str) -> PurchasePool:
        """
        Execute the purchase once the pool is fully funded.
        Ownership splits are calculated proportional to contributions.

        Returns
        -------
        PurchasePool
            The pool with ``EXECUTED`` status and ownership splits set.

        Raises
        ------
        RuntimeError
            If the pool is not fully funded.
        """
        pool = self._get_pool(pool_id)

        if pool.status != PoolStatus.FUNDED:
            raise RuntimeError(
                f"Pool {pool_id} is not fully funded (status: {pool.status.name})."
            )

        # Calculate ownership splits proportional to contributions
        for party, contribution in pool.contributions.items():
            pool.ownership_splits[party] = (
                contribution.amount / pool.total_contributed
            )

        pool.status = PoolStatus.EXECUTED
        pool.executed_at = time.time()

        return pool

    def refund_pool(self, pool_id: str) -> Dict[str, float]:
        """
        Refund all contributions in a pool that has not been executed.

        Returns
        -------
        dict
            Mapping of party -> refund amount.

        Raises
        ------
        RuntimeError
            If the pool has already been executed.
        """
        pool = self._get_pool(pool_id)

        if pool.status == PoolStatus.EXECUTED:
            raise RuntimeError(
                f"Pool {pool_id} has already been executed; cannot refund."
            )

        refunds: Dict[str, float] = {}
        for party, contribution in pool.contributions.items():
            refunds[party] = contribution.amount

        pool.status = PoolStatus.REFUNDED
        pool.total_contributed = 0.0
        pool.contributions.clear()

        return refunds

    # -- internal ---------------------------------------------------------

    def _get_pool(self, pool_id: str) -> PurchasePool:
        pool = self._pools.get(pool_id)
        if pool is None:
            raise KeyError(f"No pool found with ID {pool_id}")
        return pool
