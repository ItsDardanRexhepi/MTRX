"""
Component Exporter for Matrix-to-0pnMatrx Bridge.

Packages proven Matrix components for export to 0pnMatrx, stripping all
private references, security layers, Matrix routing, and Dardan-specific
configuration. The exported package contains only public-facing logic,
smart contract code, oracle integrations, fee enforcement logic, and
Trinity/Morpheus interface layers.
"""

import logging
import re
from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class ExportPackage:
    """A sanitised, bridge-ready export package."""
    component_name: str
    version: str
    files: Dict[str, str] = field(default_factory=dict)
    sanitizer_result: Optional[Any] = None  # SanitizationResult once scanned
    approval_status: str = "pending"  # pending | approved | rejected


# ── Stripping patterns ─────────────────────────────────────────────────────────
_PRIVATE_REF_PATTERNS: List[re.Pattern] = [
    re.compile(r"#\s*PRIVATE:.*$", re.MULTILINE),
    re.compile(r"DARDAN_PRIVATE_KEY\s*=\s*['\"].*?['\"]", re.IGNORECASE),
    re.compile(r"dardan[\-_]?config\s*=\s*\{.*?\}", re.DOTALL | re.IGNORECASE),
    re.compile(r"personal_wallet_seed\s*=\s*['\"].*?['\"]", re.IGNORECASE),
    re.compile(r"PRIVATE_GOVERNANCE_PATH\s*=\s*['\"].*?['\"]", re.IGNORECASE),
]

_SECURITY_LAYER_PATTERNS: List[re.Pattern] = [
    re.compile(r"from\s+.*?security[\-_]?layer.*?\s+import\s+.*", re.IGNORECASE),
    re.compile(r"import\s+.*?security[\-_]?layer.*", re.IGNORECASE),
    re.compile(r"MatrixSecurityLayer\(.*?\)", re.IGNORECASE),
    re.compile(r"closed[\-_]?source[\-_]?security\s*=.*$", re.MULTILINE | re.IGNORECASE),
    re.compile(r"security[\-_]?layer[\-_]?v\d+\s*[\.\(].*$", re.MULTILINE | re.IGNORECASE),
]

_MATRIX_ROUTING_PATTERNS: List[re.Pattern] = [
    re.compile(r"matrix[\-_]?router\s*[\.\(=].*$", re.MULTILINE | re.IGNORECASE),
    re.compile(r"matrix[\-_]?internal[\-_]?route\s*=.*$", re.MULTILINE | re.IGNORECASE),
    re.compile(r"governance[\-_]?private[\-_]?endpoint\s*=.*$", re.MULTILINE | re.IGNORECASE),
    re.compile(r"MATRIX_CLOSED_ROUTE\s*=.*$", re.MULTILINE | re.IGNORECASE),
    re.compile(r"matrix[\-_]?runtime[\-_]?internal\s*[\.\(].*$", re.MULTILINE | re.IGNORECASE),
]


class ComponentExporter:
    """
    Prepares Matrix components for export to 0pnMatrx.

    The exporter strips all Matrix-specific references, private governance
    paths, closed-source security layer dependencies, and Dardan-specific
    configuration from each component before packaging.
    """

    def __init__(self, component_registry: Optional[Dict[str, Dict[str, str]]] = None) -> None:
        """
        Args:
            component_registry: Mapping of component_name -> {relative_path: content}.
                                Injected by the Matrix runtime at initialisation.
        """
        self.component_registry: Dict[str, Dict[str, str]] = component_registry or {}

    def register_component(self, name: str, files: Dict[str, str]) -> None:
        """Register a component's files for potential export."""
        self.component_registry[name] = files
        logger.info("Registered component '%s' with %d files", name, len(files))

    # ── Public API ─────────────────────────────────────────────────────────

    def prepare_export(self, component_name: str) -> ExportPackage:
        """
        Prepare a component for export by loading its files and creating
        an initial ExportPackage (not yet stripped or sanitised).
        """
        if component_name not in self.component_registry:
            raise ValueError(
                f"Component '{component_name}' not found in registry. "
                f"Available: {list(self.component_registry.keys())}"
            )

        files = deepcopy(self.component_registry[component_name])
        package = ExportPackage(
            component_name=component_name,
            version=datetime.now(timezone.utc).strftime("%Y%m%d.%H%M%S"),
            files=files,
        )
        logger.info(
            "Prepared export package for '%s' (%d files)", component_name, len(files)
        )
        return package

    def strip_private_references(self, package: ExportPackage) -> ExportPackage:
        """Remove all private data references from package files."""
        package.files = self._apply_patterns(package.files, _PRIVATE_REF_PATTERNS)
        logger.info("Stripped private references from '%s'", package.component_name)
        return package

    def strip_security_layer(self, package: ExportPackage) -> ExportPackage:
        """Remove all closed-source security layer dependencies."""
        package.files = self._apply_patterns(package.files, _SECURITY_LAYER_PATTERNS)
        logger.info("Stripped security layer refs from '%s'", package.component_name)
        return package

    def strip_matrix_routing(self, package: ExportPackage) -> ExportPackage:
        """Remove all Matrix-specific internal routing."""
        package.files = self._apply_patterns(package.files, _MATRIX_ROUTING_PATTERNS)
        logger.info("Stripped Matrix routing from '%s'", package.component_name)
        return package

    def package_for_export(self, component_name: str) -> ExportPackage:
        """
        Full pipeline: prepare, strip all private/internal content, and
        run the sanitizer. Returns a clean ExportPackage ready for approval.
        """
        from runtime.matrix.bridge.sanitizer import SanitizationValidator

        package = self.prepare_export(component_name)
        package = self.strip_private_references(package)
        package = self.strip_security_layer(package)
        package = self.strip_matrix_routing(package)

        validator = SanitizationValidator()
        result = validator.scan_package(package)
        package.sanitizer_result = result

        logger.info(
            "Package '%s' ready for export — sanitizer: %s",
            component_name,
            "CLEAN" if result.is_clean else "VIOLATIONS FOUND",
        )
        return package

    # ── Internal helpers ───────────────────────────────────────────────────

    @staticmethod
    def _apply_patterns(
        files: Dict[str, str], patterns: List[re.Pattern]
    ) -> Dict[str, str]:
        """Apply regex patterns to strip matched content from all files."""
        cleaned: Dict[str, str] = {}
        for path, content in files.items():
            for pattern in patterns:
                content = pattern.sub("# [STRIPPED BY BRIDGE EXPORTER]", content)
            cleaned[path] = content
        return cleaned
