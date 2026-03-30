"""
Securities Fee Calculator — 0.25% per exchange for securities token trades.

Part of Component 18 (Securities Token Exchange).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class SecuritiesFeeResult:
    """Result of a securities fee calculation."""
    exchange_id: str
    trade_amount_wei: int
    fee_wei: int
    fee_percent: float
    fee_recipient: str
    security_token: str
    computed_at: float = field(default_factory=time.time)


@dataclass
class FeeCollectionRecord:
    """Record of a collected fee."""
    exchange_id: str
    fee_wei: int
    collected_at: float
    tx_hash: Optional[str] = None


class SecuritiesFeeCalculator:
    """
    Calculates and tracks fees for securities token exchanges.

    Fixed rate: 0.25% per exchange, sent to NeoSafe.
    No tiered pricing, no discounts — flat rate on every trade.
    """

    FEE_BPS: int = 25  # 0.25%

    def __init__(self) -> None:
        self._collections: List[FeeCollectionRecord] = []
        self._total_collected_wei: int = 0
        self._exchange_counter: int = 0
        logger.info("SecuritiesFeeCalculator initialised (0.25%% per exchange).")

    def calculate_fee(
        self,
        trade_amount_wei: int,
        security_token: str,
    ) -> SecuritiesFeeResult:
        """
        Calculate the fee for a securities exchange.

        Args:
            trade_amount_wei: Total trade amount in wei.
            security_token: Address or identifier of the security token.

        Returns:
            SecuritiesFeeResult with fee details.

        Raises:
            ValueError: If trade amount is non-positive.
        """
        if trade_amount_wei <= 0:
            raise ValueError("Trade amount must be positive.")

        self._exchange_counter += 1
        exchange_id = f"SEC-EX-{self._exchange_counter:08d}"
        fee_wei = (trade_amount_wei * self.FEE_BPS) // 10_000

        result = SecuritiesFeeResult(
            exchange_id=exchange_id,
            trade_amount_wei=trade_amount_wei,
            fee_wei=fee_wei,
            fee_percent=self.FEE_BPS / 100.0,
            fee_recipient=NEOSAFE_ADDRESS,
            security_token=security_token,
        )

        logger.info(
            "Securities fee calculated | exchange=%s | trade=%d | fee=%d (0.25%%)",
            exchange_id, trade_amount_wei, fee_wei,
        )
        return result

    def record_collection(
        self,
        exchange_id: str,
        fee_wei: int,
        tx_hash: Optional[str] = None,
    ) -> FeeCollectionRecord:
        """Record a collected fee."""
        record = FeeCollectionRecord(
            exchange_id=exchange_id,
            fee_wei=fee_wei,
            collected_at=time.time(),
            tx_hash=tx_hash,
        )
        self._collections.append(record)
        self._total_collected_wei += fee_wei
        logger.info(
            "Fee collected | exchange=%s | fee=%d -> %s",
            exchange_id, fee_wei, NEOSAFE_ADDRESS,
        )
        return record

    def get_total_collected(self) -> int:
        """Return total fees collected lifetime."""
        return self._total_collected_wei

    def get_collection_history(self, limit: int = 50) -> List[FeeCollectionRecord]:
        """Return recent fee collection records."""
        return list(reversed(self._collections[-limit:]))

    def get_fee_rate_bps(self) -> int:
        """Return the fee rate in basis points."""
        return self.FEE_BPS
