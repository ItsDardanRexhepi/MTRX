"""
Component 4 -- Property Tokenizer
===================================

Tokenization engine for real-estate assets.  Converts physical property records
into on-chain token representations with full ownership history and verification.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class PropertyType(Enum):
    RESIDENTIAL = auto()
    COMMERCIAL = auto()
    INDUSTRIAL = auto()
    AGRICULTURAL = auto()
    MIXED_USE = auto()


class TokenStatus(Enum):
    DRAFT = auto()
    VERIFIED = auto()
    TOKENIZED = auto()
    TRANSFERRED = auto()
    DELISTED = auto()


@dataclass
class TokenizedAsset:
    """On-chain representation of a tokenized real-estate property."""

    token_id: str
    asset_type: str
    owner: str
    status: TokenStatus
    metadata: Dict[str, Any]
    created_at: float
    history: List[Dict[str, Any]] = field(default_factory=list)


# ------------------------------------------------------------------ service


class PropertyTokenizer:
    """Tokenizes real-estate properties as on-chain asset representations."""

    def __init__(self) -> None:
        self._tokens: Dict[str, TokenizedAsset] = {}

    def tokenize(self, asset_details: Dict[str, Any]) -> TokenizedAsset:
        """
        Create an on-chain token for a real-estate property.

        Parameters
        ----------
        asset_details : dict
            Required keys: ``owner``, ``address``, ``property_type``.
            Optional: ``valuation``, ``legal_description``, ``parcel_id``.

        Returns
        -------
        TokenizedAsset
        """
        owner = asset_details.get("owner")
        if not owner:
            raise ValueError("Property tokenization requires an owner.")

        token_id = str(uuid.uuid4())
        now = time.time()

        token = TokenizedAsset(
            token_id=token_id,
            asset_type="property",
            owner=owner,
            status=TokenStatus.TOKENIZED,
            metadata={
                "address": asset_details.get("address", ""),
                "property_type": asset_details.get(
                    "property_type", PropertyType.RESIDENTIAL.name
                ),
                "valuation": asset_details.get("valuation"),
                "legal_description": asset_details.get("legal_description", ""),
                "parcel_id": asset_details.get("parcel_id", ""),
                "square_footage": asset_details.get("square_footage"),
                "year_built": asset_details.get("year_built"),
            },
            created_at=now,
            history=[
                {
                    "event": "tokenized",
                    "owner": owner,
                    "timestamp": now,
                }
            ],
        )

        self._tokens[token_id] = token
        return token

    def verify_ownership(self, token_id: str) -> Dict[str, Any]:
        """
        Verify current ownership of a tokenized property.

        Returns
        -------
        dict
            Contains ``token_id``, ``owner``, ``status``, ``verified_at``.
        """
        token = self._get_token(token_id)
        return {
            "token_id": token.token_id,
            "owner": token.owner,
            "status": token.status.name,
            "verified_at": time.time(),
        }

    def transfer_ownership(
        self,
        token_id: str,
        from_party: str,
        to_party: str,
    ) -> TokenizedAsset:
        """
        Transfer property ownership from one party to another.

        Raises
        ------
        PermissionError
            If ``from_party`` does not match the current owner.
        """
        token = self._get_token(token_id)

        if token.owner != from_party:
            raise PermissionError(
                f"Party {from_party} is not the current owner of {token_id}."
            )

        token.owner = to_party
        token.status = TokenStatus.TRANSFERRED
        token.history.append(
            {
                "event": "transferred",
                "from": from_party,
                "to": to_party,
                "timestamp": time.time(),
            }
        )

        return token

    def get_history(self, token_id: str) -> List[Dict[str, Any]]:
        """Return the full ownership and event history for a token."""
        token = self._get_token(token_id)
        return list(token.history)

    # -- internal ---------------------------------------------------------

    def _get_token(self, token_id: str) -> TokenizedAsset:
        token = self._tokens.get(token_id)
        if token is None:
            raise KeyError(f"No tokenized property found with ID {token_id}")
        return token
