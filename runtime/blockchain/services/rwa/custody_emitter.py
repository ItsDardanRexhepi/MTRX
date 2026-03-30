"""
Component 4 -- Custody Emitter (Component 12 Event Bridge)
============================================================

Emits ownership transfer and inspection events that the Component 12
(Supply Chain / Chain of Custody) ownership listener consumes.

Every ownership transfer automatically produces a Component 12 chain-of-custody
event, ensuring an unbroken provenance trail for every tokenized asset.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from enum import Enum, auto
from typing import Any, Callable, Dict, List, Optional


# ------------------------------------------------------------------ data models


class CustodyEventType(Enum):
    OWNERSHIP_TRANSFER = auto()
    INSPECTION = auto()
    CUSTODY_CHANGE = auto()
    VERIFICATION = auto()


@dataclass
class CustodyEvent:
    """An event destined for the Component 12 chain-of-custody ledger."""

    event_id: str
    event_type: CustodyEventType
    asset_id: str
    data: Dict[str, Any]
    timestamp: float
    emitted: bool = False


# ------------------------------------------------------------------ service


class CustodyEmitter:
    """
    Emits ownership-transfer and inspection events for Component 12.

    Listeners (typically the Component 12 ownership listener) register
    callbacks via :meth:`register_listener`.  Every emitted event is
    persisted locally and forwarded to all registered listeners.
    """

    def __init__(self) -> None:
        self._events: List[CustodyEvent] = []
        self._listeners: List[Callable[[CustodyEvent], None]] = []

    # -- public API -------------------------------------------------------

    def register_listener(
        self, callback: Callable[[CustodyEvent], None]
    ) -> None:
        """
        Register a callback that will be invoked for every emitted event.

        Parameters
        ----------
        callback : Callable
            Accepts a single ``CustodyEvent`` argument.
        """
        self._listeners.append(callback)

    def emit_transfer_event(
        self,
        asset_id: str,
        from_party: str,
        to_party: str,
        timestamp: Optional[float] = None,
    ) -> CustodyEvent:
        """
        Emit an ownership transfer event.

        Parameters
        ----------
        asset_id : str
            The tokenized asset identifier.
        from_party : str
            The current owner relinquishing ownership.
        to_party : str
            The new owner receiving ownership.
        timestamp : float, optional
            Event timestamp; defaults to ``time.time()``.

        Returns
        -------
        CustodyEvent
            The emitted event record.
        """
        ts = timestamp or time.time()

        event = CustodyEvent(
            event_id=str(uuid.uuid4()),
            event_type=CustodyEventType.OWNERSHIP_TRANSFER,
            asset_id=asset_id,
            data={
                "from": from_party,
                "to": to_party,
                "transfer_type": "ownership",
            },
            timestamp=ts,
        )

        self._dispatch(event)
        return event

    def emit_inspection_event(
        self,
        asset_id: str,
        inspector: str,
        result: Dict[str, Any],
        timestamp: Optional[float] = None,
    ) -> CustodyEvent:
        """
        Emit an inspection event (e.g. condition report, appraisal).

        Parameters
        ----------
        asset_id : str
            The tokenized asset identifier.
        inspector : str
            Identifier of the inspector or appraiser.
        result : dict
            Inspection findings.
        timestamp : float, optional
            Event timestamp; defaults to ``time.time()``.

        Returns
        -------
        CustodyEvent
            The emitted event record.
        """
        ts = timestamp or time.time()

        event = CustodyEvent(
            event_id=str(uuid.uuid4()),
            event_type=CustodyEventType.INSPECTION,
            asset_id=asset_id,
            data={
                "inspector": inspector,
                "result": result,
            },
            timestamp=ts,
        )

        self._dispatch(event)
        return event

    def get_events_for_asset(self, asset_id: str) -> List[CustodyEvent]:
        """Return all emitted events for a given asset."""
        return [e for e in self._events if e.asset_id == asset_id]

    # -- internal ---------------------------------------------------------

    def _dispatch(self, event: CustodyEvent) -> None:
        """Persist the event and notify all registered listeners."""
        self._events.append(event)
        event.emitted = True

        for listener in self._listeners:
            try:
                listener(event)
            except Exception:
                # Listener errors must not break the emitter pipeline.
                pass
