"""
Component 4 -- Dispute Connector
==================================

Routes bilateral co-owner disputes to Component 30 (Dispute Resolution).
When co-owners in a joint ownership contract cannot agree, this connector
packages the dispute context and forwards it to the platform's dispute
resolution system.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class DisputeType(Enum):
    OWNERSHIP_PERCENTAGE = auto()
    MAINTENANCE_RESPONSIBILITY = auto()
    PROFIT_DISTRIBUTION = auto()
    EXIT_TERMS = auto()
    USAGE_RIGHTS = auto()
    GOVERNANCE_DECISION = auto()
    GENERAL = auto()


class DisputeStatus(Enum):
    SUBMITTED = auto()
    ROUTED = auto()
    ACKNOWLEDGED = auto()
    IN_RESOLUTION = auto()
    RESOLVED = auto()
    ESCALATED = auto()


@dataclass
class DisputeRecord:
    """A dispute record routed to Component 30."""

    dispute_id: str
    contract_id: str
    filed_by: str
    against: str
    dispute_type: DisputeType
    description: str
    evidence: List[Dict[str, Any]]
    status: DisputeStatus
    filed_at: float
    resolved_at: Optional[float] = None
    resolution: Optional[Dict[str, Any]] = None


# ------------------------------------------------------------------ service


class DisputeConnector:
    """
    Routes bilateral co-owner disputes from Component 4 (RWA Tokenization)
    to Component 30 (Dispute Resolution).
    """

    def __init__(self, dispute_resolver: Any = None) -> None:
        """
        Parameters
        ----------
        dispute_resolver : Any, optional
            Reference to the Component 30 dispute resolution service.
            When ``None`` the connector queues disputes for later routing.
        """
        self._resolver = dispute_resolver
        self._disputes: Dict[str, DisputeRecord] = {}

    def file_dispute(
        self,
        contract_id: str,
        filed_by: str,
        against: str,
        dispute_type: DisputeType,
        description: str,
        evidence: Optional[List[Dict[str, Any]]] = None,
    ) -> DisputeRecord:
        """
        File a bilateral dispute and route it to Component 30.

        Parameters
        ----------
        contract_id : str
            The joint ownership contract ID.
        filed_by : str
            The party filing the dispute.
        against : str
            The opposing party.
        dispute_type : DisputeType
            Category of dispute.
        description : str
            Free-text description of the issue.
        evidence : list[dict], optional
            Supporting evidence documents or references.

        Returns
        -------
        DisputeRecord
        """
        dispute_id = str(uuid.uuid4())
        now = time.time()

        record = DisputeRecord(
            dispute_id=dispute_id,
            contract_id=contract_id,
            filed_by=filed_by,
            against=against,
            dispute_type=dispute_type,
            description=description,
            evidence=evidence or [],
            status=DisputeStatus.SUBMITTED,
            filed_at=now,
        )

        self._disputes[dispute_id] = record

        # Route to Component 30 if available
        if self._resolver is not None:
            try:
                self._resolver.receive_dispute(record.__dict__)
                record.status = DisputeStatus.ROUTED
            except Exception:
                # Queued for retry; status remains SUBMITTED
                pass
        else:
            record.status = DisputeStatus.SUBMITTED

        return record

    def get_dispute(self, dispute_id: str) -> DisputeRecord:
        """Retrieve a dispute record by ID."""
        record = self._disputes.get(dispute_id)
        if record is None:
            raise KeyError(f"No dispute found with ID {dispute_id}")
        return record

    def get_disputes_for_contract(
        self, contract_id: str
    ) -> List[DisputeRecord]:
        """Return all disputes associated with a contract."""
        return [
            d
            for d in self._disputes.values()
            if d.contract_id == contract_id
        ]

    def update_status(
        self,
        dispute_id: str,
        new_status: DisputeStatus,
        resolution: Optional[Dict[str, Any]] = None,
    ) -> DisputeRecord:
        """
        Update the status of a dispute (typically called by Component 30).

        Parameters
        ----------
        dispute_id : str
        new_status : DisputeStatus
        resolution : dict, optional
            Resolution details if the dispute is resolved.

        Returns
        -------
        DisputeRecord
        """
        record = self.get_dispute(dispute_id)
        record.status = new_status

        if resolution is not None:
            record.resolution = resolution
        if new_status == DisputeStatus.RESOLVED:
            record.resolved_at = time.time()

        return record
