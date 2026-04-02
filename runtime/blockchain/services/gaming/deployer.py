"""
Game Deployer
==============

Deployment pipeline for vetted games on 0pnMatrx.
Games must pass all 4 vetting stages before deployment.
Revenue splits: 80% developer / 20% NeoSafe.
60-day inactivity pause: games with no transactions for
60 days are automatically paused.
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

DEVELOPER_SHARE: Decimal = Decimal("0.80")
NEOSAFE_SHARE: Decimal = Decimal("0.20")
INACTIVITY_PAUSE_SECONDS: int = 60 * 86400  # 60 days


class DeploymentStatus(Enum):
    PENDING = "pending"
    DEPLOYING = "deploying"
    ACTIVE = "active"
    PAUSED = "paused"
    PAUSED_INACTIVITY = "paused_inactivity"
    TERMINATED = "terminated"


@dataclass
class DeployedGame:
    """A deployed game on the platform."""
    deployment_id: str = field(default_factory=lambda: f"dep-{uuid.uuid4().hex[:12]}")
    application_id: str = ""
    game_name: str = ""
    developer_wallet: str = ""
    status: DeploymentStatus = DeploymentStatus.PENDING
    contract_addresses: List[str] = field(default_factory=list)
    registry_id: Optional[str] = None
    revenue_config: Dict[str, str] = field(default_factory=dict)
    deployed_at: Optional[float] = None
    last_transaction_at: Optional[float] = None
    paused_at: Optional[float] = None
    total_revenue_eth: Decimal = Decimal("0")
    developer_earnings_eth: Decimal = Decimal("0")
    neosafe_earnings_eth: Decimal = Decimal("0")
    metadata: Dict[str, Any] = field(default_factory=dict)


class GameDeployer:
    """Deployment pipeline for approved games.

    Validates vetting completion, deploys contracts, registers in
    GameRegistry, configures revenue splits, and monitors for
    60-day inactivity.

    Parameters
    ----------
    vetting : Any
        GameVetting for approval verification.
    game_registry : Any
        GameRegistry for registration.
    revenue_splitter : Any
        RevenueSplitter for configuring 80/20 splits.
    attestation_service : Any
        Component 8 for deployment attestation.
    """

    def __init__(
        self,
        vetting: Any = None,
        game_registry: Any = None,
        revenue_splitter: Any = None,
        attestation_service: Any = None,
    ) -> None:
        self._vetting = vetting
        self._registry = game_registry
        self._revenue = revenue_splitter
        self._attestation = attestation_service
        self._deployments: Dict[str, DeployedGame] = {}
        self._by_application: Dict[str, str] = {}
        logger.info("GameDeployer initialised (inactivity_pause=%dd)", INACTIVITY_PAUSE_SECONDS // 86400)

    def deploy(self, application_id: str) -> DeployedGame:
        """Deploy an approved game.

        Validates vetting completion, deploys contracts, registers
        in GameRegistry, and configures revenue splits.

        Args:
            application_id: The approved vetting application ID.

        Returns:
            DeployedGame record.

        Raises:
            ValueError: If game not approved or already deployed.
        """
        # Verify vetting approval
        if self._vetting and not self._vetting.is_approved(application_id):
            raise ValueError(f"Application {application_id} is not approved")

        if application_id in self._by_application:
            raise ValueError(f"Application {application_id} already deployed")

        app = self._vetting.get_application(application_id) if self._vetting else None
        game_name = app.game_name if app else "Unknown"
        developer_wallet = app.developer_wallet if app else ""
        contracts = app.contract_addresses if app else []

        game = DeployedGame(
            application_id=application_id,
            game_name=game_name,
            developer_wallet=developer_wallet,
            contract_addresses=contracts,
            status=DeploymentStatus.DEPLOYING,
            revenue_config={
                "developer_share": str(DEVELOPER_SHARE),
                "neosafe_share": str(NEOSAFE_SHARE),
                "neosafe_address": NEOSAFE_ADDRESS,
            },
        )

        # Register in GameRegistry
        if self._registry:
            try:
                reg_id = self._registry.register_game(
                    name=game_name,
                    developer=developer_wallet,
                    contracts=contracts,
                )
                game.registry_id = reg_id
            except Exception as exc:
                logger.error("GameRegistry registration failed: %s", exc)

        # Configure revenue split
        if self._revenue:
            try:
                self._revenue.configure_split(
                    game_id=game.deployment_id,
                    developer_wallet=developer_wallet,
                    developer_share=float(DEVELOPER_SHARE),
                    neosafe_share=float(NEOSAFE_SHARE),
                )
            except Exception as exc:
                logger.error("Revenue split config failed: %s", exc)

        game.status = DeploymentStatus.ACTIVE
        game.deployed_at = time.time()
        game.last_transaction_at = time.time()

        self._deployments[game.deployment_id] = game
        self._by_application[application_id] = game.deployment_id

        # Attest deployment
        if self._attestation:
            try:
                self._attestation.create_attestation(
                    schema="game_deployed",
                    data={
                        "deployment_id": game.deployment_id,
                        "game_name": game_name,
                        "developer": developer_wallet,
                    },
                )
            except Exception as exc:
                logger.warning("Deployment attestation failed: %s", exc)

        logger.info("Game deployed: %s (id=%s)", game_name, game.deployment_id)
        return game

    def record_transaction(self, deployment_id: str, revenue_eth: Decimal) -> None:
        """Record a game transaction and update activity timestamp.

        Args:
            deployment_id: The deployment to update.
            revenue_eth: Revenue from this transaction.
        """
        game = self._deployments.get(deployment_id)
        if not game:
            return

        game.last_transaction_at = time.time()
        game.total_revenue_eth += revenue_eth
        dev_share = revenue_eth * DEVELOPER_SHARE
        neo_share = revenue_eth * NEOSAFE_SHARE
        game.developer_earnings_eth += dev_share
        game.neosafe_earnings_eth += neo_share

        # Unpause if was paused for inactivity
        if game.status == DeploymentStatus.PAUSED_INACTIVITY:
            game.status = DeploymentStatus.ACTIVE
            game.paused_at = None
            logger.info("Game %s unpaused (activity resumed)", game.game_name)

    def check_inactivity(self) -> List[str]:
        """Check all active games for 60-day inactivity.

        Returns:
            List of deployment IDs that were paused.
        """
        paused: List[str] = []
        now = time.time()
        for game in self._deployments.values():
            if game.status != DeploymentStatus.ACTIVE:
                continue
            if game.last_transaction_at and (now - game.last_transaction_at) > INACTIVITY_PAUSE_SECONDS:
                game.status = DeploymentStatus.PAUSED_INACTIVITY
                game.paused_at = now
                paused.append(game.deployment_id)
                logger.info(
                    "Game %s PAUSED (60-day inactivity, last tx=%s)",
                    game.game_name, time.ctime(game.last_transaction_at),
                )
        return paused

    def pause_game(self, deployment_id: str, reason: str = "manual") -> bool:
        """Manually pause a game."""
        game = self._deployments.get(deployment_id)
        if not game or game.status != DeploymentStatus.ACTIVE:
            return False
        game.status = DeploymentStatus.PAUSED
        game.paused_at = time.time()
        logger.info("Game %s paused: %s", game.game_name, reason)
        return True

    def unpause_game(self, deployment_id: str) -> bool:
        """Unpause a paused game."""
        game = self._deployments.get(deployment_id)
        if not game or game.status not in (DeploymentStatus.PAUSED, DeploymentStatus.PAUSED_INACTIVITY):
            return False
        game.status = DeploymentStatus.ACTIVE
        game.paused_at = None
        logger.info("Game %s unpaused", game.game_name)
        return True

    def terminate_game(self, deployment_id: str, reason: str = "") -> bool:
        """Permanently terminate a game deployment."""
        game = self._deployments.get(deployment_id)
        if not game:
            return False
        game.status = DeploymentStatus.TERMINATED
        logger.info("Game %s TERMINATED: %s", game.game_name, reason)
        return True

    def get_deployment(self, deployment_id: str) -> Optional[DeployedGame]:
        return self._deployments.get(deployment_id)

    def get_active_games(self) -> List[DeployedGame]:
        return [g for g in self._deployments.values() if g.status == DeploymentStatus.ACTIVE]

    def get_stats(self) -> Dict[str, Any]:
        by_status: Dict[str, int] = {}
        total_rev = Decimal("0")
        for game in self._deployments.values():
            by_status[game.status.value] = by_status.get(game.status.value, 0) + 1
            total_rev += game.total_revenue_eth
        return {
            "total_deployments": len(self._deployments),
            "by_status": by_status,
            "total_revenue_eth": str(total_rev),
        }
