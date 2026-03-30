"""
Component 4 -- Asset Verifier
===============================

Oracle-backed asset verification and valuation connector.  Uses the
Component 11 oracle interface to obtain independent asset valuations,
verification reports, and appraisal requests.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Dict, List, Optional


# ------------------------------------------------------------------ data models


class VerificationStatus(Enum):
    PENDING = auto()
    VERIFIED = auto()
    FAILED = auto()
    EXPIRED = auto()


class AppraisalStatus(Enum):
    REQUESTED = auto()
    IN_PROGRESS = auto()
    COMPLETED = auto()
    REJECTED = auto()


@dataclass
class VerificationResult:
    """Result of an asset verification check."""

    verification_id: str
    asset_id: str
    status: VerificationStatus
    details: Dict[str, Any]
    verified_at: float
    oracle_source: str


@dataclass
class ValuationResult:
    """Oracle-sourced asset valuation."""

    valuation_id: str
    asset_id: str
    estimated_value: float
    currency: str
    confidence: float  # 0.0 - 1.0
    oracle_source: str
    valued_at: float
    methodology: str


@dataclass
class AppraisalRequest:
    """A pending appraisal request sent to the oracle network."""

    request_id: str
    asset_details: Dict[str, Any]
    status: AppraisalStatus
    requested_at: float
    completed_at: Optional[float] = None
    result: Optional[ValuationResult] = None


# ------------------------------------------------------------------ service


class AssetVerifier:
    """
    Connector to the Component 11 oracle interface for independent asset
    verifications and valuations.
    """

    def __init__(self, oracle_interface: Any = None) -> None:
        """
        Parameters
        ----------
        oracle_interface : Any, optional
            Reference to the Component 11 oracle service.  When ``None`` the
            verifier operates in stub mode for development.
        """
        self._oracle = oracle_interface
        self._verifications: Dict[str, VerificationResult] = {}
        self._valuations: Dict[str, ValuationResult] = {}
        self._appraisals: Dict[str, AppraisalRequest] = {}

    def verify_asset(self, asset_id: str) -> VerificationResult:
        """
        Verify an asset's authenticity and existence through the oracle.

        Parameters
        ----------
        asset_id : str
            The unique identifier of the asset to verify.

        Returns
        -------
        VerificationResult
        """
        verification_id = str(uuid.uuid4())
        now = time.time()

        # Delegate to Component 11 oracle when available
        if self._oracle is not None:
            oracle_data = self._oracle.verify(asset_id)
            status = (
                VerificationStatus.VERIFIED
                if oracle_data.get("valid")
                else VerificationStatus.FAILED
            )
            details = oracle_data
            source = "component_11_oracle"
        else:
            status = VerificationStatus.PENDING
            details = {"message": "Oracle interface not configured; stub mode."}
            source = "stub"

        result = VerificationResult(
            verification_id=verification_id,
            asset_id=asset_id,
            status=status,
            details=details,
            verified_at=now,
            oracle_source=source,
        )

        self._verifications[verification_id] = result
        return result

    def get_valuation(self, asset_id: str) -> ValuationResult:
        """
        Retrieve the latest oracle-sourced valuation for an asset.

        Parameters
        ----------
        asset_id : str
            The unique identifier of the asset.

        Returns
        -------
        ValuationResult
        """
        valuation_id = str(uuid.uuid4())
        now = time.time()

        if self._oracle is not None:
            oracle_data = self._oracle.get_valuation(asset_id)
            result = ValuationResult(
                valuation_id=valuation_id,
                asset_id=asset_id,
                estimated_value=oracle_data.get("value", 0.0),
                currency=oracle_data.get("currency", "USD"),
                confidence=oracle_data.get("confidence", 0.0),
                oracle_source="component_11_oracle",
                valued_at=now,
                methodology=oracle_data.get("methodology", "oracle_consensus"),
            )
        else:
            result = ValuationResult(
                valuation_id=valuation_id,
                asset_id=asset_id,
                estimated_value=0.0,
                currency="USD",
                confidence=0.0,
                oracle_source="stub",
                valued_at=now,
                methodology="stub_pending_oracle",
            )

        self._valuations[valuation_id] = result
        return result

    def request_appraisal(
        self, asset_details: Dict[str, Any]
    ) -> AppraisalRequest:
        """
        Submit an appraisal request to the oracle network.

        Parameters
        ----------
        asset_details : dict
            Full description of the asset to be appraised.

        Returns
        -------
        AppraisalRequest
        """
        request_id = str(uuid.uuid4())
        now = time.time()

        appraisal = AppraisalRequest(
            request_id=request_id,
            asset_details=asset_details,
            status=AppraisalStatus.REQUESTED,
            requested_at=now,
        )

        if self._oracle is not None:
            self._oracle.request_appraisal(request_id, asset_details)
            appraisal.status = AppraisalStatus.IN_PROGRESS

        self._appraisals[request_id] = appraisal
        return appraisal
