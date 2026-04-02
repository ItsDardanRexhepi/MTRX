"""
Claims Processor
==================

Automatic insurance claim processing with zero human intervention.
Oracle trigger -> validate -> calculate -> pay. All payouts come
from ReserveFund active reserves and are attested via Component 8.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class ClaimStatus(Enum):
    PENDING = "pending"
    VALIDATED = "validated"
    PAID = "paid"
    REJECTED = "rejected"
    FAILED = "failed"


class ClaimType(Enum):
    PARAMETRIC_WEATHER = "parametric_weather"
    SMART_CONTRACT_EXPLOIT = "smart_contract_exploit"
    FLIGHT_DELAY = "flight_delay"
    COLLATERAL_LIQUIDATION = "collateral_liquidation"
    STAKING_SLASHING = "staking_slashing"
    DELIVERY_FAILURE = "delivery_failure"


@dataclass
class Claim:
    claim_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    wallet_address: str = ""
    policy_id: str = ""
    claim_type: ClaimType = ClaimType.PARAMETRIC_WEATHER
    status: ClaimStatus = ClaimStatus.PENDING
    trigger_data: Dict[str, Any] = field(default_factory=dict)
    payout_amount_eth: Decimal = Decimal("0")
    coverage_limit_eth: Decimal = Decimal("0")
    created_at: float = field(default_factory=time.time)
    processed_at: Optional[float] = None
    paid_at: Optional[float] = None
    tx_hash: Optional[str] = None
    attestation_uid: Optional[str] = None
    rejection_reason: Optional[str] = None


class ClaimsProcessor:
    """Processes insurance claims automatically with zero human steps.

    Oracle trigger -> validate policy -> calculate payout -> execute.
    """

    def __init__(
        self,
        reserve_fund: Any = None,
        policy_registry: Any = None,
        attestation_service: Any = None,
        oracle_interface: Any = None,
    ) -> None:
        self._reserve_fund = reserve_fund
        self._policy_registry = policy_registry
        self._attestation = attestation_service
        self._oracle = oracle_interface
        self._claims: Dict[str, Claim] = {}
        self._wallet_claims: Dict[str, List[str]] = {}
        logger.info("ClaimsProcessor initialised (zero human intervention)")

    def process_trigger(
        self,
        wallet_address: str,
        policy_id: str,
        claim_type: ClaimType,
        trigger_data: Dict[str, Any],
    ) -> Claim:
        """Process an oracle trigger into an insurance claim.

        Full lifecycle: validate -> calculate -> pay.
        """
        claim = Claim(
            wallet_address=wallet_address,
            policy_id=policy_id,
            claim_type=claim_type,
            trigger_data=trigger_data,
        )
        self._claims[claim.claim_id] = claim
        self._wallet_claims.setdefault(wallet_address, []).append(claim.claim_id)

        logger.info(
            "Processing claim %s (type=%s, wallet=%s)",
            claim.claim_id, claim_type.value, wallet_address,
        )

        if not self._validate_claim(claim):
            return claim
        self._calculate_payout(claim)
        self._execute_payout(claim)
        return claim

    def get_claim(self, claim_id: str) -> Optional[Claim]:
        return self._claims.get(claim_id)

    def get_wallet_claims(self, wallet_address: str) -> List[Claim]:
        claim_ids = self._wallet_claims.get(wallet_address, [])
        return [self._claims[cid] for cid in claim_ids if cid in self._claims]

    def get_stats(self) -> Dict[str, Any]:
        by_status: Dict[str, int] = {}
        by_type: Dict[str, int] = {}
        total_paid = Decimal("0")
        for claim in self._claims.values():
            by_status[claim.status.value] = by_status.get(claim.status.value, 0) + 1
            by_type[claim.claim_type.value] = by_type.get(claim.claim_type.value, 0) + 1
            if claim.status == ClaimStatus.PAID:
                total_paid += claim.payout_amount_eth
        return {
            "total_claims": len(self._claims),
            "by_status": by_status,
            "by_type": by_type,
            "total_paid_eth": str(total_paid),
        }

    def _validate_claim(self, claim: Claim) -> bool:
        if self._policy_registry:
            policy = self._policy_registry.get_policy(claim.policy_id)
            if not policy:
                claim.status = ClaimStatus.REJECTED
                claim.rejection_reason = "Policy not found"
                claim.processed_at = time.time()
                return False
            if policy.status.value != "active":
                claim.status = ClaimStatus.REJECTED
                claim.rejection_reason = f"Policy status is {policy.status.value}"
                claim.processed_at = time.time()
                return False
            claim.coverage_limit_eth = policy.coverage_limit_eth

        if self._oracle and claim.trigger_data:
            try:
                if not self._oracle.verify_trigger(claim.trigger_data):
                    claim.status = ClaimStatus.REJECTED
                    claim.rejection_reason = "Oracle could not verify trigger"
                    claim.processed_at = time.time()
                    return False
            except Exception as exc:
                logger.warning("Oracle verification failed, proceeding: %s", exc)

        claim.status = ClaimStatus.VALIDATED
        claim.processed_at = time.time()
        return True

    def _calculate_payout(self, claim: Claim) -> None:
        trigger = claim.trigger_data
        cap = claim.coverage_limit_eth

        if claim.claim_type == ClaimType.PARAMETRIC_WEATHER:
            severity = Decimal(str(trigger.get("severity", 0.5)))
            claim.payout_amount_eth = min(cap, cap * severity)

        elif claim.claim_type == ClaimType.SMART_CONTRACT_EXPLOIT:
            loss = Decimal(str(trigger.get("loss_eth", 0)))
            claim.payout_amount_eth = min(cap, loss)

        elif claim.claim_type == ClaimType.FLIGHT_DELAY:
            hours = trigger.get("hours_delayed", 0)
            if hours >= 3:
                rate = Decimal("0.25") * min(Decimal(str(hours)), Decimal("12"))
                claim.payout_amount_eth = min(cap, rate)

        elif claim.claim_type == ClaimType.COLLATERAL_LIQUIDATION:
            loss = Decimal(str(trigger.get("liquidation_loss_eth", 0)))
            claim.payout_amount_eth = min(cap, loss * Decimal("0.8"))

        elif claim.claim_type == ClaimType.STAKING_SLASHING:
            slashed = Decimal(str(trigger.get("slashed_eth", 0)))
            claim.payout_amount_eth = min(cap, slashed)

        elif claim.claim_type == ClaimType.DELIVERY_FAILURE:
            value = Decimal(str(trigger.get("item_value_eth", 0)))
            claim.payout_amount_eth = min(cap, value)

        logger.info("Claim %s payout: %.4f ETH", claim.claim_id, claim.payout_amount_eth)

    def _execute_payout(self, claim: Claim) -> None:
        if claim.payout_amount_eth <= Decimal("0"):
            claim.status = ClaimStatus.REJECTED
            claim.rejection_reason = "Calculated payout is zero"
            return

        if self._reserve_fund:
            try:
                tx = self._reserve_fund.process_payout(claim.payout_amount_eth, claim.claim_id)
                if tx:
                    claim.tx_hash = tx.tx_id
                    claim.status = ClaimStatus.PAID
                    claim.paid_at = time.time()
                else:
                    claim.status = ClaimStatus.FAILED
                    return
            except Exception as exc:
                logger.error("Payout failed for %s: %s", claim.claim_id, exc)
                claim.status = ClaimStatus.FAILED
                return
        else:
            claim.status = ClaimStatus.PAID
            claim.paid_at = time.time()

        if self._policy_registry:
            self._policy_registry.record_claim(claim.policy_id)

        if self._attestation:
            try:
                uid = self._attestation.attest_payout(
                    wallet=claim.wallet_address,
                    amount_eth=str(claim.payout_amount_eth),
                    claim_type=claim.claim_type.value,
                    claim_id=claim.claim_id,
                )
                claim.attestation_uid = uid
            except Exception as exc:
                logger.warning("Attestation failed for claim %s: %s", claim.claim_id, exc)

        logger.info("Claim %s PAID: %.4f ETH to %s", claim.claim_id, claim.payout_amount_eth, claim.wallet_address)
