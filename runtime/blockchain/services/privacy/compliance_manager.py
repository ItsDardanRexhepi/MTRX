"""
Compliance Manager — buyer privacy compliance attestation.

Part of Component 23 (Privacy Protection).
Tracks buyer compliance status against registered privacy commitments.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


class BuyerComplianceStatus(Enum):
    """Compliance attestation states."""
    PENDING = "pending"
    ATTESTED = "attested"
    REVOKED = "revoked"


@dataclass
class BuyerCompliance:
    """A buyer's compliance attestation."""
    compliance_id: str
    buyer: str
    commitment_ids: List[str]
    status: BuyerComplianceStatus = BuyerComplianceStatus.PENDING
    attested_at: float = 0.0
    compliance_proof_uri: str = ""
    created_at: float = field(default_factory=time.time)


class ComplianceManager:
    """
    Manages buyer compliance attestations against privacy commitments.

    Buyers attest that they comply with specific privacy commitments.
    Attestations can be revoked by platform administrators.
    """

    def __init__(self) -> None:
        self._records: Dict[str, BuyerCompliance] = {}
        self._by_buyer: Dict[str, str] = {}  # buyer -> compliance_id
        self._counter: int = 0
        logger.info("ComplianceManager initialised.")

    def attest_compliance(
        self,
        buyer: str,
        commitment_ids: List[str],
        proof_uri: str,
    ) -> BuyerCompliance:
        """
        Attest a buyer's compliance with privacy commitments.

        Args:
            buyer: Buyer's address.
            commitment_ids: List of commitment IDs being attested.
            proof_uri: URI of the compliance proof document.

        Returns:
            The created BuyerCompliance record.
        """
        if not buyer.startswith("0x"):
            raise ValueError("Invalid buyer address.")
        if not commitment_ids:
            raise ValueError("Must attest to at least one commitment.")
        if not proof_uri:
            raise ValueError("Proof URI must not be empty.")

        # Revoke any existing attestation
        if buyer in self._by_buyer:
            old_id = self._by_buyer[buyer]
            old = self._records.get(old_id)
            if old and old.status == BuyerComplianceStatus.ATTESTED:
                old.status = BuyerComplianceStatus.REVOKED

        self._counter += 1
        cid = f"COMP-{self._counter:08d}"

        record = BuyerCompliance(
            compliance_id=cid,
            buyer=buyer,
            commitment_ids=commitment_ids,
            status=BuyerComplianceStatus.ATTESTED,
            attested_at=time.time(),
            compliance_proof_uri=proof_uri,
        )
        self._records[cid] = record
        self._by_buyer[buyer] = cid

        logger.info(
            "Compliance attested | id=%s | buyer=%s | commitments=%d",
            cid, buyer, len(commitment_ids),
        )
        return record

    def revoke_compliance(self, buyer: str) -> BuyerCompliance:
        """Revoke a buyer's compliance attestation."""
        cid = self._by_buyer.get(buyer)
        if cid is None:
            raise ValueError(f"No compliance record for buyer {buyer}.")
        record = self._records[cid]
        if record.status != BuyerComplianceStatus.ATTESTED:
            raise ValueError(f"Compliance for {buyer} is not attested.")

        record.status = BuyerComplianceStatus.REVOKED
        logger.info("Compliance revoked | buyer=%s", buyer)
        return record

    def is_compliant(self, buyer: str) -> bool:
        """Check if a buyer currently has valid compliance."""
        cid = self._by_buyer.get(buyer)
        if cid is None:
            return False
        record = self._records.get(cid)
        return record is not None and record.status == BuyerComplianceStatus.ATTESTED

    def get_compliance(self, buyer: str) -> Optional[BuyerCompliance]:
        """Get a buyer's current compliance record."""
        cid = self._by_buyer.get(buyer)
        if cid is None:
            return None
        return self._records.get(cid)
