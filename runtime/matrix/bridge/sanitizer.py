"""
Sanitization Validator for Matrix-to-0pnMatrx Bridge.

Scans export packages for private data, security layer references,
Matrix-specific routing, and closed-source content before any component
is allowed to leave the Matrix perimeter.
"""

import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# ── Forbidden patterns ─────────────────────────────────────────────────────────
# Each tuple: (category, compiled regex, human-readable description)
FORBIDDEN_PATTERNS: List[tuple] = [
    # Private data
    ("private_data", re.compile(r"DARDAN_PRIVATE_KEY", re.IGNORECASE), "Private key reference"),
    ("private_data", re.compile(r"dardan[\-_]?config", re.IGNORECASE), "Dardan-specific config"),
    ("private_data", re.compile(r"personal_wallet_seed", re.IGNORECASE), "Wallet seed reference"),
    ("private_data", re.compile(r"matrix[\-_]?internal[\-_]?secret", re.IGNORECASE), "Internal secret"),
    ("private_data", re.compile(r"PRIVATE_GOVERNANCE_PATH", re.IGNORECASE), "Private governance path"),

    # Security layer references
    ("security_layer", re.compile(r"security[\-_]?layer[\-_]?v\d", re.IGNORECASE), "Security layer version ref"),
    ("security_layer", re.compile(r"closed[\-_]?source[\-_]?security", re.IGNORECASE), "Closed-source security ref"),
    ("security_layer", re.compile(r"matrix[\-_]?security[\-_]?core", re.IGNORECASE), "Matrix security core"),
    ("security_layer", re.compile(r"neo[\-_]?safe[\-_]?internal", re.IGNORECASE), "NeoSafe internal ref"),
    ("security_layer", re.compile(r"MatrixSecurityLayer", re.IGNORECASE), "MatrixSecurityLayer class ref"),

    # Matrix-specific routing
    ("matrix_routing", re.compile(r"matrix[\-_]?router", re.IGNORECASE), "Matrix router reference"),
    ("matrix_routing", re.compile(r"matrix[\-_]?internal[\-_]?route", re.IGNORECASE), "Internal routing path"),
    ("matrix_routing", re.compile(r"governance[\-_]?private[\-_]?endpoint", re.IGNORECASE), "Private governance endpoint"),
    ("matrix_routing", re.compile(r"matrix[\-_]?runtime[\-_]?internal", re.IGNORECASE), "Matrix runtime internal"),
    ("matrix_routing", re.compile(r"MATRIX_CLOSED_ROUTE", re.IGNORECASE), "Closed route constant"),

    # Closed-source content
    ("closed_source", re.compile(r"CLOSED[\-_]?SOURCE[\-_]?ONLY", re.IGNORECASE), "Closed-source marker"),
    ("closed_source", re.compile(r"DO[\-_]?NOT[\-_]?EXPORT", re.IGNORECASE), "Do-not-export marker"),
    ("closed_source", re.compile(r"PROPRIETARY[\-_]?MATRIX", re.IGNORECASE), "Proprietary Matrix marker"),
    ("closed_source", re.compile(r"matrix[\-_]?proprietary", re.IGNORECASE), "Proprietary reference"),
    ("closed_source", re.compile(r"INTERNAL[\-_]?USE[\-_]?ONLY", re.IGNORECASE), "Internal-use marker"),
]


@dataclass
class Violation:
    """A single sanitization violation found in a file."""
    file_path: str
    line_number: int
    category: str
    pattern_description: str
    matched_text: str


@dataclass
class SanitizationResult:
    """Outcome of a full sanitization scan."""
    is_clean: bool
    violations: List[Violation] = field(default_factory=list)
    scanned_files_count: int = 0
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def summary(self) -> str:
        if self.is_clean:
            return (
                f"CLEAN: scanned {self.scanned_files_count} files, "
                f"0 violations at {self.timestamp}"
            )
        grouped: Dict[str, int] = {}
        for v in self.violations:
            grouped[v.category] = grouped.get(v.category, 0) + 1
        breakdown = ", ".join(f"{cat}: {count}" for cat, count in grouped.items())
        return (
            f"VIOLATIONS FOUND: {len(self.violations)} across "
            f"{self.scanned_files_count} files ({breakdown}) at {self.timestamp}"
        )


class SanitizationValidator:
    """
    Scans export packages to ensure no private, security-layer,
    Matrix-routing, or closed-source content leaks into 0pnMatrx exports.
    """

    def __init__(self, extra_patterns: Optional[List[tuple]] = None) -> None:
        self.patterns: List[tuple] = list(FORBIDDEN_PATTERNS)
        if extra_patterns:
            self.patterns.extend(extra_patterns)
        self._notifier = None  # lazy-loaded to avoid circular imports

    def _get_notifier(self):
        if self._notifier is None:
            from runtime.matrix.bridge.telegram_notifier import TelegramNotifier
            self._notifier = TelegramNotifier()
        return self._notifier

    # ── Public API ─────────────────────────────────────────────────────────

    def scan_package(self, package) -> SanitizationResult:
        """
        Full scan of an ExportPackage.

        Args:
            package: An ExportPackage (from exporter module) with a `files`
                     dict mapping relative paths to file content strings.

        Returns:
            SanitizationResult with is_clean=False if any violation found.
        """
        files: Dict[str, str] = package.files if hasattr(package, "files") else package
        all_violations: List[Violation] = []

        all_violations.extend(self.check_private_data(files))
        all_violations.extend(self.check_security_references(files))
        all_violations.extend(self.check_matrix_routing(files))
        all_violations.extend(self.check_closed_source(files))

        result = SanitizationResult(
            is_clean=len(all_violations) == 0,
            violations=all_violations,
            scanned_files_count=len(files),
        )

        if not result.is_clean:
            self._halt_and_alert(package, result)

        return result

    def check_private_data(self, files: Dict[str, str]) -> List[Violation]:
        """Scan files for private data leaks."""
        return self._scan_category(files, "private_data")

    def check_security_references(self, files: Dict[str, str]) -> List[Violation]:
        """Scan files for security layer references."""
        return self._scan_category(files, "security_layer")

    def check_matrix_routing(self, files: Dict[str, str]) -> List[Violation]:
        """Scan files for Matrix-specific routing references."""
        return self._scan_category(files, "matrix_routing")

    def check_closed_source(self, files: Dict[str, str]) -> List[Violation]:
        """Scan files for closed-source markers."""
        return self._scan_category(files, "closed_source")

    # ── Internal helpers ───────────────────────────────────────────────────

    def _scan_category(
        self, files: Dict[str, str], category: str
    ) -> List[Violation]:
        """Scan all files for patterns matching a specific category."""
        violations: List[Violation] = []
        category_patterns = [
            (pat, desc) for cat, pat, desc in self.patterns if cat == category
        ]

        for file_path, content in files.items():
            for line_number, line in enumerate(content.splitlines(), start=1):
                for pattern, description in category_patterns:
                    match = pattern.search(line)
                    if match:
                        violations.append(
                            Violation(
                                file_path=file_path,
                                line_number=line_number,
                                category=category,
                                pattern_description=description,
                                matched_text=match.group(),
                            )
                        )
        return violations

    def _halt_and_alert(self, package, result: SanitizationResult) -> None:
        """Halt export and send Telegram alert with full violation report."""
        component_name = (
            package.component_name if hasattr(package, "component_name") else "unknown"
        )
        logger.critical(
            "EXPORT HALTED for '%s': %d violations found",
            component_name,
            len(result.violations),
        )

        report_lines = [
            f"EXPORT HALTED: {component_name}",
            f"Violations: {len(result.violations)}",
            f"Scanned files: {result.scanned_files_count}",
            "",
        ]
        for v in result.violations:
            report_lines.append(
                f"  [{v.category}] {v.file_path}:{v.line_number} "
                f"- {v.pattern_description} (matched: '{v.matched_text}')"
            )

        full_report = "\n".join(report_lines)

        try:
            notifier = self._get_notifier()
            notifier.send_alert(full_report)
        except Exception:
            logger.exception("Failed to send Telegram alert for sanitization violation")

        raise SanitizationError(
            f"Export halted: {len(result.violations)} violations in '{component_name}'"
        )


class SanitizationError(Exception):
    """Raised when sanitization finds violations and halts an export."""
    pass
