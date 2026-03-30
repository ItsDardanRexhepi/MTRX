"""
ERC-8004 Update Monitor
========================

Checks for new ERC-8004 standard versions on a weekly cadence.
Applies confirmed releases within 24 hours provided both the safety
validator AND the Rexhepi gate pass.

If a conflict with Rexhepi FW or the security layer is detected the
system HALTs immediately and alerts Dardan (Telegram ID 7161847911).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID = "7161847911"
CHECK_INTERVAL = timedelta(weeks=1)
APPLY_DEADLINE = timedelta(hours=24)


class UpdateStatus(Enum):
    """Lifecycle states for a detected update."""
    DETECTED = "detected"
    EVALUATING = "evaluating"
    SCHEDULED = "scheduled"
    APPLYING = "applying"
    APPLIED = "applied"
    HALTED = "halted"
    REJECTED = "rejected"


@dataclass
class ERCVersion:
    """Descriptor for an ERC-8004 version release."""
    version: str
    release_date: datetime
    changelog: str
    breaking_changes: bool = False
    affected_files: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class UpdateEvaluation:
    """Result of evaluating a potential update."""
    version: str
    is_confirmed: bool
    safety_passed: Optional[bool] = None
    rexhepi_passed: Optional[bool] = None
    conflict_details: Optional[str] = None
    evaluated_at: Optional[datetime] = None


class UpdateMonitor:
    """Monitors ERC-8004 standard releases and orchestrates safe application.

    Schedule:
        - Checks for new versions **weekly**.
        - Applies confirmed releases **within 24 hours** if both validators pass.
        - HALTs immediately on conflict with Rexhepi FW or security layer and
          sends an alert to Dardan via Telegram.
    """

    def __init__(self) -> None:
        self._last_check: Optional[datetime] = None
        self._known_versions: Dict[str, ERCVersion] = {}
        self._evaluations: Dict[str, UpdateEvaluation] = {}
        self._scheduled: Dict[str, datetime] = {}
        self._halted: bool = False
        logger.info("UpdateMonitor initialised (check interval=%s)", CHECK_INTERVAL)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check_for_updates(self) -> List[ERCVersion]:
        """Poll the ERC-8004 registry for new versions.

        Returns:
            List of newly discovered ``ERCVersion`` objects.

        Raises:
            RuntimeError: If the monitor is currently in a HALTED state.
        """
        if self._halted:
            raise RuntimeError("UpdateMonitor is HALTED — resolve conflict before checking for updates")

        now = datetime.now(timezone.utc)
        if self._last_check and (now - self._last_check) < CHECK_INTERVAL:
            logger.debug("Skipping check — last check was %s", self._last_check.isoformat())
            return []

        new_versions = self._fetch_latest_versions()
        self._last_check = now

        discovered: List[ERCVersion] = []
        for v in new_versions:
            if v.version not in self._known_versions:
                self._known_versions[v.version] = v
                discovered.append(v)
                logger.info("New ERC-8004 version discovered: %s", v.version)

        return discovered

    def evaluate_update(self, version: str) -> UpdateEvaluation:
        """Evaluate whether *version* is confirmed and conflict-free.

        Args:
            version: Semantic version string of the detected release.

        Returns:
            ``UpdateEvaluation`` summarising the assessment.

        Raises:
            KeyError: If *version* is not a known release.
        """
        if version not in self._known_versions:
            raise KeyError(f"Unknown version: {version}")

        erc_version = self._known_versions[version]
        evaluation = UpdateEvaluation(
            version=version,
            is_confirmed=self._verify_release_confirmation(erc_version),
            evaluated_at=datetime.now(timezone.utc),
        )

        if not evaluation.is_confirmed:
            evaluation.safety_passed = False
            evaluation.conflict_details = "Release not yet confirmed by ERC-8004 governance"
            self._evaluations[version] = evaluation
            logger.info("Version %s not confirmed — skipping", version)
            return evaluation

        # Conflict detection is performed later by UpdateSafetyValidator;
        # here we only record the evaluation.
        self._evaluations[version] = evaluation
        logger.info("Version %s evaluation recorded (confirmed=%s)", version, evaluation.is_confirmed)
        return evaluation

    def schedule_update(self, version: str) -> datetime:
        """Schedule a confirmed update for application within the 24-hour window.

        Args:
            version: Version to schedule.

        Returns:
            Scheduled application ``datetime``.

        Raises:
            KeyError: If *version* has not been evaluated.
            ValueError: If *version* was not confirmed or has unresolved conflicts.
            RuntimeError: If the monitor is currently HALTED.
        """
        if self._halted:
            raise RuntimeError("UpdateMonitor is HALTED — cannot schedule updates")

        evaluation = self._evaluations.get(version)
        if evaluation is None:
            raise KeyError(f"Version {version} has not been evaluated yet")
        if not evaluation.is_confirmed:
            raise ValueError(f"Version {version} is not confirmed")

        apply_at = datetime.now(timezone.utc) + APPLY_DEADLINE
        self._scheduled[version] = apply_at
        logger.info("Version %s scheduled for application at %s", version, apply_at.isoformat())
        return apply_at

    def halt_and_alert(self, reason: str) -> None:
        """HALT the update pipeline and alert Dardan via Telegram.

        Args:
            reason: Human-readable explanation of the conflict.
        """
        self._halted = True
        logger.critical("UPDATE MONITOR HALTED: %s", reason)
        self._send_telegram_alert(reason)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _fetch_latest_versions(self) -> List[ERCVersion]:
        """Retrieve the latest ERC-8004 versions from the governance registry.

        Returns:
            List of ``ERCVersion`` objects.
        """
        try:
            # TODO: Replace with actual API / on-chain call to ERC-8004 registry
            logger.debug("Fetching latest ERC-8004 versions from registry")
            return []
        except Exception as exc:
            logger.error("Failed to fetch ERC-8004 versions: %s", exc)
            return []

    @staticmethod
    def _verify_release_confirmation(version: ERCVersion) -> bool:
        """Check whether the release has been confirmed by governance.

        Returns:
            ``True`` if the release is confirmed, ``False`` otherwise.
        """
        try:
            # TODO: Replace with actual governance verification
            logger.debug("Verifying release confirmation for %s", version.version)
            return True
        except Exception as exc:
            logger.error("Release confirmation check failed for %s: %s", version.version, exc)
            return False

    @staticmethod
    def _send_telegram_alert(reason: str) -> None:
        """Send an alert to Dardan via Telegram.

        Target Telegram ID: 7161847911
        """
        try:
            # TODO: Integrate with Telegram Bot API
            # POST https://api.telegram.org/bot<TOKEN>/sendMessage
            # {"chat_id": DARDAN_TELEGRAM_ID, "text": message}
            message = (
                f"[0pnMatrx HALT] ERC-8004 Update Monitor halted.\n"
                f"Reason: {reason}\n"
                f"Immediate attention required."
            )
            logger.critical("TELEGRAM ALERT -> %s: %s", DARDAN_TELEGRAM_ID, message)
        except Exception as exc:
            logger.error("Failed to send Telegram alert: %s", exc)
