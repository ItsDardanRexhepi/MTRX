"""
Wallet Tracker
===============

Permanent lifetime balance history per wallet. Every balance change is
recorded and never deleted. Provides full audit trail of all stablecoin
movements for any wallet on the platform.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class TransactionType(Enum):
    """Types of balance-changing transactions."""
    TRANSFER_IN = "transfer_in"
    TRANSFER_OUT = "transfer_out"
    MINT = "mint"
    BURN = "burn"
    FEE_DEDUCTION = "fee_deduction"
    REWARD = "reward"
    INSURANCE_PAYOUT = "insurance_payout"
    ESCROW_LOCK = "escrow_lock"
    ESCROW_RELEASE = "escrow_release"


@dataclass
class BalanceEntry:
    """A single balance change record. Never deleted."""
    entry_id: str
    wallet_address: str
    transaction_type: TransactionType
    amount: Decimal
    balance_before: Decimal
    balance_after: Decimal
    counterparty: Optional[str] = None
    tx_hash: Optional[str] = None
    timestamp: float = field(default_factory=time.time)
    block_number: Optional[int] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class WalletSummary:
    """Aggregated wallet statistics."""
    wallet_address: str
    current_balance: Decimal
    total_received: Decimal
    total_sent: Decimal
    total_fees_paid: Decimal
    total_transactions: int
    first_transaction_at: Optional[float] = None
    last_transaction_at: Optional[float] = None
    lifetime_high_balance: Decimal = Decimal("0")
    monthly_circulation: Decimal = Decimal("0")


class WalletTracker:
    """Permanent lifetime balance history per wallet.

    Every balance change is recorded as an immutable BalanceEntry.
    Entries are never deleted, providing a complete audit trail.

    Parameters
    ----------
    web3_provider : Any
        Web3 provider for on-chain queries.
    stablecoin_contract : Any
        Deployed stablecoin contract.
    """

    def __init__(
        self,
        web3_provider: Any = None,
        stablecoin_contract: Any = None,
    ) -> None:
        self._web3 = web3_provider
        self._contract = stablecoin_contract
        self._histories: Dict[str, List[BalanceEntry]] = {}
        self._balances: Dict[str, Decimal] = {}
        logger.info("WalletTracker initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def record_transaction(
        self,
        wallet_address: str,
        transaction_type: TransactionType,
        amount: Decimal,
        counterparty: Optional[str] = None,
        tx_hash: Optional[str] = None,
        block_number: Optional[int] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> BalanceEntry:
        """Record a balance-changing transaction.

        The balance is updated atomically and the entry is permanently
        stored.

        Args:
            wallet_address: The affected wallet.
            transaction_type: Type of transaction.
            amount: Transaction amount (always positive; direction from type).
            counterparty: Other party in the transaction.
            tx_hash: On-chain transaction hash.
            block_number: Block number of the transaction.
            metadata: Additional context.

        Returns:
            The created BalanceEntry.
        """
        balance_before = self._balances.get(wallet_address, Decimal("0"))

        # Compute new balance based on transaction type
        if transaction_type in (
            TransactionType.TRANSFER_IN,
            TransactionType.MINT,
            TransactionType.REWARD,
            TransactionType.INSURANCE_PAYOUT,
            TransactionType.ESCROW_RELEASE,
        ):
            balance_after = balance_before + amount
        else:
            balance_after = balance_before - amount

        entry = BalanceEntry(
            entry_id=f"bal-{uuid.uuid4().hex[:12]}",
            wallet_address=wallet_address,
            transaction_type=transaction_type,
            amount=amount,
            balance_before=balance_before,
            balance_after=balance_after,
            counterparty=counterparty,
            tx_hash=tx_hash,
            block_number=block_number,
            metadata=metadata or {},
        )

        # Store permanently
        if wallet_address not in self._histories:
            self._histories[wallet_address] = []
        self._histories[wallet_address].append(entry)
        self._balances[wallet_address] = balance_after

        logger.debug(
            "Balance entry: %s %s %s (%.4f -> %.4f)",
            wallet_address, transaction_type.value, amount,
            balance_before, balance_after,
        )
        return entry

    def get_balance(self, wallet_address: str) -> Decimal:
        """Get current balance for a wallet."""
        return self._balances.get(wallet_address, Decimal("0"))

    def get_history(
        self,
        wallet_address: str,
        transaction_type: Optional[TransactionType] = None,
        since: Optional[float] = None,
        until: Optional[float] = None,
        limit: Optional[int] = None,
    ) -> List[BalanceEntry]:
        """Get balance history for a wallet with optional filters.

        Args:
            wallet_address: The wallet to query.
            transaction_type: Optional type filter.
            since: Optional start timestamp.
            until: Optional end timestamp.
            limit: Maximum entries to return (most recent first).

        Returns:
            List of BalanceEntry records, newest first.
        """
        entries = self._histories.get(wallet_address, [])
        filtered: List[BalanceEntry] = []

        for entry in reversed(entries):
            if transaction_type and entry.transaction_type != transaction_type:
                continue
            if since and entry.timestamp < since:
                continue
            if until and entry.timestamp > until:
                continue
            filtered.append(entry)
            if limit and len(filtered) >= limit:
                break

        return filtered

    def get_summary(self, wallet_address: str) -> WalletSummary:
        """Get aggregated wallet statistics.

        Args:
            wallet_address: The wallet to summarise.

        Returns:
            WalletSummary with lifetime statistics.
        """
        entries = self._histories.get(wallet_address, [])
        current = self._balances.get(wallet_address, Decimal("0"))

        total_received = Decimal("0")
        total_sent = Decimal("0")
        total_fees = Decimal("0")
        high_balance = Decimal("0")
        first_at: Optional[float] = None
        last_at: Optional[float] = None

        for entry in entries:
            if first_at is None or entry.timestamp < first_at:
                first_at = entry.timestamp
            if last_at is None or entry.timestamp > last_at:
                last_at = entry.timestamp

            if entry.transaction_type in (
                TransactionType.TRANSFER_IN, TransactionType.MINT,
                TransactionType.REWARD, TransactionType.INSURANCE_PAYOUT,
                TransactionType.ESCROW_RELEASE,
            ):
                total_received += entry.amount
            elif entry.transaction_type == TransactionType.FEE_DEDUCTION:
                total_fees += entry.amount
            else:
                total_sent += entry.amount

            if entry.balance_after > high_balance:
                high_balance = entry.balance_after

        # Calculate monthly circulation (last 30 days)
        thirty_days_ago = time.time() - (30 * 86400)
        monthly_circ = Decimal("0")
        for entry in entries:
            if entry.timestamp >= thirty_days_ago:
                monthly_circ += entry.amount

        return WalletSummary(
            wallet_address=wallet_address,
            current_balance=current,
            total_received=total_received,
            total_sent=total_sent,
            total_fees_paid=total_fees,
            total_transactions=len(entries),
            first_transaction_at=first_at,
            last_transaction_at=last_at,
            lifetime_high_balance=high_balance,
            monthly_circulation=monthly_circ,
        )

    def get_monthly_circulation(self, wallet_address: str) -> Decimal:
        """Calculate the total amount circulated in the last 30 days.

        Used by insurance eligibility checks (Component 13).

        Args:
            wallet_address: The wallet to check.

        Returns:
            Total amount moved (in + out) in the last 30 days.
        """
        thirty_days_ago = time.time() - (30 * 86400)
        entries = self._histories.get(wallet_address, [])
        circulation = Decimal("0")
        for entry in entries:
            if entry.timestamp >= thirty_days_ago:
                circulation += entry.amount
        return circulation

    def get_all_tracked_wallets(self) -> List[str]:
        """Return all wallet addresses with recorded history."""
        return list(self._histories.keys())
