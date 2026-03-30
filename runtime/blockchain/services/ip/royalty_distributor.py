"""
Royalty Distributor — monitors ONLY qualifying transaction types registered
for each work and auto-distributes royalties (2 % flat perpetuity).

Part of Component 15 (IP and Royalty Management).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Optional

from runtime.blockchain.services.ip.revenue_tracker import RevenueTracker, TransactionType

logger = logging.getLogger(__name__)


@dataclass
class RoyaltyPayment:
    """Record of a royalty disbursement to an IP owner."""
    ip_id: str
    owner_address: str
    amount_wei: int
    transaction_type: TransactionType
    source_tx_hash: Optional[str]
    royalty_tx_hash: Optional[str]
    timestamp: float


class RoyaltyDistributor:
    """
    Monitors ONLY qualifying transaction types registered for each IP work
    and auto-distributes royalties at 2 % flat in perpetuity.

    Gas costs are borne by the platform / caller — never by the IP holder.
    """

    ROYALTY_BPS: int = 200  # 2 %

    def __init__(self, revenue_tracker: RevenueTracker) -> None:
        """
        Args:
            revenue_tracker: Shared tracker for recording revenue alongside royalties.
        """
        self._tracker = revenue_tracker
        # ip_id -> set of qualifying TransactionTypes
        self._qualifying_types: dict[str, set[TransactionType]] = {}
        # ip_id -> owner address
        self._owners: dict[str, str] = {}
        # Payment history
        self._payments: list[RoyaltyPayment] = []

        logger.info("RoyaltyDistributor initialised (2%% flat perpetuity).")

    # ── Registration ──────────────────────────────────────────────────

    def register_ip(
        self,
        ip_id: str,
        owner_address: str,
        qualifying_types: set[TransactionType],
    ) -> None:
        """
        Register an IP work with its owner and qualifying transaction types.

        Args:
            ip_id: Unique identifier for the IP work.
            owner_address: Ethereum address of the IP owner (receives royalties).
            qualifying_types: Set of transaction types that trigger royalties.

        Raises:
            ValueError: If qualifying_types is empty or owner_address is invalid.
        """
        if not qualifying_types:
            raise ValueError("At least one qualifying transaction type is required.")
        if not owner_address or not owner_address.startswith("0x"):
            raise ValueError(f"Invalid owner address: {owner_address}")

        self._qualifying_types[ip_id] = set(qualifying_types)
        self._owners[ip_id] = owner_address

        logger.info(
            "Registered IP %s — owner=%s, qualifying=%s",
            ip_id, owner_address, [t.value for t in qualifying_types],
        )

    # ── Transaction Processing ────────────────────────────────────────

    def process_transaction(
        self,
        ip_id: str,
        transaction_type: TransactionType,
        amount_wei: int,
        source_tx_hash: Optional[str] = None,
        send_royalty_fn=None,
    ) -> Optional[RoyaltyPayment]:
        """
        Process a transaction and auto-distribute royalty if the type qualifies.

        Only transactions whose type is in the registered qualifying set for this
        IP work will trigger a royalty payment.

        Args:
            ip_id: The IP work identifier.
            transaction_type: The type of this transaction.
            amount_wei: Transaction amount in wei.
            source_tx_hash: Optional hash of the originating transaction.
            send_royalty_fn: Optional callable(to_address, amount_wei) -> tx_hash.

        Returns:
            RoyaltyPayment record if royalty was distributed, None otherwise.

        Raises:
            ValueError: If IP is not registered or amount is non-positive.
        """
        if ip_id not in self._qualifying_types:
            raise ValueError(f"IP {ip_id} is not registered with RoyaltyDistributor.")
        if amount_wei <= 0:
            raise ValueError(f"Transaction amount must be positive, got {amount_wei}")

        # Only process qualifying types
        if transaction_type not in self._qualifying_types[ip_id]:
            logger.debug(
                "Transaction type %s is NOT qualifying for IP %s — skipping royalty.",
                transaction_type.value, ip_id,
            )
            return None

        owner = self._owners[ip_id]
        royalty_amount = (amount_wei * self.ROYALTY_BPS) // 10_000

        if royalty_amount == 0:
            logger.debug("Royalty rounds to 0 for %d wei on IP %s.", amount_wei, ip_id)
            return None

        # Send royalty (gas paid by caller, not IP holder)
        royalty_tx_hash: Optional[str] = None
        if send_royalty_fn is not None:
            try:
                royalty_tx_hash = send_royalty_fn(owner, royalty_amount)
            except Exception:
                logger.exception(
                    "Failed to send royalty of %d wei to %s for IP %s.",
                    royalty_amount, owner, ip_id,
                )
                raise

        payment = RoyaltyPayment(
            ip_id=ip_id,
            owner_address=owner,
            amount_wei=royalty_amount,
            transaction_type=transaction_type,
            source_tx_hash=source_tx_hash,
            royalty_tx_hash=royalty_tx_hash,
            timestamp=time.time(),
        )
        self._payments.append(payment)

        logger.info(
            "Royalty of %d wei (2%% of %d) paid to %s for IP %s (%s).",
            royalty_amount, amount_wei, owner, ip_id, transaction_type.value,
        )
        return payment

    # ── Queries ───────────────────────────────────────────────────────

    def is_qualifying(self, ip_id: str, transaction_type: TransactionType) -> bool:
        """Check if a transaction type is qualifying for an IP work."""
        return transaction_type in self._qualifying_types.get(ip_id, set())

    def get_qualifying_types(self, ip_id: str) -> set[TransactionType]:
        """Return the set of qualifying types for an IP work."""
        return set(self._qualifying_types.get(ip_id, set()))

    def get_total_royalties(self, ip_id: str) -> int:
        """Return total royalties paid for an IP work (lifetime)."""
        return sum(p.amount_wei for p in self._payments if p.ip_id == ip_id)

    def get_payment_history(
        self, ip_id: Optional[str] = None
    ) -> list[RoyaltyPayment]:
        """Return payment history, optionally filtered by IP."""
        if ip_id is None:
            return list(self._payments)
        return [p for p in self._payments if p.ip_id == ip_id]

    def get_owner(self, ip_id: str) -> Optional[str]:
        """Return the registered owner address for an IP work."""
        return self._owners.get(ip_id)
