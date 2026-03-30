"""
Selective Disclosure
=====================

Allows users to share specific credentials with specific parties for
defined time windows. Disclosures automatically revoke when the time
window closes. The user retains full control and can manually revoke
at any point.

All disclosure grants are recorded on-chain via EAS attestations so
there is a permanent audit trail of who was granted access and when.
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


class DisclosureStatus(Enum):
    """Lifecycle states for a disclosure grant."""
    ACTIVE = "active"
    EXPIRED = "expired"
    REVOKED_BY_USER = "revoked_by_user"
    REVOKED_BY_SYSTEM = "revoked_by_system"


class DisclosureScope(Enum):
    """What level of credential detail is being disclosed."""
    FULL = "full"
    SUMMARY = "summary"
    BOOLEAN_ONLY = "boolean_only"
    FIELD_SUBSET = "field_subset"


@dataclass
class DisclosureGrant:
    """A time-bounded credential disclosure grant."""
    grant_id: str
    owner_address: str
    recipient_address: str
    credential_ids: List[str]
    scope: DisclosureScope
    disclosed_fields: List[str] = field(default_factory=list)
    granted_at: float = field(default_factory=time.time)
    expires_at: float = 0.0
    status: DisclosureStatus = DisclosureStatus.ACTIVE
    attestation_uid: Optional[str] = None
    revoked_at: Optional[float] = None
    purpose: str = ""
    access_count: int = 0
    max_access_count: Optional[int] = None

    @property
    def is_expired(self) -> bool:
        return time.time() > self.expires_at

    @property
    def is_access_exhausted(self) -> bool:
        if self.max_access_count is None:
            return False
        return self.access_count >= self.max_access_count

    @property
    def is_valid(self) -> bool:
        return (
            self.status == DisclosureStatus.ACTIVE
            and not self.is_expired
            and not self.is_access_exhausted
        )


@dataclass
class AccessAttempt:
    """Record of an attempt to access disclosed credentials."""
    grant_id: str
    requester_address: str
    timestamp: float = field(default_factory=time.time)
    granted: bool = False
    denial_reason: Optional[str] = None


class SelectiveDisclosure:
    """Manages time-bounded, auto-revoking credential disclosures.

    Users choose exactly which credentials to share, with whom, for how
    long, and at what level of detail. Every grant is attested on-chain
    and automatically expires.

    Parameters
    ----------
    credential_vault : Any
        The CredentialVault instance for credential lookups.
    eas_provider : Any
        EAS attestation provider for recording grants.
    """

    def __init__(
        self,
        credential_vault: Any,
        eas_provider: Any = None,
    ) -> None:
        self._vault = credential_vault
        self._eas = eas_provider
        self._grants: Dict[str, DisclosureGrant] = {}
        self._access_log: List[AccessAttempt] = []
        logger.info("SelectiveDisclosure initialised")

    # ------------------------------------------------------------------
    # Public API - Grant management
    # ------------------------------------------------------------------

    def create_grant(
        self,
        owner_address: str,
        recipient_address: str,
        credential_ids: List[str],
        duration_seconds: int,
        scope: DisclosureScope = DisclosureScope.FULL,
        disclosed_fields: Optional[List[str]] = None,
        purpose: str = "",
        max_access_count: Optional[int] = None,
    ) -> DisclosureGrant:
        """Create a new time-bounded disclosure grant.

        The grant allows the recipient to access the specified credentials
        for the given duration. After expiry the grant is automatically
        invalid and no further access is possible.

        Args:
            owner_address: The credential owner granting access.
            recipient_address: The party receiving access.
            credential_ids: Which credentials to disclose.
            duration_seconds: How long the grant is valid.
            scope: Level of detail to disclose.
            disclosed_fields: Specific fields when scope is FIELD_SUBSET.
            purpose: Human-readable reason for the disclosure.
            max_access_count: Optional maximum number of accesses.

        Returns:
            The created DisclosureGrant.

        Raises:
            ValueError: If any credential_id is not found or not active.
        """
        # Validate that all credentials exist and are active
        for cred_id in credential_ids:
            cred = self._vault.retrieve_credential(owner_address, cred_id)
            if cred is None:
                raise ValueError(f"Credential not found: {cred_id}")
            if cred.status.value != "active":
                raise ValueError(f"Credential not active: {cred_id} (status={cred.status.value})")

        if scope == DisclosureScope.FIELD_SUBSET and not disclosed_fields:
            raise ValueError("disclosed_fields required when scope is FIELD_SUBSET")

        grant_id = f"grant-{uuid.uuid4().hex[:16]}"
        now = time.time()

        grant = DisclosureGrant(
            grant_id=grant_id,
            owner_address=owner_address,
            recipient_address=recipient_address,
            credential_ids=credential_ids,
            scope=scope,
            disclosed_fields=disclosed_fields or [],
            granted_at=now,
            expires_at=now + duration_seconds,
            purpose=purpose,
            max_access_count=max_access_count,
        )

        # Attest on-chain
        attestation_uid = self._attest_grant(grant)
        grant.attestation_uid = attestation_uid

        self._grants[grant_id] = grant
        logger.info(
            "Disclosure grant %s created: %s -> %s (%d creds, %ds, scope=%s)",
            grant_id, owner_address, recipient_address,
            len(credential_ids), duration_seconds, scope.value,
        )
        return grant

    def check_access(
        self, grant_id: str, requester_address: str
    ) -> bool:
        """Check whether a requester currently has valid access.

        Automatically expires grants that have exceeded their time window.

        Args:
            grant_id: The disclosure grant identifier.
            requester_address: Address of the party requesting access.

        Returns:
            True if access is currently valid.
        """
        grant = self._grants.get(grant_id)
        if grant is None:
            self._log_access(grant_id, requester_address, False, "Grant not found")
            return False

        # Auto-expire
        self._refresh_grant_status(grant)

        if grant.recipient_address != requester_address:
            self._log_access(grant_id, requester_address, False, "Not the authorised recipient")
            return False

        if not grant.is_valid:
            reason = "Expired" if grant.is_expired else f"Status: {grant.status.value}"
            if grant.is_access_exhausted:
                reason = "Max access count reached"
            self._log_access(grant_id, requester_address, False, reason)
            return False

        grant.access_count += 1
        self._log_access(grant_id, requester_address, True, None)
        return True

    def revoke_grant(self, owner_address: str, grant_id: str) -> bool:
        """Manually revoke a disclosure grant.

        Only the credential owner can revoke their own grants.

        Args:
            owner_address: Must match the grant owner.
            grant_id: The grant to revoke.

        Returns:
            True if revoked, False if not found or not authorised.
        """
        grant = self._grants.get(grant_id)
        if grant is None:
            return False
        if grant.owner_address != owner_address:
            logger.warning(
                "Revoke attempt by %s on grant %s owned by %s",
                owner_address, grant_id, grant.owner_address,
            )
            return False

        grant.status = DisclosureStatus.REVOKED_BY_USER
        grant.revoked_at = time.time()

        # Record revocation on-chain
        self._attest_revocation(grant)

        logger.info("Grant %s revoked by owner %s", grant_id, owner_address)
        return True

    def revoke_all_grants(self, owner_address: str) -> int:
        """Revoke all active grants for a user. Returns count revoked."""
        count = 0
        for grant in self._grants.values():
            if grant.owner_address == owner_address and grant.status == DisclosureStatus.ACTIVE:
                grant.status = DisclosureStatus.REVOKED_BY_USER
                grant.revoked_at = time.time()
                count += 1
        if count > 0:
            logger.info("Revoked %d grants for %s", count, owner_address)
        return count

    def list_active_grants(
        self, owner_address: str
    ) -> List[DisclosureGrant]:
        """List all currently active grants for a user."""
        result: List[DisclosureGrant] = []
        for grant in self._grants.values():
            if grant.owner_address == owner_address:
                self._refresh_grant_status(grant)
                if grant.status == DisclosureStatus.ACTIVE:
                    result.append(grant)
        return result

    def list_received_grants(
        self, recipient_address: str
    ) -> List[DisclosureGrant]:
        """List all grants where the user is the recipient."""
        result: List[DisclosureGrant] = []
        for grant in self._grants.values():
            if grant.recipient_address == recipient_address:
                self._refresh_grant_status(grant)
                if grant.status == DisclosureStatus.ACTIVE:
                    result.append(grant)
        return result

    def get_access_log(
        self, grant_id: Optional[str] = None
    ) -> List[AccessAttempt]:
        """Retrieve the access log, optionally filtered by grant."""
        if grant_id is None:
            return list(self._access_log)
        return [a for a in self._access_log if a.grant_id == grant_id]

    def cleanup_expired(self) -> int:
        """Expire all grants past their time window. Returns count expired."""
        count = 0
        for grant in self._grants.values():
            if grant.status == DisclosureStatus.ACTIVE and grant.is_expired:
                grant.status = DisclosureStatus.EXPIRED
                count += 1
        if count > 0:
            logger.info("Cleaned up %d expired grants", count)
        return count

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _refresh_grant_status(self, grant: DisclosureGrant) -> None:
        """Auto-expire grants that have exceeded their time window."""
        if grant.status == DisclosureStatus.ACTIVE:
            if grant.is_expired:
                grant.status = DisclosureStatus.EXPIRED
            elif grant.is_access_exhausted:
                grant.status = DisclosureStatus.EXPIRED

    def _log_access(
        self,
        grant_id: str,
        requester: str,
        granted: bool,
        reason: Optional[str],
    ) -> None:
        attempt = AccessAttempt(
            grant_id=grant_id,
            requester_address=requester,
            granted=granted,
            denial_reason=reason,
        )
        self._access_log.append(attempt)
        level = logging.DEBUG if granted else logging.WARNING
        logger.log(
            level,
            "Access %s for grant %s by %s%s",
            "GRANTED" if granted else "DENIED",
            grant_id, requester,
            f" ({reason})" if reason else "",
        )

    def _attest_grant(self, grant: DisclosureGrant) -> Optional[str]:
        """Record the disclosure grant as an EAS attestation."""
        if self._eas is None:
            return None
        try:
            return self._eas.attest(
                schema="selective_disclosure_grant",
                data={
                    "grant_id": grant.grant_id,
                    "owner": grant.owner_address,
                    "recipient": grant.recipient_address,
                    "credential_count": len(grant.credential_ids),
                    "scope": grant.scope.value,
                    "expires_at": int(grant.expires_at),
                },
            )
        except Exception as exc:
            logger.warning("Failed to attest grant %s: %s", grant.grant_id, exc)
            return None

    def _attest_revocation(self, grant: DisclosureGrant) -> Optional[str]:
        """Record grant revocation on-chain."""
        if self._eas is None:
            return None
        try:
            return self._eas.revoke(uid=grant.attestation_uid)
        except Exception as exc:
            logger.warning("Failed to attest revocation for %s: %s", grant.grant_id, exc)
            return None
