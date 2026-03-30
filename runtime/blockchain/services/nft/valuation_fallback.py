"""
NFT Valuation Fallback Engine — Component 3

Provides fallback valuation when an NFT has NO recorded secondary trading
at the 90-day assessment mark.

Fallback hierarchy:
    1. Floor price of the most similar verified collection on Base
    2. If no comparable collection found: default to original mint value

In either case, the creator still has a 7-day window to pay 10% of
whichever value is assessed.

NeoSafe: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from web3 import Web3
from web3.contract import Contract

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────
#  Constants
# ──────────────────────────────────────────────

NEOSAFE_ADDRESS = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
PAYMENT_PERCENTAGE = Decimal("0.10")

# Base chain ID
BASE_CHAIN_ID = 8453

# Similarity matching thresholds
MIN_SIMILARITY_SCORE = Decimal("0.60")  # Minimum 60% similarity to use as comparable
MAX_COMPARABLE_AGE_DAYS = 180           # Collection must have activity within 180 days


# ──────────────────────────────────────────────
#  Data Classes
# ──────────────────────────────────────────────

@dataclass
class CollectionInfo:
    """Information about a verified NFT collection on Base."""
    address: str
    name: str
    symbol: str
    total_supply: int
    floor_price_wei: int
    volume_24h_wei: int
    verified: bool
    category: str                    # e.g., "art", "music", "photography", "generative"
    created_at: Optional[datetime] = None
    similarity_score: Decimal = Decimal("0")
    metadata_tags: List[str] = field(default_factory=list)
    chain_id: int = BASE_CHAIN_ID


@dataclass
class NFTMetadata:
    """Parsed NFT metadata for similarity matching."""
    nft_id: int
    name: str
    description: str
    category: str
    tags: List[str]
    attributes: Dict[str, Any]
    media_type: str                  # "image", "video", "audio", "3d"
    creator_address: str
    mint_price_wei: int
    collection_size: int


# ──────────────────────────────────────────────
#  Valuation Fallback Engine
# ──────────────────────────────────────────────

class ValuationFallback:
    """
    Fallback valuation engine for NFTs with no secondary market trading.

    When an NFT reaches its 90-day assessment and has zero recorded
    secondary sales, this engine determines value using:

        1. Floor price of the most similar verified collection on Base
        2. If no comparable collection exists: original mint value

    The creator still has 7 days to pay 10% of the assessed value.
    """

    def __init__(
        self,
        web3_provider: Web3,
        oracle: Any,  # Component11OracleInterface from valuation.py
        nft_contract: Optional[Contract] = None,
        subgraph_url: Optional[str] = None,
        collection_registry_url: Optional[str] = None,
    ):
        self._w3 = web3_provider
        self._oracle = oracle
        self._nft_contract = nft_contract
        self._subgraph_url = subgraph_url
        self._collection_registry_url = collection_registry_url

        # Cache verified collections for efficiency
        self._collections_cache: Optional[List[CollectionInfo]] = None
        self._cache_timestamp: Optional[datetime] = None
        self._cache_ttl_seconds = 3600  # 1 hour

    # ──────────────────────────────────────────
    #  Public API
    # ──────────────────────────────────────────

    async def find_comparable_collection(
        self, nft_metadata: Dict[str, Any]
    ) -> Optional[CollectionInfo]:
        """
        Find the most similar verified collection on Base for comparison.

        Similarity is determined by:
            - Category match (art, music, photography, generative)
            - Attribute overlap
            - Media type match
            - Price range proximity
            - Collection size similarity

        Args:
            nft_metadata: Dictionary with keys like 'uri', 'nft_id', 'category',
                         'tags', 'attributes', 'media_type', etc.

        Returns:
            CollectionInfo of the most similar verified collection, or None
        """
        logger.info(f"Finding comparable collection for NFT metadata: {nft_metadata.get('nft_id', 'unknown')}")

        # Parse NFT metadata
        parsed = await self._parse_metadata(nft_metadata)

        # Fetch verified collections on Base
        collections = await self._get_verified_collections()

        if not collections:
            logger.warning("No verified collections found on Base")
            return None

        # Score each collection for similarity
        scored_collections: List[CollectionInfo] = []
        for collection in collections:
            score = self._calculate_similarity(parsed, collection)
            collection.similarity_score = score
            if score >= MIN_SIMILARITY_SCORE:
                scored_collections.append(collection)

        if not scored_collections:
            logger.info(f"No comparable collections found above similarity threshold ({MIN_SIMILARITY_SCORE})")
            return None

        # Sort by similarity score descending, return the best match
        scored_collections.sort(key=lambda c: c.similarity_score, reverse=True)
        best_match = scored_collections[0]

        logger.info(
            f"Best comparable collection: {best_match.name} "
            f"(similarity={best_match.similarity_score}, "
            f"floor={best_match.floor_price_wei} wei)"
        )

        return best_match

    async def get_floor_price(self, collection_address: str) -> Decimal:
        """
        Get the current floor price for a verified collection on Base.

        Queries the marketplace subgraph for the lowest active listing price.

        Args:
            collection_address: Contract address of the collection

        Returns:
            Floor price in wei as Decimal, or Decimal(0) if unavailable
        """
        if not Web3.is_address(collection_address):
            raise ValueError(f"Invalid collection address: {collection_address}")

        collection_address = Web3.to_checksum_address(collection_address)

        # Query subgraph for floor price
        if self._subgraph_url:
            try:
                import aiohttp
                query = """
                query GetCollectionFloor($collection: String!) {
                    listings(
                        where: {
                            collection: $collection,
                            active: true
                        },
                        orderBy: price,
                        orderDirection: asc,
                        first: 1
                    ) {
                        price
                        tokenId
                    }
                    collectionStats(id: $collection) {
                        floorPrice
                        totalVolume
                        totalSales
                    }
                }
                """
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        self._subgraph_url,
                        json={"query": query, "variables": {"collection": collection_address.lower()}},
                        timeout=aiohttp.ClientTimeout(total=10),
                    ) as resp:
                        resp.raise_for_status()
                        data = await resp.json()

                        # Try collection stats first (more reliable)
                        stats = data.get("data", {}).get("collectionStats")
                        if stats and stats.get("floorPrice"):
                            return Decimal(str(stats["floorPrice"]))

                        # Fall back to lowest active listing
                        listings = data.get("data", {}).get("listings", [])
                        if listings:
                            return Decimal(str(listings[0]["price"]))

            except Exception as e:
                logger.warning(f"Floor price subgraph query failed for {collection_address}: {e}")

        # On-chain fallback: query recent sales for estimated floor
        try:
            # Get recent transfer events to estimate activity and floor
            latest_block = self._w3.eth.block_number
            from_block = max(0, latest_block - 100000)  # ~2 days of blocks on Base

            # Look at recent sale prices as floor proxy
            logs = self._w3.eth.get_logs({
                "fromBlock": from_block,
                "toBlock": "latest",
                "address": collection_address,
                "topics": [
                    Web3.keccak(text="Transfer(address,address,uint256)").hex()
                ],
            })

            if logs:
                # Estimate floor from transaction values
                sale_values = []
                for log_entry in logs[-50:]:  # Last 50 transfers
                    tx = self._w3.eth.get_transaction(log_entry["transactionHash"])
                    if tx.value > 0:
                        sale_values.append(tx.value)

                if sale_values:
                    return Decimal(str(min(sale_values)))

        except Exception as e:
            logger.warning(f"On-chain floor price estimation failed for {collection_address}: {e}")

        return Decimal("0")

    async def fallback_valuation(self, nft_id: int) -> Decimal:
        """
        Perform fallback valuation for an NFT with no secondary trading.

        Hierarchy:
            1. Floor price of the most similar verified collection on Base
            2. If no comparable: original mint value

        Args:
            nft_id: Token ID to value

        Returns:
            Assessed value in wei as Decimal
        """
        logger.info(f"Starting fallback valuation for NFT #{nft_id}")

        # Get token metadata for comparison
        metadata = await self._get_token_metadata(nft_id)

        # Attempt comparable collection valuation
        comparable = await self.find_comparable_collection(metadata)

        if comparable and comparable.verified:
            floor_price = await self.get_floor_price(comparable.address)
            if floor_price > 0:
                logger.info(
                    f"Fallback valuation for NFT #{nft_id}: "
                    f"using comparable collection '{comparable.name}' "
                    f"floor price = {floor_price} wei"
                )
                return floor_price

        # No comparable found — use original mint value
        mint_value = await self.use_mint_value(nft_id)
        logger.info(
            f"Fallback valuation for NFT #{nft_id}: "
            f"no comparable collection, using mint value = {mint_value} wei"
        )
        return mint_value

    async def use_mint_value(self, nft_id: int) -> Decimal:
        """
        Get the original mint value for an NFT as the final fallback.

        Args:
            nft_id: Token ID

        Returns:
            Original mint price in wei as Decimal.
            If mint was free (zero gas to creator), returns a minimum floor value.
        """
        try:
            if self._nft_contract:
                token_info = self._nft_contract.functions.tokenInfo(nft_id).call()
                mint_price = token_info[2]  # mintPrice field index

                if mint_price > 0:
                    return Decimal(str(mint_price))

            # If mint was free, look at the NFTMinted event for any value
            if self._nft_contract:
                mint_filter = self._nft_contract.events.NFTMinted.create_filter(
                    fromBlock=0,
                    argument_filters={"tokenId": nft_id},
                )
                events = mint_filter.get_all_entries()
                if events:
                    event_mint_price = events[0].args.mintPrice
                    if event_mint_price > 0:
                        return Decimal(str(event_mint_price))

        except Exception as e:
            logger.warning(f"Failed to retrieve mint value for NFT #{nft_id}: {e}")

        # Absolute minimum floor: 0.001 ETH (prevents zero-value assessments)
        minimum_floor_wei = Decimal("1000000000000000")  # 0.001 ETH in wei
        logger.info(f"NFT #{nft_id}: using minimum floor value of 0.001 ETH")
        return minimum_floor_wei

    # ──────────────────────────────────────────
    #  Internal Methods
    # ──────────────────────────────────────────

    async def _parse_metadata(self, raw_metadata: Dict[str, Any]) -> NFTMetadata:
        """Parse raw metadata dict into structured NFTMetadata."""
        # Handle both direct metadata and URI-based metadata
        nft_id = raw_metadata.get("nft_id", 0)
        uri = raw_metadata.get("uri", "")

        # If we have a URI, attempt to fetch and parse it
        resolved: Dict[str, Any] = {}
        if uri and (uri.startswith("ipfs://") or uri.startswith("https://")):
            try:
                import aiohttp
                fetch_url = uri
                if uri.startswith("ipfs://"):
                    ipfs_hash = uri.replace("ipfs://", "")
                    fetch_url = f"https://ipfs.io/ipfs/{ipfs_hash}"

                async with aiohttp.ClientSession() as session:
                    async with session.get(fetch_url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                        if resp.status == 200:
                            resolved = await resp.json()
            except Exception as e:
                logger.warning(f"Failed to fetch metadata URI for NFT #{nft_id}: {e}")

        # Merge resolved metadata with raw input
        return NFTMetadata(
            nft_id=nft_id,
            name=resolved.get("name", raw_metadata.get("name", "")),
            description=resolved.get("description", raw_metadata.get("description", "")),
            category=self._infer_category(resolved, raw_metadata),
            tags=resolved.get("tags", raw_metadata.get("tags", [])),
            attributes=resolved.get("attributes", raw_metadata.get("attributes", {})),
            media_type=self._infer_media_type(resolved, raw_metadata),
            creator_address=raw_metadata.get("creator_address", ""),
            mint_price_wei=raw_metadata.get("mint_price_wei", 0),
            collection_size=raw_metadata.get("collection_size", 1),
        )

    async def _get_token_metadata(self, nft_id: int) -> Dict[str, Any]:
        """Fetch token metadata from the contract."""
        metadata: Dict[str, Any] = {"nft_id": nft_id}

        if self._nft_contract:
            try:
                token_info = self._nft_contract.functions.tokenInfo(nft_id).call()
                metadata["creator_address"] = token_info[0]
                metadata["mint_price_wei"] = token_info[2]
                metadata["uri"] = token_info[5]

                # Try to get token URI for full metadata
                try:
                    uri = self._nft_contract.functions.tokenURI(nft_id).call()
                    metadata["uri"] = uri
                except Exception:
                    pass

            except Exception as e:
                logger.warning(f"Failed to fetch token info for NFT #{nft_id}: {e}")

        return metadata

    async def _get_verified_collections(self) -> List[CollectionInfo]:
        """Fetch list of verified collections on Base, with caching."""
        now = datetime.now(timezone.utc)

        if (
            self._collections_cache is not None
            and self._cache_timestamp is not None
            and (now - self._cache_timestamp).total_seconds() < self._cache_ttl_seconds
        ):
            return self._collections_cache

        collections: List[CollectionInfo] = []

        # Query collection registry
        if self._collection_registry_url:
            try:
                import aiohttp
                async with aiohttp.ClientSession() as session:
                    async with session.get(
                        f"{self._collection_registry_url}/v1/collections",
                        params={"chain_id": BASE_CHAIN_ID, "verified": True, "limit": 500},
                        timeout=aiohttp.ClientTimeout(total=15),
                    ) as resp:
                        resp.raise_for_status()
                        data = await resp.json()

                        for item in data.get("collections", []):
                            collections.append(CollectionInfo(
                                address=item["address"],
                                name=item["name"],
                                symbol=item.get("symbol", ""),
                                total_supply=item.get("total_supply", 0),
                                floor_price_wei=item.get("floor_price_wei", 0),
                                volume_24h_wei=item.get("volume_24h_wei", 0),
                                verified=item.get("verified", False),
                                category=item.get("category", "unknown"),
                                metadata_tags=item.get("tags", []),
                                created_at=datetime.fromisoformat(item["created_at"]) if item.get("created_at") else None,
                            ))

            except Exception as e:
                logger.warning(f"Failed to fetch verified collections: {e}")

        # Subgraph fallback for collection data
        if not collections and self._subgraph_url:
            try:
                import aiohttp
                query = """
                query GetVerifiedCollections {
                    collections(
                        where: { verified: true },
                        orderBy: totalVolume,
                        orderDirection: desc,
                        first: 200
                    ) {
                        id
                        name
                        symbol
                        totalSupply
                        floorPrice
                        volume24h
                        category
                    }
                }
                """
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        self._subgraph_url,
                        json={"query": query},
                        timeout=aiohttp.ClientTimeout(total=15),
                    ) as resp:
                        resp.raise_for_status()
                        data = await resp.json()

                        for item in data.get("data", {}).get("collections", []):
                            collections.append(CollectionInfo(
                                address=item["id"],
                                name=item["name"],
                                symbol=item.get("symbol", ""),
                                total_supply=int(item.get("totalSupply", 0)),
                                floor_price_wei=int(item.get("floorPrice", 0)),
                                volume_24h_wei=int(item.get("volume24h", 0)),
                                verified=True,
                                category=item.get("category", "unknown"),
                            ))

            except Exception as e:
                logger.warning(f"Subgraph collection query failed: {e}")

        self._collections_cache = collections
        self._cache_timestamp = now

        logger.info(f"Loaded {len(collections)} verified collections on Base")
        return collections

    def _calculate_similarity(self, nft: NFTMetadata, collection: CollectionInfo) -> Decimal:
        """
        Calculate similarity score between an NFT and a collection.

        Scoring weights:
            - Category match: 35%
            - Tag/attribute overlap: 25%
            - Media type inference: 15%
            - Price range proximity: 15%
            - Collection size proximity: 10%
        """
        score = Decimal("0")

        # Category match (35%)
        if nft.category and collection.category:
            if nft.category.lower() == collection.category.lower():
                score += Decimal("0.35")
            elif self._categories_related(nft.category, collection.category):
                score += Decimal("0.17")

        # Tag overlap (25%)
        if nft.tags and collection.metadata_tags:
            nft_tags_lower = {t.lower() for t in nft.tags}
            collection_tags_lower = {t.lower() for t in collection.metadata_tags}
            if nft_tags_lower and collection_tags_lower:
                overlap = len(nft_tags_lower & collection_tags_lower)
                total = len(nft_tags_lower | collection_tags_lower)
                jaccard = Decimal(str(overlap)) / Decimal(str(total)) if total > 0 else Decimal("0")
                score += jaccard * Decimal("0.25")

        # Media type inference (15%)
        media_categories = {
            "image": ["art", "photography", "generative", "pfp"],
            "audio": ["music", "sound"],
            "video": ["video", "animation", "film"],
            "3d": ["3d", "metaverse", "gaming"],
        }
        media_cats = media_categories.get(nft.media_type, [])
        if collection.category.lower() in media_cats:
            score += Decimal("0.15")

        # Price range proximity (15%)
        if nft.mint_price_wei > 0 and collection.floor_price_wei > 0:
            ratio = Decimal(str(min(nft.mint_price_wei, collection.floor_price_wei))) / \
                    Decimal(str(max(nft.mint_price_wei, collection.floor_price_wei)))
            score += ratio * Decimal("0.15")

        # Collection size proximity (10%)
        if nft.collection_size > 0 and collection.total_supply > 0:
            size_ratio = Decimal(str(min(nft.collection_size, collection.total_supply))) / \
                         Decimal(str(max(nft.collection_size, collection.total_supply)))
            score += size_ratio * Decimal("0.10")

        return score.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    @staticmethod
    def _categories_related(cat1: str, cat2: str) -> bool:
        """Check if two categories are semantically related."""
        related_groups = [
            {"art", "generative", "photography", "illustration"},
            {"music", "sound", "audio"},
            {"video", "animation", "film"},
            {"gaming", "3d", "metaverse", "virtual"},
            {"pfp", "collectible", "avatar"},
        ]
        c1, c2 = cat1.lower(), cat2.lower()
        for group in related_groups:
            if c1 in group and c2 in group:
                return True
        return False

    @staticmethod
    def _infer_category(resolved: Dict[str, Any], raw: Dict[str, Any]) -> str:
        """Infer category from metadata."""
        for source in [resolved, raw]:
            if "category" in source:
                return source["category"]
            # Infer from attributes or properties
            attrs = source.get("attributes", source.get("properties", {}))
            if isinstance(attrs, dict) and "category" in attrs:
                return attrs["category"]
            if isinstance(attrs, list):
                for attr in attrs:
                    if isinstance(attr, dict) and attr.get("trait_type", "").lower() == "category":
                        return attr.get("value", "unknown")
        return "unknown"

    @staticmethod
    def _infer_media_type(resolved: Dict[str, Any], raw: Dict[str, Any]) -> str:
        """Infer media type from metadata."""
        for source in [resolved, raw]:
            if "media_type" in source:
                return source["media_type"]
            # Infer from animation_url or image fields
            if "animation_url" in source:
                url = source["animation_url"].lower()
                if any(ext in url for ext in [".mp4", ".webm", ".mov"]):
                    return "video"
                if any(ext in url for ext in [".mp3", ".wav", ".flac", ".ogg"]):
                    return "audio"
                if any(ext in url for ext in [".glb", ".gltf"]):
                    return "3d"
            if "image" in source:
                return "image"
        return "image"
