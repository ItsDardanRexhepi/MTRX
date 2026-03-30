"""
Vehicle History Service
=======================

Comprehensive vehicle history tracking via the SupplyChain contract.
Aggregates ownership transfers, service records, and accident reports
into a unified vehicle profile for buyer transparency.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ── Constants ────────────────────────────────────────────────────────────────
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
VEHICLE_ASSET_TYPE: int = 2  # AssetType.VEHICLE in the contract

# Custody action mapping
ACTION_LABELS: Dict[int, str] = {
    0: "Registered",
    1: "Transferred",
    2: "Inspected",
    3: "Repaired",
    4: "Stored",
    5: "Shipped",
    6: "Delivered",
    7: "Returned",
    8: "Custom",
}


@dataclass
class VehicleOwnershipRecord:
    """A single ownership period for a vehicle."""
    owner_address: str
    acquired_at: datetime
    transferred_at: Optional[datetime] = None
    acquisition_notes: str = ""
    mileage_at_acquisition: Optional[int] = None
    mileage_at_transfer: Optional[int] = None

    @property
    def duration_days(self) -> Optional[int]:
        end = self.transferred_at or datetime.now(timezone.utc)
        return (end - self.acquired_at).days


@dataclass
class ServiceRecord:
    """A service or repair event for a vehicle."""
    event_id: int
    service_type: str
    service_provider: str
    description: str
    mileage: Optional[int]
    cost_eth: Optional[Decimal]
    timestamp: datetime
    report_uri: str = ""


@dataclass
class AccidentRecord:
    """An accident or damage event for a vehicle."""
    event_id: int
    severity: str  # "minor", "moderate", "major", "total_loss"
    description: str
    insurance_claim: bool
    repair_completed: bool
    timestamp: datetime
    report_uri: str = ""


@dataclass
class VehicleProfile:
    """Complete vehicle history profile."""
    vehicle_id: str
    asset_id: int
    vin_hash: Optional[str]
    registrant: str
    current_owner: str
    metadata_uri: str
    registered_at: datetime
    is_active: bool
    ownership_history: List[VehicleOwnershipRecord] = field(default_factory=list)
    service_history: List[ServiceRecord] = field(default_factory=list)
    accident_history: List[AccidentRecord] = field(default_factory=list)
    total_owners: int = 0
    total_services: int = 0
    total_accidents: int = 0
    generated_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class VehicleHistory:
    """
    Comprehensive vehicle history service.

    Aggregates on-chain ownership transfers, service records, and accident
    reports from the SupplyChain contract for full transparency.

    Usage::

        history = VehicleHistory(web3_provider=provider, contract=supply_chain)
        profile = history.get_full_history(vehicle_id="42")
        services = history.get_service_history(vehicle_id="42")
    """

    def __init__(
        self,
        web3_provider: Any,
        contract: Any,
    ) -> None:
        """
        Initialise the vehicle history service.

        Args:
            web3_provider: Web3 provider instance.
            contract: Deployed SupplyChain contract interface.
        """
        self._web3 = web3_provider
        self._contract = contract
        logger.info("VehicleHistory service initialised")

    # ── Public API ───────────────────────────────────────────────────────────

    def get_full_history(self, vehicle_id: str) -> VehicleProfile:
        """
        Retrieve the complete vehicle history profile.

        Args:
            vehicle_id: On-chain asset ID for the vehicle.

        Returns:
            VehicleProfile with ownership, service, and accident history.

        Raises:
            ValueError: If the vehicle does not exist.
        """
        numeric_id = self._parse_id(vehicle_id)
        asset_data = self._fetch_and_validate_asset(numeric_id)

        ownership = self.get_ownership_history(vehicle_id)
        services = self.get_service_history(vehicle_id)
        accidents = self.get_accident_history(vehicle_id)

        profile = VehicleProfile(
            vehicle_id=vehicle_id,
            asset_id=numeric_id,
            vin_hash=self._get_vin_hash(numeric_id),
            registrant=asset_data[2],
            current_owner=asset_data[3],
            metadata_uri=asset_data[4],
            registered_at=datetime.fromtimestamp(asset_data[5], tz=timezone.utc),
            is_active=asset_data[6],
            ownership_history=ownership,
            service_history=services,
            accident_history=accidents,
            total_owners=len(ownership),
            total_services=len(services),
            total_accidents=len(accidents),
        )

        logger.info(
            "Full vehicle history for %s: %d owners, %d services, %d accidents",
            vehicle_id, len(ownership), len(services), len(accidents),
        )
        return profile

    def get_ownership_history(self, vehicle_id: str) -> List[VehicleOwnershipRecord]:
        """
        Retrieve the ownership chain for a vehicle.

        Args:
            vehicle_id: On-chain asset ID.

        Returns:
            List of VehicleOwnershipRecord in chronological order.
        """
        numeric_id = self._parse_id(vehicle_id)
        records: List[VehicleOwnershipRecord] = []

        try:
            event_ids = self._contract.functions.getCustodyEventIds(numeric_id).call()
            transfer_events = []

            for eid in event_ids:
                raw = self._contract.functions.custodyEvents(eid).call()
                action = raw[2]
                if action in (0, 1):  # REGISTERED or TRANSFERRED
                    transfer_events.append(raw)

            for i, evt in enumerate(transfer_events):
                acquired_at = datetime.fromtimestamp(evt[7], tz=timezone.utc)
                transferred_at = None

                if i + 1 < len(transfer_events):
                    transferred_at = datetime.fromtimestamp(
                        transfer_events[i + 1][7], tz=timezone.utc
                    )

                mileage_acq = self._extract_mileage(evt[5])
                mileage_xfer = None
                if i + 1 < len(transfer_events):
                    mileage_xfer = self._extract_mileage(transfer_events[i + 1][5])

                records.append(VehicleOwnershipRecord(
                    owner_address=evt[4],
                    acquired_at=acquired_at,
                    transferred_at=transferred_at,
                    acquisition_notes=evt[5],
                    mileage_at_acquisition=mileage_acq,
                    mileage_at_transfer=mileage_xfer,
                ))

        except Exception as exc:
            logger.error(
                "Failed to fetch ownership history for vehicle %s: %s",
                vehicle_id, exc,
            )

        return records

    def get_service_history(self, vehicle_id: str) -> List[ServiceRecord]:
        """
        Retrieve all service and repair records for a vehicle.

        Service events are identified by CustodyAction.REPAIRED (3) or
        inspections marked as service in their notes.

        Args:
            vehicle_id: On-chain asset ID.

        Returns:
            List of ServiceRecord in chronological order.
        """
        numeric_id = self._parse_id(vehicle_id)
        records: List[ServiceRecord] = []

        try:
            # Fetch repair custody events (action == 3 = REPAIRED)
            event_ids = self._contract.functions.getCustodyEventIds(numeric_id).call()
            for eid in event_ids:
                raw = self._contract.functions.custodyEvents(eid).call()
                if raw[2] == 3:  # REPAIRED
                    records.append(ServiceRecord(
                        event_id=raw[0],
                        service_type=self._classify_service(raw[5]),
                        service_provider=raw[4],  # toCustodian = service provider
                        description=raw[5],
                        mileage=self._extract_mileage(raw[5]),
                        cost_eth=self._extract_cost(raw[5]),
                        timestamp=datetime.fromtimestamp(raw[7], tz=timezone.utc),
                    ))

            # Fetch inspection-based service records
            inspection_ids = self._contract.functions.getInspectionIds(numeric_id).call()
            for iid in inspection_ids:
                raw = self._contract.functions.inspections(iid).call()
                notes = raw[5]
                if self._is_service_inspection(notes):
                    records.append(ServiceRecord(
                        event_id=raw[0],
                        service_type=self._classify_service(notes),
                        service_provider=raw[2],
                        description=notes,
                        mileage=self._extract_mileage(notes),
                        cost_eth=self._extract_cost(notes),
                        timestamp=datetime.fromtimestamp(raw[6], tz=timezone.utc),
                        report_uri=raw[4],
                    ))

            records.sort(key=lambda r: r.timestamp)

        except Exception as exc:
            logger.error(
                "Failed to fetch service history for vehicle %s: %s",
                vehicle_id, exc,
            )

        return records

    def get_accident_history(self, vehicle_id: str) -> List[AccidentRecord]:
        """
        Retrieve all accident and damage records for a vehicle.

        Accident records are identified by keywords in custody event or
        inspection notes (e.g., "ACCIDENT", "DAMAGE", "COLLISION").

        Args:
            vehicle_id: On-chain asset ID.

        Returns:
            List of AccidentRecord in chronological order.
        """
        numeric_id = self._parse_id(vehicle_id)
        records: List[AccidentRecord] = []

        accident_keywords = {"ACCIDENT", "COLLISION", "DAMAGE", "CRASH", "TOTAL_LOSS"}

        try:
            # Check custody events for accident markers
            event_ids = self._contract.functions.getCustodyEventIds(numeric_id).call()
            for eid in event_ids:
                raw = self._contract.functions.custodyEvents(eid).call()
                notes_upper = raw[5].upper()
                if any(kw in notes_upper for kw in accident_keywords):
                    records.append(AccidentRecord(
                        event_id=raw[0],
                        severity=self._classify_severity(raw[5]),
                        description=raw[5],
                        insurance_claim="CLAIM" in notes_upper,
                        repair_completed="REPAIRED" in notes_upper or "FIXED" in notes_upper,
                        timestamp=datetime.fromtimestamp(raw[7], tz=timezone.utc),
                    ))

            # Check inspection records for accident/damage reports
            inspection_ids = self._contract.functions.getInspectionIds(numeric_id).call()
            for iid in inspection_ids:
                raw = self._contract.functions.inspections(iid).call()
                notes_upper = raw[5].upper()
                if any(kw in notes_upper for kw in accident_keywords):
                    records.append(AccidentRecord(
                        event_id=raw[0],
                        severity=self._classify_severity(raw[5]),
                        description=raw[5],
                        insurance_claim="CLAIM" in notes_upper,
                        repair_completed="REPAIRED" in notes_upper or "FIXED" in notes_upper,
                        timestamp=datetime.fromtimestamp(raw[6], tz=timezone.utc),
                        report_uri=raw[4],
                    ))

            records.sort(key=lambda r: r.timestamp)

        except Exception as exc:
            logger.error(
                "Failed to fetch accident history for vehicle %s: %s",
                vehicle_id, exc,
            )

        return records

    # ── Private Helpers ──────────────────────────────────────────────────────

    def _parse_id(self, vehicle_id: str) -> int:
        """Convert vehicle ID to integer."""
        try:
            return int(vehicle_id)
        except (ValueError, TypeError) as exc:
            raise ValueError(
                f"Invalid vehicle ID '{vehicle_id}': must be numeric"
            ) from exc

    def _fetch_and_validate_asset(self, numeric_id: int) -> tuple:
        """Fetch asset and validate it exists."""
        try:
            asset = self._contract.functions.assets(numeric_id).call()
        except Exception as exc:
            raise ValueError(
                f"Failed to fetch vehicle {numeric_id}: {exc}"
            ) from exc

        if asset[5] == 0:
            raise ValueError(f"Vehicle {numeric_id} does not exist")

        if asset[1] != VEHICLE_ASSET_TYPE:
            logger.warning(
                "Asset %d type is %d, expected %d (VEHICLE). Proceeding anyway.",
                numeric_id, asset[1], VEHICLE_ASSET_TYPE,
            )

        return asset

    def _get_vin_hash(self, numeric_id: int) -> Optional[str]:
        """Attempt to retrieve VIN hash from external ref mapping."""
        try:
            # VIN hash would be stored as an external reference
            # This is a reverse lookup; in practice the caller may have it
            return None
        except Exception:
            return None

    @staticmethod
    def _extract_mileage(notes: str) -> Optional[int]:
        """Extract mileage from notes field. Expected: 'MILEAGE:12345' or 'miles:12345'."""
        match = re.search(r"(?:MILEAGE|MILES|ODO)[:\s]*(\d+)", notes, re.IGNORECASE)
        if match:
            return int(match.group(1))
        return None

    @staticmethod
    def _extract_cost(notes: str) -> Optional[Decimal]:
        """Extract cost from notes field. Expected: 'COST:0.5' or 'cost:1.2 ETH'."""
        match = re.search(r"COST[:\s]*([\d.]+)", notes, re.IGNORECASE)
        if match:
            return Decimal(match.group(1))
        return None

    @staticmethod
    def _classify_service(notes: str) -> str:
        """Classify the service type from notes content."""
        notes_upper = notes.upper()
        if "OIL" in notes_upper:
            return "oil_change"
        if "BRAKE" in notes_upper:
            return "brake_service"
        if "TIRE" in notes_upper or "TYRE" in notes_upper:
            return "tire_service"
        if "ENGINE" in notes_upper:
            return "engine_service"
        if "TRANSMISSION" in notes_upper:
            return "transmission_service"
        if "BODY" in notes_upper or "PAINT" in notes_upper:
            return "body_work"
        if "ELECTRICAL" in notes_upper or "BATTERY" in notes_upper:
            return "electrical"
        if "INSPECTION" in notes_upper:
            return "inspection"
        return "general_maintenance"

    @staticmethod
    def _classify_severity(notes: str) -> str:
        """Classify accident severity from notes content."""
        notes_upper = notes.upper()
        if "TOTAL_LOSS" in notes_upper or "TOTAL LOSS" in notes_upper:
            return "total_loss"
        if "MAJOR" in notes_upper or "SEVERE" in notes_upper:
            return "major"
        if "MODERATE" in notes_upper or "SIGNIFICANT" in notes_upper:
            return "moderate"
        return "minor"

    @staticmethod
    def _is_service_inspection(notes: str) -> bool:
        """Determine if an inspection is service-related."""
        service_keywords = {"SERVICE", "MAINTENANCE", "REPAIR", "OIL", "BRAKE", "TIRE"}
        notes_upper = notes.upper()
        return any(kw in notes_upper for kw in service_keywords)
