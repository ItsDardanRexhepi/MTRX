"""
Manifest Manager for Matrix-to-0pnMatrx Bridge.

Manages the bridge manifest (manifest.json), tracking every component export
with sanitizer results, approval status, and deployment state. A component
cannot be exported without a manifest entry including explicit approval.
"""

import json
import logging
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

MANIFEST_PATH: Path = Path(__file__).parent / "manifest.json"


@dataclass
class ManifestEntry:
    """A single manifest record for an exported component."""
    component_name: str
    export_date: str
    sanitizer_result: str  # "clean" | "violations_found"
    dardan_approval: str   # "pending" | "approved" | "rejected"
    deployment_status: str  # "pending" | "deployed" | "failed" | "attested"


class ManifestManager:
    """
    Read/write interface for the bridge manifest.

    Enforces the invariant that no component may be exported without a
    manifest entry containing explicit Dardan approval.
    """

    def __init__(self, manifest_path: Optional[Path] = None) -> None:
        self.manifest_path: Path = manifest_path or MANIFEST_PATH

    # ── Public API ─────────────────────────────────────────────────────────

    def load_manifest(self) -> List[Dict[str, Any]]:
        """Load and return the current manifest entries."""
        try:
            with open(self.manifest_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data, list):
                logger.warning("Manifest is not a list; resetting to empty.")
                return []
            return data
        except FileNotFoundError:
            logger.info("Manifest not found at %s; returning empty list.", self.manifest_path)
            return []
        except json.JSONDecodeError:
            logger.error("Corrupt manifest at %s; returning empty list.", self.manifest_path)
            return []

    def add_entry(
        self,
        component_name: str,
        sanitizer_result: str,
        approval: str,
    ) -> ManifestEntry:
        """
        Add a new manifest entry for a component.

        Args:
            component_name: Name of the component being exported.
            sanitizer_result: "clean" or "violations_found".
            approval: "pending", "approved", or "rejected".

        Returns:
            The newly created ManifestEntry.
        """
        entries = self.load_manifest()

        # Prevent duplicate active entries
        for entry in entries:
            if (
                entry.get("component_name") == component_name
                and entry.get("deployment_status") not in ("failed",)
            ):
                logger.warning(
                    "Active manifest entry already exists for '%s'. "
                    "Update it instead of adding a duplicate.",
                    component_name,
                )
                raise ValueError(
                    f"Active manifest entry already exists for '{component_name}'"
                )

        new_entry = ManifestEntry(
            component_name=component_name,
            export_date=datetime.now(timezone.utc).isoformat(),
            sanitizer_result=sanitizer_result,
            dardan_approval=approval,
            deployment_status="pending",
        )

        entries.append(asdict(new_entry))
        self._save(entries)
        logger.info("Added manifest entry for '%s' (approval=%s)", component_name, approval)
        return new_entry

    def get_entry(self, component_name: str) -> Optional[Dict[str, Any]]:
        """Retrieve the latest manifest entry for a component, or None."""
        entries = self.load_manifest()
        for entry in reversed(entries):
            if entry.get("component_name") == component_name:
                return entry
        return None

    def update_status(self, component_name: str, status: str) -> None:
        """
        Update the deployment_status of the latest entry for a component.

        Args:
            status: "pending" | "deployed" | "failed" | "attested"
        """
        entries = self.load_manifest()
        updated = False

        for entry in reversed(entries):
            if entry.get("component_name") == component_name:
                entry["deployment_status"] = status
                updated = True
                break

        if not updated:
            raise KeyError(f"No manifest entry found for '{component_name}'")

        self._save(entries)
        logger.info("Updated '%s' deployment_status to '%s'", component_name, status)

    def is_approved(self, component_name: str) -> bool:
        """
        Check whether a component has explicit Dardan approval.

        A component cannot be exported without dardan_approval == "approved".
        """
        entry = self.get_entry(component_name)
        if entry is None:
            logger.warning("No manifest entry for '%s'; cannot approve.", component_name)
            return False
        return entry.get("dardan_approval") == "approved"

    # ── Internal helpers ───────────────────────────────────────────────────

    def _save(self, entries: List[Dict[str, Any]]) -> None:
        """Persist the manifest to disk."""
        with open(self.manifest_path, "w", encoding="utf-8") as f:
            json.dump(entries, f, indent=2, ensure_ascii=False)
        logger.debug("Manifest saved (%d entries)", len(entries))
