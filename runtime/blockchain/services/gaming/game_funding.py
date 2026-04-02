"""
Game Funding — milestone-based game funding with clawback.

Part of Component 14 (Gaming).
Platform and developer co-fund milestones. Clawback on abandonment.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
INACTIVITY_THRESHOLD_SECONDS: int = 90 * 86_400  # 90 days


class MilestoneStatus(Enum):
    """Milestone funding states."""
    PENDING = "pending"
    FUNDED = "funded"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class GameStatus(Enum):
    """Game development states."""
    ACTIVE = "active"
    LAUNCHED = "launched"
    ABANDONED = "abandoned"


@dataclass
class Milestone:
    """A game development milestone."""
    description: str
    cost_wei: int
    platform_deposit_wei: int = 0
    developer_deposit_wei: int = 0
    released_to_developer_wei: int = 0
    status: MilestoneStatus = MilestoneStatus.PENDING


@dataclass
class FundedGame:
    """A game in the funding programme."""
    game_id: str
    developer: str
    revenue_contract: str
    status: GameStatus = GameStatus.ACTIVE
    total_funded_wei: int = 0
    total_released_wei: int = 0
    last_activity: float = field(default_factory=time.time)
    milestones: List[Milestone] = field(default_factory=list)
    clawback_owed_wei: int = 0
    clawback_settled_wei: int = 0
    created_at: float = field(default_factory=time.time)


class GameFundingService:
    """
    Manages milestone-based game funding.

    Platform and developer co-fund milestones. On completion,
    funds are released to the developer. On abandonment, the platform
    can claw back its deposits.
    """

    def __init__(
        self,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._execute = execute_fn
        self._games: Dict[str, FundedGame] = {}
        self._counter: int = 0
        logger.info("GameFundingService initialised.")

    def create_game(
        self, developer: str, revenue_contract: str,
    ) -> FundedGame:
        """Register a game for funding."""
        if not developer.startswith("0x"):
            raise ValueError("Invalid developer address.")

        self._counter += 1
        gid = f"GFUND-{self._counter:08d}"

        game = FundedGame(
            game_id=gid,
            developer=developer,
            revenue_contract=revenue_contract,
        )
        self._games[gid] = game

        logger.info("Funded game created | id=%s | dev=%s", gid, developer)
        return game

    def add_milestone(
        self, game_id: str, description: str, cost_wei: int,
    ) -> int:
        """
        Add a milestone to a game.

        Returns:
            Milestone index.
        """
        game = self._get_game(game_id)
        if game.status != GameStatus.ACTIVE:
            raise ValueError("Can only add milestones to active games.")
        if cost_wei <= 0:
            raise ValueError("Cost must be positive.")

        game.milestones.append(Milestone(description=description, cost_wei=cost_wei))
        idx = len(game.milestones) - 1
        self._touch(game)

        logger.info(
            "Milestone added | game=%s | idx=%d | cost=%d",
            game_id, idx, cost_wei,
        )
        return idx

    def fund_platform_share(
        self, game_id: str, milestone_idx: int, amount_wei: int,
    ) -> Milestone:
        """Fund the platform's share of a milestone."""
        game = self._get_game(game_id)
        ms = self._get_milestone(game, milestone_idx)
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        ms.platform_deposit_wei += amount_wei
        game.total_funded_wei += amount_wei
        self._check_funded(ms)
        self._touch(game)

        logger.info(
            "Platform funded | game=%s | ms=%d | amount=%d",
            game_id, milestone_idx, amount_wei,
        )
        return ms

    def fund_developer_share(
        self, game_id: str, milestone_idx: int, caller: str, amount_wei: int,
    ) -> Milestone:
        """Fund the developer's share of a milestone."""
        game = self._get_game(game_id)
        if game.developer != caller:
            raise ValueError("Only the developer can fund their share.")
        ms = self._get_milestone(game, milestone_idx)
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        ms.developer_deposit_wei += amount_wei
        game.total_funded_wei += amount_wei
        self._check_funded(ms)
        self._touch(game)

        logger.info(
            "Developer funded | game=%s | ms=%d | amount=%d",
            game_id, milestone_idx, amount_wei,
        )
        return ms

    def complete_milestone(
        self, game_id: str, milestone_idx: int,
    ) -> Milestone:
        """Mark a milestone as completed and release funds to developer."""
        game = self._get_game(game_id)
        ms = self._get_milestone(game, milestone_idx)
        if ms.status != MilestoneStatus.FUNDED:
            raise ValueError("Milestone must be funded before completion.")

        release = ms.platform_deposit_wei + ms.developer_deposit_wei
        ms.released_to_developer_wei = release
        ms.status = MilestoneStatus.COMPLETED
        game.total_released_wei += release
        self._touch(game)

        logger.info(
            "Milestone completed | game=%s | ms=%d | released=%d",
            game_id, milestone_idx, release,
        )
        return ms

    def cancel_milestone(
        self, game_id: str, milestone_idx: int,
    ) -> Milestone:
        """Cancel an unfunded/funded milestone."""
        game = self._get_game(game_id)
        ms = self._get_milestone(game, milestone_idx)
        if ms.status == MilestoneStatus.COMPLETED:
            raise ValueError("Cannot cancel a completed milestone.")
        ms.status = MilestoneStatus.CANCELLED
        self._touch(game)
        logger.info("Milestone cancelled | game=%s | ms=%d", game_id, milestone_idx)
        return ms

    def mark_game_launched(self, game_id: str) -> FundedGame:
        """Mark a game as launched."""
        game = self._get_game(game_id)
        if game.status != GameStatus.ACTIVE:
            raise ValueError("Can only launch active games.")
        game.status = GameStatus.LAUNCHED
        logger.info("Game launched | id=%s", game_id)
        return game

    def mark_game_abandoned(self, game_id: str) -> FundedGame:
        """Mark a game as abandoned, triggering clawback."""
        game = self._get_game(game_id)
        if game.status != GameStatus.ACTIVE:
            raise ValueError("Can only abandon active games.")
        game.status = GameStatus.ABANDONED

        # Calculate platform clawback: unreleased platform deposits
        clawback = 0
        for ms in game.milestones:
            if ms.status in (MilestoneStatus.PENDING, MilestoneStatus.FUNDED):
                clawback += ms.platform_deposit_wei
        game.clawback_owed_wei = clawback

        logger.info(
            "Game abandoned | id=%s | clawback_owed=%d", game_id, clawback,
        )
        return game

    def settle_clawback(self, game_id: str, amount_wei: int) -> FundedGame:
        """Settle clawback payment from developer."""
        game = self._get_game(game_id)
        if game.status != GameStatus.ABANDONED:
            raise ValueError("Clawback only for abandoned games.")
        if amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        game.clawback_settled_wei += amount_wei
        logger.info(
            "Clawback settled | game=%s | amount=%d | remaining=%d",
            game_id, amount_wei, game.clawback_owed_wei - game.clawback_settled_wei,
        )
        return game

    def check_inactivity(self, game_id: str) -> bool:
        """Check if a game has been inactive too long."""
        game = self._get_game(game_id)
        if game.status != GameStatus.ACTIVE:
            return False
        elapsed = time.time() - game.last_activity
        return elapsed > INACTIVITY_THRESHOLD_SECONDS

    # ── Queries ───────────────────────────────────────────────────────

    def get_game(self, game_id: str) -> Optional[FundedGame]:
        """Get game or None."""
        return self._games.get(game_id)

    def get_milestone(
        self, game_id: str, idx: int,
    ) -> Optional[Milestone]:
        """Get a milestone by game and index."""
        game = self._games.get(game_id)
        if game is None or idx < 0 or idx >= len(game.milestones):
            return None
        return game.milestones[idx]

    # ── Internal ──────────────────────────────────────────────────────

    def _get_game(self, game_id: str) -> FundedGame:
        game = self._games.get(game_id)
        if game is None:
            raise ValueError(f"Game {game_id} not found.")
        return game

    def _get_milestone(self, game: FundedGame, idx: int) -> Milestone:
        if idx < 0 or idx >= len(game.milestones):
            raise ValueError(f"Milestone index {idx} out of range.")
        return game.milestones[idx]

    def _check_funded(self, ms: Milestone) -> None:
        """Check if milestone is fully funded."""
        total = ms.platform_deposit_wei + ms.developer_deposit_wei
        if total >= ms.cost_wei and ms.status == MilestoneStatus.PENDING:
            ms.status = MilestoneStatus.FUNDED

    def _touch(self, game: FundedGame) -> None:
        """Update last activity timestamp."""
        game.last_activity = time.time()
