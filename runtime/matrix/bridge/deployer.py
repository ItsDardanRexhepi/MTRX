"""
0pnMatrx Deployer for Matrix-to-0pnMatrx Bridge.

Deploys clean, sanitised, and Dardan-approved packages to the 0pnMatrx
runtime. Confirms deployment success and attests via EAS Schema 348
with note: "bridge-validated and Dardan-approved".
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class DeploymentResult:
    """Outcome of a deployment to 0pnMatrx."""
    component_name: str
    success: bool = False
    deployment_id: Optional[str] = None
    attestation_uid: Optional[str] = None
    error: Optional[str] = None
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class OpnMatrxDeployer:
    """
    Deploys bridge-validated packages to the 0pnMatrx runtime.

    Deployment only proceeds after:
        1. Sanitizer pass (is_clean == True)
        2. Dardan approval (manifest dardan_approval == "approved")
        3. Manifest entry exists

    Post-deployment, the deployer attests via EAS Schema 348.
    """

    def __init__(
        self,
        manifest_manager: Optional[Any] = None,
        eas_attestor: Optional[Any] = None,
        notifier: Optional[Any] = None,
    ) -> None:
        if manifest_manager is None:
            from runtime.matrix.bridge.manifest_manager import ManifestManager
            manifest_manager = ManifestManager()
        if eas_attestor is None:
            from runtime.matrix.bridge.eas_bridge import EASBridgeAttestor
            eas_attestor = EASBridgeAttestor()
        if notifier is None:
            from runtime.matrix.bridge.telegram_notifier import TelegramNotifier
            notifier = TelegramNotifier()

        self.manifest = manifest_manager
        self.eas = eas_attestor
        self.notifier = notifier

    # ── Public API ─────────────────────────────────────────────────────────

    def deploy(self, export_package: Any) -> DeploymentResult:
        """
        Deploy an export package to the 0pnMatrx runtime.

        Pre-conditions enforced:
            - Package must have a clean sanitizer result
            - Manifest entry must exist with dardan_approval == "approved"

        Args:
            export_package: An ExportPackage from the exporter module.

        Returns:
            DeploymentResult with success status and details.
        """
        component_name = export_package.component_name
        result = DeploymentResult(component_name=component_name)

        # ── Guard: sanitizer must have passed ──────────────────────────────
        if export_package.sanitizer_result and not export_package.sanitizer_result.is_clean:
            result.error = (
                f"Cannot deploy '{component_name}': sanitizer found violations"
            )
            logger.error(result.error)
            self.notifier.send_alert(result.error)
            return result

        # ── Guard: must have Dardan approval ───────────────────────────────
        if not self.manifest.is_approved(component_name):
            result.error = (
                f"Cannot deploy '{component_name}': no Dardan approval in manifest"
            )
            logger.error(result.error)
            self.notifier.send_alert(result.error)
            return result

        # ── Deploy to 0pnMatrx runtime ─────────────────────────────────────
        try:
            deployment_id = self._execute_deployment(export_package)
            result.deployment_id = deployment_id
            result.success = True

            # Update manifest
            self.manifest.update_status(component_name, "deployed")

            logger.info(
                "Deployed '%s' to 0pnMatrx (id=%s)", component_name, deployment_id
            )

            # Notify Dardan
            self.notifier.send_message(
                DARDAN_TELEGRAM_ID,
                f"Deployed `{component_name}` to 0pnMatrx (id: `{deployment_id}`)",
            )

        except Exception as exc:
            result.success = False
            result.error = str(exc)
            self.manifest.update_status(component_name, "failed")
            logger.exception("Deployment failed for '%s'", component_name)
            self.notifier.send_alert(
                f"DEPLOYMENT FAILED: `{component_name}` - {exc}"
            )

        return result

    def verify_deployment(self, component_name: str) -> Dict[str, Any]:
        """
        Verify that a component is successfully deployed in 0pnMatrx.

        Returns:
            Dict with verification status and details.
        """
        entry = self.manifest.get_entry(component_name)
        if entry is None:
            return {
                "verified": False,
                "component_name": component_name,
                "error": "No manifest entry found",
            }

        if entry.get("deployment_status") != "deployed":
            return {
                "verified": False,
                "component_name": component_name,
                "status": entry.get("deployment_status"),
                "error": "Component not in 'deployed' state",
            }

        # In production: ping 0pnMatrx runtime to confirm component is live
        logger.info("Deployment verified for '%s'", component_name)
        return {
            "verified": True,
            "component_name": component_name,
            "status": "deployed",
            "export_date": entry.get("export_date"),
        }

    def attest_deployment(self, component_name: str) -> Optional[str]:
        """
        Attest a deployment via EAS Schema 348.

        Note: "bridge-validated and Dardan-approved"

        Returns:
            The attestation UID on success, or None on failure.
        """
        verification = self.verify_deployment(component_name)
        if not verification.get("verified"):
            logger.error(
                "Cannot attest '%s': deployment not verified — %s",
                component_name,
                verification.get("error"),
            )
            return None

        try:
            record = self.eas.attest_deployment(component_name)
            if record.success and record.uid:
                self.manifest.update_status(component_name, "attested")
                logger.info(
                    "Attested deployment of '%s': uid=%s", component_name, record.uid
                )
                self.notifier.send_message(
                    DARDAN_TELEGRAM_ID,
                    f"Attested `{component_name}` via EAS Schema 348: `{record.uid}`\n"
                    f"Note: {record.note}",
                )
                return record.uid
            else:
                logger.error(
                    "Attestation failed for '%s': %s", component_name, record.error
                )
                return None
        except Exception as exc:
            logger.exception("Attestation error for '%s'", component_name)
            return None

    # ── Internal helpers ───────────────────────────────────────────────────

    def _execute_deployment(self, export_package: Any) -> str:
        """
        Execute the actual deployment to 0pnMatrx runtime.

        In production, this would:
            - Connect to the 0pnMatrx runtime API
            - Upload sanitised component files
            - Register component endpoints
            - Return a unique deployment ID

        Returns:
            Deployment ID string.
        """
        import hashlib
        import json

        # Generate deterministic deployment ID from package contents
        content_hash = hashlib.sha256(
            json.dumps(
                {
                    "component": export_package.component_name,
                    "version": export_package.version,
                    "files": list(export_package.files.keys()),
                },
                sort_keys=True,
            ).encode()
        ).hexdigest()[:16]

        deployment_id = f"opnmtrx-{export_package.component_name}-{content_hash}"

        logger.info(
            "Executing 0pnMatrx deployment for '%s' (%d files)",
            export_package.component_name,
            len(export_package.files),
        )

        # Production: push to 0pnMatrx runtime here
        return deployment_id
