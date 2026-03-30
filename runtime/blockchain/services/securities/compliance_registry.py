"""
Compliance Registry — tracks compliance status for securities participants.

Part of Component 18 (Securities Token Exchange).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


class ComplianceLevel(Enum):
    """Compliance verification levels."""
    NONE = "none"
    BASIC = "basic"
    ACCREDITED = "accredited"
    INSTITUTIONAL = "institutional"
    QUALIFIED_PURCHASER = "qualified_purchaser"


class ComplianceStatus(Enum):
    """Status of a compliance verification."""
    PENDING = "pending"
    VERIFIED = "verified"
    EXPIRED = "expired"
    REVOKED = "revoked"
    SUSPENDED = "suspended"


@dataclass
class ComplianceRecord:
    """Compliance record for a participant."""
    address: str
    level: ComplianceLevel
    status: ComplianceStatus
    jurisdictions: Set[str] = field(default_factory=set)
    verified_at: Optional[float] = None
    expires_at: Optional[float] = None
    verifier: str = ""
    attestation_uid: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class ComplianceRegistry:
    """
    Registry of compliance-verified participants for securities trading.

    Tracks KYC/AML status, accreditation level, and jurisdiction
    clearances for all securities market participants.
    """

    DEFAULT_EXPIRY_DAYS: int = 365

    def __init__(self) -> None:
        self._records: Dict[str, ComplianceRecord] = {}
        self._audit_log: List[Dict[str, Any]] = []
        logger.info("ComplianceRegistry initialised.")

    def register_participant(
        self,
        address: str,
        level: ComplianceLevel,
        jurisdictions: Optional[Set[str]] = None,
        verifier: str = "",
        expiry_days: int = DEFAULT_EXPIRY_DAYS,
    ) -> ComplianceRecord:
        """
        Register or update a participant's compliance record.

        Args:
            address: Participant's Ethereum address.
            level: Compliance level achieved.
            jurisdictions: Set of jurisdictions cleared.
            verifier: Address or name of the verifier.
            expiry_days: Days until verification expires.

        Returns:
            The created or updated ComplianceRecord.
        """
        if not address.startswith("0x"):
            raise ValueError(f"Invalid address: {address}")

        now = time.time()
        record = ComplianceRecord(
            address=address,
            level=level,
            status=ComplianceStatus.VERIFIED,
            jurisdictions=jurisdictions or set(),
            verified_at=now,
            expires_at=now + (expiry_days * 86_400),
            verifier=verifier,
        )
        self._records[address] = record

        self._log_audit(address, "registered", level.value)
        logger.info(
            "Participant registered | addr=%s | level=%s | jurisdictions=%s",
            address, level.value, jurisdictions,
        )
        return record

    def verify_trade_eligibility(
        self,
        buyer: str,
        seller: str,
        security_token: str,
        jurisdiction: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Verify that both parties are eligible to trade a security.

        Args:
            buyer: Buyer's address.
            seller: Seller's address.
            security_token: The security being traded.
            jurisdiction: Required jurisdiction clearance.

        Returns:
            Dict with 'eligible' (bool) and details.
        """
        issues: List[str] = []

        for role, address in [("buyer", buyer), ("seller", seller)]:
            record = self._records.get(address)
            if record is None:
                issues.append(f"{role.capitalize()} {address} is not registered.")
                continue
            if record.status != ComplianceStatus.VERIFIED:
                issues.append(f"{role.capitalize()} status is {record.status.value}.")
                continue
            if record.expires_at and time.time() > record.expires_at:
                record.status = ComplianceStatus.EXPIRED
                issues.append(f"{role.capitalize()} verification has expired.")
                continue
            if jurisdiction and jurisdiction not in record.jurisdictions:
                issues.append(
                    f"{role.capitalize()} not cleared for jurisdiction {jurisdiction}."
                )

        return {
            "eligible": len(issues) == 0,
            "buyer": buyer,
            "seller": seller,
            "security_token": security_token,
            "issues": issues,
        }

    def get_record(self, address: str) -> Optional[ComplianceRecord]:
        """Get a participant's compliance record."""
        return self._records.get(address)

    def revoke(self, address: str, reason: str) -> None:
        """Revoke a participant's compliance status."""
        record = self._records.get(address)
        if record is None:
            raise ValueError(f"No record for {address}.")
        record.status = ComplianceStatus.REVOKED
        self._log_audit(address, "revoked", reason)
        logger.info("Compliance revoked for %s: %s", address, reason)

    def suspend(self, address: str, reason: str) -> None:
        """Suspend a participant pending review."""
        record = self._records.get(address)
        if record is None:
            raise ValueError(f"No record for {address}.")
        record.status = ComplianceStatus.SUSPENDED
        self._log_audit(address, "suspended", reason)
        logger.info("Compliance suspended for %s: %s", address, reason)

    def list_verified(self, level: Optional[ComplianceLevel] = None) -> List[ComplianceRecord]:
        """List all verified participants, optionally filtered by level."""
        results = [
            r for r in self._records.values()
            if r.status == ComplianceStatus.VERIFIED
        ]
        if level is not None:
            results = [r for r in results if r.level == level]
        return results

    def _log_audit(self, address: str, action: str, detail: str) -> None:
        """Append to audit log."""
        self._audit_log.append({
            "address": address,
            "action": action,
            "detail": detail,
            "timestamp": time.time(),
        })
