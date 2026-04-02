"""
Policy Registry
================

Tracks all active insurance policies on 0pnMatrx. Supports registration,
deregistration, lookup by user or coverage type, coverage amount tracking,
expiry date management, and claim history per policy.
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


class PolicyStatus(Enum):
    """Lifecycle status of an insurance policy."""
    ACTIVE = "active"
    EXPIRED = "expired"
    CANCELLED = "cancelled"
    SUSPENDED = "suspended"
    CLAIM_IN_PROGRESS = "claim_in_progress"


class CoverageType(Enum):
    """Available insurance coverage types."""
    RENTERS = "renters"
    TRAVEL = "travel"
    PARAMETRIC_WEATHER = "parametric_weather"
    FLIGHT_DELAY = "flight_delay"
    PACKAGE_PROTECTION = "package_protection"


@dataclass
class ClaimRecord:
    """Record of a claim made against a policy."""
    claim_id: str
    policy_id: str
    trigger_id: Optional[str] = None
    amount_eth: float = 0.0
    status: str = "pending"
    filed_at: float = field(default_factory=time.time)
    resolved_at: Optional[float] = None
    payout_tx_hash: Optional[str] = None
    attestation_uid: Optional[str] = None
    notes: Optional[str] = None


@dataclass
class InsurancePolicy:
    """An insurance policy record."""
    policy_id: str
    wallet_address: str
    coverage_type: CoverageType
    coverage_amount_eth: float
    premium_eth: float
    status: PolicyStatus = PolicyStatus.ACTIVE
    created_at: float = field(default_factory=time.time)
    expires_at: Optional[float] = None
    cancelled_at: Optional[float] = None
    last_premium_paid_at: Optional[float] = None
    total_premiums_paid_eth: float = 0.0
    total_claims_paid_eth: float = 0.0
    claims: List[ClaimRecord] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def active(self) -> bool:
        """Whether the policy is currently active and not expired."""
        if self.status != PolicyStatus.ACTIVE:
            return False
        if self.expires_at and time.time() > self.expires_at:
            return False
        return True

    def to_dict(self) -> Dict[str, Any]:
        """Serialize the policy to a dictionary."""
        return {
            "policy_id": self.policy_id,
            "wallet_address": self.wallet_address,
            "coverage_type": self.coverage_type.value,
            "coverage_amount": self.coverage_amount_eth,
            "premium_eth": self.premium_eth,
            "status": self.status.value,
            "active": self.active,
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "total_premiums_paid_eth": self.total_premiums_paid_eth,
            "total_claims_paid_eth": self.total_claims_paid_eth,
            "claim_count": len(self.claims),
        }


class PolicyRegistry:
    """Central registry for all insurance policies.

    Manages the full lifecycle: registration, expiry, cancellation,
    claim tracking, and lookups by wallet or coverage type.

    Parameters
    ----------
    eligibility_tracker : Any
        EligibilityTracker to verify wallet eligibility on registration.
    default_policy_duration_days : int
        Default duration for new policies (default 30 days).
    """

    def __init__(
        self,
        eligibility_tracker: Any = None,
        default_policy_duration_days: int = 30,
    ) -> None:
        self._eligibility = eligibility_tracker
        self._default_duration_seconds = default_policy_duration_days * 86400
        self._policies: Dict[str, InsurancePolicy] = {}
        self._by_wallet: Dict[str, List[str]] = {}
        self._by_type: Dict[CoverageType, List[str]] = {}
        logger.info("PolicyRegistry initialised (default_duration=%dd)", default_policy_duration_days)

    def register_policy(
        self,
        wallet_address: str,
        coverage_type: CoverageType,
        coverage_amount_eth: float,
        premium_eth: float,
        duration_days: Optional[int] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> InsurancePolicy:
        """Register a new insurance policy.

        Args:
            wallet_address: The insured wallet address.
            coverage_type: Type of coverage.
            coverage_amount_eth: Maximum coverage in ETH.
            premium_eth: Monthly premium in ETH.
            duration_days: Policy duration (default from config).
            metadata: Optional metadata.

        Returns:
            The registered InsurancePolicy.

        Raises:
            ValueError: If wallet not eligible or duplicate active coverage.
        """
        if self._eligibility and not self._eligibility.is_eligible(wallet_address):
            raise ValueError(f"Wallet {wallet_address} is not eligible for insurance")

        existing = self.get_active_policies(wallet_address=wallet_address, coverage_type=coverage_type)
        if existing:
            raise ValueError(
                f"Wallet {wallet_address} already has active {coverage_type.value} "
                f"coverage (policy {existing[0].policy_id})"
            )

        duration_secs = (duration_days * 86400 if duration_days else self._default_duration_seconds)
        policy = InsurancePolicy(
            policy_id=f"pol-{uuid.uuid4().hex[:12]}",
            wallet_address=wallet_address,
            coverage_type=coverage_type,
            coverage_amount_eth=coverage_amount_eth,
            premium_eth=premium_eth,
            expires_at=time.time() + duration_secs,
            last_premium_paid_at=time.time(),
            total_premiums_paid_eth=premium_eth,
            metadata=metadata or {},
        )
        self._policies[policy.policy_id] = policy
        self._by_wallet.setdefault(wallet_address, []).append(policy.policy_id)
        self._by_type.setdefault(coverage_type, []).append(policy.policy_id)

        logger.info(
            "Policy registered: %s | wallet=%s type=%s coverage=%.4f ETH",
            policy.policy_id, wallet_address, coverage_type.value, coverage_amount_eth,
        )
        return policy

    def deregister_policy(self, policy_id: str, reason: str = "cancelled") -> Optional[InsurancePolicy]:
        """Deregister (cancel) a policy.

        Args:
            policy_id: The policy to deregister.
            reason: Reason for deregistration.

        Returns:
            Updated policy or None if not found.
        """
        policy = self._policies.get(policy_id)
        if policy is None:
            return None
        policy.status = PolicyStatus.CANCELLED
        policy.cancelled_at = time.time()
        logger.info("Policy deregistered: %s (reason=%s)", policy_id, reason)
        return policy

    def renew_policy(
        self, policy_id: str, premium_eth: Optional[float] = None, duration_days: Optional[int] = None,
    ) -> Optional[InsurancePolicy]:
        """Renew an active or expired policy.

        Args:
            policy_id: The policy to renew.
            premium_eth: New premium or keep existing.
            duration_days: Renewal duration or use default.

        Returns:
            Renewed policy or None if not found.
        """
        policy = self._policies.get(policy_id)
        if policy is None or policy.status == PolicyStatus.CANCELLED:
            return None

        duration_secs = (duration_days * 86400 if duration_days else self._default_duration_seconds)
        now = time.time()
        base = max(policy.expires_at or now, now)
        policy.expires_at = base + duration_secs
        policy.status = PolicyStatus.ACTIVE
        policy.last_premium_paid_at = now
        actual_premium = premium_eth if premium_eth is not None else policy.premium_eth
        policy.premium_eth = actual_premium
        policy.total_premiums_paid_eth += actual_premium
        logger.info("Policy renewed: %s | expires=%s", policy_id, time.ctime(policy.expires_at))
        return policy

    def get_policy(self, policy_id: str) -> Optional[Dict[str, Any]]:
        """Get a policy by ID as a dictionary (used by TriggerManager).

        Args:
            policy_id: The policy identifier.

        Returns:
            Policy dict or None.
        """
        policy = self._policies.get(policy_id)
        if policy is None:
            return None
        self._check_expiry(policy)
        return policy.to_dict()

    def get_policy_object(self, policy_id: str) -> Optional[InsurancePolicy]:
        """Get a policy by ID as an InsurancePolicy object."""
        policy = self._policies.get(policy_id)
        if policy:
            self._check_expiry(policy)
        return policy

    def get_policies_by_wallet(self, wallet_address: str) -> List[InsurancePolicy]:
        """Get all policies for a wallet address."""
        policy_ids = self._by_wallet.get(wallet_address, [])
        results = []
        for pid in policy_ids:
            policy = self._policies.get(pid)
            if policy:
                self._check_expiry(policy)
                results.append(policy)
        return results

    def get_policies_by_type(self, coverage_type: CoverageType) -> List[InsurancePolicy]:
        """Get all policies of a given coverage type."""
        policy_ids = self._by_type.get(coverage_type, [])
        results = []
        for pid in policy_ids:
            policy = self._policies.get(pid)
            if policy:
                self._check_expiry(policy)
                results.append(policy)
        return results

    def get_active_policies(
        self,
        wallet_address: Optional[str] = None,
        coverage_type: Optional[CoverageType] = None,
    ) -> List[InsurancePolicy]:
        """Get active policies with optional filters."""
        if wallet_address:
            candidates = self.get_policies_by_wallet(wallet_address)
        elif coverage_type:
            candidates = self.get_policies_by_type(coverage_type)
        else:
            candidates = list(self._policies.values())
            for p in candidates:
                self._check_expiry(p)

        return [
            p for p in candidates
            if p.active
            and (not coverage_type or p.coverage_type == coverage_type)
            and (not wallet_address or p.wallet_address == wallet_address)
        ]

    def record_claim(
        self,
        policy_id: str,
        claim_id: str,
        amount_eth: float,
        trigger_id: Optional[str] = None,
        payout_tx_hash: Optional[str] = None,
        attestation_uid: Optional[str] = None,
    ) -> Optional[ClaimRecord]:
        """Record a claim against a policy.

        Args:
            policy_id: The policy the claim is against.
            claim_id: Unique claim identifier.
            amount_eth: Claim payout amount in ETH.
            trigger_id: Associated trigger ID.
            payout_tx_hash: Blockchain transaction hash.
            attestation_uid: EAS attestation UID.

        Returns:
            ClaimRecord or None if policy not found.
        """
        policy = self._policies.get(policy_id)
        if policy is None:
            return None
        claim = ClaimRecord(
            claim_id=claim_id,
            policy_id=policy_id,
            trigger_id=trigger_id,
            amount_eth=amount_eth,
            status="paid",
            resolved_at=time.time(),
            payout_tx_hash=payout_tx_hash,
            attestation_uid=attestation_uid,
        )
        policy.claims.append(claim)
        policy.total_claims_paid_eth += amount_eth
        logger.info("Claim recorded: %s on policy %s for %.4f ETH", claim_id, policy_id, amount_eth)
        return claim

    def get_claim_history(self, policy_id: str) -> List[ClaimRecord]:
        """Get all claims for a policy."""
        policy = self._policies.get(policy_id)
        return list(policy.claims) if policy else []

    def expire_stale_policies(self) -> List[str]:
        """Scan and mark expired policies. Returns expired policy IDs."""
        expired: List[str] = []
        now = time.time()
        for policy in self._policies.values():
            if policy.status == PolicyStatus.ACTIVE and policy.expires_at and now > policy.expires_at:
                policy.status = PolicyStatus.EXPIRED
                expired.append(policy.policy_id)
        if expired:
            logger.info("Expired %d stale policies", len(expired))
        return expired

    def get_stats(self) -> Dict[str, Any]:
        """Get registry statistics."""
        by_status: Dict[str, int] = {}
        by_type: Dict[str, int] = {}
        total_coverage = 0.0
        total_premiums = 0.0
        total_claims = 0.0
        for policy in self._policies.values():
            self._check_expiry(policy)
            by_status[policy.status.value] = by_status.get(policy.status.value, 0) + 1
            by_type[policy.coverage_type.value] = by_type.get(policy.coverage_type.value, 0) + 1
            if policy.active:
                total_coverage += policy.coverage_amount_eth
            total_premiums += policy.total_premiums_paid_eth
            total_claims += policy.total_claims_paid_eth
        return {
            "total_policies": len(self._policies),
            "by_status": by_status,
            "by_type": by_type,
            "total_active_coverage_eth": total_coverage,
            "total_premiums_collected_eth": total_premiums,
            "total_claims_paid_eth": total_claims,
        }

    def _check_expiry(self, policy: InsurancePolicy) -> None:
        """Check and update policy expiry status."""
        if policy.status == PolicyStatus.ACTIVE and policy.expires_at and time.time() > policy.expires_at:
            policy.status = PolicyStatus.EXPIRED
