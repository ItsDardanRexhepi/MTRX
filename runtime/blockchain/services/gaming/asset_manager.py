"""
Game Asset Manager — ERC-1155 game asset management.

Part of Component 14 (Gaming).
Manages game asset types, minting, batch minting, and play-to-earn
claims with cooldown enforcement.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class AssetType:
    """Definition of a game asset type."""
    token_id: int
    game_id: str
    name: str
    max_supply: int
    current_supply: int = 0
    transferable: bool = True
    play_to_earn_eligible: bool = False
    earn_cooldown: int = 0           # Seconds between P2E claims
    uri: str = ""
    created_at: float = field(default_factory=time.time)


@dataclass
class MintRecord:
    """Record of a minting event."""
    token_id: int
    recipient: str
    amount: int
    timestamp: float = field(default_factory=time.time)


class GameAssetManager:
    """
    Manages ERC-1155 game assets.

    Features:
    - Create asset types with configurable supply, transferability, P2E eligibility
    - Mint and batch mint with supply cap enforcement
    - Play-to-earn claims with per-player cooldown tracking
    """

    def __init__(
        self,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._execute = execute_fn
        self._asset_types: Dict[int, AssetType] = {}
        # (player, token_id) -> last claim timestamp
        self._p2e_cooldowns: Dict[Tuple[str, int], float] = {}
        # player -> { token_id -> balance }
        self._balances: Dict[str, Dict[int, int]] = {}
        self._mint_history: List[MintRecord] = []
        self._next_token_id: int = 1
        logger.info("GameAssetManager initialised.")

    # ── Asset Types ───────────────────────────────────────────────────

    def create_asset_type(
        self,
        game_id: str,
        name: str,
        max_supply: int,
        transferable: bool = True,
        play_to_earn_eligible: bool = False,
        earn_cooldown: int = 0,
    ) -> AssetType:
        """
        Create a new game asset type.

        Args:
            game_id: The game this asset belongs to.
            name: Asset type name.
            max_supply: Maximum mintable supply (0 = unlimited).
            transferable: Whether this asset can be transferred between players.
            play_to_earn_eligible: Whether players can earn this via gameplay.
            earn_cooldown: Seconds between P2E claims per player.

        Returns:
            The created AssetType.
        """
        if not name:
            raise ValueError("Asset name must not be empty.")
        if max_supply < 0:
            raise ValueError("Max supply must be non-negative.")

        token_id = self._next_token_id
        self._next_token_id += 1

        asset_type = AssetType(
            token_id=token_id,
            game_id=game_id,
            name=name,
            max_supply=max_supply,
            transferable=transferable,
            play_to_earn_eligible=play_to_earn_eligible,
            earn_cooldown=earn_cooldown,
        )
        self._asset_types[token_id] = asset_type

        logger.info(
            "Asset type created | token=%d | game=%s | name=%s | max=%d",
            token_id, game_id, name, max_supply,
        )
        return asset_type

    def set_token_uri(self, token_id: int, uri: str) -> None:
        """Set the metadata URI for an asset type."""
        asset = self._get_asset_type(token_id)
        asset.uri = uri
        logger.info("Token URI set | token=%d", token_id)

    # ── Minting ───────────────────────────────────────────────────────

    def mint(
        self, recipient: str, token_id: int, amount: int,
    ) -> MintRecord:
        """
        Mint game assets to a recipient.

        Args:
            recipient: Player's address.
            token_id: Asset type to mint.
            amount: Number of tokens.

        Returns:
            MintRecord.
        """
        if not recipient.startswith("0x"):
            raise ValueError("Invalid recipient address.")
        if amount <= 0:
            raise ValueError("Amount must be positive.")

        asset = self._get_asset_type(token_id)
        if asset.max_supply > 0:
            if asset.current_supply + amount > asset.max_supply:
                raise ValueError(
                    f"Would exceed max supply: {asset.current_supply + amount} > {asset.max_supply}."
                )

        asset.current_supply += amount
        self._balances.setdefault(recipient, {})
        self._balances[recipient][token_id] = self._balances[recipient].get(token_id, 0) + amount

        record = MintRecord(token_id=token_id, recipient=recipient, amount=amount)
        self._mint_history.append(record)

        logger.info(
            "Minted | token=%d | to=%s | amount=%d | supply=%d/%d",
            token_id, recipient, amount, asset.current_supply, asset.max_supply,
        )
        return record

    def mint_batch(
        self,
        recipient: str,
        token_ids: List[int],
        amounts: List[int],
    ) -> List[MintRecord]:
        """Batch mint multiple asset types to a recipient."""
        if len(token_ids) != len(amounts):
            raise ValueError("Token IDs and amounts must match in length.")

        records = []
        for tid, amt in zip(token_ids, amounts):
            records.append(self.mint(recipient, tid, amt))
        return records

    # ── Play-to-Earn ──────────────────────────────────────────────────

    def claim_play_to_earn(
        self, player: str, token_id: int, amount: int,
    ) -> MintRecord:
        """
        Claim play-to-earn rewards. Enforces cooldown per player per asset.

        Args:
            player: Player's address.
            token_id: Asset type to claim.
            amount: Number of tokens.

        Returns:
            MintRecord.
        """
        asset = self._get_asset_type(token_id)
        if not asset.play_to_earn_eligible:
            raise ValueError(f"Asset {token_id} is not play-to-earn eligible.")

        # Check cooldown
        key = (player, token_id)
        last_claim = self._p2e_cooldowns.get(key, 0.0)
        now = time.time()
        if asset.earn_cooldown > 0 and (now - last_claim) < asset.earn_cooldown:
            remaining = int(asset.earn_cooldown - (now - last_claim))
            raise ValueError(
                f"Cooldown active: {remaining}s remaining."
            )

        record = self.mint(player, token_id, amount)
        self._p2e_cooldowns[key] = now

        logger.info(
            "P2E claimed | player=%s | token=%d | amount=%d",
            player, token_id, amount,
        )
        return record

    # ── Queries ───────────────────────────────────────────────────────

    def get_asset_type(self, token_id: int) -> Optional[AssetType]:
        """Get asset type or None."""
        return self._asset_types.get(token_id)

    def get_balance(self, player: str, token_id: int) -> int:
        """Get a player's balance of a specific asset."""
        return self._balances.get(player, {}).get(token_id, 0)

    def get_inventory(self, player: str) -> Dict[int, int]:
        """Get a player's full inventory: token_id -> balance."""
        return dict(self._balances.get(player, {}))

    # ── Internal ──────────────────────────────────────────────────────

    def _get_asset_type(self, token_id: int) -> AssetType:
        asset = self._asset_types.get(token_id)
        if asset is None:
            raise ValueError(f"Asset type {token_id} not found.")
        return asset
