"""
Component 4 -- Vehicle Tokenizer
==================================

Tokenization engine for vehicle assets.  Converts vehicle ownership records
into on-chain token representations with full history tracking.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class VehicleType(Enum):
    AUTOMOBILE = auto()
    MOTORCYCLE = auto()
    TRUCK = auto()
    BOAT = auto()
    AIRCRAFT = auto()
    HEAVY_EQUIPMENT = auto()
    OTHER = auto()


class TokenStatus(Enum):
    DRAFT = auto()
    VERIFIED = auto()
    TOKENIZED = auto()
    TRANSFERRED = auto()
    DELISTED = auto()


@dataclass
class TokenizedAsset:
    """On-chain representation of a tokenized vehicle."""

    token_id: str
    asset_type: str
    owner: str
    status: TokenStatus
    metadata: Dict[str, Any]
    created_at: float
    history: List[Dict[str, Any]] = field(default_factory=list)


# ------------------------------------------------------------------ service


class VehicleTokenizer:
    """Tokenizes vehicles as on-chain asset representations."""

    def __init__(self) -> None:
        self._tokens: Dict[str, TokenizedAsset] = {}

    def tokenize(self, asset_details: Dict[str, Any]) -> TokenizedAsset:
        """
        Create an on-chain token for a vehicle.

        Parameters
        ----------
        asset_details : dict
            Required keys: ``owner``, ``vin`` (or equivalent identifier).
            Optional: ``make``, ``model``, ``year``, ``vehicle_type``,
            ``mileage``, ``valuation``.

        Returns
        -------
        TokenizedAsset
        """
        owner = asset_details.get("owner")
        if not owner:
            raise ValueError("Vehicle tokenization requires an owner.")

        token_id = str(uuid.uuid4())
        now = time.time()

        token = TokenizedAsset(
            token_id=token_id,
            asset_type="vehicle",
            owner=owner,
            status=TokenStatus.TOKENIZED,
            metadata={
                "vin": asset_details.get("vin", ""),
                "make": asset_details.get("make", ""),
                "model": asset_details.get("model", ""),
                "year": asset_details.get("year"),
                "vehicle_type": asset_details.get(
                    "vehicle_type", VehicleType.AUTOMOBILE.name
                ),
                "mileage": asset_details.get("mileage"),
                "color": asset_details.get("color", ""),
                "valuation": asset_details.get("valuation"),
                "registration": asset_details.get("registration", ""),
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
        Verify current ownership of a tokenized vehicle.

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
        Transfer vehicle ownership from one party to another.

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
            raise KeyError(f"No tokenized vehicle found with ID {token_id}")
        return token
