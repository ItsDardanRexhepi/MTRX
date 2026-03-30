"""
Terms Negotiator — manages bilateral terms negotiation for securities trades.

Part of Component 18 (Securities Token Exchange).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class NegotiationStatus(Enum):
    """Status of a terms negotiation."""
    PROPOSED = "proposed"
    COUNTER_OFFERED = "counter_offered"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    EXPIRED = "expired"
    CANCELLED = "cancelled"


@dataclass
class TradeTerms:
    """Proposed terms for a securities trade."""
    security_token: str
    quantity: int
    price_per_unit_wei: int
    settlement_period_hours: int = 48
    lock_up_days: int = 0
    conditions: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Negotiation:
    """A terms negotiation between two parties."""
    negotiation_id: str
    proposer: str
    counterparty: str
    current_terms: TradeTerms
    status: NegotiationStatus = NegotiationStatus.PROPOSED
    history: List[Dict[str, Any]] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    expires_at: float = 0.0
    accepted_at: Optional[float] = None


class TermsNegotiator:
    """
    Manages bilateral terms negotiation for securities token trades.

    Supports propose -> counter -> accept/reject flow with full
    history tracking and expiry enforcement.
    """

    DEFAULT_EXPIRY_HOURS: int = 72

    def __init__(self) -> None:
        self._negotiations: Dict[str, Negotiation] = {}
        self._counter: int = 0
        logger.info("TermsNegotiator initialised.")

    def propose_terms(
        self,
        proposer: str,
        counterparty: str,
        terms: TradeTerms,
        expiry_hours: int = DEFAULT_EXPIRY_HOURS,
    ) -> Negotiation:
        """
        Propose trade terms to a counterparty.

        Args:
            proposer: Address of the proposing party.
            counterparty: Address of the counterparty.
            terms: The proposed trade terms.
            expiry_hours: Hours until the proposal expires.

        Returns:
            The created Negotiation.
        """
        if proposer == counterparty:
            raise ValueError("Cannot negotiate with yourself.")
        if terms.quantity <= 0 or terms.price_per_unit_wei <= 0:
            raise ValueError("Quantity and price must be positive.")

        self._counter += 1
        neg_id = f"NEG-{self._counter:08d}"
        now = time.time()

        negotiation = Negotiation(
            negotiation_id=neg_id,
            proposer=proposer,
            counterparty=counterparty,
            current_terms=terms,
            expires_at=now + (expiry_hours * 3600),
        )
        negotiation.history.append({
            "action": "proposed",
            "by": proposer,
            "terms": self._terms_to_dict(terms),
            "timestamp": now,
        })

        self._negotiations[neg_id] = negotiation
        logger.info(
            "Terms proposed | neg=%s | %s -> %s | token=%s | qty=%d",
            neg_id, proposer, counterparty, terms.security_token, terms.quantity,
        )
        return negotiation

    def counter_offer(
        self,
        negotiation_id: str,
        from_address: str,
        new_terms: TradeTerms,
    ) -> Negotiation:
        """
        Submit a counter-offer with modified terms.

        Args:
            negotiation_id: The negotiation to counter.
            from_address: Address of the party countering.
            new_terms: The counter-proposed terms.

        Returns:
            Updated Negotiation.
        """
        negotiation = self._get_active_negotiation(negotiation_id)
        self._validate_participant(negotiation, from_address)

        negotiation.current_terms = new_terms
        negotiation.status = NegotiationStatus.COUNTER_OFFERED
        negotiation.history.append({
            "action": "counter_offered",
            "by": from_address,
            "terms": self._terms_to_dict(new_terms),
            "timestamp": time.time(),
        })

        logger.info("Counter-offer on %s by %s.", negotiation_id, from_address)
        return negotiation

    def accept_terms(
        self,
        negotiation_id: str,
        from_address: str,
    ) -> Negotiation:
        """
        Accept the current terms.

        Args:
            negotiation_id: The negotiation to accept.
            from_address: Address of the accepting party.

        Returns:
            Updated Negotiation in ACCEPTED status.
        """
        negotiation = self._get_active_negotiation(negotiation_id)
        self._validate_participant(negotiation, from_address)

        negotiation.status = NegotiationStatus.ACCEPTED
        negotiation.accepted_at = time.time()
        negotiation.history.append({
            "action": "accepted",
            "by": from_address,
            "timestamp": time.time(),
        })

        logger.info("Terms accepted on %s by %s.", negotiation_id, from_address)
        return negotiation

    def reject_terms(
        self,
        negotiation_id: str,
        from_address: str,
        reason: str = "",
    ) -> Negotiation:
        """Reject the current terms."""
        negotiation = self._get_active_negotiation(negotiation_id)
        self._validate_participant(negotiation, from_address)

        negotiation.status = NegotiationStatus.REJECTED
        negotiation.history.append({
            "action": "rejected",
            "by": from_address,
            "reason": reason,
            "timestamp": time.time(),
        })

        logger.info("Terms rejected on %s by %s.", negotiation_id, from_address)
        return negotiation

    def get_negotiation(self, negotiation_id: str) -> Optional[Negotiation]:
        """Get a negotiation by ID."""
        return self._negotiations.get(negotiation_id)

    def get_negotiations_for(self, address: str) -> List[Negotiation]:
        """Get all negotiations involving an address."""
        return [
            n for n in self._negotiations.values()
            if n.proposer == address or n.counterparty == address
        ]

    # ── Internal ──────────────────────────────────────────────────────

    def _get_active_negotiation(self, negotiation_id: str) -> Negotiation:
        """Get a negotiation that is still active."""
        neg = self._negotiations.get(negotiation_id)
        if neg is None:
            raise ValueError(f"Negotiation {negotiation_id} not found.")

        if neg.status in (NegotiationStatus.ACCEPTED, NegotiationStatus.REJECTED,
                          NegotiationStatus.CANCELLED):
            raise ValueError(f"Negotiation {negotiation_id} is already {neg.status.value}.")

        if time.time() > neg.expires_at:
            neg.status = NegotiationStatus.EXPIRED
            raise ValueError(f"Negotiation {negotiation_id} has expired.")

        return neg

    def _validate_participant(self, negotiation: Negotiation, address: str) -> None:
        """Validate that address is a participant."""
        if address not in (negotiation.proposer, negotiation.counterparty):
            raise ValueError(f"Address {address} is not a participant in this negotiation.")

    def _terms_to_dict(self, terms: TradeTerms) -> Dict[str, Any]:
        """Serialize terms for history."""
        return {
            "security_token": terms.security_token,
            "quantity": terms.quantity,
            "price_per_unit_wei": terms.price_per_unit_wei,
            "settlement_period_hours": terms.settlement_period_hours,
            "lock_up_days": terms.lock_up_days,
            "conditions": terms.conditions,
        }
