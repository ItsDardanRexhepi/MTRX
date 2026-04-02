"""
0pnMatrx Game SDK
==================

SDK interfaces for game developers building on 0pnMatrx.
Provides access to asset management, player identity, leaderboards,
matchmaking, and revenue tracking.

Usage:
    from runtime.blockchain.services.gaming.sdk import GameSDK

    sdk = GameSDK(game_id="my-game")
    player = sdk.identity.get_player(wallet_address)
    sdk.assets.mint_item(player, "sword", metadata={...})
    sdk.leaderboard.submit_score(player, 1500)
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


@dataclass
class Player:
    """A game player identity."""
    wallet_address: str
    display_name: str = ""
    did: Optional[str] = None
    registered_at: float = field(default_factory=time.time)
    stats: Dict[str, Any] = field(default_factory=dict)


@dataclass
class GameItem:
    """An in-game item (ERC-1155 backed)."""
    item_id: str = field(default_factory=lambda: f"item-{uuid.uuid4().hex[:8]}")
    name: str = ""
    owner_wallet: str = ""
    token_id: Optional[int] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)


@dataclass
class LeaderboardEntry:
    """A leaderboard score entry."""
    wallet_address: str
    score: int = 0
    rank: int = 0
    submitted_at: float = field(default_factory=time.time)


class AssetManager:
    """Game asset management (ERC-1155 backed, player-owned)."""

    def __init__(self, game_id: str, asset_contract: Any = None) -> None:
        self._game_id = game_id
        self._contract = asset_contract
        self._items: Dict[str, GameItem] = {}

    def mint_item(
        self, player: Player, name: str, metadata: Optional[Dict[str, Any]] = None,
    ) -> GameItem:
        item = GameItem(name=name, owner_wallet=player.wallet_address, metadata=metadata or {})
        self._items[item.item_id] = item
        logger.info("Minted item %s for %s", item.item_id, player.wallet_address)
        return item

    def transfer_item(self, item_id: str, to_wallet: str) -> bool:
        item = self._items.get(item_id)
        if not item:
            return False
        item.owner_wallet = to_wallet
        logger.info("Transferred item %s to %s", item_id, to_wallet)
        return True

    def get_player_items(self, wallet_address: str) -> List[GameItem]:
        return [i for i in self._items.values() if i.owner_wallet == wallet_address]

    def get_item(self, item_id: str) -> Optional[GameItem]:
        return self._items.get(item_id)


class IdentityManager:
    """Player identity management backed by Component 5 DID."""

    def __init__(self, game_id: str) -> None:
        self._game_id = game_id
        self._players: Dict[str, Player] = {}

    def register_player(self, wallet_address: str, display_name: str = "") -> Player:
        if wallet_address in self._players:
            return self._players[wallet_address]
        player = Player(wallet_address=wallet_address, display_name=display_name)
        self._players[wallet_address] = player
        logger.info("Player registered: %s (%s)", wallet_address, display_name)
        return player

    def get_player(self, wallet_address: str) -> Optional[Player]:
        return self._players.get(wallet_address)

    def get_all_players(self) -> List[Player]:
        return list(self._players.values())


class LeaderboardManager:
    """Game leaderboards backed by GameKit integration."""

    def __init__(self, game_id: str) -> None:
        self._game_id = game_id
        self._boards: Dict[str, List[LeaderboardEntry]] = {}

    def submit_score(
        self, wallet_address: str, score: int, board_name: str = "default",
    ) -> LeaderboardEntry:
        entry = LeaderboardEntry(wallet_address=wallet_address, score=score)
        self._boards.setdefault(board_name, []).append(entry)
        self._boards[board_name].sort(key=lambda e: e.score, reverse=True)
        for i, e in enumerate(self._boards[board_name]):
            e.rank = i + 1
        logger.info("Score submitted: %s = %d on %s", wallet_address, score, board_name)
        return entry

    def get_leaderboard(self, board_name: str = "default", limit: int = 100) -> List[LeaderboardEntry]:
        entries = self._boards.get(board_name, [])
        return entries[:limit]

    def get_player_rank(self, wallet_address: str, board_name: str = "default") -> Optional[int]:
        for entry in self._boards.get(board_name, []):
            if entry.wallet_address == wallet_address:
                return entry.rank
        return None


class MatchmakingManager:
    """Simple matchmaking for multiplayer games."""

    def __init__(self, game_id: str) -> None:
        self._game_id = game_id
        self._queue: List[str] = []
        self._matches: Dict[str, List[str]] = {}

    def join_queue(self, wallet_address: str) -> None:
        if wallet_address not in self._queue:
            self._queue.append(wallet_address)
            logger.info("Player %s joined matchmaking queue", wallet_address)

    def leave_queue(self, wallet_address: str) -> None:
        if wallet_address in self._queue:
            self._queue.remove(wallet_address)

    def find_match(self, players_per_match: int = 2) -> Optional[Dict[str, Any]]:
        if len(self._queue) < players_per_match:
            return None
        matched = self._queue[:players_per_match]
        self._queue = self._queue[players_per_match:]
        match_id = f"match-{uuid.uuid4().hex[:8]}"
        self._matches[match_id] = matched
        logger.info("Match created: %s with %s", match_id, matched)
        return {"match_id": match_id, "players": matched}

    def get_queue_size(self) -> int:
        return len(self._queue)


class RevenueTracker:
    """Track game revenue with 80/20 split."""

    def __init__(self, game_id: str, developer_wallet: str) -> None:
        self._game_id = game_id
        self._developer_wallet = developer_wallet
        self._total_revenue = Decimal("0")
        self._developer_earnings = Decimal("0")
        self._neosafe_earnings = Decimal("0")
        self._transactions: List[Dict[str, Any]] = []

    def record_revenue(self, amount_eth: Decimal, source: str = "") -> Dict[str, Decimal]:
        dev_share = amount_eth * Decimal("0.80")
        neo_share = amount_eth * Decimal("0.20")
        self._total_revenue += amount_eth
        self._developer_earnings += dev_share
        self._neosafe_earnings += neo_share
        self._transactions.append({
            "amount_eth": str(amount_eth),
            "developer_share": str(dev_share),
            "neosafe_share": str(neo_share),
            "source": source,
            "timestamp": time.time(),
        })
        return {"developer": dev_share, "neosafe": neo_share}

    def get_earnings(self) -> Dict[str, str]:
        return {
            "total_revenue_eth": str(self._total_revenue),
            "developer_earnings_eth": str(self._developer_earnings),
            "neosafe_earnings_eth": str(self._neosafe_earnings),
            "neosafe_address": NEOSAFE_ADDRESS,
        }


class GameSDK:
    """Main entry point for game developers.

    Provides unified access to all SDK subsystems.

    Parameters
    ----------
    game_id : str
        Unique game identifier.
    developer_wallet : str
        Developer's wallet address for revenue.
    """

    def __init__(self, game_id: str, developer_wallet: str = "") -> None:
        self.game_id = game_id
        self.assets = AssetManager(game_id)
        self.identity = IdentityManager(game_id)
        self.leaderboard = LeaderboardManager(game_id)
        self.matchmaking = MatchmakingManager(game_id)
        self.revenue = RevenueTracker(game_id, developer_wallet)
        logger.info("GameSDK initialised for game %s", game_id)


__all__ = [
    "GameSDK",
    "AssetManager",
    "IdentityManager",
    "LeaderboardManager",
    "MatchmakingManager",
    "RevenueTracker",
    "Player",
    "GameItem",
    "LeaderboardEntry",
]
