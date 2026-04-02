"""
Commitment Registry — registers and manages privacy commitments.

Part of Component 23 (Privacy Protection).
Stores privacy commitment hashes and URIs on-chain.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class PrivacyCommitment:
    """A registered privacy commitment."""
    commitment_id: str
    commitment_hash: str
    commitment_uri: str
    registered_at: float = field(default_factory=time.time)
    registered_by: str = ""
    active: bool = True


class CommitmentRegistry:
    """
    Registry of privacy commitments.

    Each commitment represents an entity's promise about how
    they handle user data. Commitments are referenced by violation
    reports and buyer compliance attestations.
    """

    def __init__(self) -> None:
        self._commitments: Dict[str, PrivacyCommitment] = {}
        self._counter: int = 0
        logger.info("CommitmentRegistry initialised.")

    def register(
        self,
        commitment_hash: str,
        commitment_uri: str,
        registered_by: str,
    ) -> PrivacyCommitment:
        """
        Register a new privacy commitment.

        Args:
            commitment_hash: Hash of the commitment document.
            commitment_uri: URI pointing to the full commitment.
            registered_by: Address of the registering entity.

        Returns:
            The created PrivacyCommitment.
        """
        if not commitment_hash:
            raise ValueError("Commitment hash must not be empty.")
        if not commitment_uri:
            raise ValueError("Commitment URI must not be empty.")
        if not registered_by.startswith("0x"):
            raise ValueError("Invalid registerer address.")

        self._counter += 1
        cid = f"COMMIT-{self._counter:08d}"

        commitment = PrivacyCommitment(
            commitment_id=cid,
            commitment_hash=commitment_hash,
            commitment_uri=commitment_uri,
            registered_by=registered_by,
        )
        self._commitments[cid] = commitment

        logger.info(
            "Commitment registered | id=%s | by=%s", cid, registered_by,
        )
        return commitment

    def deactivate(self, commitment_id: str) -> PrivacyCommitment:
        """Deactivate a commitment."""
        c = self._get(commitment_id)
        c.active = False
        logger.info("Commitment deactivated | id=%s", commitment_id)
        return c

    def get(self, commitment_id: str) -> Optional[PrivacyCommitment]:
        """Get commitment or None."""
        return self._commitments.get(commitment_id)

    def list_active(self) -> List[PrivacyCommitment]:
        """List all active commitments."""
        return [c for c in self._commitments.values() if c.active]

    def _get(self, commitment_id: str) -> PrivacyCommitment:
        """Get commitment or raise."""
        c = self._commitments.get(commitment_id)
        if c is None:
            raise ValueError(f"Commitment {commitment_id} not found.")
        return c
