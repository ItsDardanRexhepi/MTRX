"""C14 - Gaming: game registry, funding, assets, and revenue."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.gaming.game_registry import GameRegistryService
from runtime.blockchain.services.gaming.game_funding import GameFundingService
from runtime.blockchain.services.gaming.asset_manager import GameAssetManager
from runtime.blockchain.services.gaming.revenue_splitter import RevenueSplitter

router = APIRouter()

_registry = GameRegistryService()
_funding = GameFundingService()
_assets = GameAssetManager()
_splitters: dict = {}  # game_id -> RevenueSplitter


class SubmitGameRequest(BaseModel):
    developer: str
    name: str
    metadata_uri: str


class CreateFundedGameRequest(BaseModel):
    developer: str
    revenue_contract: str


class MilestoneRequest(BaseModel):
    description: str
    cost_wei: int


class FundRequest(BaseModel):
    amount_wei: int
    caller: str = ""


class AssetTypeRequest(BaseModel):
    game_id: str
    name: str
    max_supply: int
    transferable: bool = True
    play_to_earn_eligible: bool = False
    earn_cooldown: int = 0


class MintRequest(BaseModel):
    recipient: str
    token_id: int
    amount: int


class RevenueRequest(BaseModel):
    amount_wei: int


# ── Registry ──────────────────────────────────────────────────────

@router.post("/registry/submit")
async def submit_game(request: SubmitGameRequest):
    """Submit a game for vetting."""
    try:
        g = _registry.submit_game(request.developer, request.name, request.metadata_uri)
        return {"game_id": g.game_id, "name": g.name, "stage": g.stage.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/registry/{game_id}")
async def get_game(game_id: str):
    """Get game registry details."""
    g = _registry.get_game(game_id)
    if g is None:
        raise HTTPException(status_code=404, detail="Game not found.")
    return {
        "game_id": g.game_id, "developer": g.developer, "name": g.name,
        "stage": g.stage.value, "version": g.version,
    }


# ── Funding ───────────────────────────────────────────────────────

@router.post("/funding/create")
async def create_funded_game(request: CreateFundedGameRequest):
    """Register a game for milestone funding."""
    try:
        g = _funding.create_game(request.developer, request.revenue_contract)
        return {"game_id": g.game_id, "developer": g.developer, "status": g.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/funding/{game_id}/milestone")
async def add_milestone(game_id: str, request: MilestoneRequest):
    """Add a milestone to a funded game."""
    try:
        idx = _funding.add_milestone(game_id, request.description, request.cost_wei)
        return {"game_id": game_id, "milestone_index": idx}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/funding/{game_id}/milestone/{idx}/fund-platform")
async def fund_platform(game_id: str, idx: int, request: FundRequest):
    """Fund the platform share of a milestone."""
    try:
        ms = _funding.fund_platform_share(game_id, idx, request.amount_wei)
        return {"status": ms.status.value, "platform_deposit_wei": ms.platform_deposit_wei}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/funding/{game_id}/milestone/{idx}/fund-developer")
async def fund_developer(game_id: str, idx: int, request: FundRequest):
    """Fund the developer share of a milestone."""
    try:
        ms = _funding.fund_developer_share(game_id, idx, request.caller, request.amount_wei)
        return {"status": ms.status.value, "developer_deposit_wei": ms.developer_deposit_wei}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/funding/{game_id}/milestone/{idx}/complete")
async def complete_milestone(game_id: str, idx: int):
    """Mark a milestone as completed."""
    try:
        ms = _funding.complete_milestone(game_id, idx)
        return {"status": ms.status.value, "released_wei": ms.released_to_developer_wei}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ── Assets ────────────────────────────────────────────────────────

@router.post("/asset/create-type")
async def create_asset_type(request: AssetTypeRequest):
    """Create a new game asset type."""
    try:
        a = _assets.create_asset_type(
            request.game_id, request.name, request.max_supply,
            request.transferable, request.play_to_earn_eligible, request.earn_cooldown,
        )
        return {"token_id": a.token_id, "name": a.name, "max_supply": a.max_supply}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/asset/mint")
async def mint_asset(request: MintRequest):
    """Mint game assets to a recipient."""
    try:
        r = _assets.mint(request.recipient, request.token_id, request.amount)
        return {"token_id": r.token_id, "recipient": r.recipient, "amount": r.amount}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/asset/{token_id}")
async def get_asset_type(token_id: int):
    """Get game asset type details."""
    a = _assets.get_asset_type(token_id)
    if a is None:
        raise HTTPException(status_code=404, detail="Asset type not found.")
    return {
        "token_id": a.token_id, "game_id": a.game_id, "name": a.name,
        "max_supply": a.max_supply, "current_supply": a.current_supply,
        "transferable": a.transferable, "play_to_earn_eligible": a.play_to_earn_eligible,
    }


@router.get("/player/{player_address}/inventory")
async def get_inventory(player_address: str):
    """Get a player's game asset inventory."""
    inv = _assets.get_inventory(player_address)
    return {"player": player_address, "assets": inv, "total": sum(inv.values())}


# ── Revenue ───────────────────────────────────────────────────────

@router.post("/revenue/{game_id}/deposit")
async def deposit_revenue(game_id: str, request: RevenueRequest):
    """Deposit game revenue for splitting."""
    if game_id not in _splitters:
        g = _funding.get_game(game_id)
        if g is None:
            raise HTTPException(status_code=404, detail="Game not found.")
        _splitters[game_id] = RevenueSplitter(game_id, g.developer)
    try:
        balance = _splitters[game_id].deposit_revenue(request.amount_wei)
        return {"game_id": game_id, "pending_balance_wei": balance}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/revenue/{game_id}/distribute")
async def distribute_revenue(game_id: str):
    """Distribute pending revenue (80% dev / 20% platform)."""
    if game_id not in _splitters:
        raise HTTPException(status_code=404, detail="No revenue deposited.")
    try:
        d = _splitters[game_id].distribute_balance()
        return {"game_id": game_id, "developer_wei": d.developer_wei, "platform_wei": d.platform_wei}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
