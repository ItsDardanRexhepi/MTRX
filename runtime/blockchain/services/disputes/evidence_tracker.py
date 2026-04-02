"""
Evidence Tracker — manages evidence submissions for disputes.

Part of Component 30 (Dispute Resolution).
Tracks evidence URIs, hashes, deadlines, and submission history.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class EvidenceSubmission:
    """A single piece of evidence submitted to a dispute."""
    evidence_id: str
    dispute_id: str
    submitter: str
    evidence_uri: str
    evidence_hash: str
    submitted_at: float = field(default_factory=time.time)


class EvidenceTracker:
    """
    Tracks evidence submissions per dispute.

    Enforces deadlines and provides retrieval by dispute or submitter.
    """

    def __init__(self) -> None:
        self._submissions: Dict[str, EvidenceSubmission] = {}
        self._by_dispute: Dict[str, List[str]] = {}
        self._counter: int = 0
        logger.info("EvidenceTracker initialised.")

    def submit(
        self,
        dispute_id: str,
        submitter: str,
        evidence_uri: str,
        evidence_hash: str,
        deadline: float,
    ) -> EvidenceSubmission:
        """
        Submit evidence for a dispute.

        Args:
            dispute_id: The dispute this evidence belongs to.
            submitter: Address of the submitter.
            evidence_uri: URI pointing to the evidence document.
            evidence_hash: Hash of the evidence content.
            deadline: Unix timestamp after which submissions are rejected.

        Returns:
            The created EvidenceSubmission.

        Raises:
            ValueError: If deadline has passed or inputs are invalid.
        """
        now = time.time()
        if now > deadline:
            raise ValueError(
                f"Evidence deadline has passed for dispute {dispute_id}."
            )
        if not submitter.startswith("0x"):
            raise ValueError("Invalid submitter address.")
        if not evidence_uri:
            raise ValueError("Evidence URI must not be empty.")
        if not evidence_hash:
            raise ValueError("Evidence hash must not be empty.")

        self._counter += 1
        eid = f"EV-{self._counter:08d}"

        sub = EvidenceSubmission(
            evidence_id=eid,
            dispute_id=dispute_id,
            submitter=submitter,
            evidence_uri=evidence_uri,
            evidence_hash=evidence_hash,
        )
        self._submissions[eid] = sub
        self._by_dispute.setdefault(dispute_id, []).append(eid)

        logger.info(
            "Evidence submitted | id=%s | dispute=%s | submitter=%s",
            eid, dispute_id, submitter,
        )
        return sub

    def get_evidence(self, evidence_id: str) -> EvidenceSubmission:
        """Get a single evidence submission by ID."""
        ev = self._submissions.get(evidence_id)
        if ev is None:
            raise ValueError(f"Evidence {evidence_id} not found.")
        return ev

    def get_for_dispute(self, dispute_id: str) -> List[EvidenceSubmission]:
        """Get all evidence submissions for a dispute."""
        ids = self._by_dispute.get(dispute_id, [])
        return [self._submissions[eid] for eid in ids]

    def get_count(self, dispute_id: str) -> int:
        """Return number of evidence submissions for a dispute."""
        return len(self._by_dispute.get(dispute_id, []))
