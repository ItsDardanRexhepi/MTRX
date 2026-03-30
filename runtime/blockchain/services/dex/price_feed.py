"""
DEX Price Feed — real-time price data via Component 11 oracle.

Part of Component 21 (DEX).
All price data routes through the Component 11 oracle interface.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class PricePoint:
    """A single price data point."""
    token: str
    quote_currency: str
    price: float
    timestamp: float
    source: str = "component_11_oracle"


@dataclass
class PriceSummary:
    """Price summary for a token pair."""
    token: str
    quote_currency: str
    current_price: float
    price_24h_ago: float
    change_24h_pct: float
    high_24h: float
    low_24h: float
    last_updated: float


class DEXPriceFeed:
    """
    Real-time price feed for the DEX via Component 11 oracle.

    All prices are sourced from the Component 11 oracle interface.
    No direct external API calls. Maintains a local cache with TTL
    for performance.
    """

    CACHE_TTL_SECONDS: int = 10
    HISTORY_RETENTION: int = 1000

    def __init__(self, oracle: Optional[Any] = None) -> None:
        """
        Args:
            oracle: Component 11 oracle interface.
        """
        self._oracle = oracle
        self._cache: Dict[str, PricePoint] = {}
        self._history: Dict[str, List[PricePoint]] = {}
        logger.info("DEXPriceFeed initialised (via Component 11 oracle).")

    def get_price(self, token: str, quote: str = "USD") -> float:
        """
        Get current price for a token pair.

        Args:
            token: Token address or symbol.
            quote: Quote currency (default USD).

        Returns:
            Current price as float.
        """
        cache_key = f"{token}/{quote}"
        cached = self._cache.get(cache_key)

        if cached and (time.time() - cached.timestamp) < self.CACHE_TTL_SECONDS:
            return cached.price

        price = self._fetch_from_oracle(token, quote)
        point = PricePoint(token=token, quote_currency=quote, price=price, timestamp=time.time())
        self._cache[cache_key] = point

        if cache_key not in self._history:
            self._history[cache_key] = []
        self._history[cache_key].append(point)
        if len(self._history[cache_key]) > self.HISTORY_RETENTION:
            self._history[cache_key] = self._history[cache_key][-self.HISTORY_RETENTION:]

        return price

    def get_price_summary(self, token: str, quote: str = "USD") -> PriceSummary:
        """Get 24h price summary for a token."""
        current = self.get_price(token, quote)
        cache_key = f"{token}/{quote}"
        history = self._history.get(cache_key, [])

        cutoff = time.time() - 86_400
        recent = [p for p in history if p.timestamp > cutoff]

        if not recent:
            return PriceSummary(
                token=token, quote_currency=quote,
                current_price=current, price_24h_ago=current,
                change_24h_pct=0.0, high_24h=current, low_24h=current,
                last_updated=time.time(),
            )

        prices = [p.price for p in recent]
        oldest = recent[0].price

        return PriceSummary(
            token=token, quote_currency=quote,
            current_price=current,
            price_24h_ago=oldest,
            change_24h_pct=((current - oldest) / oldest * 100) if oldest > 0 else 0.0,
            high_24h=max(prices),
            low_24h=min(prices),
            last_updated=time.time(),
        )

    def get_prices_batch(self, tokens: List[str], quote: str = "USD") -> Dict[str, float]:
        """Get prices for multiple tokens."""
        return {token: self.get_price(token, quote) for token in tokens}

    def _fetch_from_oracle(self, token: str, quote: str) -> float:
        """Fetch price from Component 11 oracle."""
        if self._oracle is not None:
            try:
                return self._oracle.get_price(token, quote)
            except Exception:
                logger.exception("Oracle price fetch failed for %s/%s.", token, quote)
                raise
        logger.warning("Oracle not connected — returning 0.0 for %s/%s.", token, quote)
        return 0.0
