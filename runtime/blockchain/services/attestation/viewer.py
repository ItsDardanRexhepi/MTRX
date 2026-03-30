"""
Attestation Viewer
===================

User-facing attestation history and shareable proof links. Provides
read access to all attestations associated with a user, with filtering,
pagination, and the ability to generate shareable verification URLs.
"""

from __future__ import annotations

import hashlib
import logging
import time
import urllib.parse
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
EAS_SCAN_BASE_URL: str = "https://base.easscan.org/attestation/view"


@dataclass
class AttestationRecord:
    """An attestation record for display."""
    attestation_uid: str
    schema_uid: str
    attester: str
    recipient: str
    data: Dict[str, Any]
    timestamp: float
    revoked: bool = False
    revocation_time: Optional[float] = None
    tx_hash: Optional[str] = None
    source_component: Optional[int] = None
    category: str = ""
    human_summary: Optional[str] = None


@dataclass
class ShareableLink:
    """A shareable proof link for an attestation."""
    attestation_uid: str
    url: str
    verification_code: str
    created_at: float = field(default_factory=time.time)
    expires_at: Optional[float] = None
    access_count: int = 0


@dataclass
class AttestationPage:
    """Paginated attestation results."""
    records: List[AttestationRecord]
    total_count: int
    page: int
    page_size: int
    has_next: bool
    has_previous: bool


class AttestationViewer:
    """User attestation history and shareable proof links.

    Provides a read-only view of all attestations associated with
    a user. Supports filtering by category, date range, and component.
    Generates shareable verification URLs backed by EAS scan.

    Parameters
    ----------
    eas_provider : Any
        EAS query provider for fetching attestation data.
    proof_generator : Any, optional
        ProofGenerator for human-readable summaries.
    base_url : str
        Base URL for shareable proof links.
    """

    def __init__(
        self,
        eas_provider: Any = None,
        proof_generator: Any = None,
        base_url: str = EAS_SCAN_BASE_URL,
    ) -> None:
        self._eas = eas_provider
        self._proof_gen = proof_generator
        self._base_url = base_url
        self._attestation_cache: Dict[str, List[AttestationRecord]] = {}
        self._shared_links: Dict[str, ShareableLink] = {}
        logger.info("AttestationViewer initialised")

    # ------------------------------------------------------------------
    # Public API - History
    # ------------------------------------------------------------------

    def get_attestations(
        self,
        user_address: str,
        category: Optional[str] = None,
        source_component: Optional[int] = None,
        since: Optional[float] = None,
        until: Optional[float] = None,
        page: int = 1,
        page_size: int = 25,
    ) -> AttestationPage:
        """Get paginated attestation history for a user.

        Args:
            user_address: The user's wallet address.
            category: Optional category filter.
            source_component: Optional component ID filter.
            since: Optional start timestamp.
            until: Optional end timestamp.
            page: Page number (1-indexed).
            page_size: Records per page.

        Returns:
            AttestationPage with filtered, paginated results.
        """
        records = self._fetch_user_attestations(user_address)

        # Apply filters
        filtered: List[AttestationRecord] = []
        for record in records:
            if category and record.category != category:
                continue
            if source_component is not None and record.source_component != source_component:
                continue
            if since and record.timestamp < since:
                continue
            if until and record.timestamp > until:
                continue
            filtered.append(record)

        # Sort by timestamp descending (newest first)
        filtered.sort(key=lambda r: r.timestamp, reverse=True)

        # Paginate
        total = len(filtered)
        start = (page - 1) * page_size
        end = start + page_size
        page_records = filtered[start:end]

        # Attach human summaries if proof_generator available
        if self._proof_gen:
            for record in page_records:
                if record.human_summary is None:
                    record.human_summary = self._proof_gen.generate_summary(record)

        return AttestationPage(
            records=page_records,
            total_count=total,
            page=page,
            page_size=page_size,
            has_next=end < total,
            has_previous=page > 1,
        )

    def get_attestation(
        self, attestation_uid: str
    ) -> Optional[AttestationRecord]:
        """Get a single attestation by UID.

        Args:
            attestation_uid: The attestation UID.

        Returns:
            AttestationRecord or None.
        """
        for records in self._attestation_cache.values():
            for record in records:
                if record.attestation_uid == attestation_uid:
                    if self._proof_gen and record.human_summary is None:
                        record.human_summary = self._proof_gen.generate_summary(record)
                    return record
        return None

    def get_attestation_count(
        self,
        user_address: str,
        category: Optional[str] = None,
    ) -> int:
        """Get total attestation count for a user."""
        records = self._fetch_user_attestations(user_address)
        if category:
            return sum(1 for r in records if r.category == category)
        return len(records)

    # ------------------------------------------------------------------
    # Public API - Shareable Links
    # ------------------------------------------------------------------

    def create_shareable_link(
        self,
        attestation_uid: str,
        duration_seconds: Optional[int] = None,
    ) -> ShareableLink:
        """Create a shareable verification link for an attestation.

        Args:
            attestation_uid: The attestation to share.
            duration_seconds: Optional expiry time for the link.

        Returns:
            ShareableLink with the verification URL.
        """
        verification_code = hashlib.sha256(
            f"{attestation_uid}:{time.time()}".encode()
        ).hexdigest()[:16]

        url = f"{self._base_url}/{attestation_uid}"

        link = ShareableLink(
            attestation_uid=attestation_uid,
            url=url,
            verification_code=verification_code,
            expires_at=(
                time.time() + duration_seconds if duration_seconds else None
            ),
        )
        self._shared_links[verification_code] = link

        logger.info(
            "Shareable link created for %s (code=%s, expires=%s)",
            attestation_uid, verification_code,
            link.expires_at or "never",
        )
        return link

    def verify_shareable_link(self, verification_code: str) -> Optional[AttestationRecord]:
        """Verify a shareable link and return the attestation.

        Args:
            verification_code: The verification code from the link.

        Returns:
            AttestationRecord if valid, None if expired or not found.
        """
        link = self._shared_links.get(verification_code)
        if link is None:
            return None

        if link.expires_at and time.time() > link.expires_at:
            logger.info("Shareable link %s has expired", verification_code)
            return None

        link.access_count += 1
        return self.get_attestation(link.attestation_uid)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _fetch_user_attestations(
        self, user_address: str
    ) -> List[AttestationRecord]:
        """Fetch and cache attestations for a user."""
        if user_address in self._attestation_cache:
            return self._attestation_cache[user_address]

        records: List[AttestationRecord] = []
        if self._eas:
            try:
                raw = self._eas.get_attestations_for(user_address)
                for item in raw:
                    records.append(AttestationRecord(
                        attestation_uid=item.get("uid", ""),
                        schema_uid=item.get("schema", ""),
                        attester=item.get("attester", ""),
                        recipient=item.get("recipient", user_address),
                        data=item.get("data", {}),
                        timestamp=item.get("time", time.time()),
                        revoked=item.get("revoked", False),
                        tx_hash=item.get("txid"),
                        source_component=item.get("source_component"),
                        category=item.get("category", ""),
                    ))
            except Exception as exc:
                logger.warning("Failed to fetch attestations for %s: %s", user_address, exc)

        self._attestation_cache[user_address] = records
        return records

    def invalidate_cache(self, user_address: Optional[str] = None) -> None:
        """Invalidate the attestation cache.

        Args:
            user_address: Optional specific user to invalidate.
                If None, invalidates all cached data.
        """
        if user_address:
            self._attestation_cache.pop(user_address, None)
        else:
            self._attestation_cache.clear()
