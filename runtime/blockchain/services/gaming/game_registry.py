"""
Game Registry — on-chain game vetting pipeline.

Part of Component 14 (Gaming).
Manages game submissions through a multi-stage vetting process:
Submitted → UnderReview → TechReview → Approved/Rejected/Suspended.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Set

logger = logging.getLogger(__name__)


class VettingStage(Enum):
    """Stages in the game vetting pipeline."""
    SUBMITTED = "submitted"
    UNDER_REVIEW = "under_review"
    TECH_REVIEW = "tech_review"
    APPROVED = "approved"
    REJECTED = "rejected"
    SUSPENDED = "suspended"


@dataclass
class Game:
    """A game in the registry."""
    game_id: str
    developer: str
    name: str
    metadata_uri: str
    stage: VettingStage = VettingStage.SUBMITTED
    current_reviewer: str = ""
    submitted_at: float = field(default_factory=time.time)
    approved_at: float = 0.0
    rejected_at: float = 0.0
    rejection_reason: str = ""
    version: int = 1


@dataclass
class ReviewRecord:
    """An entry in the review audit trail."""
    game_id: str
    reviewer: str
    from_stage: VettingStage
    to_stage: VettingStage
    notes: str
    timestamp: float = field(default_factory=time.time)


class GameRegistryService:
    """
    Manages the game vetting pipeline.

    Roles:
    - Developers: submit and resubmit games
    - Reviewers: pick up, advance to tech review, or reject
    - Tech Auditors: final approval
    - Owner: suspend/reinstate, manage roles
    """

    def __init__(self) -> None:
        self._games: Dict[str, Game] = {}
        self._by_developer: Dict[str, List[str]] = {}
        self._reviews: Dict[str, List[ReviewRecord]] = {}
        self._reviewers: Set[str] = set()
        self._tech_auditors: Set[str] = set()
        self._counter: int = 0
        logger.info("GameRegistryService initialised.")

    # ── Role Management ───────────────────────────────────────────────

    def add_reviewer(self, address: str) -> None:
        """Add a reviewer."""
        self._reviewers.add(address)
        logger.info("Reviewer added | addr=%s", address)

    def remove_reviewer(self, address: str) -> None:
        """Remove a reviewer."""
        self._reviewers.discard(address)

    def add_tech_auditor(self, address: str) -> None:
        """Add a tech auditor."""
        self._tech_auditors.add(address)
        logger.info("Tech auditor added | addr=%s", address)

    def remove_tech_auditor(self, address: str) -> None:
        """Remove a tech auditor."""
        self._tech_auditors.discard(address)

    # ── Submission ────────────────────────────────────────────────────

    def submit_game(
        self, developer: str, name: str, metadata_uri: str,
    ) -> Game:
        """
        Submit a new game for vetting.

        Args:
            developer: Developer's address.
            name: Game name.
            metadata_uri: URI of game metadata.

        Returns:
            The created Game.
        """
        if not developer.startswith("0x"):
            raise ValueError("Invalid developer address.")
        if not name:
            raise ValueError("Game name must not be empty.")

        self._counter += 1
        gid = f"GAME-{self._counter:08d}"

        game = Game(
            game_id=gid,
            developer=developer,
            name=name,
            metadata_uri=metadata_uri,
        )
        self._games[gid] = game
        self._by_developer.setdefault(developer, []).append(gid)
        self._reviews[gid] = []

        logger.info(
            "Game submitted | id=%s | developer=%s | name=%s",
            gid, developer, name,
        )
        return game

    def resubmit_game(
        self, game_id: str, caller: str, metadata_uri: str,
    ) -> Game:
        """Resubmit a rejected game with updated metadata."""
        game = self._get_game(game_id)
        if game.developer != caller:
            raise ValueError("Only the developer can resubmit.")
        if game.stage != VettingStage.REJECTED:
            raise ValueError("Can only resubmit rejected games.")

        game.metadata_uri = metadata_uri
        game.stage = VettingStage.SUBMITTED
        game.version += 1
        game.rejection_reason = ""
        game.rejected_at = 0.0

        self._log_review(game_id, caller, VettingStage.REJECTED, VettingStage.SUBMITTED, "Resubmitted")
        logger.info("Game resubmitted | id=%s | v%d", game_id, game.version)
        return game

    # ── Review Pipeline ───────────────────────────────────────────────

    def pickup_for_review(self, game_id: str, reviewer: str) -> Game:
        """Reviewer picks up a submitted game."""
        self._check_reviewer(reviewer)
        game = self._get_game(game_id)
        if game.stage != VettingStage.SUBMITTED:
            raise ValueError("Game is not in SUBMITTED stage.")

        game.stage = VettingStage.UNDER_REVIEW
        game.current_reviewer = reviewer

        self._log_review(game_id, reviewer, VettingStage.SUBMITTED, VettingStage.UNDER_REVIEW, "Picked up for review")
        logger.info("Game picked up | id=%s | reviewer=%s", game_id, reviewer)
        return game

    def advance_to_tech_review(
        self, game_id: str, reviewer: str, notes: str,
    ) -> Game:
        """Advance a game from review to tech review."""
        self._check_reviewer(reviewer)
        game = self._get_game(game_id)
        if game.stage != VettingStage.UNDER_REVIEW:
            raise ValueError("Game is not under review.")

        game.stage = VettingStage.TECH_REVIEW
        game.current_reviewer = ""

        self._log_review(game_id, reviewer, VettingStage.UNDER_REVIEW, VettingStage.TECH_REVIEW, notes)
        logger.info("Game advanced to tech review | id=%s", game_id)
        return game

    def approve_game(self, game_id: str, auditor: str, notes: str) -> Game:
        """Tech auditor approves a game."""
        self._check_auditor(auditor)
        game = self._get_game(game_id)
        if game.stage != VettingStage.TECH_REVIEW:
            raise ValueError("Game is not in tech review.")

        game.stage = VettingStage.APPROVED
        game.approved_at = time.time()

        self._log_review(game_id, auditor, VettingStage.TECH_REVIEW, VettingStage.APPROVED, notes)
        logger.info("Game approved | id=%s", game_id)
        return game

    def reject_game(
        self, game_id: str, reviewer: str, reason: str,
    ) -> Game:
        """Reject a game during review."""
        self._check_reviewer(reviewer)
        game = self._get_game(game_id)
        if game.stage not in (VettingStage.UNDER_REVIEW, VettingStage.TECH_REVIEW):
            raise ValueError("Game is not in a reviewable stage.")

        old_stage = game.stage
        game.stage = VettingStage.REJECTED
        game.rejected_at = time.time()
        game.rejection_reason = reason

        self._log_review(game_id, reviewer, old_stage, VettingStage.REJECTED, reason)
        logger.info("Game rejected | id=%s | reason=%s", game_id, reason)
        return game

    def suspend_game(self, game_id: str, reason: str) -> Game:
        """Suspend an approved game (owner action)."""
        game = self._get_game(game_id)
        if game.stage != VettingStage.APPROVED:
            raise ValueError("Can only suspend approved games.")

        game.stage = VettingStage.SUSPENDED
        self._log_review(game_id, "owner", VettingStage.APPROVED, VettingStage.SUSPENDED, reason)
        logger.info("Game suspended | id=%s", game_id)
        return game

    def reinstate_game(self, game_id: str) -> Game:
        """Reinstate a suspended game (owner action)."""
        game = self._get_game(game_id)
        if game.stage != VettingStage.SUSPENDED:
            raise ValueError("Can only reinstate suspended games.")

        game.stage = VettingStage.APPROVED
        self._log_review(game_id, "owner", VettingStage.SUSPENDED, VettingStage.APPROVED, "Reinstated")
        logger.info("Game reinstated | id=%s", game_id)
        return game

    def update_metadata(
        self, game_id: str, caller: str, metadata_uri: str,
    ) -> Game:
        """Update game metadata (developer only)."""
        game = self._get_game(game_id)
        if game.developer != caller:
            raise ValueError("Only the developer can update metadata.")
        game.metadata_uri = metadata_uri
        logger.info("Metadata updated | id=%s", game_id)
        return game

    # ── Queries ───────────────────────────────────────────────────────

    def get_game(self, game_id: str) -> Optional[Game]:
        """Get game or None."""
        return self._games.get(game_id)

    def get_developer_games(self, developer: str) -> List[Game]:
        """Get all games by a developer."""
        ids = self._by_developer.get(developer, [])
        return [self._games[gid] for gid in ids if gid in self._games]

    def get_review_history(self, game_id: str) -> List[ReviewRecord]:
        """Get review history for a game."""
        return self._reviews.get(game_id, [])

    # ── Internal ──────────────────────────────────────────────────────

    def _check_reviewer(self, address: str) -> None:
        if address not in self._reviewers:
            raise ValueError(f"{address} is not an authorized reviewer.")

    def _check_auditor(self, address: str) -> None:
        if address not in self._tech_auditors:
            raise ValueError(f"{address} is not an authorized tech auditor.")

    def _get_game(self, game_id: str) -> Game:
        game = self._games.get(game_id)
        if game is None:
            raise ValueError(f"Game {game_id} not found.")
        return game

    def _log_review(
        self, game_id: str, reviewer: str,
        from_stage: VettingStage, to_stage: VettingStage, notes: str,
    ) -> None:
        self._reviews.setdefault(game_id, []).append(ReviewRecord(
            game_id=game_id,
            reviewer=reviewer,
            from_stage=from_stage,
            to_stage=to_stage,
            notes=notes,
        ))
