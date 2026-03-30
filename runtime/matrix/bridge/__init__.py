"""
Matrix-to-0pnMatrx Bridge Package.

Provides the complete bridge pipeline for exporting proven Matrix components
to the 0pnMatrx public runtime and packaging them for the MTRX iOS app.

Pipeline:
    1. ComponentExporter   — strips private refs, security layers, routing
    2. SanitizationValidator — scans for forbidden patterns, halts on violation
    3. ApprovalGate        — blocks until explicit Dardan approval via Telegram
    4. ManifestManager     — tracks every export in manifest.json
    5. OpnMatrxDeployer    — deploys to 0pnMatrx runtime
    6. EASBridgeAttestor   — attests exports/deployments via EAS Schema 348
    7. MTRXPackager        — packages for MTRX iOS app (closed-source)
    8. TelegramNotifier    — centralised Telegram messaging

Constants:
    NEOSAFE_ADDRESS  = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
    DARDAN_TELEGRAM_ID = 7161847911
"""

from runtime.matrix.bridge.exporter import ComponentExporter, ExportPackage
from runtime.matrix.bridge.sanitizer import (
    SanitizationError,
    SanitizationResult,
    SanitizationValidator,
    Violation,
)
from runtime.matrix.bridge.approval_gate import ApprovalGate
from runtime.matrix.bridge.manifest_manager import ManifestEntry, ManifestManager
from runtime.matrix.bridge.deployer import DeploymentResult, OpnMatrxDeployer
from runtime.matrix.bridge.eas_bridge import (
    AttestationRecord,
    EASBridgeAttestor,
)
from runtime.matrix.bridge.mtrx_packager import (
    IOSComponent,
    IOSPackageConfig,
    IOSPackageResult,
    MTRXPackager,
)
from runtime.matrix.bridge.telegram_notifier import TelegramNotifier, TelegramResponse

# ── Constants ──────────────────────────────────────────────────────────────────
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
DARDAN_TELEGRAM_ID: int = 7161847911

__all__ = [
    # Core pipeline
    "ComponentExporter",
    "ExportPackage",
    "SanitizationValidator",
    "SanitizationResult",
    "SanitizationError",
    "Violation",
    "ApprovalGate",
    "ManifestManager",
    "ManifestEntry",
    "OpnMatrxDeployer",
    "DeploymentResult",
    "EASBridgeAttestor",
    "AttestationRecord",
    "MTRXPackager",
    "IOSPackageConfig",
    "IOSPackageResult",
    "IOSComponent",
    "TelegramNotifier",
    "TelegramResponse",
    # Constants
    "NEOSAFE_ADDRESS",
    "DARDAN_TELEGRAM_ID",
]
