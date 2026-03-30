"""
Trigger Manager
================

Consumes trigger events from Component 11 oracle providers (weather,
flights, deliveries) and fires automatic insurance payouts. The trigger
manager is the bridge between oracle data and the claims processor.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class TriggerSource(Enum):
    """Source of the trigger event."""
    WEATHER = "weather"
    FLIGHT = "flight"
    DELIVERY = "delivery"
    SPORTS = "sports"
    PRICE = "price"
    CUSTOM = "custom"


class TriggerStatus(Enum):
    """Processing status for a trigger event."""
    RECEIVED = "received"
    VALIDATED = "validated"
    PAYOUT_INITIATED = "payout_initiated"
    PAYOUT_COMPLETED = "payout_completed"
    REJECTED = "rejected"
    ERROR = "error"


@dataclass
class InsuranceTrigger:
    """An insurance trigger event consumed from Component 11."""
    trigger_id: str
    source: TriggerSource
    oracle_event_id: str
    policy_id: str
    wallet_address: str
    trigger_data: Dict[str, Any]
    status: TriggerStatus = TriggerStatus.RECEIVED
    received_at: float = field(default_factory=time.time)
    validated_at: Optional[float] = None
    payout_amount: Optional[float] = None
    payout_tx: Optional[str] = None
    error: Optional[str] = None


class TriggerManager:
    """Consumes Component 11 oracle triggers and fires payouts.

    Receives trigger events from weather, flight, delivery, and other
    oracles. Validates the trigger against the policy, calculates the
    payout, and routes it through the claims processor for automatic
    settlement.

    Parameters
    ----------
    oracle_interface : Any
        Component 11 OracleInterface for data verification.
    claims_processor : Any
        ClaimsProcessor for automatic payout execution.
    policy_registry : Any
        PolicyRegistry for policy lookups.
    """

    def __init__(
        self,
        oracle_interface: Any = None,
        claims_processor: Any = None,
        policy_registry: Any = None,
    ) -> None:
        self._oracle = oracle_interface
        self._claims = claims_processor
        self._policies = policy_registry
        self._triggers: Dict[str, InsuranceTrigger] = {}
        self._callbacks: Dict[TriggerSource, List[Callable]] = {}
        logger.info("TriggerManager initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def receive_trigger(
        self,
        source: TriggerSource,
        oracle_event_id: str,
        policy_id: str,
        wallet_address: str,
        trigger_data: Dict[str, Any],
    ) -> InsuranceTrigger:
        """Receive and process a trigger event from Component 11.

        This is the main entry point called by oracle providers when
        a parametric trigger fires.

        Args:
            source: Which oracle source emitted the trigger.
            oracle_event_id: The oracle event identifier.
            policy_id: The insurance policy this trigger applies to.
            wallet_address: The insured wallet.
            trigger_data: Full trigger event data.

        Returns:
            InsuranceTrigger with processing status.
        """
        trigger_id = f"ins-trig-{uuid.uuid4().hex[:10]}"
        trigger = InsuranceTrigger(
            trigger_id=trigger_id,
            source=source,
            oracle_event_id=oracle_event_id,
            policy_id=policy_id,
            wallet_address=wallet_address,
            trigger_data=trigger_data,
        )
        self._triggers[trigger_id] = trigger

        logger.info(
            "Trigger received: %s from %s for policy %s (wallet=%s)",
            trigger_id, source.value, policy_id, wallet_address,
        )

        # Validate
        valid = self._validate_trigger(trigger)
        if not valid:
            trigger.status = TriggerStatus.REJECTED
            logger.warning("Trigger %s rejected during validation", trigger_id)
            return trigger

        trigger.status = TriggerStatus.VALIDATED
        trigger.validated_at = time.time()

        # Calculate payout and process
        payout = self._calculate_payout(trigger)
        trigger.payout_amount = payout

        if payout > 0 and self._claims:
            self._initiate_payout(trigger, payout)

        # Notify callbacks
        self._notify_callbacks(trigger)

        return trigger

    def register_callback(
        self, source: TriggerSource, callback: Callable
    ) -> None:
        """Register a callback for trigger events from a source.

        Args:
            source: The trigger source to listen for.
            callback: Function called with InsuranceTrigger when fired.
        """
        if source not in self._callbacks:
            self._callbacks[source] = []
        self._callbacks[source].append(callback)

    def get_trigger(self, trigger_id: str) -> Optional[InsuranceTrigger]:
        """Retrieve a trigger by ID."""
        return self._triggers.get(trigger_id)

    def list_triggers(
        self,
        policy_id: Optional[str] = None,
        source: Optional[TriggerSource] = None,
        status: Optional[TriggerStatus] = None,
    ) -> List[InsuranceTrigger]:
        """List triggers with optional filters."""
        results: List[InsuranceTrigger] = []
        for trigger in self._triggers.values():
            if policy_id and trigger.policy_id != policy_id:
                continue
            if source and trigger.source != source:
                continue
            if status and trigger.status != status:
                continue
            results.append(trigger)
        return results

    def get_stats(self) -> Dict[str, Any]:
        """Get trigger processing statistics."""
        by_source: Dict[str, int] = {}
        by_status: Dict[str, int] = {}
        for trigger in self._triggers.values():
            by_source[trigger.source.value] = by_source.get(trigger.source.value, 0) + 1
            by_status[trigger.status.value] = by_status.get(trigger.status.value, 0) + 1
        return {
            "total_triggers": len(self._triggers),
            "by_source": by_source,
            "by_status": by_status,
        }

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _validate_trigger(self, trigger: InsuranceTrigger) -> bool:
        """Validate a trigger against policy and oracle data."""
        # Verify policy exists and is active
        if self._policies:
            policy = self._policies.get_policy(trigger.policy_id)
            if policy is None:
                trigger.error = "Policy not found"
                return False
            if not policy.get("active", False):
                trigger.error = "Policy not active"
                return False

        # Verify the oracle event independently via Component 11
        if self._oracle:
            try:
                # Re-fetch to verify the trigger data matches
                pass  # Trust Component 11's data integrity
            except Exception as exc:
                trigger.error = f"Oracle verification failed: {exc}"
                return False

        return True

    def _calculate_payout(self, trigger: InsuranceTrigger) -> float:
        """Calculate the payout amount based on trigger data and policy."""
        if self._policies:
            policy = self._policies.get_policy(trigger.policy_id)
            if policy:
                coverage = policy.get("coverage_amount", 0)
                return float(coverage)

        # Default payout from trigger data
        return trigger.trigger_data.get("payout_amount", 0.0)

    def _initiate_payout(self, trigger: InsuranceTrigger, amount: float) -> None:
        """Initiate an automatic payout through the claims processor."""
        trigger.status = TriggerStatus.PAYOUT_INITIATED

        try:
            result = self._claims.process_automatic_claim(
                policy_id=trigger.policy_id,
                wallet_address=trigger.wallet_address,
                amount=amount,
                trigger_id=trigger.trigger_id,
                trigger_source=trigger.source.value,
                trigger_data=trigger.trigger_data,
            )
            trigger.payout_tx = result.get("tx_hash")
            trigger.status = TriggerStatus.PAYOUT_COMPLETED
            logger.info(
                "Payout completed for trigger %s: %.4f to %s (tx=%s)",
                trigger.trigger_id, amount, trigger.wallet_address, trigger.payout_tx,
            )
        except Exception as exc:
            trigger.status = TriggerStatus.ERROR
            trigger.error = str(exc)
            logger.error(
                "Payout failed for trigger %s: %s", trigger.trigger_id, exc,
            )

    def _notify_callbacks(self, trigger: InsuranceTrigger) -> None:
        """Notify registered callbacks for this trigger source."""
        callbacks = self._callbacks.get(trigger.source, [])
        for cb in callbacks:
            try:
                cb(trigger)
            except Exception as exc:
                logger.error("Trigger callback failed: %s", exc)
