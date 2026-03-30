"""
Chainlink Price Feed
=====================

ETH, USDC, and all supported asset price feeds via Chainlink oracles
on Base. Provides real-time and historical price data for the platform.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
BASE_CHAIN_ID: int = 8453

# Chainlink price feed addresses on Base
CHAINLINK_FEEDS: Dict[str, str] = {
    "ETH/USD": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
    "USDC/USD": "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B",
    "BTC/USD": "0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F",
    "LINK/USD": "0x17CAb8FE31cA45e4654FaFb5b5e2e5a4e0E58E4e",
    "DAI/USD": "0x591e79239a7d679378eC8c847e5038150364C78F",
    "WETH/USD": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
}

# Standard Chainlink AggregatorV3 ABI (latestRoundData)
AGGREGATOR_ABI = [
    {
        "inputs": [],
        "name": "latestRoundData",
        "outputs": [
            {"name": "roundId", "type": "uint80"},
            {"name": "answer", "type": "int256"},
            {"name": "startedAt", "type": "uint256"},
            {"name": "updatedAt", "type": "uint256"},
            {"name": "answeredInRound", "type": "uint80"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "stateMutability": "view",
        "type": "function",
    },
]


@dataclass
class PricePoint:
    """A single price data point."""
    asset: str
    currency: str
    price: Decimal
    decimals: int
    round_id: int
    updated_at: float
    source: str = "chainlink"
    feed_address: str = ""

    @property
    def age_seconds(self) -> float:
        return time.time() - self.updated_at


@dataclass
class PriceHistory:
    """Historical price data for an asset."""
    asset: str
    currency: str
    data_points: List[PricePoint] = field(default_factory=list)


class ChainlinkPriceFeed:
    """Chainlink price feed provider for Base.

    Reads real-time prices from Chainlink's decentralised oracle
    network on Base. Supports ETH, USDC, BTC, LINK, DAI, and
    custom feed registration.

    Parameters
    ----------
    web3_provider : Any
        Web3 provider connected to Base.
    custom_feeds : dict, optional
        Additional feed address mappings.
    staleness_threshold : int
        Maximum acceptable price age in seconds.
    """

    def __init__(
        self,
        web3_provider: Any = None,
        custom_feeds: Optional[Dict[str, str]] = None,
        staleness_threshold: int = 3600,
    ) -> None:
        self._web3 = web3_provider
        self._feeds = dict(CHAINLINK_FEEDS)
        if custom_feeds:
            self._feeds.update(custom_feeds)
        self._staleness = staleness_threshold
        self._price_cache: Dict[str, PricePoint] = {}
        self._history: Dict[str, PriceHistory] = {}
        logger.info(
            "ChainlinkPriceFeed initialised with %d feeds", len(self._feeds)
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def fetch(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Fetch price data (called by OracleInterface).

        Args:
            parameters: Must contain 'asset' and optionally 'currency'.

        Returns:
            Dict with price data for aggregation.
        """
        asset = parameters.get("asset", "ETH")
        currency = parameters.get("currency", "USD")
        price_point = self.get_price(asset, currency)

        return {
            "value": float(price_point.price),
            "asset": asset,
            "currency": currency,
            "updated_at": price_point.updated_at,
            "source": "chainlink",
            "round_id": price_point.round_id,
            "decimals": price_point.decimals,
            "feed_address": price_point.feed_address,
        }

    def get_price(self, asset: str, currency: str = "USD") -> PricePoint:
        """Get the latest price for an asset pair.

        Args:
            asset: Asset symbol (ETH, BTC, USDC, etc.).
            currency: Quote currency (default USD).

        Returns:
            PricePoint with the latest price.

        Raises:
            ValueError: If no feed exists for the pair.
        """
        pair = f"{asset.upper()}/{currency.upper()}"
        feed_address = self._feeds.get(pair)
        if feed_address is None:
            raise ValueError(f"No Chainlink feed for {pair}")

        # Check cache
        cached = self._price_cache.get(pair)
        if cached and cached.age_seconds < 30:
            return cached

        # Fetch from chain
        price_point = self._read_feed(pair, feed_address)

        # Validate staleness
        if price_point.age_seconds > self._staleness:
            logger.warning(
                "Price data for %s is stale (%.0fs old)", pair, price_point.age_seconds
            )

        # Update cache and history
        self._price_cache[pair] = price_point
        if pair not in self._history:
            self._history[pair] = PriceHistory(asset=asset, currency=currency)
        self._history[pair].data_points.append(price_point)

        return price_point

    def get_prices_batch(
        self, pairs: List[str]
    ) -> Dict[str, PricePoint]:
        """Get prices for multiple pairs.

        Args:
            pairs: List of pair strings like ["ETH/USD", "BTC/USD"].

        Returns:
            Dict mapping pair to PricePoint.
        """
        results: Dict[str, PricePoint] = {}
        for pair in pairs:
            parts = pair.split("/")
            if len(parts) == 2:
                try:
                    results[pair] = self.get_price(parts[0], parts[1])
                except Exception as exc:
                    logger.error("Failed to fetch %s: %s", pair, exc)
        return results

    def get_history(
        self, asset: str, currency: str = "USD", limit: int = 100
    ) -> List[PricePoint]:
        """Get price history for an asset pair."""
        pair = f"{asset.upper()}/{currency.upper()}"
        history = self._history.get(pair)
        if history is None:
            return []
        return list(reversed(history.data_points[-limit:]))

    def register_feed(self, pair: str, feed_address: str) -> None:
        """Register a custom Chainlink feed address."""
        self._feeds[pair.upper()] = feed_address
        logger.info("Custom feed registered: %s -> %s", pair, feed_address)

    def list_supported_pairs(self) -> List[str]:
        """List all supported price pairs."""
        return list(self._feeds.keys())

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _read_feed(self, pair: str, feed_address: str) -> PricePoint:
        """Read the latest round data from a Chainlink feed."""
        asset, currency = pair.split("/")

        if self._web3 is None:
            # Simulated prices for when no web3 connection
            simulated_prices = {
                "ETH": Decimal("3200.50"),
                "BTC": Decimal("67500.00"),
                "USDC": Decimal("1.0000"),
                "LINK": Decimal("18.75"),
                "DAI": Decimal("1.0001"),
                "WETH": Decimal("3200.50"),
            }
            return PricePoint(
                asset=asset,
                currency=currency,
                price=simulated_prices.get(asset, Decimal("0")),
                decimals=8,
                round_id=0,
                updated_at=time.time(),
                feed_address=feed_address,
            )

        contract = self._web3.eth.contract(
            address=feed_address, abi=AGGREGATOR_ABI
        )

        round_id, answer, _, updated_at, _ = contract.functions.latestRoundData().call()
        decimals = contract.functions.decimals().call()

        price = Decimal(str(answer)) / Decimal(10 ** decimals)

        return PricePoint(
            asset=asset,
            currency=currency,
            price=price,
            decimals=decimals,
            round_id=round_id,
            updated_at=float(updated_at),
            feed_address=feed_address,
        )
