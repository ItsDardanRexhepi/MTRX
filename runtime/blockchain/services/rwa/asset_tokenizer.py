"""
Component 4 -- General Asset Tokenizer
========================================

General-purpose tokenization engine for any real-world asset class not covered
by the specialised property or vehicle tokenizers.  Handles art, machinery,
intellectual property, commodities, and any other tangible or intangible asset.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class AssetCategory(Enum):
    ART = auto()
    MACHINERY = auto()
    INTELLECTUAL_PROPERTY = auto()
    COMMODITY = auto()
    COLLECTIBLE = auto()
    JEWELRY = auto()
    EQUIPMENT = auto()
    OTHER = auto()


class TokenStatus(Enum):
    DRAFT = auto()
    VERIFIED = auto()
    TOKENIZED = auto()
    TRANSFERRED = auto()
    DELISTED = auto()


@dataclass
class TokenizedAsset:
    """On-chain representation of a tokenized general asset."""

    token_id: str
    asset_type: str
    owner: str
    status: TokenStatus
    metadata: Dict[str, Any]
    created_at: float
    history: List[Dict[str, Any]] = field(default_factory=list)


# ------------------------------------------------------------------ service


class AssetTokenizer:
    """General-purpose tokenizer for any real-world asset class."""

    def __init__(self) -> None:
        self._tokens: Dict[str, TokenizedAsset] = {}

    def tokenize(self, asset_details: Dict[str, Any]) -> TokenizedAsset:
        """
        Create an on-chain token for a general asset.

        Parameters
        ----------
        asset_details : dict
            Required keys: ``owner``, ``asset_name``.
            Optional: ``category``, ``description``, ``serial_number``,
            ``valuation``, ``provenance``.

        Returns
        -------
        TokenizedAsset
        """
        owner = asset_details.get("owner")
        if not owner:
            raise ValueError("Asset tokenization requires an owner.")

        asset_name = asset_details.get("asset_name", "Unnamed Asset")
        token_id = str(uuid.uuid4())
        now = time.time()

        token = TokenizedAsset(
            token_id=token_id,
            asset_type="general",
            owner=owner,
            status=TokenStatus.TOKENIZED,
            metadata={
                "asset_name": asset_name,
                "category": asset_details.get(
                    "category", AssetCategory.OTHER.name
                ),
                "description": asset_details.get("description", ""),
                "serial_number": asset_details.get("serial_number", ""),
                "valuation": asset_details.get("valuation"),
                "provenance": asset_details.get("provenance", ""),
                "condition": asset_details.get("condition", ""),
                "location": asset_details.get("location", ""),
            },
            created_at=now,
            history=[
                {
                    "event": "tokenized",
                    "owner": owner,
                    "asset_name": asset_name,
                    "timestamp": now,
                }
            ],
        )

        self._tokens[token_id] = token
        return token

    def verify_ownership(self, token_id: str) -> Dict[str, Any]:
        """
        Verify current ownership of a tokenized asset.

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
        Transfer asset ownership from one party to another.

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
            raise KeyError(f"No tokenized asset found with ID {token_id}")
        return token
