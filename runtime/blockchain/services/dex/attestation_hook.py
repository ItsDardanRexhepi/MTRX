"""
DEX Attestation Hook — EAS attestation for DEX operations.

Part of Component 21 (DEX).
Creates on-chain attestations for swaps, LP positions, and significant events.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class AttestationEvent(Enum):
    """Events that trigger attestations."""
    SWAP_COMPLETED = "swap_completed"
    LIQUIDITY_ADDED = "liquidity_added"
    LIQUIDITY_REMOVED = "liquidity_removed"
    LARGE_TRADE = "large_trade"
    POOL_CREATED = "pool_created"


@dataclass
class DEXAttestation:
    """Record of a DEX attestation."""
    attestation_id: str
    event_type: AttestationEvent
    data: Dict[str, Any]
    eas_uid: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    on_chain: bool = False


class DEXAttestationHook:
    """
    EAS attestation hook for DEX operations.

    Creates attestations for:
    - Completed swaps (trade record)
    - LP position changes
    - Large trades exceeding threshold
    - Pool creation events
    """

    LARGE_TRADE_THRESHOLD_WEI: int = 100 * 10**18  # 100 ETH equivalent

    def __init__(self, eas_service: Optional[Any] = None) -> None:
        self._eas = eas_service
        self._attestations: List[DEXAttestation] = []
        self._counter: int = 0
        logger.info("DEXAttestationHook initialised.")

    def on_swap(self, swap_data: Dict[str, Any]) -> DEXAttestation:
        """Create attestation for a completed swap."""
        self._counter += 1
        attestation = DEXAttestation(
            attestation_id=f"DEX-ATT-{self._counter:08d}",
            event_type=AttestationEvent.SWAP_COMPLETED,
            data=swap_data,
        )
        self._submit_attestation(attestation)
        return attestation

    def on_liquidity_change(
        self, event: AttestationEvent, position_data: Dict[str, Any],
    ) -> DEXAttestation:
        """Create attestation for LP changes."""
        self._counter += 1
        attestation = DEXAttestation(
            attestation_id=f"DEX-ATT-{self._counter:08d}",
            event_type=event,
            data=position_data,
        )
        self._submit_attestation(attestation)
        return attestation

    def check_large_trade(self, amount_wei: int, swap_data: Dict[str, Any]) -> Optional[DEXAttestation]:
        """Check if a trade exceeds the large trade threshold."""
        if amount_wei >= self.LARGE_TRADE_THRESHOLD_WEI:
            self._counter += 1
            attestation = DEXAttestation(
                attestation_id=f"DEX-ATT-{self._counter:08d}",
                event_type=AttestationEvent.LARGE_TRADE,
                data={**swap_data, "flagged": True, "threshold_wei": self.LARGE_TRADE_THRESHOLD_WEI},
            )
            self._submit_attestation(attestation)
            return attestation
        return None

    def get_attestations(self, event_type: Optional[AttestationEvent] = None) -> List[DEXAttestation]:
        """Get attestation history."""
        if event_type:
            return [a for a in self._attestations if a.event_type == event_type]
        return list(self._attestations)

    def _submit_attestation(self, attestation: DEXAttestation) -> None:
        """Submit attestation to EAS."""
        if self._eas is not None:
            try:
                uid = self._eas.attest(
                    schema="dex_operation",
                    data=attestation.data,
                )
                attestation.eas_uid = uid
                attestation.on_chain = True
            except Exception:
                logger.exception("EAS attestation failed for %s.", attestation.attestation_id)
        self._attestations.append(attestation)
