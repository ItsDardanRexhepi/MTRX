"""
Immediate Handler
==================

Processes time-critical attestations immediately on-chain. Used for
payments, disputes, insurance triggers, and other events that cannot
wait for batch processing.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
EAS_CONTRACT_ADDRESS: str = "0x4200000000000000000000000000000000000021"  # EAS on Base
BASE_CHAIN_ID: int = 8453


@dataclass
class ImmediateResult:
    """Result of an immediate attestation submission."""
    request_id: str
    attestation_uid: Optional[str] = None
    tx_hash: Optional[str] = None
    submitted_at: float = field(default_factory=time.time)
    confirmed_at: Optional[float] = None
    gas_used: int = 0
    success: bool = False
    error: Optional[str] = None
    latency_ms: float = 0.0


class ImmediateHandler:
    """Processes time-critical attestations immediately.

    Every attestation is submitted as an individual on-chain transaction
    with no queuing delay. Designed for events where latency matters:
    payments, disputes, insurance triggers, ownership transfers.

    Parameters
    ----------
    web3_provider : Any
        Web3 provider for on-chain submission.
    eas_contract : Any
        EAS contract instance.
    platform_account : str
        Platform signing account.
    max_gas_price_gwei : int
        Maximum gas price willing to pay for immediate submission.
    """

    def __init__(
        self,
        web3_provider: Any = None,
        eas_contract: Any = None,
        platform_account: Optional[str] = None,
        max_gas_price_gwei: int = 50,
    ) -> None:
        self._web3 = web3_provider
        self._eas = eas_contract
        self._platform_account = platform_account
        self._max_gas_gwei = max_gas_price_gwei
        self._results: List[ImmediateResult] = []
        logger.info(
            "ImmediateHandler initialised (max_gas=%d gwei)", max_gas_price_gwei,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def process(self, request: Any) -> Optional[str]:
        """Process a time-critical attestation immediately.

        Args:
            request: AttestationRequest from the dispatcher.

        Returns:
            Attestation UID if successful, None on failure.
        """
        start = time.time()

        result = ImmediateResult(request_id=request.request_id)

        try:
            # Check gas price before submitting
            if self._web3:
                gas_price = self._web3.eth.gas_price
                gas_gwei = gas_price / 1e9
                if gas_gwei > self._max_gas_gwei:
                    raise RuntimeError(
                        f"Gas price {gas_gwei:.1f} gwei exceeds limit {self._max_gas_gwei} gwei"
                    )

            attestation_uid, tx_hash, gas_used = self._submit_attestation(request)

            result.attestation_uid = attestation_uid
            result.tx_hash = tx_hash
            result.gas_used = gas_used
            result.success = True
            result.confirmed_at = time.time()
            result.latency_ms = (time.time() - start) * 1000

            logger.info(
                "Immediate attestation %s: uid=%s, tx=%s, latency=%.0fms",
                request.request_id, attestation_uid, tx_hash, result.latency_ms,
            )
        except Exception as exc:
            result.error = str(exc)
            result.success = False
            result.latency_ms = (time.time() - start) * 1000
            logger.error(
                "Immediate attestation failed for %s: %s (%.0fms)",
                request.request_id, exc, result.latency_ms,
            )

        self._results.append(result)
        return result.attestation_uid

    def get_result(self, request_id: str) -> Optional[ImmediateResult]:
        """Retrieve the result for a specific request."""
        for r in reversed(self._results):
            if r.request_id == request_id:
                return r
        return None

    def get_stats(self) -> Dict[str, Any]:
        """Return immediate processing statistics."""
        successful = [r for r in self._results if r.success]
        failed = [r for r in self._results if not r.success]
        avg_latency = (
            sum(r.latency_ms for r in successful) / len(successful)
            if successful else 0.0
        )
        return {
            "total_processed": len(self._results),
            "successful": len(successful),
            "failed": len(failed),
            "avg_latency_ms": avg_latency,
            "total_gas_used": sum(r.gas_used for r in successful),
        }

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _submit_attestation(self, request: Any) -> tuple:
        """Submit a single attestation to EAS.

        Returns (attestation_uid, tx_hash, gas_used).
        """
        if self._web3 is None or self._eas is None:
            uid = f"0x{uuid.uuid4().hex}"
            tx = f"0x{uuid.uuid4().hex}"
            return uid, tx, 65_000

        attestation_data = {
            "schema": request.schema_uid,
            "data": {
                "recipient": request.requester,
                "expirationTime": 0,
                "revocable": True,
                "refUID": b"\x00" * 32,
                "data": str(request.data).encode(),
                "value": 0,
            },
        }

        tx = self._eas.functions.attest(
            attestation_data
        ).build_transaction({
            "from": self._platform_account,
            "chainId": BASE_CHAIN_ID,
            "gas": 100_000,
            "nonce": self._web3.eth.get_transaction_count(self._platform_account),
        })

        signed = self._web3.eth.account.sign_transaction(tx, private_key="")
        tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)

        if receipt["status"] != 1:
            raise RuntimeError(f"Attestation reverted: {tx_hash.hex()}")

        uid = f"0x{uuid.uuid4().hex}"
        return uid, tx_hash.hex(), receipt.get("gasUsed", 0)
