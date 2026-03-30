"""
Delivery Oracle
================

Package protection delivery status tracking. Monitors shipment
status for parametric insurance triggers on lost, damaged, or
significantly delayed packages.
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


class DeliveryStatus(Enum):
    """Package delivery status values."""
    LABEL_CREATED = "label_created"
    PICKED_UP = "picked_up"
    IN_TRANSIT = "in_transit"
    OUT_FOR_DELIVERY = "out_for_delivery"
    DELIVERED = "delivered"
    DELIVERY_ATTEMPTED = "delivery_attempted"
    DELAYED = "delayed"
    LOST = "lost"
    DAMAGED = "damaged"
    RETURNED = "returned"
    UNKNOWN = "unknown"


class Carrier(Enum):
    """Supported shipping carriers."""
    USPS = "usps"
    UPS = "ups"
    FEDEX = "fedex"
    DHL = "dhl"
    AMAZON = "amazon"
    OTHER = "other"


@dataclass
class DeliveryData:
    """Package delivery tracking data."""
    tracking_number: str
    carrier: Carrier
    status: DeliveryStatus
    origin: str = ""
    destination: str = ""
    estimated_delivery: Optional[float] = None
    actual_delivery: Optional[float] = None
    last_location: str = ""
    last_update: float = field(default_factory=time.time)
    delay_days: int = 0
    is_insured: bool = False
    declared_value: float = 0.0
    source: str = ""
    confidence: float = 0.0
    events: List[Dict[str, Any]] = field(default_factory=list)

    @property
    def is_disrupted(self) -> bool:
        return self.status in (
            DeliveryStatus.LOST,
            DeliveryStatus.DAMAGED,
            DeliveryStatus.RETURNED,
        )

    @property
    def is_significantly_delayed(self) -> bool:
        return self.delay_days >= 3


@dataclass
class DeliveryTrigger:
    """Parametric trigger for package protection insurance."""
    trigger_id: str
    tracking_number: str
    carrier: Carrier
    policy_id: Optional[str] = None
    delay_threshold_days: int = 3
    active: bool = True
    triggered: bool = False
    triggered_at: Optional[float] = None
    trigger_reason: Optional[str] = None


@dataclass
class DeliveryTriggerEvent:
    """Emitted when a delivery trigger fires."""
    event_id: str
    trigger_id: str
    tracking_number: str
    status: DeliveryStatus
    delay_days: int
    policy_id: Optional[str] = None
    timestamp: float = field(default_factory=time.time)


class DeliveryOracle:
    """Package delivery status provider for protection insurance.

    Monitors shipment tracking data and evaluates parametric triggers
    for lost, damaged, or significantly delayed packages.

    Parameters
    ----------
    api_credentials : dict, optional
        API keys for shipping carrier APIs.
    trigger_callback : callable, optional
        Called when a delivery trigger fires.
    """

    def __init__(
        self,
        api_credentials: Optional[Dict[str, str]] = None,
        trigger_callback: Any = None,
    ) -> None:
        self._credentials = api_credentials or {}
        self._trigger_callback = trigger_callback
        self._deliveries: Dict[str, DeliveryData] = {}
        self._triggers: Dict[str, DeliveryTrigger] = {}
        self._trigger_events: List[DeliveryTriggerEvent] = []
        logger.info("DeliveryOracle initialised")

    # ------------------------------------------------------------------
    # OracleInterface integration
    # ------------------------------------------------------------------

    def fetch(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Fetch delivery data (called by OracleInterface).

        Args:
            parameters: Must contain 'tracking_number' and 'carrier'.

        Returns:
            Dict with delivery data for aggregation.
        """
        tracking = parameters.get("tracking_number", "")
        carrier_str = parameters.get("carrier", "other")

        try:
            carrier = Carrier(carrier_str)
        except ValueError:
            carrier = Carrier.OTHER

        data = self.get_delivery_status(tracking, carrier)

        return {
            "value": {
                "status": data.status.value,
                "delay_days": data.delay_days,
                "is_disrupted": data.is_disrupted,
            },
            "tracking_number": data.tracking_number,
            "carrier": data.carrier.value,
            "last_location": data.last_location,
            "source": data.source,
            "confidence": data.confidence,
        }

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_delivery_status(
        self, tracking_number: str, carrier: Carrier
    ) -> DeliveryData:
        """Get current delivery status for a package.

        Args:
            tracking_number: Package tracking number.
            carrier: Shipping carrier.

        Returns:
            DeliveryData with current status.
        """
        key = f"{carrier.value}:{tracking_number}"
        cached = self._deliveries.get(key)
        if cached and (time.time() - cached.last_update) < 600:
            return cached

        data = self._fetch_delivery_data(tracking_number, carrier)
        self._deliveries[key] = data

        self._evaluate_triggers(data)

        return data

    def register_trigger(
        self,
        tracking_number: str,
        carrier: Carrier,
        delay_threshold_days: int = 3,
        policy_id: Optional[str] = None,
    ) -> DeliveryTrigger:
        """Register a parametric delivery trigger.

        Args:
            tracking_number: Package to monitor.
            carrier: Shipping carrier.
            delay_threshold_days: Days of delay before trigger fires.
            policy_id: Associated insurance policy.

        Returns:
            The registered DeliveryTrigger.
        """
        trigger_id = f"dtrig-{uuid.uuid4().hex[:10]}"
        trigger = DeliveryTrigger(
            trigger_id=trigger_id,
            tracking_number=tracking_number,
            carrier=carrier,
            delay_threshold_days=delay_threshold_days,
            policy_id=policy_id,
        )
        self._triggers[trigger_id] = trigger
        logger.info(
            "Delivery trigger registered: %s for %s (%s)",
            trigger_id, tracking_number, carrier.value,
        )
        return trigger

    def get_trigger_events(
        self, policy_id: Optional[str] = None
    ) -> List[DeliveryTriggerEvent]:
        """Get trigger events, optionally filtered by policy."""
        if policy_id is None:
            return list(self._trigger_events)
        return [e for e in self._trigger_events if e.policy_id == policy_id]

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _fetch_delivery_data(
        self, tracking_number: str, carrier: Carrier
    ) -> DeliveryData:
        """Fetch delivery data from carrier API."""
        # Production: calls UPS, FedEx, USPS, DHL APIs
        return DeliveryData(
            tracking_number=tracking_number,
            carrier=carrier,
            status=DeliveryStatus.IN_TRANSIT,
            source="carrier_api",
            confidence=0.95,
        )

    def _evaluate_triggers(self, data: DeliveryData) -> None:
        """Evaluate triggers against current delivery data."""
        for trigger in self._triggers.values():
            if not trigger.active or trigger.triggered:
                continue
            if trigger.tracking_number != data.tracking_number:
                continue

            should_fire = False
            reason = ""

            if data.status == DeliveryStatus.LOST:
                should_fire = True
                reason = "Package reported lost"
            elif data.status == DeliveryStatus.DAMAGED:
                should_fire = True
                reason = "Package reported damaged"
            elif data.delay_days >= trigger.delay_threshold_days:
                should_fire = True
                reason = f"Delivery delayed {data.delay_days} days (threshold: {trigger.delay_threshold_days})"

            if should_fire:
                trigger.triggered = True
                trigger.triggered_at = time.time()
                trigger.trigger_reason = reason

                event = DeliveryTriggerEvent(
                    event_id=f"devt-{uuid.uuid4().hex[:10]}",
                    trigger_id=trigger.trigger_id,
                    tracking_number=data.tracking_number,
                    status=data.status,
                    delay_days=data.delay_days,
                    policy_id=trigger.policy_id,
                )
                self._trigger_events.append(event)

                logger.info(
                    "Delivery trigger FIRED: %s %s (%s)",
                    trigger.trigger_id, data.tracking_number, reason,
                )

                if self._trigger_callback:
                    try:
                        self._trigger_callback(event)
                    except Exception as exc:
                        logger.error("Delivery trigger callback failed: %s", exc)
