"""
Attestation Dispatcher
========================

Classifies incoming attestation requests as time-critical or batchable
and routes them to the appropriate handler. Time-critical attestations
(payments, disputes, insurance triggers) go to ImmediateHandler.
Batchable attestations (routine logging, metadata updates) go to
BatchProcessor for gas-efficient grouped submission.
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


class AttestationPriority(Enum):
    """Priority classification for attestation requests."""
    IMMEDIATE = "immediate"
    BATCH = "batch"


class AttestationCategory(Enum):
    """Semantic categories of attestations."""
    PAYMENT = "payment"
    DISPUTE = "dispute"
    INSURANCE_TRIGGER = "insurance_trigger"
    INSURANCE_PAYOUT = "insurance_payout"
    OWNERSHIP_TRANSFER = "ownership_transfer"
    IDENTITY_VERIFICATION = "identity_verification"
    AGENT_ACTION = "agent_action"
    GOVERNANCE_VOTE = "governance_vote"
    SUPPLY_CHAIN_EVENT = "supply_chain_event"
    FEE_COLLECTION = "fee_collection"
    CREDENTIAL_ANCHOR = "credential_anchor"
    GENERAL = "general"


# Categories that are always time-critical
IMMEDIATE_CATEGORIES = frozenset({
    AttestationCategory.PAYMENT,
    AttestationCategory.DISPUTE,
    AttestationCategory.INSURANCE_TRIGGER,
    AttestationCategory.INSURANCE_PAYOUT,
    AttestationCategory.OWNERSHIP_TRANSFER,
})


@dataclass
class AttestationRequest:
    """An incoming attestation request."""
    request_id: str
    schema_uid: str
    category: AttestationCategory
    data: Dict[str, Any]
    source_component: int
    requester: str
    priority: Optional[AttestationPriority] = None
    created_at: float = field(default_factory=time.time)
    routed_at: Optional[float] = None
    attestation_uid: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class DispatchResult:
    """Result of dispatching an attestation request."""
    request_id: str
    priority: AttestationPriority
    handler: str
    queued: bool
    attestation_uid: Optional[str] = None
    error: Optional[str] = None


class AttestationDispatcher:
    """Classifies and routes attestation requests.

    Time-critical attestations are sent to ImmediateHandler for
    instant on-chain submission. Batchable attestations are queued
    in BatchProcessor for gas-efficient grouped submission.

    Parameters
    ----------
    immediate_handler : Any
        ImmediateHandler for time-critical attestations.
    batch_processor : Any
        BatchProcessor for batchable attestations.
    """

    def __init__(
        self,
        immediate_handler: Any = None,
        batch_processor: Any = None,
    ) -> None:
        self._immediate = immediate_handler
        self._batch = batch_processor
        self._dispatch_log: List[DispatchResult] = []
        self._stats = {"immediate": 0, "batch": 0, "errors": 0}
        logger.info("AttestationDispatcher initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def dispatch(self, request: AttestationRequest) -> DispatchResult:
        """Classify and route an attestation request.

        Args:
            request: The attestation request to dispatch.

        Returns:
            DispatchResult with routing outcome.
        """
        # Classify priority
        priority = self._classify(request)
        request.priority = priority
        request.routed_at = time.time()

        if priority == AttestationPriority.IMMEDIATE:
            return self._route_immediate(request)
        else:
            return self._route_batch(request)

    def dispatch_many(
        self, requests: List[AttestationRequest]
    ) -> List[DispatchResult]:
        """Dispatch multiple attestation requests.

        Args:
            requests: List of attestation requests.

        Returns:
            List of DispatchResult for each request.
        """
        return [self.dispatch(r) for r in requests]

    def create_request(
        self,
        schema_uid: str,
        category: AttestationCategory,
        data: Dict[str, Any],
        source_component: int,
        requester: str,
        force_immediate: bool = False,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> AttestationRequest:
        """Create and dispatch an attestation request in one call.

        Args:
            schema_uid: EAS schema UID.
            category: Attestation category.
            data: Attestation payload data.
            source_component: Component ID originating the request.
            requester: Address of the requesting party.
            force_immediate: Override classification to immediate.
            metadata: Additional metadata.

        Returns:
            The created AttestationRequest (with dispatch result attached).
        """
        request = AttestationRequest(
            request_id=f"att-{uuid.uuid4().hex[:12]}",
            schema_uid=schema_uid,
            category=category,
            data=data,
            source_component=source_component,
            requester=requester,
            metadata=metadata or {},
        )

        if force_immediate:
            request.priority = AttestationPriority.IMMEDIATE

        result = self.dispatch(request)
        request.attestation_uid = result.attestation_uid
        return request

    def get_stats(self) -> Dict[str, int]:
        """Return dispatch statistics."""
        return dict(self._stats)

    def get_dispatch_log(self, limit: int = 100) -> List[DispatchResult]:
        """Return recent dispatch results."""
        return list(reversed(self._dispatch_log[-limit:]))

    # ------------------------------------------------------------------
    # Classification
    # ------------------------------------------------------------------

    def _classify(self, request: AttestationRequest) -> AttestationPriority:
        """Classify an attestation request as immediate or batchable.

        Rules:
        1. If priority is already set (e.g. force_immediate), use it.
        2. If category is in IMMEDIATE_CATEGORIES, classify as immediate.
        3. Otherwise, classify as batchable.
        """
        if request.priority is not None:
            return request.priority

        if request.category in IMMEDIATE_CATEGORIES:
            return AttestationPriority.IMMEDIATE

        return AttestationPriority.BATCH

    # ------------------------------------------------------------------
    # Routing
    # ------------------------------------------------------------------

    def _route_immediate(self, request: AttestationRequest) -> DispatchResult:
        """Route to ImmediateHandler for instant processing."""
        self._stats["immediate"] += 1

        try:
            attestation_uid = None
            if self._immediate:
                attestation_uid = self._immediate.process(request)
            result = DispatchResult(
                request_id=request.request_id,
                priority=AttestationPriority.IMMEDIATE,
                handler="ImmediateHandler",
                queued=False,
                attestation_uid=attestation_uid,
            )
        except Exception as exc:
            self._stats["errors"] += 1
            result = DispatchResult(
                request_id=request.request_id,
                priority=AttestationPriority.IMMEDIATE,
                handler="ImmediateHandler",
                queued=False,
                error=str(exc),
            )
            logger.error("Immediate dispatch failed for %s: %s", request.request_id, exc)

        self._dispatch_log.append(result)
        return result

    def _route_batch(self, request: AttestationRequest) -> DispatchResult:
        """Route to BatchProcessor for queued submission."""
        self._stats["batch"] += 1

        try:
            if self._batch:
                self._batch.enqueue(request)
            result = DispatchResult(
                request_id=request.request_id,
                priority=AttestationPriority.BATCH,
                handler="BatchProcessor",
                queued=True,
            )
        except Exception as exc:
            self._stats["errors"] += 1
            result = DispatchResult(
                request_id=request.request_id,
                priority=AttestationPriority.BATCH,
                handler="BatchProcessor",
                queued=False,
                error=str(exc),
            )
            logger.error("Batch dispatch failed for %s: %s", request.request_id, exc)

        self._dispatch_log.append(result)
        return result
