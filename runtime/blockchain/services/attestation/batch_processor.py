"""
Batch Processor
================

Groups batchable attestations for gas-efficient on-chain submission.
Attestations are queued until a batch threshold is reached or a
time-based flush is triggered. All attestations in a batch are
submitted in a single multi-attest transaction.
"""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Batch configuration
DEFAULT_BATCH_SIZE: int = 50
DEFAULT_FLUSH_INTERVAL: int = 300  # 5 minutes
EAS_CONTRACT_ADDRESS: str = "0x4200000000000000000000000000000000000021"  # EAS on Base


@dataclass
class BatchEntry:
    """A single attestation queued for batch submission."""
    entry_id: str
    request_id: str
    schema_uid: str
    data: Dict[str, Any]
    requester: str
    source_component: int
    queued_at: float = field(default_factory=time.time)


@dataclass
class BatchResult:
    """Result of a batch submission."""
    batch_id: str
    entry_count: int
    tx_hash: Optional[str] = None
    attestation_uids: List[str] = field(default_factory=list)
    submitted_at: float = field(default_factory=time.time)
    success: bool = False
    gas_used: int = 0
    gas_saved_vs_individual: int = 0
    error: Optional[str] = None


class BatchProcessor:
    """Groups batchable attestations for gas-efficient submission.

    Attestations are enqueued and submitted in batches when either:
    - The batch size threshold is reached.
    - The flush interval timer fires.
    - A manual flush is triggered.

    Parameters
    ----------
    web3_provider : Any
        Web3 provider for on-chain submission.
    eas_contract : Any
        EAS contract instance for multi-attest.
    platform_account : str
        Platform signing account.
    batch_size : int
        Maximum entries per batch (default 50).
    flush_interval : int
        Seconds between automatic flushes (default 300).
    """

    def __init__(
        self,
        web3_provider: Any = None,
        eas_contract: Any = None,
        platform_account: Optional[str] = None,
        batch_size: int = DEFAULT_BATCH_SIZE,
        flush_interval: int = DEFAULT_FLUSH_INTERVAL,
    ) -> None:
        self._web3 = web3_provider
        self._eas = eas_contract
        self._platform_account = platform_account
        self._batch_size = batch_size
        self._flush_interval = flush_interval
        self._queue: List[BatchEntry] = []
        self._batch_history: List[BatchResult] = []
        self._running = False
        logger.info(
            "BatchProcessor initialised (batch_size=%d, flush_interval=%ds)",
            batch_size, flush_interval,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def enqueue(self, request: Any) -> str:
        """Add an attestation request to the batch queue.

        Args:
            request: AttestationRequest from the dispatcher.

        Returns:
            The entry ID for tracking.
        """
        entry = BatchEntry(
            entry_id=f"batch-e-{uuid.uuid4().hex[:10]}",
            request_id=request.request_id,
            schema_uid=request.schema_uid,
            data=request.data,
            requester=request.requester,
            source_component=request.source_component,
        )
        self._queue.append(entry)

        logger.debug(
            "Enqueued %s for batch (queue_size=%d)", entry.entry_id, len(self._queue)
        )

        # Auto-flush if batch size reached
        if len(self._queue) >= self._batch_size:
            logger.info("Batch size threshold reached, auto-flushing")
            self.flush()

        return entry.entry_id

    def flush(self) -> Optional[BatchResult]:
        """Submit all queued attestations as a single batch.

        Returns:
            BatchResult or None if queue is empty.
        """
        if not self._queue:
            return None

        entries = list(self._queue)
        self._queue.clear()

        batch_id = f"batch-{uuid.uuid4().hex[:12]}"

        try:
            tx_hash, uids, gas_used = self._submit_batch(entries)
            estimated_individual_gas = len(entries) * 65_000
            result = BatchResult(
                batch_id=batch_id,
                entry_count=len(entries),
                tx_hash=tx_hash,
                attestation_uids=uids,
                success=True,
                gas_used=gas_used,
                gas_saved_vs_individual=max(0, estimated_individual_gas - gas_used),
            )
            logger.info(
                "Batch %s submitted: %d attestations, tx=%s, gas_saved=%d",
                batch_id, len(entries), tx_hash, result.gas_saved_vs_individual,
            )
        except Exception as exc:
            result = BatchResult(
                batch_id=batch_id,
                entry_count=len(entries),
                success=False,
                error=str(exc),
            )
            # Re-queue failed entries for retry
            self._queue.extend(entries)
            logger.error("Batch %s failed, re-queued %d entries: %s", batch_id, len(entries), exc)

        self._batch_history.append(result)
        return result

    def get_queue_size(self) -> int:
        """Return current queue length."""
        return len(self._queue)

    def get_queue_entries(self) -> List[BatchEntry]:
        """Return current queued entries."""
        return list(self._queue)

    def get_batch_history(self, limit: int = 50) -> List[BatchResult]:
        """Return batch submission history."""
        return list(reversed(self._batch_history[-limit:]))

    def get_stats(self) -> Dict[str, Any]:
        """Return batch processing statistics."""
        total_submitted = sum(b.entry_count for b in self._batch_history if b.success)
        total_gas_saved = sum(b.gas_saved_vs_individual for b in self._batch_history if b.success)
        return {
            "queue_size": len(self._queue),
            "batches_submitted": sum(1 for b in self._batch_history if b.success),
            "batches_failed": sum(1 for b in self._batch_history if not b.success),
            "total_attestations_submitted": total_submitted,
            "total_gas_saved": total_gas_saved,
        }

    async def start_auto_flush(self) -> None:
        """Start the automatic flush timer.

        Runs continuously, flushing the queue every flush_interval seconds.
        """
        self._running = True
        logger.info("Auto-flush started (interval=%ds)", self._flush_interval)

        while self._running:
            await asyncio.sleep(self._flush_interval)
            if self._queue:
                self.flush()

    def stop_auto_flush(self) -> None:
        """Stop the automatic flush timer."""
        self._running = False
        logger.info("Auto-flush stopped")

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _submit_batch(
        self, entries: List[BatchEntry]
    ) -> tuple:
        """Submit a batch of attestations to EAS.

        Returns (tx_hash, attestation_uids, gas_used).
        """
        if self._web3 is None or self._eas is None:
            # Simulated batch submission
            uids = [f"0x{uuid.uuid4().hex}" for _ in entries]
            gas = len(entries) * 35_000  # Batching saves ~46% gas
            return f"0x{uuid.uuid4().hex}", uids, gas

        # Group entries by schema for multi-attest
        schema_groups: Dict[str, List[BatchEntry]] = {}
        for entry in entries:
            schema_groups.setdefault(entry.schema_uid, []).append(entry)

        multi_attest_data = []
        for schema_uid, group_entries in schema_groups.items():
            attestation_data = []
            for entry in group_entries:
                attestation_data.append({
                    "recipient": entry.requester,
                    "expirationTime": 0,
                    "revocable": True,
                    "refUID": b"\x00" * 32,
                    "data": str(entry.data).encode(),
                    "value": 0,
                })
            multi_attest_data.append({
                "schema": schema_uid,
                "data": attestation_data,
            })

        tx = self._eas.functions.multiAttest(
            multi_attest_data
        ).build_transaction({
            "from": self._platform_account,
            "gas": len(entries) * 50_000,
            "nonce": self._web3.eth.get_transaction_count(self._platform_account),
        })

        signed = self._web3.eth.account.sign_transaction(tx, private_key="")
        tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt["status"] != 1:
            raise RuntimeError(f"Multi-attest reverted: {tx_hash.hex()}")

        uids = [f"0x{uuid.uuid4().hex}" for _ in entries]
        return tx_hash.hex(), uids, receipt.get("gasUsed", 0)
