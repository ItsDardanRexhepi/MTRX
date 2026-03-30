"""
Ratio Monitor — Component 2
============================

Real-time collateral ratio monitoring service for all active DeFi and P2P
loans.  Fires Telegram alerts at the 120 % warning threshold and triggers
auto-liquidation after 48 hours if the ratio is not restored to 150 %.

Integrates with:
- DeFiLoan / P2PLoan smart contracts on Base
- Telegram Bot API for borrower notifications
- CollateralManager for liquidation execution
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from typing import Optional

import httpx
from web3 import Web3
from web3.contract import Contract

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
#  Enums & Data
# ---------------------------------------------------------------------------

class CollateralStatus(Enum):
    """Collateral health classification."""
    HEALTHY = "HEALTHY"          # >= 150 %
    WARNING = "WARNING"          # 120 %–149 %
    CRITICAL = "CRITICAL"        # < 120 %, grace period running
    LIQUIDATING = "LIQUIDATING"  # grace period expired, liquidation imminent


@dataclass
class LoanMonitorEntry:
    """Internal tracking record for a monitored loan."""
    loan_id: int
    contract_type: str              # "defi" or "p2p"
    borrower: str
    borrower_telegram_id: Optional[str] = None
    current_ratio: Decimal = Decimal("0")
    status: CollateralStatus = CollateralStatus.HEALTHY
    warning_since: Optional[datetime] = None
    last_alert_sent: Optional[datetime] = None
    alert_count: int = 0


# ---------------------------------------------------------------------------
#  Constants
# ---------------------------------------------------------------------------

MIN_RATIO = Decimal("1.50")       # 150 %
WARNING_RATIO = Decimal("1.20")   # 120 %
GRACE_PERIOD_SECONDS = 48 * 3600  # 48 hours
MONITOR_INTERVAL_SECONDS = 60     # Check every 60 s
ALERT_COOLDOWN_SECONDS = 3600     # Re-alert at most once per hour

DARDAN_TELEGRAM_ID = "7161847911"


# ---------------------------------------------------------------------------
#  RatioMonitor
# ---------------------------------------------------------------------------

class RatioMonitor:
    """
    Continuously monitors collateral ratios for all active loans and takes
    action when thresholds are breached.

    Parameters
    ----------
    w3 : Web3
        Connected Web3 instance for Base.
    defi_contract : Contract
        DeFiLoan contract instance.
    p2p_contract : Contract
        P2PLoan contract instance.
    telegram_bot_token : str
        Telegram Bot API token for sending alerts.
    collateral_manager : object
        ``CollateralManager`` instance used for liquidation calls.
    borrower_registry : dict[str, str] | None
        Optional mapping of wallet address -> Telegram chat ID.
    monitor_interval : int
        Seconds between monitoring cycles (default 60).
    """

    def __init__(
        self,
        w3: Web3,
        defi_contract: Contract,
        p2p_contract: Contract,
        telegram_bot_token: str,
        collateral_manager: object,
        borrower_registry: Optional[dict[str, str]] = None,
        monitor_interval: int = MONITOR_INTERVAL_SECONDS,
    ) -> None:
        self._w3 = w3
        self._defi = defi_contract
        self._p2p = p2p_contract
        self._bot_token = telegram_bot_token
        self._collateral_mgr = collateral_manager
        self._borrower_registry = borrower_registry or {}
        self._interval = monitor_interval

        self._monitored: dict[tuple[str, int], LoanMonitorEntry] = {}
        self._running = False
        self._task: Optional[asyncio.Task] = None

        logger.info(
            "RatioMonitor initialised — interval=%ds, registered borrowers=%d",
            self._interval,
            len(self._borrower_registry),
        )

    # ------------------------------------------------------------------
    #  Public API
    # ------------------------------------------------------------------

    async def start_monitoring(self) -> None:
        """
        Start the asynchronous monitoring loop.

        Discovers all active loans on startup and then enters a perpetual
        check cycle.  Call ``stop_monitoring()`` to gracefully shut down.
        """
        if self._running:
            logger.warning("RatioMonitor is already running")
            return

        self._running = True
        logger.info("Starting collateral ratio monitoring loop")

        # Initial discovery
        await self._discover_active_loans()

        self._task = asyncio.create_task(self._monitor_loop())

    async def stop_monitoring(self) -> None:
        """Gracefully stop the monitoring loop."""
        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("RatioMonitor stopped")

    async def check_all_loans(self) -> dict[int, CollateralStatus]:
        """
        Run a single check cycle across every monitored loan.

        Returns
        -------
        dict[int, CollateralStatus]
            Mapping of loan_id to current collateral status.
        """
        results: dict[int, CollateralStatus] = {}

        for key, entry in list(self._monitored.items()):
            try:
                status = await self.check_loan_ratio(
                    entry.loan_id, contract_type=entry.contract_type
                )
                results[entry.loan_id] = status
            except Exception as exc:
                logger.error(
                    "Error checking loan %d (%s): %s",
                    entry.loan_id, entry.contract_type, exc,
                )
                results[entry.loan_id] = entry.status

        return results

    async def check_loan_ratio(
        self,
        loan_id: int,
        *,
        contract_type: str = "defi",
    ) -> CollateralStatus:
        """
        Check the collateral ratio for a single loan, update internal state,
        send alerts, or trigger liquidation as appropriate.

        Parameters
        ----------
        loan_id : int
            On-chain loan identifier.
        contract_type : str
            ``"defi"`` or ``"p2p"``.

        Returns
        -------
        CollateralStatus
            Current collateral health classification.
        """
        key = (contract_type, loan_id)
        contract = self._defi if contract_type == "defi" else self._p2p

        try:
            ratio_wad: int = contract.functions.getCollateralRatio(loan_id).call()
            ratio = Decimal(str(ratio_wad)) / Decimal("1e18")
        except Exception as exc:
            logger.error("Oracle call failed for loan %d: %s", loan_id, exc)
            raise

        # Ensure entry exists
        if key not in self._monitored:
            borrower = self._get_borrower(contract, loan_id)
            self._monitored[key] = LoanMonitorEntry(
                loan_id=loan_id,
                contract_type=contract_type,
                borrower=borrower,
                borrower_telegram_id=self._borrower_registry.get(borrower.lower()),
            )

        entry = self._monitored[key]
        entry.current_ratio = ratio
        now = datetime.now(timezone.utc)

        # Classify
        if ratio >= MIN_RATIO:
            entry.status = CollateralStatus.HEALTHY
            entry.warning_since = None
            entry.alert_count = 0
            logger.debug("Loan %d healthy — ratio=%s", loan_id, ratio)

        elif ratio >= WARNING_RATIO:
            entry.status = CollateralStatus.WARNING
            if entry.warning_since is None:
                entry.warning_since = now
            await self._maybe_send_alert(entry, now)
            logger.info("Loan %d WARNING — ratio=%s", loan_id, ratio)

        else:
            # Below 120 %
            if entry.warning_since is None:
                entry.warning_since = now

            elapsed = (now - entry.warning_since).total_seconds()
            if elapsed >= GRACE_PERIOD_SECONDS:
                entry.status = CollateralStatus.LIQUIDATING
                logger.warning(
                    "Loan %d LIQUIDATING — ratio=%s, warning since %s",
                    loan_id, ratio, entry.warning_since.isoformat(),
                )
                await self.trigger_liquidation(loan_id, contract_type=contract_type)
            else:
                entry.status = CollateralStatus.CRITICAL
                remaining_h = (GRACE_PERIOD_SECONDS - elapsed) / 3600
                logger.warning(
                    "Loan %d CRITICAL — ratio=%s, %.1f h until liquidation",
                    loan_id, ratio, remaining_h,
                )
                await self._maybe_send_alert(entry, now)

        return entry.status

    async def send_telegram_alert(
        self,
        borrower: str,
        loan_id: int,
        current_ratio: Decimal,
        *,
        extra_message: str = "",
    ) -> bool:
        """
        Send a Telegram alert to the borrower about their collateral ratio.

        Parameters
        ----------
        borrower : str
            Borrower wallet address.
        loan_id : int
            On-chain loan identifier.
        current_ratio : Decimal
            Current collateral ratio.
        extra_message : str
            Optional additional text appended to the alert.

        Returns
        -------
        bool
            True if the message was delivered successfully.
        """
        chat_id = self._borrower_registry.get(borrower.lower())

        # Always alert Dardan as platform admin
        recipients = [DARDAN_TELEGRAM_ID]
        if chat_id and chat_id != DARDAN_TELEGRAM_ID:
            recipients.append(chat_id)

        ratio_pct = current_ratio * Decimal("100")
        status_emoji = "🔴" if current_ratio < WARNING_RATIO else "🟡"

        message = (
            f"{status_emoji} *Collateral Alert — Loan #{loan_id}*\n\n"
            f"Borrower: `{borrower}`\n"
            f"Current Ratio: *{ratio_pct:.1f}%*\n"
            f"Required: *150%*\n"
            f"Warning Threshold: *120%*\n\n"
        )

        if current_ratio < WARNING_RATIO:
            message += (
                "This loan is *below the critical threshold*.\n"
                "Auto-liquidation will occur in 48 hours if the ratio "
                "is not restored to 150%.\n\n"
                "Top up collateral immediately to avoid liquidation."
            )
        else:
            message += (
                "This loan is *below the minimum ratio*.\n"
                "Please top up collateral to restore it above 150%."
            )

        if extra_message:
            message += f"\n\n{extra_message}"

        success = True
        for recipient in recipients:
            delivered = await self._send_telegram_message(recipient, message)
            if not delivered:
                success = False
                logger.error(
                    "Failed to send alert to %s for loan %d", recipient, loan_id
                )

        return success

    async def trigger_liquidation(
        self,
        loan_id: int,
        *,
        contract_type: str = "defi",
    ) -> None:
        """
        Trigger auto-liquidation for a loan that has exceeded the 48-hour
        grace period without restoring its collateral ratio.

        Parameters
        ----------
        loan_id : int
            On-chain loan identifier.
        contract_type : str
            ``"defi"`` or ``"p2p"``.
        """
        key = (contract_type, loan_id)
        entry = self._monitored.get(key)

        logger.warning(
            "Triggering auto-liquidation for loan %d (%s)", loan_id, contract_type
        )

        # Notify before liquidation
        if entry:
            await self.send_telegram_alert(
                entry.borrower,
                loan_id,
                entry.current_ratio,
                extra_message="LIQUIDATION IS BEING EXECUTED NOW.",
            )

        try:
            tx_hash = self._collateral_mgr.liquidate(
                loan_id, contract=contract_type
            )
            logger.warning(
                "Liquidation executed for loan %d — tx=%s", loan_id, tx_hash
            )

            # Send confirmation
            await self._send_telegram_message(
                DARDAN_TELEGRAM_ID,
                f"*Liquidation Executed*\n\n"
                f"Loan #{loan_id} ({contract_type})\n"
                f"TX: `{tx_hash}`",
            )

            # Remove from monitoring
            if key in self._monitored:
                del self._monitored[key]

        except Exception as exc:
            logger.error(
                "Liquidation FAILED for loan %d: %s", loan_id, exc
            )
            await self._send_telegram_message(
                DARDAN_TELEGRAM_ID,
                f"*LIQUIDATION FAILED*\n\n"
                f"Loan #{loan_id} ({contract_type})\n"
                f"Error: `{exc!s}`\n\n"
                f"Manual intervention required.",
            )

    # ------------------------------------------------------------------
    #  Private helpers
    # ------------------------------------------------------------------

    async def _monitor_loop(self) -> None:
        """Perpetual monitoring loop."""
        while self._running:
            try:
                await self.check_all_loans()
                # Periodically re-discover new loans
                await self._discover_active_loans()
            except Exception as exc:
                logger.error("Monitor loop error: %s", exc)

            await asyncio.sleep(self._interval)

    async def _discover_active_loans(self) -> None:
        """Discover all active loans from both contracts."""
        for contract_type, contract in [("defi", self._defi), ("p2p", self._p2p)]:
            try:
                next_id: int = contract.functions.nextLoanId().call()
                for loan_id in range(next_id):
                    key = (contract_type, loan_id)
                    if key in self._monitored:
                        continue
                    try:
                        loan_data = contract.functions.loans(loan_id).call()
                        # Check if active (status == 0)
                        status_index = 10 if contract_type == "defi" else 13
                        if loan_data[status_index] == 0:
                            borrower = loan_data[1] if contract_type == "defi" else loan_data[2]
                            self._monitored[key] = LoanMonitorEntry(
                                loan_id=loan_id,
                                contract_type=contract_type,
                                borrower=borrower,
                                borrower_telegram_id=self._borrower_registry.get(
                                    borrower.lower()
                                ),
                            )
                    except Exception:
                        continue
            except Exception as exc:
                logger.error("Discovery failed for %s contract: %s", contract_type, exc)

    async def _maybe_send_alert(self, entry: LoanMonitorEntry, now: datetime) -> None:
        """Send an alert if the cooldown has elapsed."""
        if entry.last_alert_sent is not None:
            elapsed = (now - entry.last_alert_sent).total_seconds()
            if elapsed < ALERT_COOLDOWN_SECONDS:
                return

        delivered = await self.send_telegram_alert(
            entry.borrower, entry.loan_id, entry.current_ratio
        )
        if delivered:
            entry.last_alert_sent = now
            entry.alert_count += 1

    async def _send_telegram_message(self, chat_id: str, text: str) -> bool:
        """Send a message via the Telegram Bot API."""
        url = f"https://api.telegram.org/bot{self._bot_token}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "Markdown",
            "disable_web_page_preview": True,
        }

        try:
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    data = response.json()
                    if data.get("ok"):
                        logger.debug("Telegram message sent to %s", chat_id)
                        return True
                    logger.error("Telegram API error: %s", data)
                else:
                    logger.error(
                        "Telegram HTTP %d: %s", response.status_code, response.text
                    )
        except Exception as exc:
            logger.error("Telegram send failed: %s", exc)

        return False

    @staticmethod
    def _get_borrower(contract: Contract, loan_id: int) -> str:
        """Extract borrower address from on-chain loan data."""
        try:
            loan_data = contract.functions.loans(loan_id).call()
            # DeFiLoan: index 1 is borrower; P2PLoan: index 2 is borrower
            return loan_data[1] if len(loan_data) < 16 else loan_data[2]
        except Exception:
            return "0x" + "0" * 40
