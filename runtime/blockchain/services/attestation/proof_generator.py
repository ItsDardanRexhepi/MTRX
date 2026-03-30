"""
Proof Generator
================

Generates plain-language, human-readable summaries of on-chain
attestations. Transforms raw attestation data into understandable
descriptions that non-technical users can read and verify.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class ProofSummary:
    """A human-readable proof summary."""
    attestation_uid: str
    title: str
    plain_language: str
    verified: bool
    verification_note: str
    generated_at: float = field(default_factory=time.time)
    details: Dict[str, str] = field(default_factory=dict)


# Template mapping: category -> (title_template, body_template)
CATEGORY_TEMPLATES: Dict[str, tuple] = {
    "payment": (
        "Payment Confirmation",
        "A payment of {amount} {currency} was processed on {date}. "
        "The transaction was initiated by {requester} and settled on Base."
    ),
    "dispute": (
        "Dispute Filing Record",
        "A dispute was filed on {date} by {requester}. "
        "The dispute has been recorded on-chain and routed for resolution."
    ),
    "insurance_trigger": (
        "Insurance Trigger Event",
        "An insurance trigger event was detected on {date}. "
        "The triggering condition was verified by the oracle system."
    ),
    "insurance_payout": (
        "Insurance Payout Confirmation",
        "An insurance payout of {amount} was automatically processed on {date}. "
        "The payout was triggered by a verified event and settled to {recipient}."
    ),
    "ownership_transfer": (
        "Ownership Transfer Record",
        "An ownership transfer was recorded on {date}. "
        "Ownership moved from {from_owner} to {to_owner} and was permanently "
        "recorded on the blockchain."
    ),
    "identity_verification": (
        "Identity Verification",
        "An identity credential was verified on {date}. "
        "The verification was anchored on-chain without revealing the underlying data."
    ),
    "agent_action": (
        "Agent Action Record",
        "An automated agent action was executed on {date}. "
        "The action was performed by agent {agent_id} and recorded for audit purposes."
    ),
    "governance_vote": (
        "Governance Vote Record",
        "A governance vote was cast on {date} by {requester}. "
        "The vote was recorded on-chain as part of DAO decision-making."
    ),
    "supply_chain_event": (
        "Supply Chain Verification",
        "A supply chain event was recorded on {date}. "
        "The event was permanently added to the asset's chain of custody."
    ),
    "fee_collection": (
        "Fee Collection Record",
        "A platform fee of {amount} was collected on {date} "
        "and routed to the NeoSafe treasury."
    ),
    "credential_anchor": (
        "Credential Anchor",
        "A credential hash was anchored on-chain on {date}. "
        "This proves the credential existed at this time without revealing its contents."
    ),
}


class ProofGenerator:
    """Generates plain-language proof summaries from attestation data.

    Transforms raw on-chain attestation data into readable descriptions
    that any user can understand. Supports all attestation categories
    with appropriate templates.

    Parameters
    ----------
    eas_provider : Any, optional
        EAS provider for fetching additional attestation context.
    """

    def __init__(self, eas_provider: Any = None) -> None:
        self._eas = eas_provider
        self._custom_templates: Dict[str, tuple] = {}
        self._generation_log: List[ProofSummary] = []
        logger.info("ProofGenerator initialised")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def generate_summary(self, attestation: Any) -> str:
        """Generate a plain-language summary for an attestation.

        Args:
            attestation: AttestationRecord or similar object with
                attestation_uid, category, data, timestamp, etc.

        Returns:
            Human-readable summary string.
        """
        proof = self.generate_proof(attestation)
        return proof.plain_language

    def generate_proof(self, attestation: Any) -> ProofSummary:
        """Generate a full proof summary with metadata.

        Args:
            attestation: AttestationRecord or similar object.

        Returns:
            ProofSummary with title, description, and details.
        """
        category = getattr(attestation, "category", "general")
        data = getattr(attestation, "data", {})
        uid = getattr(attestation, "attestation_uid", "unknown")
        timestamp = getattr(attestation, "timestamp", time.time())
        revoked = getattr(attestation, "revoked", False)

        # Format date
        date_str = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime(
            "%B %d, %Y at %H:%M UTC"
        )

        # Get template
        templates = {**CATEGORY_TEMPLATES, **self._custom_templates}
        title_template, body_template = templates.get(
            category,
            ("On-Chain Attestation", "An event was recorded on-chain on {date}."),
        )

        # Build template variables
        template_vars = {
            "date": date_str,
            "requester": data.get("requester", data.get("attester", "a platform user")),
            "recipient": data.get("recipient", "the recipient"),
            "amount": data.get("amount", "an amount"),
            "currency": data.get("currency", "USDC"),
            "from_owner": data.get("from_owner", data.get("from", "the previous owner")),
            "to_owner": data.get("to_owner", data.get("to", "the new owner")),
            "agent_id": data.get("agent_id", "an automated agent"),
        }

        # Generate text
        try:
            title = title_template.format(**template_vars)
            body = body_template.format(**template_vars)
        except KeyError:
            title = title_template
            body = f"An event was recorded on-chain on {date_str}."

        # Add verification note
        if revoked:
            verification_note = "This attestation has been REVOKED and is no longer valid."
            verified = False
        else:
            verification_note = (
                "This attestation is verified on-chain and can be independently "
                "confirmed via the Ethereum Attestation Service on Base."
            )
            verified = True

        # Build detail fields
        details: Dict[str, str] = {
            "Attestation ID": uid,
            "Recorded On": date_str,
            "Category": category.replace("_", " ").title(),
            "Chain": "Base (Chain ID 8453)",
            "Status": "Revoked" if revoked else "Active",
        }
        if data.get("tx_hash"):
            details["Transaction"] = data["tx_hash"]

        proof = ProofSummary(
            attestation_uid=uid,
            title=title,
            plain_language=body,
            verified=verified,
            verification_note=verification_note,
            details=details,
        )
        self._generation_log.append(proof)
        return proof

    def register_template(
        self,
        category: str,
        title_template: str,
        body_template: str,
    ) -> None:
        """Register a custom template for a category.

        Args:
            category: The attestation category.
            title_template: Template string for the title.
            body_template: Template string for the body.
        """
        self._custom_templates[category] = (title_template, body_template)
        logger.info("Custom template registered for category: %s", category)

    def generate_batch_summaries(
        self, attestations: List[Any]
    ) -> List[ProofSummary]:
        """Generate summaries for multiple attestations.

        Args:
            attestations: List of attestation objects.

        Returns:
            List of ProofSummary objects.
        """
        return [self.generate_proof(a) for a in attestations]
