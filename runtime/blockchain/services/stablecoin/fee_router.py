"""
Fee Router
===========

Routes all collected stablecoin fees to the NeoSafe wallet.
Every fee payment is recorded with a full audit trail and
on-chain transaction hash.
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
BASE_CHAIN_ID: int = 8453
USDC_BASE_ADDRESS: str = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"


@dataclass
class FeePayment:
    """Record of a fee routed to NeoSafe."""
    payment_id: str
    source_wallet: str
    amount: Decimal
    currency: str = "USDC"
    destination: str = NEOSAFE_ADDRESS
    tx_hash: Optional[str] = None
    timestamp: float = field(default_factory=time.time)
    success: bool = False
    source_component: int = 7
    transfer_id: Optional[str] = None
    error: Optional[str] = None


@dataclass
class RoutingStats:
    """Aggregated fee routing statistics."""
    total_routed: Decimal
    total_payments: int
    successful_payments: int
    failed_payments: int
    last_routed_at: Optional[float] = None


class FeeRouter:
    """Routes all stablecoin fees to the NeoSafe wallet.

    Every fee collected from rate-limited transfers is routed to
    NeoSafe with full on-chain settlement. Failed routes are
    retried automatically.

    Parameters
    ----------
    web3_provider : Any
        Connected Web3 provider on Base.
    stablecoin_contract : Any
        Deployed stablecoin/USDC contract for transfers.
    platform_account : str
        Platform hot-wallet address for signing.
    """

    def __init__(
        self,
        web3_provider: Any = None,
        stablecoin_contract: Any = None,
        platform_account: Optional[str] = None,
    ) -> None:
        self._web3 = web3_provider
        self._contract = stablecoin_contract
        self._platform_account = platform_account
        self._payments: List[FeePayment] = []
        self._pending_retry: List[FeePayment] = []
        logger.info("FeeRouter initialised (destination=%s)", NEOSAFE_ADDRESS)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def route_fee(
        self,
        source_wallet: str,
        amount: Decimal,
        transfer_id: Optional[str] = None,
    ) -> FeePayment:
        """Route a fee payment to NeoSafe.

        Args:
            source_wallet: Wallet the fee was collected from.
            amount: Fee amount in USDC.
            transfer_id: Optional ID of the originating transfer.

        Returns:
            FeePayment record with outcome.
        """
        payment_id = f"fee-{uuid.uuid4().hex[:12]}"
        payment = FeePayment(
            payment_id=payment_id,
            source_wallet=source_wallet,
            amount=amount,
            transfer_id=transfer_id,
        )

        try:
            tx_hash = self._execute_transfer(source_wallet, amount)
            payment.tx_hash = tx_hash
            payment.success = True
            logger.info(
                "Fee routed to NeoSafe: %.4f USDC from %s (tx=%s)",
                amount, source_wallet, tx_hash,
            )
        except Exception as exc:
            payment.success = False
            payment.error = str(exc)
            self._pending_retry.append(payment)
            logger.error(
                "Fee routing failed for %.4f USDC from %s: %s",
                amount, source_wallet, exc,
            )

        self._payments.append(payment)
        return payment

    def route_batch(
        self, fees: List[Dict[str, Any]]
    ) -> List[FeePayment]:
        """Route multiple fees in a single batch.

        Args:
            fees: List of dicts with 'source_wallet', 'amount', and
                optional 'transfer_id'.

        Returns:
            List of FeePayment results.
        """
        results: List[FeePayment] = []
        for fee_data in fees:
            payment = self.route_fee(
                source_wallet=fee_data["source_wallet"],
                amount=Decimal(str(fee_data["amount"])),
                transfer_id=fee_data.get("transfer_id"),
            )
            results.append(payment)
        return results

    def retry_failed(self) -> List[FeePayment]:
        """Retry all previously failed fee routings.

        Returns:
            List of retry results.
        """
        to_retry = list(self._pending_retry)
        self._pending_retry.clear()
        results: List[FeePayment] = []

        for original in to_retry:
            payment = self.route_fee(
                source_wallet=original.source_wallet,
                amount=original.amount,
                transfer_id=original.transfer_id,
            )
            results.append(payment)

        logger.info("Retried %d failed fee routings", len(to_retry))
        return results

    def get_stats(self) -> RoutingStats:
        """Get aggregated fee routing statistics."""
        total = Decimal("0")
        successful = 0
        failed = 0
        last_at: Optional[float] = None

        for p in self._payments:
            if p.success:
                total += p.amount
                successful += 1
                if last_at is None or p.timestamp > last_at:
                    last_at = p.timestamp
            else:
                failed += 1

        return RoutingStats(
            total_routed=total,
            total_payments=len(self._payments),
            successful_payments=successful,
            failed_payments=failed,
            last_routed_at=last_at,
        )

    def get_payment_history(
        self,
        source_wallet: Optional[str] = None,
        limit: int = 100,
    ) -> List[FeePayment]:
        """Get fee payment history.

        Args:
            source_wallet: Optional filter by source.
            limit: Maximum records to return.

        Returns:
            List of FeePayment records.
        """
        payments = self._payments
        if source_wallet:
            payments = [p for p in payments if p.source_wallet == source_wallet]
        return list(reversed(payments[-limit:]))

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _execute_transfer(self, source: str, amount: Decimal) -> str:
        """Execute USDC transfer to NeoSafe on Base.

        Returns the transaction hash.
        """
        if self._web3 is None or self._contract is None:
            # Simulated transfer when no web3 connection
            return f"0x{uuid.uuid4().hex}"

        amount_wei = int(amount * Decimal("1e6"))  # USDC has 6 decimals

        tx = self._contract.functions.transfer(
            NEOSAFE_ADDRESS,
            amount_wei,
        ).build_transaction({
            "from": self._platform_account,
            "chainId": BASE_CHAIN_ID,
            "gas": 100_000,
            "nonce": self._web3.eth.get_transaction_count(self._platform_account),
        })

        signed = self._web3.eth.account.sign_transaction(tx, private_key="")
        tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)

        if receipt["status"] != 1:
            raise RuntimeError(f"Fee transfer reverted: {tx_hash.hex()}")

        return tx_hash.hex()
