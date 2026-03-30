"""
Flight Oracle
==============

Travel insurance flight status data. Monitors flight delays,
cancellations, and diversions for parametric insurance triggers.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class FlightStatus(Enum):
    """Flight status values."""
    SCHEDULED = "scheduled"
    DEPARTED = "departed"
    EN_ROUTE = "en_route"
    LANDED = "landed"
    DELAYED = "delayed"
    CANCELLED = "cancelled"
    DIVERTED = "diverted"
    UNKNOWN = "unknown"


@dataclass
class FlightData:
    """Flight status data point."""
    flight_number: str
    airline: str
    departure_airport: str
    arrival_airport: str
    scheduled_departure: float
    scheduled_arrival: float
    status: FlightStatus
    actual_departure: Optional[float] = None
    actual_arrival: Optional[float] = None
    delay_minutes: int = 0
    cancellation_reason: Optional[str] = None
    diversion_airport: Optional[str] = None
    source: str = ""
    confidence: float = 0.0
    fetched_at: float = field(default_factory=time.time)

    @property
    def is_disrupted(self) -> bool:
        return self.status in (
            FlightStatus.DELAYED,
            FlightStatus.CANCELLED,
            FlightStatus.DIVERTED,
        )

    @property
    def is_significantly_delayed(self) -> bool:
        return self.delay_minutes >= 120


@dataclass
class FlightTrigger:
    """Parametric trigger for flight disruption insurance."""
    trigger_id: str
    flight_number: str
    date: str
    delay_threshold_minutes: int = 120
    policy_id: Optional[str] = None
    active: bool = True
    triggered: bool = False
    triggered_at: Optional[float] = None
    trigger_reason: Optional[str] = None


@dataclass
class FlightTriggerEvent:
    """Emitted when a flight trigger fires."""
    event_id: str
    trigger_id: str
    flight_number: str
    status: FlightStatus
    delay_minutes: int
    policy_id: Optional[str] = None
    timestamp: float = field(default_factory=time.time)


class FlightOracle:
    """Flight status data provider for travel insurance.

    Monitors flights for delays, cancellations, and diversions.
    Supports parametric triggers for automatic insurance payouts.

    Parameters
    ----------
    api_credentials : dict, optional
        API keys for flight data providers (FlightAware, AviationStack).
    trigger_callback : callable, optional
        Called when a flight trigger fires.
    """

    def __init__(
        self,
        api_credentials: Optional[Dict[str, str]] = None,
        trigger_callback: Any = None,
    ) -> None:
        self._credentials = api_credentials or {}
        self._trigger_callback = trigger_callback
        self._flights: Dict[str, FlightData] = {}
        self._triggers: Dict[str, FlightTrigger] = {}
        self._trigger_events: List[FlightTriggerEvent] = []
        logger.info("FlightOracle initialised")

    # ------------------------------------------------------------------
    # OracleInterface integration
    # ------------------------------------------------------------------

    def fetch(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Fetch flight data (called by OracleInterface).

        Args:
            parameters: Must contain 'flight_number' and 'date'.

        Returns:
            Dict with flight data for aggregation.
        """
        flight_number = parameters.get("flight_number", "")
        date = parameters.get("date", "")

        flight = self.get_flight_status(flight_number, date)

        return {
            "value": {
                "status": flight.status.value,
                "delay_minutes": flight.delay_minutes,
                "is_disrupted": flight.is_disrupted,
            },
            "flight_number": flight.flight_number,
            "airline": flight.airline,
            "departure": flight.departure_airport,
            "arrival": flight.arrival_airport,
            "source": flight.source,
            "confidence": flight.confidence,
        }

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_flight_status(
        self, flight_number: str, date: str
    ) -> FlightData:
        """Get the current status of a flight.

        Args:
            flight_number: IATA flight number (e.g. "AA100").
            date: Flight date (e.g. "2026-03-30").

        Returns:
            FlightData with current status.
        """
        key = f"{flight_number}:{date}"
        cached = self._flights.get(key)
        if cached and (time.time() - cached.fetched_at) < 300:
            return cached

        flight = self._fetch_flight_data(flight_number, date)
        self._flights[key] = flight

        # Evaluate triggers
        self._evaluate_triggers(flight)

        return flight

    def register_trigger(
        self,
        flight_number: str,
        date: str,
        delay_threshold_minutes: int = 120,
        policy_id: Optional[str] = None,
    ) -> FlightTrigger:
        """Register a parametric flight trigger.

        Args:
            flight_number: Flight to monitor.
            date: Flight date.
            delay_threshold_minutes: Delay threshold for trigger.
            policy_id: Associated insurance policy.

        Returns:
            The registered FlightTrigger.
        """
        trigger_id = f"ftrig-{uuid.uuid4().hex[:10]}"
        trigger = FlightTrigger(
            trigger_id=trigger_id,
            flight_number=flight_number,
            date=date,
            delay_threshold_minutes=delay_threshold_minutes,
            policy_id=policy_id,
        )
        self._triggers[trigger_id] = trigger
        logger.info(
            "Flight trigger registered: %s for %s on %s (>%dmin delay)",
            trigger_id, flight_number, date, delay_threshold_minutes,
        )
        return trigger

    def get_trigger_events(
        self, policy_id: Optional[str] = None
    ) -> List[FlightTriggerEvent]:
        """Get trigger events, optionally filtered by policy."""
        if policy_id is None:
            return list(self._trigger_events)
        return [e for e in self._trigger_events if e.policy_id == policy_id]

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _fetch_flight_data(
        self, flight_number: str, date: str
    ) -> FlightData:
        """Fetch flight data from external API."""
        # Production: calls FlightAware or AviationStack API
        return FlightData(
            flight_number=flight_number,
            airline=flight_number[:2],
            departure_airport="",
            arrival_airport="",
            scheduled_departure=time.time(),
            scheduled_arrival=time.time() + 14400,
            status=FlightStatus.SCHEDULED,
            source="flight_api",
            confidence=0.95,
        )

    def _evaluate_triggers(self, flight: FlightData) -> None:
        """Evaluate triggers against current flight data."""
        for trigger in self._triggers.values():
            if not trigger.active or trigger.triggered:
                continue
            if trigger.flight_number != flight.flight_number:
                continue

            should_fire = False
            reason = ""

            if flight.status == FlightStatus.CANCELLED:
                should_fire = True
                reason = "Flight cancelled"
            elif flight.status == FlightStatus.DIVERTED:
                should_fire = True
                reason = "Flight diverted"
            elif flight.delay_minutes >= trigger.delay_threshold_minutes:
                should_fire = True
                reason = f"Delay of {flight.delay_minutes} minutes exceeds {trigger.delay_threshold_minutes} minute threshold"

            if should_fire:
                trigger.triggered = True
                trigger.triggered_at = time.time()
                trigger.trigger_reason = reason

                event = FlightTriggerEvent(
                    event_id=f"fevt-{uuid.uuid4().hex[:10]}",
                    trigger_id=trigger.trigger_id,
                    flight_number=flight.flight_number,
                    status=flight.status,
                    delay_minutes=flight.delay_minutes,
                    policy_id=trigger.policy_id,
                )
                self._trigger_events.append(event)

                logger.info(
                    "Flight trigger FIRED: %s %s (%s)",
                    trigger.trigger_id, flight.flight_number, reason,
                )

                if self._trigger_callback:
                    try:
                        self._trigger_callback(event)
                    except Exception as exc:
                        logger.error("Flight trigger callback failed: %s", exc)
