"""
IP Proof Generator — generates ownership and creation proofs
anchored to blockchain timestamps.

Part of Component 15 (IP and Royalty Management).
"""

from __future__ import annotations

import hashlib
import json
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger(__name__)


class ProofType(str, Enum):
    """Types of IP proof that can be generated."""
    OWNERSHIP = "ownership"
    CREATION = "creation"
    TIMESTAMP = "timestamp"
    REGISTRATION = "registration"


@dataclass
class BlockchainAnchor:
    """On-chain anchor point for a proof."""
    block_number: int
    block_hash: str
    transaction_hash: str
    timestamp: float
    chain_id: int = 1  # Ethereum mainnet default


@dataclass
class IPProof:
    """
    A cryptographic proof of IP ownership or creation,
    anchored to a specific blockchain state.
    """
    proof_id: str
    proof_type: ProofType
    ip_id: str
    owner_address: str
    content_hash: str
    anchor: BlockchainAnchor
    generated_at: float
    metadata: dict[str, Any] = field(default_factory=dict)
    signature: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        """Serialise the proof to a dictionary for storage or transmission."""
        return {
            "proof_id": self.proof_id,
            "proof_type": self.proof_type.value,
            "ip_id": self.ip_id,
            "owner_address": self.owner_address,
            "content_hash": self.content_hash,
            "anchor": {
                "block_number": self.anchor.block_number,
                "block_hash": self.anchor.block_hash,
                "transaction_hash": self.anchor.transaction_hash,
                "timestamp": self.anchor.timestamp,
                "chain_id": self.anchor.chain_id,
            },
            "generated_at": self.generated_at,
            "metadata": self.metadata,
            "signature": self.signature,
        }

    def verify_content_hash(self, content: bytes) -> bool:
        """Verify that the supplied content matches the stored hash."""
        computed = hashlib.sha256(content).hexdigest()
        return computed == self.content_hash


class IPProofGenerator:
    """
    Generates cryptographically verifiable ownership and creation proofs
    for registered IP works, anchored to blockchain timestamps.
    """

    def __init__(self) -> None:
        self._proofs: dict[str, IPProof] = {}  # proof_id -> IPProof
        self._ip_proofs: dict[str, list[str]] = {}  # ip_id -> [proof_id]
        logger.info("IPProofGenerator initialised.")

    # ── Proof Generation ──────────────────────────────────────────────

    def generate_ownership_proof(
        self,
        ip_id: str,
        owner_address: str,
        content_hash: str,
        anchor: BlockchainAnchor,
        metadata: Optional[dict[str, Any]] = None,
    ) -> IPProof:
        """
        Generate an ownership proof for an IP work.

        Args:
            ip_id: Unique identifier of the registered IP work.
            owner_address: Ethereum address of the IP owner.
            content_hash: SHA-256 hash of the work content.
            anchor: Blockchain anchor data (block, tx, timestamp).
            metadata: Optional additional metadata.

        Returns:
            The generated IPProof.

        Raises:
            ValueError: If required fields are missing or invalid.
        """
        self._validate_inputs(ip_id, owner_address, content_hash)

        proof_id = self._compute_proof_id(
            ProofType.OWNERSHIP, ip_id, owner_address, content_hash, anchor
        )

        proof = IPProof(
            proof_id=proof_id,
            proof_type=ProofType.OWNERSHIP,
            ip_id=ip_id,
            owner_address=owner_address,
            content_hash=content_hash,
            anchor=anchor,
            generated_at=time.time(),
            metadata=metadata or {},
        )

        self._store_proof(proof)
        logger.info("Generated ownership proof %s for IP %s.", proof_id, ip_id)
        return proof

    def generate_creation_proof(
        self,
        ip_id: str,
        creator_address: str,
        content_hash: str,
        anchor: BlockchainAnchor,
        metadata: Optional[dict[str, Any]] = None,
    ) -> IPProof:
        """
        Generate a creation/timestamp proof for an IP work.

        Args:
            ip_id: Unique identifier of the registered IP work.
            creator_address: Ethereum address of the creator.
            content_hash: SHA-256 hash of the work content.
            anchor: Blockchain anchor data.
            metadata: Optional additional metadata.

        Returns:
            The generated IPProof.
        """
        self._validate_inputs(ip_id, creator_address, content_hash)

        proof_id = self._compute_proof_id(
            ProofType.CREATION, ip_id, creator_address, content_hash, anchor
        )

        proof = IPProof(
            proof_id=proof_id,
            proof_type=ProofType.CREATION,
            ip_id=ip_id,
            owner_address=creator_address,
            content_hash=content_hash,
            anchor=anchor,
            generated_at=time.time(),
            metadata=metadata or {},
        )

        self._store_proof(proof)
        logger.info("Generated creation proof %s for IP %s.", proof_id, ip_id)
        return proof

    # ── Verification ──────────────────────────────────────────────────

    def verify_proof(self, proof_id: str) -> bool:
        """
        Verify that a proof exists and its internal hash is consistent.

        Args:
            proof_id: The proof identifier to verify.

        Returns:
            True if the proof is valid and internally consistent.
        """
        proof = self._proofs.get(proof_id)
        if proof is None:
            logger.warning("Proof %s not found.", proof_id)
            return False

        expected_id = self._compute_proof_id(
            proof.proof_type, proof.ip_id, proof.owner_address,
            proof.content_hash, proof.anchor,
        )
        valid = expected_id == proof.proof_id
        if not valid:
            logger.warning("Proof %s failed consistency check.", proof_id)
        return valid

    def verify_content(self, proof_id: str, content: bytes) -> bool:
        """
        Verify that the given content matches the proof's content hash.

        Args:
            proof_id: The proof to verify against.
            content: Raw content bytes.

        Returns:
            True if the content hash matches.
        """
        proof = self._proofs.get(proof_id)
        if proof is None:
            logger.warning("Proof %s not found for content verification.", proof_id)
            return False
        return proof.verify_content_hash(content)

    # ── Queries ───────────────────────────────────────────────────────

    def get_proof(self, proof_id: str) -> Optional[IPProof]:
        """Retrieve a proof by its ID."""
        return self._proofs.get(proof_id)

    def get_proofs_for_ip(self, ip_id: str) -> list[IPProof]:
        """Retrieve all proofs associated with an IP work."""
        proof_ids = self._ip_proofs.get(ip_id, [])
        return [self._proofs[pid] for pid in proof_ids if pid in self._proofs]

    def export_proof(self, proof_id: str) -> Optional[str]:
        """
        Export a proof as a JSON string for external verification.

        Returns:
            JSON string of the proof, or None if not found.
        """
        proof = self._proofs.get(proof_id)
        if proof is None:
            return None
        return json.dumps(proof.to_dict(), indent=2)

    # ── Internal ──────────────────────────────────────────────────────

    @staticmethod
    def _validate_inputs(ip_id: str, address: str, content_hash: str) -> None:
        if not ip_id:
            raise ValueError("ip_id is required.")
        if not address or not address.startswith("0x"):
            raise ValueError(f"Invalid address: {address}")
        if not content_hash:
            raise ValueError("content_hash is required.")

    @staticmethod
    def _compute_proof_id(
        proof_type: ProofType,
        ip_id: str,
        address: str,
        content_hash: str,
        anchor: BlockchainAnchor,
    ) -> str:
        payload = (
            f"{proof_type.value}:{ip_id}:{address}:{content_hash}"
            f":{anchor.block_number}:{anchor.transaction_hash}"
        )
        return hashlib.sha256(payload.encode()).hexdigest()

    def _store_proof(self, proof: IPProof) -> None:
        self._proofs[proof.proof_id] = proof
        if proof.ip_id not in self._ip_proofs:
            self._ip_proofs[proof.ip_id] = []
        self._ip_proofs[proof.ip_id].append(proof.proof_id)
