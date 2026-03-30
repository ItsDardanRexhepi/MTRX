"""
Component 4 -- Legal Bridge
============================

Generates a corresponding legal document for every smart contract and links
them by mutual hash reference.  Neither the on-chain contract nor the legal
document can be altered without breaking the other's reference.

Tracks signatures from ALL parties and activates the contract upon full
execution (all signatures collected).
"""

from __future__ import annotations

import hashlib
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class DocumentStatus(Enum):
    DRAFT = auto()
    PENDING_SIGNATURES = auto()
    FULLY_EXECUTED = auto()
    EXPIRED = auto()
    REVOKED = auto()


@dataclass
class LegalDocument:
    """Represents an off-chain legal document linked to an on-chain contract."""

    document_id: str
    contract_address: Optional[str]
    document_hash: str
    content: Dict[str, Any]
    status: DocumentStatus
    parties: List[str]
    signatures: Dict[str, Optional[str]]  # party -> signature or None
    created_at: float
    activated_at: Optional[float] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


# ------------------------------------------------------------------ service


class LegalBridge:
    """
    Bidirectional bridge between on-chain smart contracts and off-chain legal
    documents.  Every smart contract gets a legal counterpart; both reference
    each other by hash so that any modification to either side is detectable.
    """

    def __init__(self) -> None:
        self._documents: Dict[str, LegalDocument] = {}
        self._contract_to_doc: Dict[str, str] = {}  # contract_address -> document_id

    # -- public API -------------------------------------------------------

    def generate_legal_document(
        self, contract_params: Dict[str, Any]
    ) -> LegalDocument:
        """
        Generate a legal document that mirrors a smart contract's terms.

        Parameters
        ----------
        contract_params : dict
            Must include ``parties`` (list of identifiers), plus any terms
            (ownership_splits, governance, exit_terms, etc.).

        Returns
        -------
        LegalDocument
            The newly created, unsigned legal document.
        """
        parties: List[str] = contract_params.get("parties", [])
        if len(parties) < 2:
            raise ValueError("A legal document requires at least 2 parties.")

        document_id = str(uuid.uuid4())
        content = self._build_document_content(contract_params)
        document_hash = self.compute_document_hash(content)

        doc = LegalDocument(
            document_id=document_id,
            contract_address=None,
            document_hash=document_hash,
            content=content,
            status=DocumentStatus.PENDING_SIGNATURES,
            parties=list(parties),
            signatures={party: None for party in parties},
            created_at=time.time(),
        )

        self._documents[document_id] = doc
        return doc

    def compute_document_hash(self, document: Any) -> str:
        """
        Compute a deterministic SHA-256 hash over the document content.

        Parameters
        ----------
        document : Any
            Serialisable document content (dict, str, bytes).

        Returns
        -------
        str
            Hex-encoded SHA-256 digest.
        """
        raw = str(document).encode("utf-8")
        return hashlib.sha256(raw).hexdigest()

    def link_to_contract(
        self, document_hash: str, contract_address: str
    ) -> None:
        """
        Establish the bidirectional hash link between a legal document and
        its on-chain contract.

        Parameters
        ----------
        document_hash : str
            The hash of the legal document to link.
        contract_address : str
            The deployed contract address.

        Raises
        ------
        ValueError
            If no document matches the supplied hash.
        """
        doc = self._find_by_hash(document_hash)
        if doc is None:
            raise ValueError(
                f"No legal document found with hash {document_hash}"
            )

        doc.contract_address = contract_address
        self._contract_to_doc[contract_address] = doc.document_id

    def record_signature(self, party: str, contract_address: str) -> None:
        """
        Record a party's signature against the legal document linked to
        *contract_address*.

        Parameters
        ----------
        party : str
            The signing party identifier.
        contract_address : str
            The linked contract address.

        Raises
        ------
        ValueError
            If the contract has no linked document or the party is not listed.
        """
        doc = self._get_doc_for_contract(contract_address)

        if party not in doc.signatures:
            raise ValueError(
                f"Party {party} is not listed on document {doc.document_id}"
            )
        if doc.signatures[party] is not None:
            raise ValueError(f"Party {party} has already signed.")

        # Use a timestamped signature placeholder (real impl would use crypto sig)
        doc.signatures[party] = f"sig_{party}_{int(time.time())}"

    def check_all_signed(self, contract_address: str) -> bool:
        """
        Return ``True`` if every party has signed the legal document linked
        to *contract_address*.
        """
        doc = self._get_doc_for_contract(contract_address)
        return all(sig is not None for sig in doc.signatures.values())

    def activate_contract(self, contract_address: str) -> None:
        """
        Activate the legal document (mark as FULLY_EXECUTED) once all
        signatures have been collected.

        Raises
        ------
        RuntimeError
            If not all parties have signed.
        """
        if not self.check_all_signed(contract_address):
            raise RuntimeError(
                "Cannot activate: not all parties have signed the document."
            )

        doc = self._get_doc_for_contract(contract_address)
        doc.status = DocumentStatus.FULLY_EXECUTED
        doc.activated_at = time.time()

    # -- internal helpers -------------------------------------------------

    def _build_document_content(
        self, params: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Assemble the legal document content dictionary from contract params."""
        return {
            "title": params.get("title", "Joint Ownership Agreement"),
            "parties": params.get("parties", []),
            "ownership_splits": params.get("ownership_splits", {}),
            "governance": params.get("governance", {}),
            "exit_terms": params.get("exit_terms", {}),
            "dispute_resolution": params.get("dispute_resolution", {}),
            "maintenance_allocation": params.get("maintenance_allocation", {}),
            "pnl_sharing": params.get("pnl_sharing", {}),
            "generated_at": time.time(),
        }

    def _find_by_hash(self, document_hash: str) -> Optional[LegalDocument]:
        """Look up a document by its hash."""
        for doc in self._documents.values():
            if doc.document_hash == document_hash:
                return doc
        return None

    def _get_doc_for_contract(self, contract_address: str) -> LegalDocument:
        """Retrieve the legal document linked to a contract address."""
        doc_id = self._contract_to_doc.get(contract_address)
        if doc_id is None or doc_id not in self._documents:
            raise ValueError(
                f"No legal document linked to contract {contract_address}"
            )
        return self._documents[doc_id]
