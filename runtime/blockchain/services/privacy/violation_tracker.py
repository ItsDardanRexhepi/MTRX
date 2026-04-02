"""
Violation Tracker — reports and investigates privacy violations.

Part of Component 23 (Privacy Protection).
Full investigation workflow: report → investigate → verify/dismiss → compensate.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class ViolationStatus(Enum):
    """States of a violation report."""
    REPORTED = "reported"
    UNDER_INVESTIGATION = "under_investigation"
    VERIFIED = "verified"
    DISMISSED = "dismissed"
    COMPENSATED = "compensated"


@dataclass
class ViolationReport:
    """A privacy violation report."""
    violation_id: str
    reporter: str
    violator: str
    commitment_id: str
    evidence_uri: str
    evidence_hash: str
    status: ViolationStatus = ViolationStatus.REPORTED
    reported_at: float = field(default_factory=time.time)
    resolved_at: float = 0.0
    investigator: str = ""
    compensation_amount_wei: int = 0
    affected_users: List[str] = field(default_factory=list)


class ViolationTracker:
    """
    Tracks privacy violations from report through compensation.

    Investigators (authorized addresses) move violations through
    the investigation workflow. Compensation is paid from escrowed
    revenue of the violating entity.
    """

    def __init__(
        self,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._execute = execute_fn
        self._violations: Dict[str, ViolationReport] = {}
        self._investigators: set = set()
        self._escrow: Dict[str, Dict[str, int]] = {}  # entity -> {token -> balance}
        self._counter: int = 0
        logger.info("ViolationTracker initialised.")

    # ── Investigator Management ───────────────────────────────────────

    def add_investigator(self, address: str) -> None:
        """Add an authorized investigator."""
        if not address.startswith("0x"):
            raise ValueError("Invalid address.")
        self._investigators.add(address)
        logger.info("Investigator added | addr=%s", address)

    def remove_investigator(self, address: str) -> None:
        """Remove an investigator."""
        self._investigators.discard(address)
        logger.info("Investigator removed | addr=%s", address)

    # ── Escrow ────────────────────────────────────────────────────────

    def escrow_revenue(
        self, entity: str, token: str, amount_wei: int,
    ) -> int:
        """
        Deposit revenue into escrow for potential compensation.

        Returns:
            New escrow balance.
        """
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")
        self._escrow.setdefault(entity, {})
        self._escrow[entity][token] = self._escrow[entity].get(token, 0) + amount_wei
        balance = self._escrow[entity][token]
        logger.info(
            "Revenue escrowed | entity=%s | token=%s | amount=%d | balance=%d",
            entity, token, amount_wei, balance,
        )
        return balance

    def get_escrow_balance(self, entity: str, token: str) -> int:
        """Get escrow balance for an entity and token."""
        return self._escrow.get(entity, {}).get(token, 0)

    # ── Violation Lifecycle ───────────────────────────────────────────

    def report_violation(
        self,
        reporter: str,
        violator: str,
        commitment_id: str,
        evidence_uri: str,
        evidence_hash: str,
        affected_users: Optional[List[str]] = None,
    ) -> ViolationReport:
        """
        Report a privacy violation.

        Args:
            reporter: Address of the reporter.
            violator: Address of the entity that violated privacy.
            commitment_id: Which commitment was violated.
            evidence_uri: URI of evidence document.
            evidence_hash: Hash of evidence.
            affected_users: List of affected user addresses.

        Returns:
            The created ViolationReport.
        """
        if not reporter.startswith("0x") or not violator.startswith("0x"):
            raise ValueError("Invalid address format.")
        if not evidence_uri:
            raise ValueError("Evidence URI must not be empty.")

        self._counter += 1
        vid = f"VIOL-{self._counter:08d}"

        report = ViolationReport(
            violation_id=vid,
            reporter=reporter,
            violator=violator,
            commitment_id=commitment_id,
            evidence_uri=evidence_uri,
            evidence_hash=evidence_hash,
            affected_users=affected_users or [],
        )
        self._violations[vid] = report

        logger.info(
            "Violation reported | id=%s | reporter=%s | violator=%s",
            vid, reporter, violator,
        )
        return report

    def investigate(self, violation_id: str, investigator: str) -> ViolationReport:
        """Start investigation of a violation."""
        self._check_investigator(investigator)
        v = self._get_violation(violation_id)
        if v.status != ViolationStatus.REPORTED:
            raise ValueError(f"Violation {violation_id} is not in REPORTED status.")

        v.status = ViolationStatus.UNDER_INVESTIGATION
        v.investigator = investigator
        logger.info(
            "Investigation started | id=%s | investigator=%s",
            violation_id, investigator,
        )
        return v

    def verify(
        self, violation_id: str, investigator: str, compensation_wei: int,
    ) -> ViolationReport:
        """Verify a violation and set compensation amount."""
        self._check_investigator(investigator)
        v = self._get_violation(violation_id)
        if v.status != ViolationStatus.UNDER_INVESTIGATION:
            raise ValueError("Can only verify violations under investigation.")
        if compensation_wei < 0:
            raise ValueError("Compensation must be non-negative.")

        v.status = ViolationStatus.VERIFIED
        v.compensation_amount_wei = compensation_wei
        v.resolved_at = time.time()
        logger.info(
            "Violation verified | id=%s | compensation=%d",
            violation_id, compensation_wei,
        )
        return v

    def dismiss(self, violation_id: str, investigator: str) -> ViolationReport:
        """Dismiss a violation report."""
        self._check_investigator(investigator)
        v = self._get_violation(violation_id)
        if v.status not in (ViolationStatus.REPORTED, ViolationStatus.UNDER_INVESTIGATION):
            raise ValueError("Cannot dismiss a resolved violation.")

        v.status = ViolationStatus.DISMISSED
        v.resolved_at = time.time()
        logger.info("Violation dismissed | id=%s", violation_id)
        return v

    def execute_compensation(
        self, violation_id: str, token: str,
    ) -> int:
        """
        Execute compensation from violator's escrow to affected users.

        Returns:
            Total compensation distributed in wei.
        """
        v = self._get_violation(violation_id)
        if v.status != ViolationStatus.VERIFIED:
            raise ValueError("Can only compensate verified violations.")
        if v.compensation_amount_wei <= 0:
            raise ValueError("No compensation amount set.")
        if not v.affected_users:
            raise ValueError("No affected users to compensate.")

        escrow_balance = self.get_escrow_balance(v.violator, token)
        if escrow_balance < v.compensation_amount_wei:
            raise ValueError(
                f"Insufficient escrow: {escrow_balance} < {v.compensation_amount_wei}."
            )

        # Deduct from escrow
        self._escrow[v.violator][token] -= v.compensation_amount_wei

        # Per-user share
        per_user = v.compensation_amount_wei // len(v.affected_users)
        total_distributed = per_user * len(v.affected_users)

        v.status = ViolationStatus.COMPENSATED
        logger.info(
            "Compensation executed | id=%s | total=%d | per_user=%d | users=%d",
            violation_id, total_distributed, per_user, len(v.affected_users),
        )
        return total_distributed

    # ── Queries ───────────────────────────────────────────────────────

    def get_violation(self, violation_id: str) -> Optional[ViolationReport]:
        """Get violation or None."""
        return self._violations.get(violation_id)

    def get_affected_users(self, violation_id: str) -> List[str]:
        """Get affected users for a violation."""
        v = self._violations.get(violation_id)
        return v.affected_users if v else []

    def list_violations(
        self, status: Optional[ViolationStatus] = None,
    ) -> List[ViolationReport]:
        """List violations, optionally filtered by status."""
        violations = list(self._violations.values())
        if status is not None:
            violations = [v for v in violations if v.status == status]
        return violations

    # ── Internal ──────────────────────────────────────────────────────

    def _check_investigator(self, address: str) -> None:
        """Verify address is an authorized investigator."""
        if address not in self._investigators:
            raise ValueError(f"Address {address} is not an authorized investigator.")

    def _get_violation(self, violation_id: str) -> ViolationReport:
        """Get violation or raise."""
        v = self._violations.get(violation_id)
        if v is None:
            raise ValueError(f"Violation {violation_id} not found.")
        return v
