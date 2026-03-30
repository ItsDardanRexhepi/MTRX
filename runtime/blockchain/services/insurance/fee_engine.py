"""
Insurance Fee Engine
=====================

Calculates insurance fees: 10% of circulated ETH up to a 10 ETH cap.
All fees route to NeoSafe. Fee calculation happens monthly based on
actual circulation data from WalletTracker.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Fee parameters
FEE_RATE: Decimal = Decimal("0.10")  # 10% of circulated ETH
MAX_FEE_ETH: Decimal = Decimal("10")  # 10 ETH cap


@dataclass
class FeeCalculation:
    """Result of a fee calculation."""
    wallet_address: str
    monthly_circulation_eth: Decimal
    fee_rate: Decimal
    raw_fee_eth: Decimal
    capped_fee_eth: Decimal
    cap_applied: bool
    calculated_at: float = field(default_factory=time.time)


@dataclass
class FeePayment:
    """Record of a fee routed to NeoSafe."""
    payment_id: str
    wallet_address: str
    fee_eth: Decimal
    fee_usd: Optional[Decimal] = None
    tx_hash: Optional[str] = None
    routed_at: float = field(default_factory=time.time)
    success: bool = False
    error: Optional[str] = None


class InsuranceFeeEngine:
    """Insurance fee calculation and collection engine.

    Calculates 10% of monthly circulated ETH as the insurance fee,
    capped at 10 ETH per wallet per month. All collected fees route
    to the NeoSafe wallet.

    Parameters
    ----------
    wallet_tracker : Any
        Component 7 WalletTracker for circulation data.
    fee_router : Any
        Component 7 FeeRouter for routing to NeoSafe.
    oracle_interface : Any
        Component 11 OracleInterface for ETH/USD price.
    fee_rate : Decimal
        Fee rate (default 10%).
    max_fee_eth : Decimal
        Maximum fee per wallet per month (default 10 ETH).
    """

    def __init__(
        self,
        wallet_tracker: Any = None,
        fee_router: Any = None,
        oracle_interface: Any = None,
        fee_rate: Decimal = FEE_RATE,
        max_fee_eth: Decimal = MAX_FEE_ETH,
    ) -> None:
        self._wallet_tracker = wallet_tracker
        self._fee_router = fee_router
        self._oracle = oracle_interface
        self._fee_rate = fee_rate
        self._max_fee = max_fee_eth
        self._calculations: Dict[str, List[FeeCalculation]] = {}
        self._payments: List[FeePayment] = []
        logger.info(
            "InsuranceFeeEngine initialised (rate=%.0f%%, cap=%.0f ETH)",
            fee_rate * 100, max_fee_eth,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def calculate_fee(self, wallet_address: str) -> FeeCalculation:
        """Calculate the monthly insurance fee for a wallet.

        Args:
            wallet_address: The wallet to calculate for.

        Returns:
            FeeCalculation with the computed fee.
        """
        circulation = self._get_circulation(wallet_address)
        raw_fee = circulation * self._fee_rate
        cap_applied = raw_fee > self._max_fee
        capped_fee = min(raw_fee, self._max_fee)

        calc = FeeCalculation(
            wallet_address=wallet_address,
            monthly_circulation_eth=circulation,
            fee_rate=self._fee_rate,
            raw_fee_eth=raw_fee,
            capped_fee_eth=capped_fee,
            cap_applied=cap_applied,
        )

        if wallet_address not in self._calculations:
            self._calculations[wallet_address] = []
        self._calculations[wallet_address].append(calc)

        logger.info(
            "Fee calculated for %s: circulation=%.4f ETH, fee=%.4f ETH (capped=%s)",
            wallet_address, circulation, capped_fee, cap_applied,
        )
        return calc

    def collect_fee(self, wallet_address: str) -> FeePayment:
        """Calculate and collect the monthly insurance fee.

        Routes the fee to NeoSafe via FeeRouter.

        Args:
            wallet_address: The wallet to collect from.

        Returns:
            FeePayment record.
        """
        calc = self.calculate_fee(wallet_address)
        payment_id = f"ins-fee-{uuid.uuid4().hex[:10]}"

        payment = FeePayment(
            payment_id=payment_id,
            wallet_address=wallet_address,
            fee_eth=calc.capped_fee_eth,
        )

        # Get USD value from oracle
        if self._oracle:
            try:
                price_resp = self._oracle.get_price("ETH", "USD", source_component=13)
                if price_resp.value:
                    payment.fee_usd = calc.capped_fee_eth * Decimal(str(price_resp.value))
            except Exception as exc:
                logger.warning("Failed to get ETH price for fee USD conversion: %s", exc)

        # Route to NeoSafe
        if self._fee_router and calc.capped_fee_eth > 0:
            try:
                route_result = self._fee_router.route_fee(
                    source_wallet=wallet_address,
                    amount=calc.capped_fee_eth,
                    transfer_id=payment_id,
                )
                payment.tx_hash = route_result.tx_hash
                payment.success = route_result.success
            except Exception as exc:
                payment.error = str(exc)
                logger.error("Fee routing failed for %s: %s", wallet_address, exc)
        else:
            payment.success = True  # No fee to collect

        self._payments.append(payment)
        return payment

    def collect_all_fees(self, eligible_wallets: List[str]) -> List[FeePayment]:
        """Collect monthly fees from all eligible wallets.

        Args:
            eligible_wallets: List of eligible wallet addresses.

        Returns:
            List of FeePayment records.
        """
        results: List[FeePayment] = []
        for wallet in eligible_wallets:
            payment = self.collect_fee(wallet)
            results.append(payment)
        total = sum(p.fee_eth for p in results if p.success)
        logger.info(
            "Collected fees from %d wallets: total=%.4f ETH",
            len(results), total,
        )
        return results

    def get_fee_history(
        self, wallet_address: str
    ) -> List[FeeCalculation]:
        """Get fee calculation history for a wallet."""
        return self._calculations.get(wallet_address, [])

    def get_payment_history(self, limit: int = 100) -> List[FeePayment]:
        """Get recent fee payment history."""
        return list(reversed(self._payments[-limit:]))

    def get_stats(self) -> Dict[str, Any]:
        """Get fee engine statistics."""
        total_collected = sum(p.fee_eth for p in self._payments if p.success)
        return {
            "total_collected_eth": float(total_collected),
            "total_payments": len(self._payments),
            "successful_payments": sum(1 for p in self._payments if p.success),
            "failed_payments": sum(1 for p in self._payments if not p.success),
            "fee_rate_percent": float(self._fee_rate * 100),
            "max_fee_eth": float(self._max_fee),
        }

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _get_circulation(self, wallet_address: str) -> Decimal:
        """Get monthly circulation in ETH from WalletTracker."""
        if self._wallet_tracker:
            return self._wallet_tracker.get_monthly_circulation(wallet_address)
        return Decimal("0")
