"""
Verification UI — Plain-Language Timeline Renderer
====================================================

Converts raw chain-of-custody data from the SupplyChain contract into
clean, human-readable timelines and HTML reports. Designed to be
consumed by front-end verification pages linked from QR codes.
"""

from __future__ import annotations

import html
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ── Constants ────────────────────────────────────────────────────────────────
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Maps on-chain CustodyAction enum values to human-readable labels
CUSTODY_ACTION_LABELS: Dict[int, str] = {
    0: "Registered",
    1: "Transferred",
    2: "Inspected",
    3: "Repaired",
    4: "Stored",
    5: "Shipped",
    6: "Delivered",
    7: "Returned",
    8: "Custom Event",
}

INSPECTION_RESULT_LABELS: Dict[int, str] = {
    0: "Pass",
    1: "Fail",
    2: "Conditional",
    3: "Pending",
}


class EventCategory(Enum):
    """Categories for timeline rendering."""
    CUSTODY = "custody"
    INSPECTION = "inspection"
    REGISTRATION = "registration"
    QR_GENERATED = "qr_generated"


@dataclass
class TimelineEvent:
    """A single event in the asset's timeline."""
    event_id: int
    category: EventCategory
    action_label: str
    description: str
    from_party: Optional[str]
    to_party: Optional[str]
    timestamp: datetime
    notes: str = ""
    location_hash: str = ""
    inspector: Optional[str] = None
    inspection_result: Optional[str] = None
    report_uri: Optional[str] = None

    @property
    def formatted_time(self) -> str:
        """Human-readable timestamp."""
        return self.timestamp.strftime("%B %d, %Y at %I:%M %p UTC")


@dataclass
class Timeline:
    """Complete verified timeline for an asset."""
    asset_id: str
    asset_type: str
    registrant: str
    current_custodian: str
    metadata_uri: str
    registered_at: datetime
    is_active: bool
    events: List[TimelineEvent] = field(default_factory=list)
    total_custody_transfers: int = 0
    total_inspections: int = 0
    generated_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    @property
    def event_count(self) -> int:
        return len(self.events)


# ── Asset type labels ────────────────────────────────────────────────────────
ASSET_TYPE_LABELS: Dict[int, str] = {
    0: "Physical Item",
    1: "Digital Asset",
    2: "Vehicle",
    3: "Property",
    4: "Artwork",
    5: "Collectible",
    6: "Game Item",
    7: "Other",
}


class VerificationUI:
    """
    Converts raw chain-of-custody data from the SupplyChain contract into
    clean plain-language timelines and HTML verification reports.

    Usage::

        ui = VerificationUI(web3_provider=provider, contract=supply_chain_contract)
        timeline = ui.render_timeline(asset_id="42")
        report = ui.generate_html_report(asset_id="42")
    """

    def __init__(
        self,
        web3_provider: Any,
        contract: Any,
    ) -> None:
        """
        Initialise the verification UI renderer.

        Args:
            web3_provider: Web3 provider instance for on-chain reads.
            contract: Deployed SupplyChain contract interface.
        """
        self._web3 = web3_provider
        self._contract = contract
        logger.info("VerificationUI initialised")

    # ── Public API ───────────────────────────────────────────────────────────

    def render_timeline(self, asset_id: str) -> Timeline:
        """
        Build a complete chronological timeline for the given asset.

        Args:
            asset_id: The on-chain asset identifier.

        Returns:
            Timeline dataclass with all events in chronological order.

        Raises:
            ValueError: If the asset does not exist on-chain.
        """
        numeric_id = self._parse_asset_id(asset_id)
        asset_data = self._fetch_asset(numeric_id)

        if asset_data is None:
            raise ValueError(f"Asset '{asset_id}' not found on-chain")

        # Fetch custody events
        custody_events = self._fetch_custody_events(numeric_id)

        # Fetch inspections
        inspection_events = self._fetch_inspection_events(numeric_id)

        # Merge and sort chronologically
        all_events = custody_events + inspection_events
        all_events.sort(key=lambda e: e.timestamp)

        timeline = Timeline(
            asset_id=asset_id,
            asset_type=ASSET_TYPE_LABELS.get(asset_data[1], "Unknown"),
            registrant=asset_data[2],
            current_custodian=asset_data[3],
            metadata_uri=asset_data[4],
            registered_at=datetime.fromtimestamp(asset_data[5], tz=timezone.utc),
            is_active=asset_data[6],
            events=all_events,
            total_custody_transfers=len(custody_events),
            total_inspections=len(inspection_events),
        )

        logger.info(
            "Timeline rendered for asset %s: %d events",
            asset_id, timeline.event_count,
        )
        return timeline

    def format_event(self, event: TimelineEvent) -> str:
        """
        Format a single timeline event as a plain-language string.

        Args:
            event: The timeline event to format.

        Returns:
            Human-readable string describing the event.
        """
        if event.category == EventCategory.INSPECTION:
            result_str = event.inspection_result or "Unknown"
            line = (
                f"[{event.formatted_time}] Inspection by {self._shorten_address(event.inspector)}: "
                f"Result — {result_str}"
            )
            if event.notes:
                line += f". Notes: {event.notes}"
            return line

        if event.category == EventCategory.REGISTRATION:
            return (
                f"[{event.formatted_time}] {event.action_label}: "
                f"Registered by {self._shorten_address(event.to_party)}"
            )

        # Custody transfer
        from_str = self._shorten_address(event.from_party) if event.from_party else "Origin"
        to_str = self._shorten_address(event.to_party) if event.to_party else "Unknown"
        line = (
            f"[{event.formatted_time}] {event.action_label}: "
            f"{from_str} → {to_str}"
        )
        if event.notes:
            line += f". {event.notes}"
        return line

    def generate_html_report(self, asset_id: str) -> str:
        """
        Generate a self-contained HTML verification report for the asset.

        Args:
            asset_id: The on-chain asset identifier.

        Returns:
            HTML string containing the full verification report.

        Raises:
            ValueError: If the asset does not exist on-chain.
        """
        timeline = self.render_timeline(asset_id)
        events_html = "\n".join(
            self._event_to_html(evt) for evt in timeline.events
        )

        status_badge = (
            '<span class="badge active">Active</span>'
            if timeline.is_active
            else '<span class="badge inactive">Inactive</span>'
        )

        report = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Verification Report — Asset {html.escape(asset_id)}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
               max-width: 800px; margin: 0 auto; padding: 20px; background: #f8f9fa; }}
        .header {{ background: #1a1a2e; color: white; padding: 24px; border-radius: 12px;
                   margin-bottom: 24px; }}
        .header h1 {{ margin: 0 0 8px 0; font-size: 1.5rem; }}
        .meta {{ display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
                 background: white; padding: 16px; border-radius: 8px; margin-bottom: 24px;
                 box-shadow: 0 1px 3px rgba(0,0,0,0.1); }}
        .meta-item {{ font-size: 0.9rem; }}
        .meta-label {{ font-weight: 600; color: #555; }}
        .badge {{ padding: 4px 12px; border-radius: 12px; font-size: 0.8rem; font-weight: 600; }}
        .badge.active {{ background: #d4edda; color: #155724; }}
        .badge.inactive {{ background: #f8d7da; color: #721c24; }}
        .timeline {{ position: relative; padding-left: 32px; }}
        .timeline::before {{ content: ''; position: absolute; left: 12px; top: 0;
                             bottom: 0; width: 2px; background: #dee2e6; }}
        .event {{ position: relative; margin-bottom: 20px; background: white;
                  padding: 16px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }}
        .event::before {{ content: ''; position: absolute; left: -26px; top: 20px;
                          width: 12px; height: 12px; border-radius: 50%;
                          background: #1a1a2e; border: 2px solid white; }}
        .event.inspection::before {{ background: #0d6efd; }}
        .event-time {{ font-size: 0.8rem; color: #888; margin-bottom: 4px; }}
        .event-action {{ font-weight: 600; margin-bottom: 4px; }}
        .event-detail {{ font-size: 0.9rem; color: #555; }}
        .footer {{ text-align: center; padding: 20px; font-size: 0.8rem; color: #999; }}
        .verified {{ display: flex; align-items: center; gap: 8px; color: #28a745;
                     font-weight: 600; margin-top: 8px; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Verified Asset Report</h1>
        <p>Asset #{html.escape(asset_id)} — {html.escape(timeline.asset_type)}</p>
        <div class="verified">On-chain verified via 0pnMatrx SupplyChain</div>
    </div>

    <div class="meta">
        <div class="meta-item">
            <div class="meta-label">Status</div>
            {status_badge}
        </div>
        <div class="meta-item">
            <div class="meta-label">Current Custodian</div>
            <div>{html.escape(self._shorten_address(timeline.current_custodian))}</div>
        </div>
        <div class="meta-item">
            <div class="meta-label">Registered</div>
            <div>{timeline.registered_at.strftime('%B %d, %Y')}</div>
        </div>
        <div class="meta-item">
            <div class="meta-label">Total Events</div>
            <div>{timeline.event_count} ({timeline.total_custody_transfers} transfers, {timeline.total_inspections} inspections)</div>
        </div>
    </div>

    <h2>Chain of Custody Timeline</h2>
    <div class="timeline">
        {events_html}
    </div>

    <div class="footer">
        <p>Report generated {html.escape(timeline.generated_at)} by 0pnMatrx Platform</p>
        <p>All data verified on-chain. Tamper-proof and immutable.</p>
    </div>
</body>
</html>"""

        logger.info("HTML report generated for asset %s", asset_id)
        return report

    # ── Private Helpers ──────────────────────────────────────────────────────

    def _parse_asset_id(self, asset_id: str) -> int:
        """Convert asset ID string to integer."""
        try:
            return int(asset_id)
        except (ValueError, TypeError) as exc:
            raise ValueError(f"Invalid asset ID '{asset_id}': must be numeric") from exc

    def _fetch_asset(self, numeric_id: int) -> Optional[tuple]:
        """Fetch asset data from the contract."""
        try:
            asset = self._contract.functions.assets(numeric_id).call()
            if asset[5] == 0:  # registeredAt == 0 means not found
                return None
            return asset
        except Exception as exc:
            logger.error("Failed to fetch asset %d: %s", numeric_id, exc)
            return None

    def _fetch_custody_events(self, numeric_id: int) -> List[TimelineEvent]:
        """Fetch all custody events for an asset."""
        events: List[TimelineEvent] = []
        try:
            event_ids = self._contract.functions.getCustodyEventIds(numeric_id).call()
            for eid in event_ids:
                raw = self._contract.functions.custodyEvents(eid).call()
                action_int = raw[2]
                category = (
                    EventCategory.REGISTRATION
                    if action_int == 0
                    else EventCategory.CUSTODY
                )
                events.append(TimelineEvent(
                    event_id=raw[0],
                    category=category,
                    action_label=CUSTODY_ACTION_LABELS.get(action_int, "Unknown"),
                    description=raw[5],
                    from_party=raw[3],
                    to_party=raw[4],
                    timestamp=datetime.fromtimestamp(raw[7], tz=timezone.utc),
                    notes=raw[5],
                    location_hash=raw[6],
                ))
        except Exception as exc:
            logger.error("Failed to fetch custody events for asset %d: %s", numeric_id, exc)
        return events

    def _fetch_inspection_events(self, numeric_id: int) -> List[TimelineEvent]:
        """Fetch all inspection events for an asset."""
        events: List[TimelineEvent] = []
        try:
            inspection_ids = self._contract.functions.getInspectionIds(numeric_id).call()
            for iid in inspection_ids:
                raw = self._contract.functions.inspections(iid).call()
                result_label = INSPECTION_RESULT_LABELS.get(raw[3], "Unknown")
                events.append(TimelineEvent(
                    event_id=raw[0],
                    category=EventCategory.INSPECTION,
                    action_label="Inspection",
                    description=f"Inspection result: {result_label}",
                    from_party=None,
                    to_party=None,
                    timestamp=datetime.fromtimestamp(raw[6], tz=timezone.utc),
                    notes=raw[5],
                    inspector=raw[2],
                    inspection_result=result_label,
                    report_uri=raw[4],
                ))
        except Exception as exc:
            logger.error("Failed to fetch inspections for asset %d: %s", numeric_id, exc)
        return events

    def _event_to_html(self, event: TimelineEvent) -> str:
        """Render a single timeline event as an HTML block."""
        css_class = "inspection" if event.category == EventCategory.INSPECTION else ""
        details = html.escape(self.format_event(event))

        notes_html = ""
        if event.notes:
            notes_html = f'<div class="event-detail">{html.escape(event.notes)}</div>'

        report_html = ""
        if event.report_uri:
            safe_uri = html.escape(event.report_uri)
            report_html = f'<div class="event-detail"><a href="{safe_uri}">View Report</a></div>'

        return f"""        <div class="event {css_class}">
            <div class="event-time">{html.escape(event.formatted_time)}</div>
            <div class="event-action">{html.escape(event.action_label)}</div>
            <div class="event-detail">{details}</div>
            {notes_html}
            {report_html}
        </div>"""

    @staticmethod
    def _shorten_address(address: Optional[str]) -> str:
        """Shorten an Ethereum address for display."""
        if not address or address == "0x" + "0" * 40:
            return "N/A"
        if len(address) == 42 and address.startswith("0x"):
            return f"{address[:6]}...{address[-4:]}"
        return str(address)
