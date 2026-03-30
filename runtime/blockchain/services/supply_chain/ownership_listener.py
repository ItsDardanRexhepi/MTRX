"""
Ownership Transfer Listener
============================

Subscribes to Component 4 (JointOwnership) ownership transfer events via
the custody_emitter interface and automatically records them in the relevant
asset's chain of custody on the SupplyChain contract.

This listener is always active once started; no manual triggering is required.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

# ── Constants ────────────────────────────────────────────────────────────────
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class ListenerState(Enum):
    """Listener operational states."""
    IDLE = "idle"
    RUNNING = "running"
    STOPPING = "stopping"
    ERROR = "error"


@dataclass
class TransferEvent:
    """Represents an ownership transfer event from Component 4."""
    contract_address: str
    asset_id: int
    from_owner: str
    to_owner: str
    ownership_bps: int
    timestamp: int
    transaction_hash: str
    block_number: int
    event_name: str = "OwnershipTransferred"


@dataclass
class InspectionEvent:
    """Represents an inspection event from Component 4."""
    contract_address: str
    asset_id: int
    inspector: str
    result: int
    report_uri: str
    notes: str
    timestamp: int
    transaction_hash: str
    block_number: int
    event_name: str = "InspectionCompleted"


@dataclass
class ListenerMetrics:
    """Operational metrics for the listener."""
    events_received: int = 0
    events_recorded: int = 0
    events_failed: int = 0
    inspections_received: int = 0
    inspections_recorded: int = 0
    last_event_at: Optional[str] = None
    last_block_processed: int = 0
    started_at: Optional[str] = None
    state: ListenerState = ListenerState.IDLE


class OwnershipTransferListener:
    """
    Subscribes to Component 4 (JointOwnership) ownership transfer and
    inspection events and automatically records them in the SupplyChain
    contract's chain of custody.

    Always active once started. No manual triggering required.

    Usage::

        listener = OwnershipTransferListener(
            web3_provider=provider,
            supply_chain_contract=sc_contract,
            custody_emitter=joint_ownership_contract,
        )
        await listener.start_listening()
    """

    def __init__(
        self,
        web3_provider: Any,
        supply_chain_contract: Any,
        custody_emitter: Any,
        asset_mapping: Optional[Dict[str, int]] = None,
        poll_interval: float = 2.0,
    ) -> None:
        """
        Initialise the ownership transfer listener.

        Args:
            web3_provider: Web3 provider instance.
            supply_chain_contract: Deployed SupplyChain contract interface.
            custody_emitter: Component 4 JointOwnership contract that emits events.
            asset_mapping: Optional mapping of JointOwnership contract addresses
                           to SupplyChain asset IDs. Auto-discovered if not provided.
            poll_interval: Seconds between event polling cycles.
        """
        self._web3 = web3_provider
        self._supply_chain = supply_chain_contract
        self._custody_emitter = custody_emitter
        self._asset_mapping: Dict[str, int] = asset_mapping or {}
        self._poll_interval = poll_interval

        self._metrics = ListenerMetrics()
        self._running = False
        self._task: Optional[asyncio.Task] = None
        self._event_handlers: List[Callable] = []

        logger.info("OwnershipTransferListener initialised (poll_interval=%.1fs)", poll_interval)

    # ── Public API ───────────────────────────────────────────────────────────

    async def start_listening(self) -> None:
        """
        Start listening for ownership transfer and inspection events.

        This method runs continuously until stop() is called. It processes
        events from Component 4 and records them on the SupplyChain contract.

        Raises:
            RuntimeError: If the listener is already running.
        """
        if self._running:
            raise RuntimeError("Listener is already running")

        self._running = True
        self._metrics.state = ListenerState.RUNNING
        self._metrics.started_at = datetime.now(timezone.utc).isoformat()

        logger.info("Ownership transfer listener started")

        try:
            last_block = self._web3.eth.block_number

            while self._running:
                try:
                    current_block = self._web3.eth.block_number

                    if current_block > last_block:
                        # Process transfer events
                        transfer_events = self._fetch_transfer_events(
                            last_block + 1, current_block
                        )
                        for event in transfer_events:
                            await self.on_transfer_event(event)

                        # Process inspection events
                        inspection_events = self._fetch_inspection_events(
                            last_block + 1, current_block
                        )
                        for event in inspection_events:
                            await self.on_inspection_event(event)

                        last_block = current_block
                        self._metrics.last_block_processed = current_block

                    await asyncio.sleep(self._poll_interval)

                except asyncio.CancelledError:
                    logger.info("Listener cancelled")
                    break
                except Exception as exc:
                    logger.error("Error in listener loop: %s", exc)
                    self._metrics.state = ListenerState.ERROR
                    await asyncio.sleep(self._poll_interval * 5)
                    self._metrics.state = ListenerState.RUNNING

        finally:
            self._running = False
            self._metrics.state = ListenerState.IDLE
            logger.info("Ownership transfer listener stopped")

    def stop(self) -> None:
        """Signal the listener to stop gracefully."""
        self._running = False
        self._metrics.state = ListenerState.STOPPING
        if self._task and not self._task.done():
            self._task.cancel()
        logger.info("Listener stop requested")

    async def on_transfer_event(self, event: TransferEvent) -> None:
        """
        Handle an incoming ownership transfer event from Component 4.

        Resolves the asset ID in the SupplyChain contract and records the
        custody transfer on-chain.

        Args:
            event: The transfer event to process.
        """
        self._metrics.events_received += 1
        self._metrics.last_event_at = datetime.now(timezone.utc).isoformat()

        logger.info(
            "Transfer event received: asset=%d, from=%s, to=%s, tx=%s",
            event.asset_id, event.from_owner, event.to_owner, event.transaction_hash,
        )

        try:
            supply_chain_asset_id = self._resolve_asset_id(event)
            if supply_chain_asset_id is None:
                logger.warning(
                    "No SupplyChain asset mapping for Component 4 asset %d. "
                    "Auto-registering.",
                    event.asset_id,
                )
                supply_chain_asset_id = await self._auto_register_asset(event)

            await self.record_custody_event(supply_chain_asset_id, event)
            self._metrics.events_recorded += 1

            # Notify any registered handlers
            for handler in self._event_handlers:
                try:
                    handler(event)
                except Exception as exc:
                    logger.warning("Event handler error: %s", exc)

        except Exception as exc:
            self._metrics.events_failed += 1
            logger.error(
                "Failed to record transfer event for asset %d: %s",
                event.asset_id, exc,
            )

    async def record_custody_event(
        self,
        asset_id: int,
        event: TransferEvent,
    ) -> None:
        """
        Record a custody transfer event on the SupplyChain contract.

        Args:
            asset_id: SupplyChain asset ID.
            event: The transfer event data.

        Raises:
            RuntimeError: If the on-chain transaction fails.
        """
        try:
            # CustodyAction.TRANSFERRED = 1
            tx = self._supply_chain.functions.transferCustody(
                asset_id,
                1,  # TRANSFERRED
                event.to_owner,
                f"Ownership transfer from Component 4. "
                f"Share: {event.ownership_bps}bps. "
                f"Tx: {event.transaction_hash}",
                "",  # location hash
            ).build_transaction({
                "from": self._web3.eth.default_account,
            })

            signed = self._web3.eth.account.sign_transaction(
                tx, private_key=self._web3.eth.default_account
            )
            tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
            receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash)

            if receipt.status != 1:
                raise RuntimeError(
                    f"On-chain custody transfer failed (tx: {tx_hash.hex()})"
                )

            logger.info(
                "Custody event recorded on-chain for asset %d (tx: %s)",
                asset_id, tx_hash.hex(),
            )

        except Exception as exc:
            raise RuntimeError(
                f"Failed to record custody event for asset {asset_id}: {exc}"
            ) from exc

    async def on_inspection_event(self, event: InspectionEvent) -> None:
        """
        Handle an incoming inspection event from Component 4.

        Records the inspection on the SupplyChain contract.

        Args:
            event: The inspection event to process.
        """
        self._metrics.inspections_received += 1
        self._metrics.last_event_at = datetime.now(timezone.utc).isoformat()

        logger.info(
            "Inspection event received: asset=%d, inspector=%s, result=%d",
            event.asset_id, event.inspector, event.result,
        )

        try:
            supply_chain_asset_id = self._resolve_asset_id_from_inspection(event)
            if supply_chain_asset_id is None:
                logger.warning(
                    "No SupplyChain asset mapping for inspected asset %d",
                    event.asset_id,
                )
                return

            tx = self._supply_chain.functions.recordInspection(
                supply_chain_asset_id,
                event.inspector,
                event.result,
                event.report_uri,
                f"{event.notes} [Source: Component 4, Tx: {event.transaction_hash}]",
            ).build_transaction({
                "from": self._web3.eth.default_account,
            })

            signed = self._web3.eth.account.sign_transaction(
                tx, private_key=self._web3.eth.default_account
            )
            tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
            receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash)

            if receipt.status != 1:
                raise RuntimeError(
                    f"On-chain inspection record failed (tx: {tx_hash.hex()})"
                )

            self._metrics.inspections_recorded += 1
            logger.info(
                "Inspection recorded on-chain for asset %d (tx: %s)",
                supply_chain_asset_id, tx_hash.hex(),
            )

        except Exception as exc:
            logger.error(
                "Failed to record inspection for asset %d: %s",
                event.asset_id, exc,
            )

    def register_event_handler(self, handler: Callable) -> None:
        """Register an additional callback for processed events."""
        self._event_handlers.append(handler)

    @property
    def metrics(self) -> ListenerMetrics:
        """Return current listener metrics."""
        return self._metrics

    @property
    def is_running(self) -> bool:
        """Check if the listener is currently active."""
        return self._running

    # ── Private Helpers ──────────────────────────────────────────────────────

    def _fetch_transfer_events(
        self, from_block: int, to_block: int
    ) -> List[TransferEvent]:
        """Fetch ownership transfer events from Component 4 in the given block range."""
        events: List[TransferEvent] = []
        try:
            raw_events = self._custody_emitter.events.OwnershipTransferred.get_logs(
                fromBlock=from_block, toBlock=to_block
            )
            for raw in raw_events:
                events.append(TransferEvent(
                    contract_address=raw.address,
                    asset_id=raw.args.get("assetId", 0),
                    from_owner=raw.args.get("fromOwner", ""),
                    to_owner=raw.args.get("toOwner", ""),
                    ownership_bps=raw.args.get("ownershipBps", 0),
                    timestamp=raw.args.get("timestamp", 0),
                    transaction_hash=raw.transactionHash.hex(),
                    block_number=raw.blockNumber,
                ))
        except Exception as exc:
            logger.error(
                "Failed to fetch transfer events (blocks %d-%d): %s",
                from_block, to_block, exc,
            )
        return events

    def _fetch_inspection_events(
        self, from_block: int, to_block: int
    ) -> List[InspectionEvent]:
        """Fetch inspection events from Component 4 in the given block range."""
        events: List[InspectionEvent] = []
        try:
            raw_events = self._custody_emitter.events.InspectionCompleted.get_logs(
                fromBlock=from_block, toBlock=to_block
            )
            for raw in raw_events:
                events.append(InspectionEvent(
                    contract_address=raw.address,
                    asset_id=raw.args.get("assetId", 0),
                    inspector=raw.args.get("inspector", ""),
                    result=raw.args.get("result", 3),
                    report_uri=raw.args.get("reportURI", ""),
                    notes=raw.args.get("notes", ""),
                    timestamp=raw.args.get("timestamp", 0),
                    transaction_hash=raw.transactionHash.hex(),
                    block_number=raw.blockNumber,
                ))
        except Exception as exc:
            logger.error(
                "Failed to fetch inspection events (blocks %d-%d): %s",
                from_block, to_block, exc,
            )
        return events

    def _resolve_asset_id(self, event: TransferEvent) -> Optional[int]:
        """Resolve a Component 4 event to a SupplyChain asset ID."""
        key = f"{event.contract_address}:{event.asset_id}"
        return self._asset_mapping.get(key)

    def _resolve_asset_id_from_inspection(self, event: InspectionEvent) -> Optional[int]:
        """Resolve a Component 4 inspection event to a SupplyChain asset ID."""
        key = f"{event.contract_address}:{event.asset_id}"
        return self._asset_mapping.get(key)

    async def _auto_register_asset(self, event: TransferEvent) -> int:
        """
        Auto-register a new asset on the SupplyChain contract when a Component 4
        event references an asset not yet tracked.

        Returns:
            The new SupplyChain asset ID.
        """
        try:
            # AssetType.OTHER = 7 (generic for cross-component auto-registration)
            tx = self._supply_chain.functions.registerAsset(
                7,  # OTHER
                event.from_owner,
                f"Auto-registered from Component 4 (contract: {event.contract_address})",
                bytes(32),  # no external ref
            ).build_transaction({
                "from": self._web3.eth.default_account,
            })

            signed = self._web3.eth.account.sign_transaction(
                tx, private_key=self._web3.eth.default_account
            )
            tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
            receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash)

            if receipt.status != 1:
                raise RuntimeError("Auto-registration transaction failed")

            # Parse the asset ID from the ProductRegistered event
            logs = self._supply_chain.events.ProductRegistered().process_receipt(receipt)
            if logs:
                new_id = logs[0].args.assetId
                key = f"{event.contract_address}:{event.asset_id}"
                self._asset_mapping[key] = new_id
                logger.info("Auto-registered asset %d from Component 4", new_id)
                return new_id

            raise RuntimeError("No ProductRegistered event in receipt")

        except Exception as exc:
            raise RuntimeError(
                f"Auto-registration failed for Component 4 asset {event.asset_id}: {exc}"
            ) from exc
