"""C3 - NFT: minting, transfer, and metadata management for non-fungible tokens."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class MintRequest(BaseModel):
    name: str
    description: str
    image_uri: str
    attributes: dict | None = None
    collection_id: str | None = None


class TransferRequest(BaseModel):
    token_id: str
    to_address: str


class NFTResponse(BaseModel):
    token_id: str
    name: str
    owner: str
    contract_address: str
    status: str


@router.post("/mint", response_model=NFTResponse)
async def mint_nft(request: MintRequest):
    """Mint a new NFT on Base."""
    return NFTResponse(token_id="", name=request.name, owner="", contract_address="", status="pending")


@router.get("/{token_id}")
async def get_nft(token_id: str):
    """Get NFT metadata and ownership info."""
    return {"token_id": token_id, "name": "", "owner": "", "metadata": {}}


@router.post("/transfer")
async def transfer_nft(request: TransferRequest):
    """Transfer an NFT to another address."""
    return {"token_id": request.token_id, "to": request.to_address, "status": "pending"}


@router.get("/collection/{collection_id}")
async def list_collection(collection_id: str):
    """List all NFTs in a collection."""
    return {"collection_id": collection_id, "tokens": [], "total": 0}


@router.post("/{token_id}/burn")
async def burn_nft(token_id: str):
    """Burn an NFT permanently."""
    return {"token_id": token_id, "status": "burned"}
