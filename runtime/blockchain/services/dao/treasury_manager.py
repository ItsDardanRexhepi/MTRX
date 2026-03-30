"""
Component 6 - TreasuryManager

Real-time treasury tracking and monthly fee routing to NeoSafe.
Monitors DAO treasury values and triggers automatic monthly maintenance
fee calculations and payments.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from web3 import Web3
from web3.contract import Contract

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Base mainnet constants
# ---------------------------------------------------------------------------
BASE_CHAIN_ID: int = 8453
NEOSAFE: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
EAS_SCHEMA_UID: str = "0x348"

SECONDS_PER_MONTH: int = 2_592_000  # 30 days


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


@dataclass
class TreasurySnapshot:
    """Point-in-time record of a DAO's treasury value."""

    dao_id: str
    value_usd: float
    captured_at: float = field(default_factory=time.time)
    source: str = "oracle"


@dataclass
class FeePayment:
    """Record of a monthly fee payment routed to NeoSafe."""

    dao_id: str
    treasury_at_calculation: float
    annual_rate_bps: int
    monthly_fee_usd: float
    tx_hash: Optional[str] = None
    routed_at: float = field(default_factory=time.time)
    success: bool = False


@dataclass
class TreasuryState:
    """Aggregated state for a single DAO's treasury tracking."""

    dao_id: str
    current_value_usd: float = 0.0
    last_snapshot_at: float = 0.0
    last_fee_at: float = 0.0
    total_fees_paid_usd: float = 0.0
    snapshots: list[TreasurySnapshot] = field(default_factory=list)
    fee_history: list[FeePayment] = field(default_factory=list)


# ---------------------------------------------------------------------------
# TreasuryManager
# ---------------------------------------------------------------------------


class TreasuryManager:
    """Real-time treasury tracking and monthly fee routing to NeoSafe.

    Monitors treasury values for all managed DAOs and automatically
    routes monthly maintenance fees to the NeoSafe wallet based on the
    current treasury tier at the time of calculation.

    Parameters
    ----------
    web3 : Web3
        Connected Web3 instance pointed at Base mainnet.
    dao_contract : Contract
        Deployed ``OpenMatrixDAO`` contract instance.
    platform_account : str
        Platform hot-wallet that pays gas for fee routing.
    tier_calculator : object
        ``TierCalculator`` instance for fee-rate lookups.
    """

    def __init__(
        self,
        web3: Web3,
        dao_contract: Contract,
        platform_account: str,
        tier_calculator: object,
    ) -> None:
        self._w3 = web3
        self._contract = dao_contract
        self._platform_account = Web3.to_checksum_address(platform_account)
        self._tier_calculator = tier_calculator
        self._treasuries: dict[str, TreasuryState] = {}
        logger.info("TreasuryManager initialised on chain %s", web3.eth.chain_id)

    # ------------------------------------------------------------------
    # Public API - Snapshot management
    # ------------------------------------------------------------------

    def register_dao(self, dao_id: str, initial_value_usd: float = 0.0) -> TreasuryState:
        """Register a DAO for treasury tracking.

        Parameters
        ----------
        dao_id : str
            Unique identifier for the DAO.
        initial_value_usd : float
            Starting treasury value in USD.

        Returns
        -------
        TreasuryState
            The initial treasury state.
        """
        if dao_id in self._treasuries:
            logger.warning("DAO %s already registered; returning existing state", dao_id)
            return self._treasuries[dao_id]

        state = TreasuryState(
            dao_id=dao_id,
            current_value_usd=initial_value_usd,
            last_snapshot_at=time.time(),
        )
        self._treasuries[dao_id] = state
        logger.info("DAO %s registered with treasury $%.2f", dao_id, initial_value_usd)
        return state

    def record_snapshot(
        self,
        dao_id: str,
        value_usd: float,
        source: str = "oracle",
    ) -> TreasurySnapshot:
        """Record a new treasury value snapshot.

        Also pushes the updated value to the on-chain contract via
        ``updateTreasuryValue()``.

        Parameters
        ----------
        dao_id : str
            DAO identifier.
        value_usd : float
            Current treasury value in USD.
        source : str
            Data source label (e.g. ``"oracle"``, ``"manual"``).

        Returns
        -------
        TreasurySnapshot
            The recorded snapshot.

        Raises
        ------
        ValueError
            If the DAO is not registered.
        """
        state = self._get_state(dao_id)
        snapshot = TreasurySnapshot(dao_id=dao_id, value_usd=value_usd, source=source)
        state.snapshots.append(snapshot)
        state.current_value_usd = value_usd
        state.last_snapshot_at = snapshot.captured_at

        # Push to chain
        self._update_on_chain_treasury(dao_id, value_usd)

        logger.info("Snapshot recorded for DAO %s: $%.2f (%s)", dao_id, value_usd, source)
        return snapshot

    def get_current_value(self, dao_id: str) -> float:
        """Return the most recent treasury value for a DAO.

        Raises
        ------
        ValueError
            If the DAO is not registered.
        """
        return self._get_state(dao_id).current_value_usd

    def get_snapshot_history(self, dao_id: str) -> list[TreasurySnapshot]:
        """Return the full snapshot history for a DAO."""
        return self._get_state(dao_id).snapshots

    # ------------------------------------------------------------------
    # Public API - Monthly fee routing
    # ------------------------------------------------------------------

    async def route_monthly_fee(self, dao_id: str) -> FeePayment:
        """Calculate and route the monthly maintenance fee to NeoSafe.

        The fee is computed from the CURRENT treasury value at the moment
        of calculation and adjusts BOTH directions (up or down) based on
        the tier thresholds.

        Parameters
        ----------
        dao_id : str
            DAO identifier.

        Returns
        -------
        FeePayment
            Record of the routed fee.

        Raises
        ------
        ValueError
            If the DAO is not registered.
        RuntimeError
            If the on-chain fee routing transaction fails.
        """
        state = self._get_state(dao_id)
        treasury_usd = state.current_value_usd

        # Use TierCalculator for rate lookup
        annual_bps: int = self._tier_calculator.get_annual_rate_bps(  # type: ignore[attr-defined]
            dao_id=dao_id,
            treasury_value_usd=treasury_usd,
        )
        monthly_fee_usd = (treasury_usd * annual_bps / 10_000) / 12

        payment = FeePayment(
            dao_id=dao_id,
            treasury_at_calculation=treasury_usd,
            annual_rate_bps=annual_bps,
            monthly_fee_usd=monthly_fee_usd,
        )

        try:
            tx_hash = self._route_fee_on_chain(dao_id, monthly_fee_usd)
            payment.tx_hash = tx_hash
            payment.success = True
            payment.routed_at = time.time()

            state.last_fee_at = payment.routed_at
            state.total_fees_paid_usd += monthly_fee_usd
            state.fee_history.append(payment)

            logger.info(
                "Monthly fee routed for DAO %s: $%.2f (%d bps) tx=%s",
                dao_id,
                monthly_fee_usd,
                annual_bps,
                tx_hash,
            )
        except Exception as exc:
            payment.success = False
            state.fee_history.append(payment)
            logger.error("Fee routing failed for DAO %s: %s", dao_id, exc)
            raise RuntimeError(f"Fee routing failed: {exc}") from exc

        return payment

    async def route_all_monthly_fees(self) -> list[FeePayment]:
        """Route monthly fees for all registered DAOs.

        Returns a list of ``FeePayment`` records (including failures).
        """
        payments: list[FeePayment] = []
        for dao_id in list(self._treasuries.keys()):
            try:
                payment = await self.route_monthly_fee(dao_id)
                payments.append(payment)
            except RuntimeError:
                # Already logged; continue to next DAO
                if self._treasuries[dao_id].fee_history:
                    payments.append(self._treasuries[dao_id].fee_history[-1])
        return payments

    def is_fee_due(self, dao_id: str) -> bool:
        """Check whether a monthly fee is due for the DAO.

        A fee is due if more than 30 days have elapsed since the last
        fee payment (or since registration if no fee has been paid).
        """
        state = self._get_state(dao_id)
        reference = state.last_fee_at or state.last_snapshot_at
        return (time.time() - reference) >= SECONDS_PER_MONTH

    def get_fee_history(self, dao_id: str) -> list[FeePayment]:
        """Return the fee payment history for a DAO."""
        return self._get_state(dao_id).fee_history

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_state(self, dao_id: str) -> TreasuryState:
        state = self._treasuries.get(dao_id)
        if state is None:
            raise ValueError(f"DAO not registered: {dao_id}")
        return state

    def _update_on_chain_treasury(self, dao_id: str, value_usd: float) -> None:
        """Push the treasury value to the on-chain contract."""
        try:
            value_wei = Web3.to_wei(value_usd, "ether")
            dao_id_bytes = bytes.fromhex(dao_id) if len(dao_id) == 64 else Web3.keccak(text=dao_id)

            tx = self._contract.functions.updateTreasuryValue(
                dao_id_bytes,
                value_wei,
            ).build_transaction({
                "from": self._platform_account,
                "chainId": BASE_CHAIN_ID,
                "gas": 100_000,
                "nonce": self._w3.eth.get_transaction_count(self._platform_account),
            })
            signed = self._w3.eth.account.sign_transaction(tx, private_key="")
            tx_hash = self._w3.eth.send_raw_transaction(signed.raw_transaction)
            self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
            logger.debug("On-chain treasury updated for DAO %s: tx=%s", dao_id, tx_hash.hex())
        except Exception as exc:
            logger.warning("Failed to update on-chain treasury for DAO %s: %s", dao_id, exc)

    def _route_fee_on_chain(self, dao_id: str, fee_usd: float) -> str:
        """Call ``routeMonthlyFee`` on the on-chain contract.

        Returns the transaction hash as a hex string.
        """
        fee_wei = Web3.to_wei(fee_usd, "ether")
        dao_id_bytes = bytes.fromhex(dao_id) if len(dao_id) == 64 else Web3.keccak(text=dao_id)

        tx = self._contract.functions.routeMonthlyFee(
            dao_id_bytes,
        ).build_transaction({
            "from": self._platform_account,
            "chainId": BASE_CHAIN_ID,
            "value": fee_wei,
            "gas": 200_000,
            "nonce": self._w3.eth.get_transaction_count(self._platform_account),
        })
        signed = self._w3.eth.account.sign_transaction(tx, private_key="")
        tx_hash = self._w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt["status"] != 1:
            raise RuntimeError(f"routeMonthlyFee reverted: {tx_hash.hex()}")

        return tx_hash.hex()
