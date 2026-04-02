"""
Marketplace Service — peer-to-peer NFT/asset trading.

Part of Component 24 (Marketplace).
Handles listing, purchasing, cancellation, compliance filtering,
EAS attestation attachment, and contract blocking.
5% platform fee on purchases flows to NeoSafe.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional, Set

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
PLATFORM_FEE_BPS: int = 500  # 5%


class AssetStandard(Enum):
    """Supported asset token standards."""
    ERC721 = "erc721"
    ERC1155 = "erc1155"


class ListingStatus(Enum):
    """Marketplace listing states."""
    ACTIVE = "active"
    SOLD = "sold"
    CANCELLED = "cancelled"


@dataclass
class Listing:
    """A marketplace listing."""
    listing_id: str
    seller: str
    asset_contract: str
    token_id: int
    amount: int                      # 1 for ERC721, variable for ERC1155
    price_per_unit_wei: int
    standard: AssetStandard
    status: ListingStatus = ListingStatus.ACTIVE
    eas_attestation: str = ""
    created_at: float = field(default_factory=time.time)
    buyer: str = ""
    sold_at: float = 0.0


@dataclass
class PurchaseRecord:
    """Record of a marketplace purchase."""
    listing_id: str
    buyer: str
    seller: str
    total_price_wei: int
    platform_fee_wei: int
    seller_proceeds_wei: int
    timestamp: float = field(default_factory=time.time)


class MarketplaceService:
    """
    Manages the peer-to-peer NFT/asset marketplace.

    Features:
    - ERC721 and ERC1155 listing support
    - 5% platform fee on all purchases
    - Compliance filtering: blocked contracts cannot be listed
    - EAS attestation attachment for verified assets
    """

    def __init__(
        self,
        compliance_filter: Optional[Any] = None,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._compliance = compliance_filter
        self._execute = execute_fn
        self._listings: Dict[str, Listing] = {}
        self._blocked_contracts: Set[str] = set()
        self._purchases: List[PurchaseRecord] = []
        self._counter: int = 0
        logger.info("MarketplaceService initialised.")

    # ── Listing ───────────────────────────────────────────────────────

    def list_erc721(
        self,
        seller: str,
        asset_contract: str,
        token_id: int,
        price_wei: int,
    ) -> Listing:
        """
        List an ERC721 asset for sale.

        Args:
            seller: Seller's address.
            asset_contract: NFT contract address.
            token_id: Token ID.
            price_wei: Listing price in wei.

        Returns:
            The created Listing.
        """
        self._validate_listing(seller, asset_contract, price_wei)

        self._counter += 1
        lid = f"LIST-{self._counter:08d}"

        listing = Listing(
            listing_id=lid,
            seller=seller,
            asset_contract=asset_contract,
            token_id=token_id,
            amount=1,
            price_per_unit_wei=price_wei,
            standard=AssetStandard.ERC721,
        )
        self._listings[lid] = listing

        logger.info(
            "ERC721 listed | id=%s | seller=%s | contract=%s | token=%d | price=%d",
            lid, seller, asset_contract, token_id, price_wei,
        )
        return listing

    def list_erc1155(
        self,
        seller: str,
        asset_contract: str,
        token_id: int,
        amount: int,
        price_per_unit_wei: int,
    ) -> Listing:
        """
        List ERC1155 assets for sale.

        Args:
            seller: Seller's address.
            asset_contract: Asset contract address.
            token_id: Token ID.
            amount: Number of units.
            price_per_unit_wei: Price per unit in wei.

        Returns:
            The created Listing.
        """
        self._validate_listing(seller, asset_contract, price_per_unit_wei)
        if amount <= 0:
            raise ValueError("Amount must be positive.")

        self._counter += 1
        lid = f"LIST-{self._counter:08d}"

        listing = Listing(
            listing_id=lid,
            seller=seller,
            asset_contract=asset_contract,
            token_id=token_id,
            amount=amount,
            price_per_unit_wei=price_per_unit_wei,
            standard=AssetStandard.ERC1155,
        )
        self._listings[lid] = listing

        logger.info(
            "ERC1155 listed | id=%s | seller=%s | amount=%d | price=%d",
            lid, seller, amount, price_per_unit_wei,
        )
        return listing

    # ── Purchase ──────────────────────────────────────────────────────

    def purchase(self, listing_id: str, buyer: str) -> PurchaseRecord:
        """
        Purchase a listed asset.

        Args:
            buyer: Buyer's address.

        Returns:
            PurchaseRecord with fee breakdown.
        """
        listing = self._get_listing(listing_id)
        if listing.status != ListingStatus.ACTIVE:
            raise ValueError(f"Listing {listing_id} is {listing.status.value}.")
        if not buyer.startswith("0x"):
            raise ValueError("Invalid buyer address.")
        if buyer == listing.seller:
            raise ValueError("Seller cannot buy their own listing.")

        total_price = listing.price_per_unit_wei * listing.amount
        fee = (total_price * PLATFORM_FEE_BPS) // 10_000
        seller_proceeds = total_price - fee

        listing.status = ListingStatus.SOLD
        listing.buyer = buyer
        listing.sold_at = time.time()

        record = PurchaseRecord(
            listing_id=listing_id,
            buyer=buyer,
            seller=listing.seller,
            total_price_wei=total_price,
            platform_fee_wei=fee,
            seller_proceeds_wei=seller_proceeds,
        )
        self._purchases.append(record)

        logger.info(
            "Purchased | id=%s | buyer=%s | total=%d | fee=%d",
            listing_id, buyer, total_price, fee,
        )
        return record

    def cancel_listing(self, listing_id: str, caller: str) -> Listing:
        """Cancel a listing. Only the seller can cancel."""
        listing = self._get_listing(listing_id)
        if listing.seller != caller:
            raise ValueError("Only the seller can cancel.")
        if listing.status != ListingStatus.ACTIVE:
            raise ValueError(f"Listing is {listing.status.value}.")

        listing.status = ListingStatus.CANCELLED
        logger.info("Listing cancelled | id=%s", listing_id)
        return listing

    # ── EAS Attestation ───────────────────────────────────────────────

    def attach_attestation(
        self, listing_id: str, caller: str, attestation_uid: str,
    ) -> Listing:
        """Attach an EAS attestation to a listing."""
        listing = self._get_listing(listing_id)
        if listing.seller != caller:
            raise ValueError("Only the seller can attach attestations.")
        if listing.status != ListingStatus.ACTIVE:
            raise ValueError("Can only attach to active listings.")

        listing.eas_attestation = attestation_uid
        logger.info(
            "Attestation attached | listing=%s | uid=%s",
            listing_id, attestation_uid,
        )
        return listing

    def get_attestation(self, listing_id: str) -> tuple[bool, str]:
        """Get attestation info for a listing."""
        listing = self._listings.get(listing_id)
        if listing is None:
            return False, ""
        has = bool(listing.eas_attestation)
        return has, listing.eas_attestation

    # ── Compliance ────────────────────────────────────────────────────

    def block_contract(self, contract_addr: str) -> None:
        """Block a contract from being listed."""
        self._blocked_contracts.add(contract_addr)
        logger.info("Contract blocked | addr=%s", contract_addr)

    def unblock_contract(self, contract_addr: str) -> None:
        """Unblock a contract."""
        self._blocked_contracts.discard(contract_addr)
        logger.info("Contract unblocked | addr=%s", contract_addr)

    # ── Queries ───────────────────────────────────────────────────────

    def get_listing(self, listing_id: str) -> Optional[Listing]:
        """Get listing or None."""
        return self._listings.get(listing_id)

    def list_listings(
        self,
        status: Optional[ListingStatus] = None,
        asset_contract: Optional[str] = None,
    ) -> List[Listing]:
        """List marketplace listings with optional filters."""
        listings = list(self._listings.values())
        if status is not None:
            listings = [l for l in listings if l.status == status]
        if asset_contract is not None:
            listings = [l for l in listings if l.asset_contract == asset_contract]
        return listings

    def get_total_volume_wei(self) -> int:
        """Get total marketplace trading volume."""
        return sum(p.total_price_wei for p in self._purchases)

    def get_total_fees_wei(self) -> int:
        """Get total platform fees collected."""
        return sum(p.platform_fee_wei for p in self._purchases)

    # ── Internal ──────────────────────────────────────────────────────

    def _validate_listing(
        self, seller: str, asset_contract: str, price_wei: int,
    ) -> None:
        """Validate listing preconditions."""
        if not seller.startswith("0x"):
            raise ValueError("Invalid seller address.")
        if not asset_contract.startswith("0x"):
            raise ValueError("Invalid asset contract address.")
        if price_wei <= 0:
            raise ValueError("Price must be positive.")
        if asset_contract in self._blocked_contracts:
            raise ValueError(f"Contract {asset_contract} is blocked.")

    def _get_listing(self, listing_id: str) -> Listing:
        """Get listing or raise."""
        listing = self._listings.get(listing_id)
        if listing is None:
            raise ValueError(f"Listing {listing_id} not found.")
        return listing
