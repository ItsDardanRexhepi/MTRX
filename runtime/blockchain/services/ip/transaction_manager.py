"""
Qualifying Transaction Manager — registers and manages transaction types
that qualify for IP royalties per work.

Part of Component 15 (IP and Royalty Management).
Only registered qualifying transaction types trigger royalty distributions.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set

from runtime.blockchain.services.ip.revenue_tracker import TransactionType

logger = logging.getLogger(__name__)


@dataclass
class QualifyingRule:
    """A rule defining a qualifying transaction type for an IP work."""
    ip_id: str
    transaction_type: TransactionType
    added_by: str
    added_at: float = field(default_factory=time.time)
    min_amount_wei: int = 0
    active: bool = True
    rationale: str = ""


@dataclass
class TransactionEvaluation:
    """Result of evaluating whether a transaction qualifies for royalties."""
    qualifies: bool
    ip_id: str
    transaction_type: TransactionType
    amount_wei: int
    reason: str
    matching_rule: Optional[QualifyingRule] = None


class QualifyingTransactionManager:
    """
    Manages registration of qualifying transaction types for IP works.

    Each IP work has a set of registered transaction types. Only transactions
    matching these registered types trigger royalty distribution via the
    RoyaltyDistributor. IP owners register which types of transactions
    (resale, licensing, streaming, etc.) should generate royalties for their work.
    """

    def __init__(self) -> None:
        # ip_id -> dict of TransactionType -> QualifyingRule
        self._rules: Dict[str, Dict[TransactionType, QualifyingRule]] = {}
        # Audit log of all rule changes
        self._audit_log: List[dict] = []
        logger.info("QualifyingTransactionManager initialised.")

    # ── Registration ──────────────────────────────────────────────────

    def register_qualifying_type(
        self,
        ip_id: str,
        transaction_type: TransactionType,
        owner_address: str,
        min_amount_wei: int = 0,
        rationale: str = "",
    ) -> QualifyingRule:
        """
        Register a transaction type as qualifying for royalties on an IP work.

        Args:
            ip_id: Unique identifier for the IP work.
            transaction_type: The transaction type to register.
            owner_address: Address of the IP owner making the registration.
            min_amount_wei: Minimum transaction amount to qualify (0 = no minimum).
            rationale: Optional explanation for why this type qualifies.

        Returns:
            The created QualifyingRule.

        Raises:
            ValueError: If already registered or min_amount is negative.
        """
        if min_amount_wei < 0:
            raise ValueError("Minimum amount cannot be negative.")

        if ip_id not in self._rules:
            self._rules[ip_id] = {}

        if transaction_type in self._rules[ip_id]:
            existing = self._rules[ip_id][transaction_type]
            if existing.active:
                raise ValueError(
                    f"Transaction type {transaction_type.value} is already registered "
                    f"as qualifying for IP {ip_id}."
                )
            # Reactivate previously deactivated rule
            existing.active = True
            existing.min_amount_wei = min_amount_wei
            existing.rationale = rationale
            self._log_audit(ip_id, "reactivated", transaction_type, owner_address)
            logger.info(
                "Reactivated qualifying type %s for IP %s.",
                transaction_type.value, ip_id,
            )
            return existing

        rule = QualifyingRule(
            ip_id=ip_id,
            transaction_type=transaction_type,
            added_by=owner_address,
            min_amount_wei=min_amount_wei,
            rationale=rationale,
        )
        self._rules[ip_id][transaction_type] = rule

        self._log_audit(ip_id, "registered", transaction_type, owner_address)
        logger.info(
            "Registered qualifying type %s for IP %s (min=%d wei).",
            transaction_type.value, ip_id, min_amount_wei,
        )
        return rule

    def deactivate_qualifying_type(
        self,
        ip_id: str,
        transaction_type: TransactionType,
        owner_address: str,
    ) -> None:
        """
        Deactivate a qualifying transaction type (soft delete).

        Args:
            ip_id: The IP work identifier.
            transaction_type: The type to deactivate.
            owner_address: Address of the owner requesting deactivation.

        Raises:
            ValueError: If not registered or not the owner.
        """
        rule = self._get_rule(ip_id, transaction_type)
        if rule.added_by != owner_address:
            raise ValueError(
                f"Only the registering owner ({rule.added_by}) can deactivate."
            )
        rule.active = False
        self._log_audit(ip_id, "deactivated", transaction_type, owner_address)
        logger.info(
            "Deactivated qualifying type %s for IP %s.", transaction_type.value, ip_id,
        )

    # ── Bulk Registration ─────────────────────────────────────────────

    def register_multiple(
        self,
        ip_id: str,
        types: Set[TransactionType],
        owner_address: str,
        min_amount_wei: int = 0,
    ) -> List[QualifyingRule]:
        """
        Register multiple qualifying types at once.

        Args:
            ip_id: The IP work identifier.
            types: Set of transaction types to register.
            owner_address: Address of the IP owner.
            min_amount_wei: Minimum amount for all types.

        Returns:
            List of created QualifyingRule objects.
        """
        rules = []
        for tx_type in types:
            rule = self.register_qualifying_type(
                ip_id=ip_id,
                transaction_type=tx_type,
                owner_address=owner_address,
                min_amount_wei=min_amount_wei,
            )
            rules.append(rule)
        return rules

    # ── Evaluation ────────────────────────────────────────────────────

    def evaluate_transaction(
        self,
        ip_id: str,
        transaction_type: TransactionType,
        amount_wei: int,
    ) -> TransactionEvaluation:
        """
        Evaluate whether a transaction qualifies for royalties.

        Args:
            ip_id: The IP work being transacted.
            transaction_type: The type of the transaction.
            amount_wei: The transaction amount in wei.

        Returns:
            TransactionEvaluation with qualification decision and reason.
        """
        if ip_id not in self._rules:
            return TransactionEvaluation(
                qualifies=False,
                ip_id=ip_id,
                transaction_type=transaction_type,
                amount_wei=amount_wei,
                reason=f"IP {ip_id} has no registered qualifying types.",
            )

        rule = self._rules[ip_id].get(transaction_type)
        if rule is None or not rule.active:
            return TransactionEvaluation(
                qualifies=False,
                ip_id=ip_id,
                transaction_type=transaction_type,
                amount_wei=amount_wei,
                reason=f"Transaction type {transaction_type.value} is not qualifying for IP {ip_id}.",
            )

        if amount_wei < rule.min_amount_wei:
            return TransactionEvaluation(
                qualifies=False,
                ip_id=ip_id,
                transaction_type=transaction_type,
                amount_wei=amount_wei,
                reason=(
                    f"Amount {amount_wei} wei is below minimum {rule.min_amount_wei} wei "
                    f"for type {transaction_type.value}."
                ),
                matching_rule=rule,
            )

        return TransactionEvaluation(
            qualifies=True,
            ip_id=ip_id,
            transaction_type=transaction_type,
            amount_wei=amount_wei,
            reason=f"Transaction qualifies under {transaction_type.value} rule.",
            matching_rule=rule,
        )

    # ── Queries ───────────────────────────────────────────────────────

    def get_qualifying_types(self, ip_id: str) -> Set[TransactionType]:
        """Return the set of active qualifying transaction types for an IP work."""
        if ip_id not in self._rules:
            return set()
        return {
            tx_type for tx_type, rule in self._rules[ip_id].items()
            if rule.active
        }

    def get_rule(self, ip_id: str, transaction_type: TransactionType) -> Optional[QualifyingRule]:
        """Get the rule for a specific type, or None if not registered."""
        if ip_id not in self._rules:
            return None
        rule = self._rules[ip_id].get(transaction_type)
        if rule and rule.active:
            return rule
        return None

    def get_all_rules(self, ip_id: str) -> List[QualifyingRule]:
        """Return all rules (including inactive) for an IP work."""
        if ip_id not in self._rules:
            return []
        return list(self._rules[ip_id].values())

    def get_audit_log(self, ip_id: Optional[str] = None) -> List[dict]:
        """Return the audit log, optionally filtered by IP."""
        if ip_id is None:
            return list(self._audit_log)
        return [entry for entry in self._audit_log if entry["ip_id"] == ip_id]

    # ── Internal ──────────────────────────────────────────────────────

    def _get_rule(self, ip_id: str, transaction_type: TransactionType) -> QualifyingRule:
        """Get a rule or raise if not found."""
        if ip_id not in self._rules or transaction_type not in self._rules[ip_id]:
            raise ValueError(
                f"No rule for type {transaction_type.value} on IP {ip_id}."
            )
        return self._rules[ip_id][transaction_type]

    def _log_audit(
        self,
        ip_id: str,
        action: str,
        transaction_type: TransactionType,
        actor: str,
    ) -> None:
        """Append an entry to the audit log."""
        self._audit_log.append({
            "ip_id": ip_id,
            "action": action,
            "transaction_type": transaction_type.value,
            "actor": actor,
            "timestamp": time.time(),
        })
