"""
Eligibility Tracker
=====================

Monitors monthly ETH circulation per wallet and manages automatic
enrollment/disenrollment for insurance coverage.

Rules:
- Auto-enroll at 0.5 ETH monthly circulation.
- Auto-disenroll at 0.2 ETH monthly circulation.
- Hysteresis band prevents rapid toggling near threshold.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Eligibility thresholds in ETH
ENROLL_THRESHOLD: Decimal = Decimal("0.5")
DISENROLL_THRESHOLD: Decimal = Decimal("0.2")


class EligibilityStatus(Enum):
    """Insurance eligibility status."""
    ELIGIBLE = "eligible"
    NOT_ELIGIBLE = "not_eligible"
    GRACE_PERIOD = "grace_period"


@dataclass
class EligibilityRecord:
    """Eligibility state for a single wallet."""
    wallet_address: str
    status: EligibilityStatus = EligibilityStatus.NOT_ELIGIBLE
    current_monthly_circulation: Decimal = Decimal("0")
    enrolled_at: Optional[float] = None
    disenrolled_at: Optional[float] = None
    last_checked_at: float = field(default_factory=time.time)
    consecutive_eligible_months: int = 0
    grace_period_until: Optional[float] = None
    history: List[Dict[str, Any]] = field(default_factory=list)


class EligibilityTracker:
    """Monitors monthly ETH circulation for insurance eligibility.

    Automatically enrolls wallets that reach the 0.5 ETH monthly
    circulation threshold and disenrolls those that fall below 0.2 ETH.
    The hysteresis band between 0.2 and 0.5 prevents rapid toggling.

    Parameters
    ----------
    wallet_tracker : Any
        Component 7 WalletTracker for circulation data.
    on_enroll : callable, optional
        Callback when a wallet becomes eligible.
    on_disenroll : callable, optional
        Callback when a wallet loses eligibility.
    grace_period_days : int
        Days of grace period before disenrollment takes effect.
    """

    def __init__(
        self,
        wallet_tracker: Any = None,
        on_enroll: Optional[Callable] = None,
        on_disenroll: Optional[Callable] = None,
        grace_period_days: int = 7,
    ) -> None:
        self._wallet_tracker = wallet_tracker
        self._on_enroll = on_enroll
        self._on_disenroll = on_disenroll
        self._grace_period_seconds = grace_period_days * 86400
        self._records: Dict[str, EligibilityRecord] = {}
        logger.info(
            "EligibilityTracker initialised (enroll=%.1f ETH, disenroll=%.1f ETH, grace=%dd)",
            ENROLL_THRESHOLD, DISENROLL_THRESHOLD, grace_period_days,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check_eligibility(self, wallet_address: str) -> EligibilityRecord:
        """Check and update eligibility for a wallet.

        Reads the wallet's monthly circulation from WalletTracker
        and applies enrollment/disenrollment rules.

        Args:
            wallet_address: The wallet to check.

        Returns:
            Updated EligibilityRecord.
        """
        record = self._get_or_create(wallet_address)
        circulation = self._get_circulation(wallet_address)
        record.current_monthly_circulation = circulation
        record.last_checked_at = time.time()

        previous_status = record.status

        if record.status == EligibilityStatus.NOT_ELIGIBLE:
            if circulation >= ENROLL_THRESHOLD:
                self._enroll(record)
        elif record.status == EligibilityStatus.ELIGIBLE:
            if circulation < DISENROLL_THRESHOLD:
                self._start_grace_period(record)
        elif record.status == EligibilityStatus.GRACE_PERIOD:
            if circulation >= ENROLL_THRESHOLD:
                # Recovered -- cancel grace period
                record.status = EligibilityStatus.ELIGIBLE
                record.grace_period_until = None
                logger.info("Grace period cancelled for %s (circulation recovered)", wallet_address)
            elif record.grace_period_until and time.time() > record.grace_period_until:
                self._disenroll(record)

        # Log status change
        if record.status != previous_status:
            record.history.append({
                "from": previous_status.value,
                "to": record.status.value,
                "circulation": str(circulation),
                "timestamp": time.time(),
            })

        return record

    def check_all(self) -> Dict[str, EligibilityRecord]:
        """Check eligibility for all tracked wallets.

        Returns:
            Dict mapping wallet address to updated EligibilityRecord.
        """
        if self._wallet_tracker:
            wallets = self._wallet_tracker.get_all_tracked_wallets()
            for addr in wallets:
                self.check_eligibility(addr)
        return dict(self._records)

    def is_eligible(self, wallet_address: str) -> bool:
        """Quick check: is the wallet currently eligible?"""
        record = self._records.get(wallet_address)
        if record is None:
            record = self.check_eligibility(wallet_address)
        return record.status == EligibilityStatus.ELIGIBLE

    def get_eligible_wallets(self) -> List[str]:
        """Get all currently eligible wallet addresses."""
        return [
            addr for addr, rec in self._records.items()
            if rec.status == EligibilityStatus.ELIGIBLE
        ]

    def get_record(self, wallet_address: str) -> Optional[EligibilityRecord]:
        """Get the eligibility record for a wallet."""
        return self._records.get(wallet_address)

    def get_stats(self) -> Dict[str, int]:
        """Get eligibility statistics."""
        stats = {"eligible": 0, "not_eligible": 0, "grace_period": 0}
        for record in self._records.values():
            stats[record.status.value] += 1
        return stats

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _get_or_create(self, wallet_address: str) -> EligibilityRecord:
        if wallet_address not in self._records:
            self._records[wallet_address] = EligibilityRecord(
                wallet_address=wallet_address
            )
        return self._records[wallet_address]

    def _get_circulation(self, wallet_address: str) -> Decimal:
        """Get monthly circulation from WalletTracker."""
        if self._wallet_tracker:
            return self._wallet_tracker.get_monthly_circulation(wallet_address)
        return Decimal("0")

    def _enroll(self, record: EligibilityRecord) -> None:
        record.status = EligibilityStatus.ELIGIBLE
        record.enrolled_at = time.time()
        record.disenrolled_at = None
        record.consecutive_eligible_months += 1
        logger.info(
            "Wallet %s AUTO-ENROLLED (circulation=%.4f ETH)",
            record.wallet_address, record.current_monthly_circulation,
        )
        if self._on_enroll:
            try:
                self._on_enroll(record.wallet_address)
            except Exception as exc:
                logger.error("Enroll callback failed for %s: %s", record.wallet_address, exc)

    def _start_grace_period(self, record: EligibilityRecord) -> None:
        record.status = EligibilityStatus.GRACE_PERIOD
        record.grace_period_until = time.time() + self._grace_period_seconds
        logger.info(
            "Wallet %s entered GRACE PERIOD (circulation=%.4f ETH, expires=%s)",
            record.wallet_address, record.current_monthly_circulation,
            time.ctime(record.grace_period_until),
        )

    def _disenroll(self, record: EligibilityRecord) -> None:
        record.status = EligibilityStatus.NOT_ELIGIBLE
        record.disenrolled_at = time.time()
        record.grace_period_until = None
        record.consecutive_eligible_months = 0
        logger.info(
            "Wallet %s AUTO-DISENROLLED (circulation=%.4f ETH)",
            record.wallet_address, record.current_monthly_circulation,
        )
        if self._on_disenroll:
            try:
                self._on_disenroll(record.wallet_address)
            except Exception as exc:
                logger.error("Disenroll callback failed for %s: %s", record.wallet_address, exc)
