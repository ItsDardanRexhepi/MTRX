"""
Reserve Fund Management
========================

Manages the insurance reserve fund with a 60/40 split between reserves
and operations. Enforces a $500k floor minimum with advisory alerts
(non-blocking). Tracks fund balance, contributions, and withdrawals.

All oracle data (e.g. ETH/USD price) routes through Component 11.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Fund allocation parameters
RESERVE_RATIO: Decimal = Decimal("0.60")
OPERATIONS_RATIO: Decimal = Decimal("0.40")
FLOOR_MINIMUM_USD: Decimal = Decimal("500000")


class FundAlertLevel(Enum):
    """Advisory alert levels for reserve fund health."""
    HEALTHY = "healthy"
    WARNING = "warning"
    CRITICAL = "critical"
    SEVERELY_DEPLETED = "severely_depleted"


class TransactionType(Enum):
    """Type of fund transaction."""
    CONTRIBUTION = "contribution"
    WITHDRAWAL = "withdrawal"
    PAYOUT = "payout"
    REBALANCE = "rebalance"
    FEE_DEPOSIT = "fee_deposit"


@dataclass
class FundTransaction:
    """Record of a reserve fund transaction."""
    transaction_id: str
    transaction_type: TransactionType
    amount_eth: Decimal
    amount_usd: Optional[Decimal] = None
    source: Optional[str] = None
    destination: Optional[str] = None
    reserve_portion_eth: Decimal = Decimal("0")
    operations_portion_eth: Decimal = Decimal("0")
    balance_after_eth: Decimal = Decimal("0")
    reserve_balance_after_eth: Decimal = Decimal("0")
    operations_balance_after_eth: Decimal = Decimal("0")
    tx_hash: Optional[str] = None
    timestamp: float = field(default_factory=time.time)
    notes: Optional[str] = None


@dataclass
class FundAlert:
    """Advisory alert issued when fund drops below thresholds."""
    alert_id: str
    level: FundAlertLevel
    reserve_balance_eth: Decimal
    reserve_balance_usd: Optional[Decimal]
    floor_minimum_usd: Decimal
    message: str
    issued_at: float = field(default_factory=time.time)
    acknowledged: bool = False
    acknowledged_at: Optional[float] = None


class ReserveFund:
    """Insurance reserve fund with 60/40 split and $500k advisory floor.

    Incoming funds are automatically split 60% to reserves and 40% to
    operations. The $500k floor triggers advisory alerts but does NOT
    block withdrawals or payouts.

    Parameters
    ----------
    oracle_interface : Any
        Component 11 OracleInterface for ETH/USD price data.
    on_alert : callable, optional
        Callback invoked when an advisory alert is issued.
    floor_minimum_usd : Decimal
        Advisory floor minimum in USD (default $500k).
    """

    def __init__(
        self,
        oracle_interface: Any = None,
        on_alert: Optional[Callable[[FundAlert], None]] = None,
        floor_minimum_usd: Decimal = FLOOR_MINIMUM_USD,
    ) -> None:
        self._oracle = oracle_interface
        self._on_alert = on_alert
        self._floor_minimum_usd = floor_minimum_usd
        self._reserve_balance: Decimal = Decimal("0")
        self._operations_balance: Decimal = Decimal("0")
        self._transactions: List[FundTransaction] = []
        self._alerts: List[FundAlert] = []
        logger.info(
            "ReserveFund initialised (split=%.0f/%.0f, floor=$%s)",
            RESERVE_RATIO * 100, OPERATIONS_RATIO * 100, floor_minimum_usd,
        )

    @property
    def total_balance_eth(self) -> Decimal:
        """Total fund balance (reserves + operations) in ETH."""
        return self._reserve_balance + self._operations_balance

    @property
    def reserve_balance_eth(self) -> Decimal:
        """Reserve portion balance in ETH."""
        return self._reserve_balance

    @property
    def operations_balance_eth(self) -> Decimal:
        """Operations portion balance in ETH."""
        return self._operations_balance

    def deposit(
        self,
        amount_eth: Decimal,
        transaction_type: TransactionType = TransactionType.FEE_DEPOSIT,
        source: Optional[str] = None,
        notes: Optional[str] = None,
    ) -> FundTransaction:
        """Deposit funds with automatic 60/40 split.

        Args:
            amount_eth: Amount to deposit in ETH.
            transaction_type: Type of deposit transaction.
            source: Source wallet or identifier.
            notes: Optional notes.

        Returns:
            FundTransaction record.
        """
        if amount_eth <= 0:
            raise ValueError("Deposit amount must be positive")

        reserve_portion = amount_eth * RESERVE_RATIO
        operations_portion = amount_eth * OPERATIONS_RATIO
        self._reserve_balance += reserve_portion
        self._operations_balance += operations_portion

        txn = FundTransaction(
            transaction_id=f"rf-dep-{uuid.uuid4().hex[:10]}",
            transaction_type=transaction_type,
            amount_eth=amount_eth,
            amount_usd=self._eth_to_usd(amount_eth),
            source=source,
            destination=NEOSAFE_ADDRESS,
            reserve_portion_eth=reserve_portion,
            operations_portion_eth=operations_portion,
            balance_after_eth=self.total_balance_eth,
            reserve_balance_after_eth=self._reserve_balance,
            operations_balance_after_eth=self._operations_balance,
            notes=notes,
        )
        self._transactions.append(txn)
        logger.info(
            "Deposit %.4f ETH (reserve=%.4f, ops=%.4f) | total=%.4f ETH",
            amount_eth, reserve_portion, operations_portion, self.total_balance_eth,
        )
        self._check_fund_health()
        return txn

    def withdraw_for_payout(
        self,
        amount_eth: Decimal,
        destination: str,
        notes: Optional[str] = None,
    ) -> FundTransaction:
        """Withdraw from reserves to fund an insurance payout.

        Draws from reserve balance first; overflows to operations.
        Advisory-alert only -- withdrawals are NEVER blocked.

        Args:
            amount_eth: Amount to withdraw in ETH.
            destination: Destination wallet address.
            notes: Optional notes.

        Returns:
            FundTransaction record.

        Raises:
            ValueError: If total fund balance is insufficient.
        """
        if amount_eth <= 0:
            raise ValueError("Withdrawal amount must be positive")
        if amount_eth > self.total_balance_eth:
            raise ValueError(
                f"Insufficient funds: requested {amount_eth} ETH, "
                f"available {self.total_balance_eth} ETH"
            )

        reserve_draw = min(amount_eth, self._reserve_balance)
        operations_draw = amount_eth - reserve_draw
        self._reserve_balance -= reserve_draw
        self._operations_balance -= operations_draw

        txn = FundTransaction(
            transaction_id=f"rf-pay-{uuid.uuid4().hex[:10]}",
            transaction_type=TransactionType.PAYOUT,
            amount_eth=amount_eth,
            amount_usd=self._eth_to_usd(amount_eth),
            source=NEOSAFE_ADDRESS,
            destination=destination,
            reserve_portion_eth=reserve_draw,
            operations_portion_eth=operations_draw,
            balance_after_eth=self.total_balance_eth,
            reserve_balance_after_eth=self._reserve_balance,
            operations_balance_after_eth=self._operations_balance,
            notes=notes,
        )
        self._transactions.append(txn)
        logger.info(
            "Payout %.4f ETH to %s (reserve=%.4f, ops=%.4f) | total=%.4f ETH",
            amount_eth, destination, reserve_draw, operations_draw,
            self.total_balance_eth,
        )
        self._check_fund_health()
        return txn

    def withdraw_operations(
        self,
        amount_eth: Decimal,
        destination: str,
        notes: Optional[str] = None,
    ) -> FundTransaction:
        """Withdraw from operations balance only.

        Args:
            amount_eth: Amount to withdraw in ETH.
            destination: Destination wallet address.
            notes: Optional notes.

        Returns:
            FundTransaction record.
        """
        if amount_eth <= 0:
            raise ValueError("Withdrawal amount must be positive")
        if amount_eth > self._operations_balance:
            raise ValueError(
                f"Insufficient operations funds: requested {amount_eth} ETH, "
                f"available {self._operations_balance} ETH"
            )
        self._operations_balance -= amount_eth
        txn = FundTransaction(
            transaction_id=f"rf-ops-{uuid.uuid4().hex[:10]}",
            transaction_type=TransactionType.WITHDRAWAL,
            amount_eth=amount_eth,
            amount_usd=self._eth_to_usd(amount_eth),
            source=NEOSAFE_ADDRESS,
            destination=destination,
            reserve_portion_eth=Decimal("0"),
            operations_portion_eth=amount_eth,
            balance_after_eth=self.total_balance_eth,
            reserve_balance_after_eth=self._reserve_balance,
            operations_balance_after_eth=self._operations_balance,
            notes=notes,
        )
        self._transactions.append(txn)
        logger.info(
            "Operations withdrawal %.4f ETH to %s | ops=%.4f ETH",
            amount_eth, destination, self._operations_balance,
        )
        self._check_fund_health()
        return txn

    def rebalance(self) -> Optional[FundTransaction]:
        """Rebalance the fund to restore the 60/40 split.

        Returns:
            FundTransaction if rebalancing occurred, else None.
        """
        total = self.total_balance_eth
        if total == 0:
            return None
        target_reserve = total * RESERVE_RATIO
        target_operations = total * OPERATIONS_RATIO
        reserve_delta = target_reserve - self._reserve_balance
        if abs(reserve_delta) < Decimal("0.0001"):
            return None

        self._reserve_balance = target_reserve
        self._operations_balance = target_operations

        txn = FundTransaction(
            transaction_id=f"rf-rbl-{uuid.uuid4().hex[:10]}",
            transaction_type=TransactionType.REBALANCE,
            amount_eth=abs(reserve_delta),
            source="internal_rebalance",
            destination="internal_rebalance",
            reserve_portion_eth=target_reserve,
            operations_portion_eth=target_operations,
            balance_after_eth=total,
            reserve_balance_after_eth=self._reserve_balance,
            operations_balance_after_eth=self._operations_balance,
            notes=f"Rebalanced: moved {reserve_delta:+.4f} ETH to reserves",
        )
        self._transactions.append(txn)
        logger.info(
            "Fund rebalanced: reserve=%.4f, ops=%.4f (delta=%.4f)",
            self._reserve_balance, self._operations_balance, reserve_delta,
        )
        return txn

    def get_fund_health(self) -> Dict[str, Any]:
        """Assess current fund health including USD valuation."""
        reserve_usd = self._eth_to_usd(self._reserve_balance)
        total_usd = self._eth_to_usd(self.total_balance_eth)
        alert_level = self._determine_alert_level(reserve_usd)
        total = self.total_balance_eth
        return {
            "total_balance_eth": float(self.total_balance_eth),
            "reserve_balance_eth": float(self._reserve_balance),
            "operations_balance_eth": float(self._operations_balance),
            "total_balance_usd": float(total_usd) if total_usd else None,
            "reserve_balance_usd": float(reserve_usd) if reserve_usd else None,
            "floor_minimum_usd": float(self._floor_minimum_usd),
            "alert_level": alert_level.value,
            "actual_reserve_ratio": float(self._reserve_balance / total) if total > 0 else 0.0,
            "actual_operations_ratio": float(self._operations_balance / total) if total > 0 else 0.0,
            "target_reserve_ratio": float(RESERVE_RATIO),
            "target_operations_ratio": float(OPERATIONS_RATIO),
        }

    def get_transaction_history(self, limit: int = 100) -> List[FundTransaction]:
        """Get recent fund transactions."""
        return list(reversed(self._transactions[-limit:]))

    def get_alerts(self, unacknowledged_only: bool = False) -> List[FundAlert]:
        """Get fund alerts."""
        if unacknowledged_only:
            return [a for a in self._alerts if not a.acknowledged]
        return list(self._alerts)

    def acknowledge_alert(self, alert_id: str) -> bool:
        """Acknowledge a fund alert."""
        for alert in self._alerts:
            if alert.alert_id == alert_id:
                alert.acknowledged = True
                alert.acknowledged_at = time.time()
                return True
        return False

    def get_stats(self) -> Dict[str, Any]:
        """Get reserve fund statistics."""
        total_deposits = sum(
            t.amount_eth for t in self._transactions
            if t.transaction_type in (TransactionType.CONTRIBUTION, TransactionType.FEE_DEPOSIT)
        )
        total_payouts = sum(
            t.amount_eth for t in self._transactions
            if t.transaction_type == TransactionType.PAYOUT
        )
        return {
            "total_balance_eth": float(self.total_balance_eth),
            "reserve_balance_eth": float(self._reserve_balance),
            "operations_balance_eth": float(self._operations_balance),
            "total_deposits_eth": float(total_deposits),
            "total_payouts_eth": float(total_payouts),
            "transaction_count": len(self._transactions),
            "active_alerts": sum(1 for a in self._alerts if not a.acknowledged),
        }

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _eth_to_usd(self, amount_eth: Decimal) -> Optional[Decimal]:
        """Convert ETH to USD via Component 11 oracle."""
        if not self._oracle:
            return None
        try:
            price_resp = self._oracle.get_price("ETH", "USD", source_component=13)
            if price_resp.value:
                return amount_eth * Decimal(str(price_resp.value))
        except Exception as exc:
            logger.warning("Failed to get ETH/USD price from oracle: %s", exc)
        return None

    def _determine_alert_level(self, reserve_usd: Optional[Decimal]) -> FundAlertLevel:
        """Determine alert level based on reserve USD value."""
        if reserve_usd is None:
            return FundAlertLevel.HEALTHY
        if reserve_usd >= Decimal("750000"):
            return FundAlertLevel.HEALTHY
        if reserve_usd >= self._floor_minimum_usd:
            return FundAlertLevel.WARNING
        if reserve_usd >= Decimal("250000"):
            return FundAlertLevel.CRITICAL
        return FundAlertLevel.SEVERELY_DEPLETED

    def _check_fund_health(self) -> None:
        """Check fund health and issue advisory alerts if needed."""
        reserve_usd = self._eth_to_usd(self._reserve_balance)
        level = self._determine_alert_level(reserve_usd)
        if level == FundAlertLevel.HEALTHY:
            return

        recent_cutoff = time.time() - 3600
        for existing in reversed(self._alerts):
            if existing.level == level and existing.issued_at > recent_cutoff:
                return

        usd_str = f"${reserve_usd:,.2f}" if reserve_usd else "unknown"
        messages = {
            FundAlertLevel.WARNING: f"Reserve below $750k warning. Current: {usd_str}. Advisory only.",
            FundAlertLevel.CRITICAL: f"Reserve below ${self._floor_minimum_usd:,.0f} floor. Current: {usd_str}. Advisory only.",
            FundAlertLevel.SEVERELY_DEPLETED: f"Reserve severely depleted (<$250k). Current: {usd_str}. Attention needed.",
        }

        alert = FundAlert(
            alert_id=f"rf-alert-{uuid.uuid4().hex[:10]}",
            level=level,
            reserve_balance_eth=self._reserve_balance,
            reserve_balance_usd=reserve_usd,
            floor_minimum_usd=self._floor_minimum_usd,
            message=messages.get(level, f"Fund status: {level.value}"),
        )
        self._alerts.append(alert)
        logger.warning("FUND ALERT [%s]: %s", level.value, alert.message)

        if self._on_alert:
            try:
                self._on_alert(alert)
            except Exception as exc:
                logger.error("Alert callback failed: %s", exc)
