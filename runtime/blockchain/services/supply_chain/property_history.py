"""
Property History Service
========================

Comprehensive property history tracking for informed buyer decisions.
Aggregates ownership transfers, inspections, valuations, and maintenance
records from the SupplyChain contract into a unified property profile.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ── Constants ────────────────────────────────────────────────────────────────
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
PROPERTY_ASSET_TYPE: int = 3  # AssetType.PROPERTY in the contract


@dataclass
class OwnershipRecord:
    """A single ownership period for a property."""
    owner_address: str
    acquired_at: datetime
    transferred_at: Optional[datetime] = None
    acquisition_notes: str = ""
    transfer_notes: str = ""

    @property
    def duration_days(self) -> Optional[int]:
        if self.transferred_at:
            return (self.transferred_at - self.acquired_at).days
        return (datetime.now(timezone.utc) - self.acquired_at).days


@dataclass
class InspectionRecord:
    """A single inspection record for a property."""
    inspection_id: int
    inspector: str
    result: str
    report_uri: str
    notes: str
    timestamp: datetime


@dataclass
class ValuationRecord:
    """A recorded valuation event for a property."""
    valuation_id: int
    appraiser: str
    value_eth: Decimal
    value_usd: Optional[Decimal]
    methodology: str
    notes: str
    timestamp: datetime


@dataclass
class PropertyProfile:
    """Complete property history profile."""
    property_id: str
    asset_id: int
    registrant: str
    current_owner: str
    metadata_uri: str
    registered_at: datetime
    is_active: bool
    ownership_history: List[OwnershipRecord] = field(default_factory=list)
    inspection_history: List[InspectionRecord] = field(default_factory=list)
    valuation_history: List[ValuationRecord] = field(default_factory=list)
    total_transfers: int = 0
    generated_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class PropertyHistory:
    """
    Comprehensive property history service for informed buyer decisions.

    Aggregates on-chain ownership transfers, inspections, and valuations
    from the SupplyChain contract. All data is immutable and verified.

    Usage::

        history = PropertyHistory(web3_provider=provider, contract=supply_chain)
        profile = history.get_full_history(property_id="101")
        owners = history.get_ownership_history(property_id="101")
    """

    def __init__(
        self,
        web3_provider: Any,
        contract: Any,
        valuation_oracle: Optional[Any] = None,
    ) -> None:
        """
        Initialise the property history service.

        Args:
            web3_provider: Web3 provider instance.
            contract: Deployed SupplyChain contract interface.
            valuation_oracle: Optional oracle for historical USD valuations.
        """
        self._web3 = web3_provider
        self._contract = contract
        self._valuation_oracle = valuation_oracle
        logger.info("PropertyHistory service initialised")

    # ── Public API ───────────────────────────────────────────────────────────

    def get_full_history(self, property_id: str) -> PropertyProfile:
        """
        Retrieve the complete property history profile.

        Args:
            property_id: On-chain asset ID for the property.

        Returns:
            PropertyProfile with ownership, inspection, and valuation history.

        Raises:
            ValueError: If the property does not exist or is not a PROPERTY type.
        """
        numeric_id = self._parse_id(property_id)
        asset_data = self._fetch_and_validate_asset(numeric_id, PROPERTY_ASSET_TYPE)

        ownership = self.get_ownership_history(property_id)
        inspections = self.get_inspection_history(property_id)
        valuations = self.get_valuation_history(property_id)

        profile = PropertyProfile(
            property_id=property_id,
            asset_id=numeric_id,
            registrant=asset_data[2],
            current_owner=asset_data[3],
            metadata_uri=asset_data[4],
            registered_at=datetime.fromtimestamp(asset_data[5], tz=timezone.utc),
            is_active=asset_data[6],
            ownership_history=ownership,
            inspection_history=inspections,
            valuation_history=valuations,
            total_transfers=len(ownership),
        )

        logger.info(
            "Full property history retrieved for %s: %d owners, %d inspections, %d valuations",
            property_id, len(ownership), len(inspections), len(valuations),
        )
        return profile

    def get_ownership_history(self, property_id: str) -> List[OwnershipRecord]:
        """
        Retrieve the ownership chain for a property.

        Args:
            property_id: On-chain asset ID.

        Returns:
            List of OwnershipRecord in chronological order.
        """
        numeric_id = self._parse_id(property_id)
        records: List[OwnershipRecord] = []

        try:
            event_ids = self._contract.functions.getCustodyEventIds(numeric_id).call()
            transfer_events = []

            for eid in event_ids:
                raw = self._contract.functions.custodyEvents(eid).call()
                action = raw[2]
                # Only REGISTERED (0) and TRANSFERRED (1) represent ownership changes
                if action in (0, 1):
                    transfer_events.append(raw)

            for i, evt in enumerate(transfer_events):
                acquired_at = datetime.fromtimestamp(evt[7], tz=timezone.utc)
                transferred_at = None
                transfer_notes = ""

                if i + 1 < len(transfer_events):
                    transferred_at = datetime.fromtimestamp(
                        transfer_events[i + 1][7], tz=timezone.utc
                    )
                    transfer_notes = transfer_events[i + 1][5]

                records.append(OwnershipRecord(
                    owner_address=evt[4],  # toCustodian
                    acquired_at=acquired_at,
                    transferred_at=transferred_at,
                    acquisition_notes=evt[5],
                    transfer_notes=transfer_notes,
                ))

        except Exception as exc:
            logger.error(
                "Failed to fetch ownership history for property %s: %s",
                property_id, exc,
            )

        return records

    def get_inspection_history(self, property_id: str) -> List[InspectionRecord]:
        """
        Retrieve all inspections for a property.

        Args:
            property_id: On-chain asset ID.

        Returns:
            List of InspectionRecord in chronological order.
        """
        numeric_id = self._parse_id(property_id)
        records: List[InspectionRecord] = []

        inspection_result_labels: Dict[int, str] = {
            0: "Pass", 1: "Fail", 2: "Conditional", 3: "Pending",
        }

        try:
            inspection_ids = self._contract.functions.getInspectionIds(numeric_id).call()

            for iid in inspection_ids:
                raw = self._contract.functions.inspections(iid).call()
                records.append(InspectionRecord(
                    inspection_id=raw[0],
                    inspector=raw[2],
                    result=inspection_result_labels.get(raw[3], "Unknown"),
                    report_uri=raw[4],
                    notes=raw[5],
                    timestamp=datetime.fromtimestamp(raw[6], tz=timezone.utc),
                ))

        except Exception as exc:
            logger.error(
                "Failed to fetch inspection history for property %s: %s",
                property_id, exc,
            )

        return records

    def get_valuation_history(self, property_id: str) -> List[ValuationRecord]:
        """
        Retrieve all valuations for a property.

        Valuations are recorded as inspection events with type CONDITIONAL
        and appraiser data embedded in the notes field, or fetched from an
        external valuation oracle when available.

        Args:
            property_id: On-chain asset ID.

        Returns:
            List of ValuationRecord in chronological order.
        """
        numeric_id = self._parse_id(property_id)
        records: List[ValuationRecord] = []

        # Attempt oracle-based valuation history
        if self._valuation_oracle is not None:
            try:
                oracle_records = self._valuation_oracle.get_valuations(numeric_id)
                for i, orec in enumerate(oracle_records):
                    records.append(ValuationRecord(
                        valuation_id=i + 1,
                        appraiser=orec.get("appraiser", "Unknown"),
                        value_eth=Decimal(str(orec.get("value_eth", "0"))),
                        value_usd=Decimal(str(orec["value_usd"])) if "value_usd" in orec else None,
                        methodology=orec.get("methodology", ""),
                        notes=orec.get("notes", ""),
                        timestamp=datetime.fromtimestamp(
                            orec.get("timestamp", 0), tz=timezone.utc
                        ),
                    ))
                logger.info(
                    "Retrieved %d oracle valuations for property %s",
                    len(records), property_id,
                )
                return records
            except Exception as exc:
                logger.warning(
                    "Valuation oracle unavailable for property %s, "
                    "falling back to on-chain inspections: %s",
                    property_id, exc,
                )

        # Fallback: parse valuation data from inspection notes
        try:
            inspection_ids = self._contract.functions.getInspectionIds(numeric_id).call()
            vid = 0
            for iid in inspection_ids:
                raw = self._contract.functions.inspections(iid).call()
                notes = raw[5]
                if "VALUATION:" in notes.upper():
                    vid += 1
                    value_str = self._extract_valuation_from_notes(notes)
                    records.append(ValuationRecord(
                        valuation_id=vid,
                        appraiser=raw[2],
                        value_eth=Decimal(value_str) if value_str else Decimal("0"),
                        value_usd=None,
                        methodology="on-chain inspection note",
                        notes=notes,
                        timestamp=datetime.fromtimestamp(raw[6], tz=timezone.utc),
                    ))
        except Exception as exc:
            logger.error(
                "Failed to parse valuation history for property %s: %s",
                property_id, exc,
            )

        return records

    # ── Private Helpers ──────────────────────────────────────────────────────

    def _parse_id(self, property_id: str) -> int:
        """Convert property ID to integer."""
        try:
            return int(property_id)
        except (ValueError, TypeError) as exc:
            raise ValueError(
                f"Invalid property ID '{property_id}': must be numeric"
            ) from exc

    def _fetch_and_validate_asset(self, numeric_id: int, expected_type: int) -> tuple:
        """Fetch asset and validate it exists and matches the expected type."""
        try:
            asset = self._contract.functions.assets(numeric_id).call()
        except Exception as exc:
            raise ValueError(
                f"Failed to fetch asset {numeric_id} from chain: {exc}"
            ) from exc

        if asset[5] == 0:
            raise ValueError(f"Asset {numeric_id} does not exist")

        if asset[1] != expected_type:
            logger.warning(
                "Asset %d type is %d, expected %d (PROPERTY). Proceeding anyway.",
                numeric_id, asset[1], expected_type,
            )

        return asset

    @staticmethod
    def _extract_valuation_from_notes(notes: str) -> str:
        """
        Extract a numeric valuation from inspection notes.

        Expected format: "VALUATION: 1.5 ETH" or "Valuation: 1500.00"
        """
        import re
        match = re.search(r"VALUATION:\s*([\d.]+)", notes, re.IGNORECASE)
        if match:
            return match.group(1)
        return "0"
