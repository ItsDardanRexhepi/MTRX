"""
Game Vetting Pipeline
======================

4-stage vetting process for games before deployment on 0pnMatrx:
1. Submission Review - Basic requirements check
2. Code Audit - Smart contract security review
3. Economic Model Review - Fee structure and tokenomics
4. Community Preview - Limited release for feedback

Fee disclosure must show BOTH Component 3 (NFT) and Component 14
(Gaming) fees. All disputes route to Component 30.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Revenue split
DEVELOPER_SHARE: Decimal = Decimal("0.80")
NEOSAFE_SHARE: Decimal = Decimal("0.20")


class VettingStage(Enum):
    SUBMISSION = "submission_review"
    CODE_AUDIT = "code_audit"
    ECONOMIC_REVIEW = "economic_model_review"
    COMMUNITY_PREVIEW = "community_preview"
    APPROVED = "approved"
    REJECTED = "rejected"


class VettingStatus(Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    PASSED = "passed"
    FAILED = "failed"
    NEEDS_REVISION = "needs_revision"


@dataclass
class FeeDisclosure:
    """Mandatory fee disclosure for game listings."""
    component_3_nft_fee_pct: Decimal = Decimal("5.0")
    component_14_gaming_fee_pct: Decimal = Decimal("20.0")
    total_platform_fee_pct: Decimal = Decimal("25.0")
    developer_revenue_pct: Decimal = Decimal("80.0")
    neosafe_revenue_pct: Decimal = Decimal("20.0")
    neosafe_address: str = NEOSAFE_ADDRESS
    disclosure_text: str = ""

    def __post_init__(self) -> None:
        self.total_platform_fee_pct = self.component_3_nft_fee_pct + self.component_14_gaming_fee_pct
        self.disclosure_text = (
            f"Platform fees: {self.component_3_nft_fee_pct}% NFT (Component 3) + "
            f"{self.component_14_gaming_fee_pct}% Gaming (Component 14) = "
            f"{self.total_platform_fee_pct}% total. "
            f"Revenue split: {self.developer_revenue_pct}% developer / "
            f"{self.neosafe_revenue_pct}% NeoSafe ({self.neosafe_address})."
        )


@dataclass
class StageResult:
    """Result of a single vetting stage."""
    stage: VettingStage
    status: VettingStatus = VettingStatus.PENDING
    reviewer: Optional[str] = None
    findings: List[str] = field(default_factory=list)
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    notes: str = ""


@dataclass
class VettingApplication:
    """A game vetting application."""
    application_id: str = field(default_factory=lambda: f"vet-{uuid.uuid4().hex[:12]}")
    game_name: str = ""
    developer_wallet: str = ""
    developer_name: str = ""
    current_stage: VettingStage = VettingStage.SUBMISSION
    stages: Dict[str, StageResult] = field(default_factory=dict)
    fee_disclosure: FeeDisclosure = field(default_factory=FeeDisclosure)
    contract_addresses: List[str] = field(default_factory=list)
    submitted_at: float = field(default_factory=time.time)
    approved_at: Optional[float] = None
    rejected_at: Optional[float] = None
    rejection_reason: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.stages:
            for stage in [VettingStage.SUBMISSION, VettingStage.CODE_AUDIT,
                          VettingStage.ECONOMIC_REVIEW, VettingStage.COMMUNITY_PREVIEW]:
                self.stages[stage.value] = StageResult(stage=stage)


class GameVetting:
    """4-stage game vetting pipeline.

    Every game must pass all 4 stages before deployment.
    Fee disclosure showing Component 3 + Component 14 fees is mandatory.

    Parameters
    ----------
    attestation_service : Any
        Component 8 for vetting attestations.
    dispute_connector : Any
        Routes to Component 30 DisputeResolution.
    """

    def __init__(
        self,
        attestation_service: Any = None,
        dispute_connector: Any = None,
    ) -> None:
        self._attestation = attestation_service
        self._disputes = dispute_connector
        self._applications: Dict[str, VettingApplication] = {}
        self._by_developer: Dict[str, List[str]] = {}
        logger.info("GameVetting pipeline initialised (4 stages)")

    def submit_game(
        self,
        game_name: str,
        developer_wallet: str,
        developer_name: str,
        contract_addresses: List[str],
        metadata: Optional[Dict[str, Any]] = None,
    ) -> VettingApplication:
        """Submit a game for vetting.

        Args:
            game_name: Name of the game.
            developer_wallet: Developer's wallet address.
            developer_name: Developer name or studio.
            contract_addresses: Game smart contract addresses.
            metadata: Additional game info.

        Returns:
            VettingApplication with fee disclosure attached.
        """
        app = VettingApplication(
            game_name=game_name,
            developer_wallet=developer_wallet,
            developer_name=developer_name,
            contract_addresses=contract_addresses,
            metadata=metadata or {},
        )
        self._applications[app.application_id] = app
        self._by_developer.setdefault(developer_wallet, []).append(app.application_id)

        # Start stage 1 automatically
        stage = app.stages[VettingStage.SUBMISSION.value]
        stage.status = VettingStatus.IN_PROGRESS
        stage.started_at = time.time()

        logger.info(
            "Game submitted for vetting: %s by %s (id=%s)",
            game_name, developer_name, app.application_id,
        )
        return app

    def advance_stage(
        self,
        application_id: str,
        passed: bool,
        findings: Optional[List[str]] = None,
        reviewer: Optional[str] = None,
        notes: str = "",
    ) -> VettingApplication:
        """Complete the current stage and advance to next.

        Args:
            application_id: The application to advance.
            passed: Whether the current stage passed.
            findings: List of findings from review.
            reviewer: Who reviewed this stage.
            notes: Additional notes.

        Returns:
            Updated VettingApplication.
        """
        app = self._applications.get(application_id)
        if not app:
            raise ValueError(f"Application {application_id} not found")

        current = app.stages.get(app.current_stage.value)
        if not current:
            raise ValueError(f"Invalid stage: {app.current_stage}")

        current.status = VettingStatus.PASSED if passed else VettingStatus.FAILED
        current.completed_at = time.time()
        current.reviewer = reviewer
        current.findings = findings or []
        current.notes = notes

        if not passed:
            if findings:
                current.status = VettingStatus.NEEDS_REVISION
                logger.info("Stage %s needs revision: %s", app.current_stage.value, findings)
            else:
                app.current_stage = VettingStage.REJECTED
                app.rejected_at = time.time()
                app.rejection_reason = notes or "Failed vetting"
                logger.info("Game %s REJECTED at %s", app.game_name, current.stage.value)
            return app

        # Advance to next stage
        stage_order = [
            VettingStage.SUBMISSION,
            VettingStage.CODE_AUDIT,
            VettingStage.ECONOMIC_REVIEW,
            VettingStage.COMMUNITY_PREVIEW,
        ]
        current_idx = stage_order.index(app.current_stage)

        if current_idx < len(stage_order) - 1:
            next_stage = stage_order[current_idx + 1]
            app.current_stage = next_stage
            next_result = app.stages[next_stage.value]
            next_result.status = VettingStatus.IN_PROGRESS
            next_result.started_at = time.time()
            logger.info("Game %s advanced to %s", app.game_name, next_stage.value)
        else:
            app.current_stage = VettingStage.APPROVED
            app.approved_at = time.time()
            logger.info("Game %s APPROVED for deployment", app.game_name)
            if self._attestation:
                try:
                    self._attestation.create_attestation(
                        schema="game_vetting_approved",
                        data={
                            "game_name": app.game_name,
                            "developer": app.developer_wallet,
                            "application_id": app.application_id,
                        },
                    )
                except Exception as exc:
                    logger.warning("Attestation failed: %s", exc)

        return app

    def get_fee_disclosure(self, application_id: str) -> FeeDisclosure:
        """Get the mandatory fee disclosure for a game."""
        app = self._applications.get(application_id)
        if not app:
            return FeeDisclosure()
        return app.fee_disclosure

    def is_approved(self, application_id: str) -> bool:
        """Check if a game has been approved."""
        app = self._applications.get(application_id)
        return app is not None and app.current_stage == VettingStage.APPROVED

    def get_application(self, application_id: str) -> Optional[VettingApplication]:
        return self._applications.get(application_id)

    def get_developer_applications(self, developer_wallet: str) -> List[VettingApplication]:
        app_ids = self._by_developer.get(developer_wallet, [])
        return [self._applications[aid] for aid in app_ids if aid in self._applications]

    def get_stats(self) -> Dict[str, Any]:
        by_stage: Dict[str, int] = {}
        for app in self._applications.values():
            by_stage[app.current_stage.value] = by_stage.get(app.current_stage.value, 0) + 1
        return {
            "total_applications": len(self._applications),
            "by_stage": by_stage,
            "approved": by_stage.get(VettingStage.APPROVED.value, 0),
            "rejected": by_stage.get(VettingStage.REJECTED.value, 0),
        }
