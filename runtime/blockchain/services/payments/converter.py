"""
Currency Converter — converts between currencies using Component 11 oracle prices.

Part of Component 17 (Payments).
All price data routes through the Component 11 oracle interface.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Protocol

logger = logging.getLogger(__name__)


class OracleInterface(Protocol):
    """Protocol for Component 11 oracle price data."""

    def get_price(self, base: str, quote: str) -> float:
        """Get the price of base currency in terms of quote currency."""
        ...

    def get_price_wei(self, base: str, quote: str) -> int:
        """Get the price in wei-denominated fixed point."""
        ...


@dataclass
class ConversionQuote:
    """A currency conversion quote from the oracle."""
    quote_id: str
    from_currency: str
    to_currency: str
    from_amount_wei: int
    to_amount_wei: int
    exchange_rate: float
    oracle_price_timestamp: float
    valid_until: float
    slippage_bps: int = 0


@dataclass
class ConversionRecord:
    """Record of a completed conversion."""
    record_id: str
    quote: ConversionQuote
    executed_at: float
    actual_to_amount_wei: int
    tx_hash: Optional[str] = None


class CurrencyConverter:
    """
    Converts between currencies using Component 11 oracle price feeds.

    All price data is fetched from the Component 11 oracle interface.
    No direct external API calls are made — the oracle is the single
    source of truth for exchange rates.

    Supports configurable slippage tolerance and quote expiry.
    """

    DEFAULT_QUOTE_TTL: int = 60          # 60 seconds
    DEFAULT_SLIPPAGE_BPS: int = 50       # 0.5%
    MAX_SLIPPAGE_BPS: int = 500          # 5%

    def __init__(
        self,
        oracle: Optional[Any] = None,
        quote_ttl: int = DEFAULT_QUOTE_TTL,
        default_slippage_bps: int = DEFAULT_SLIPPAGE_BPS,
    ) -> None:
        """
        Args:
            oracle: Component 11 oracle interface for price data.
            quote_ttl: How long a conversion quote is valid (seconds).
            default_slippage_bps: Default slippage tolerance in basis points.
        """
        self._oracle = oracle
        self._quote_ttl = quote_ttl
        self._default_slippage = default_slippage_bps

        self._quotes: Dict[str, ConversionQuote] = {}
        self._records: List[ConversionRecord] = []
        self._counter: int = 0

        # Supported currency pairs (extensible)
        self._supported_currencies = {"ETH", "USDC", "USDT", "DAI", "MTRX", "WETH"}

        logger.info(
            "CurrencyConverter initialised (oracle=%s, ttl=%ds).",
            "connected" if oracle else "disconnected", quote_ttl,
        )

    # ── Quoting ───────────────────────────────────────────────────────

    def get_quote(
        self,
        from_currency: str,
        to_currency: str,
        from_amount_wei: int,
        slippage_bps: Optional[int] = None,
    ) -> ConversionQuote:
        """
        Get a conversion quote from the Component 11 oracle.

        Args:
            from_currency: Source currency code.
            to_currency: Target currency code.
            from_amount_wei: Amount to convert in wei.
            slippage_bps: Slippage tolerance (defaults to class default).

        Returns:
            ConversionQuote with exchange rate and output amount.

        Raises:
            ValueError: If currencies are unsupported or oracle is unavailable.
        """
        from_currency = from_currency.upper()
        to_currency = to_currency.upper()

        if from_currency not in self._supported_currencies:
            raise ValueError(f"Unsupported currency: {from_currency}")
        if to_currency not in self._supported_currencies:
            raise ValueError(f"Unsupported currency: {to_currency}")
        if from_currency == to_currency:
            raise ValueError("Cannot convert a currency to itself.")
        if from_amount_wei <= 0:
            raise ValueError("Amount must be positive.")

        slippage = slippage_bps if slippage_bps is not None else self._default_slippage
        if slippage > self.MAX_SLIPPAGE_BPS:
            raise ValueError(
                f"Slippage {slippage} bps exceeds maximum {self.MAX_SLIPPAGE_BPS} bps."
            )

        # Fetch rate from Component 11 oracle
        rate = self._get_oracle_rate(from_currency, to_currency)
        now = time.time()

        # Apply slippage for worst-case estimate
        slippage_factor = 1.0 - (slippage / 10_000)
        to_amount = int(from_amount_wei * rate * slippage_factor)

        self._counter += 1
        quote_id = f"QUOTE-{self._counter:08d}"

        quote = ConversionQuote(
            quote_id=quote_id,
            from_currency=from_currency,
            to_currency=to_currency,
            from_amount_wei=from_amount_wei,
            to_amount_wei=to_amount,
            exchange_rate=rate,
            oracle_price_timestamp=now,
            valid_until=now + self._quote_ttl,
            slippage_bps=slippage,
        )
        self._quotes[quote_id] = quote

        logger.info(
            "Quote generated | id=%s | %s->%s | rate=%.6f | amount=%d -> %d",
            quote_id, from_currency, to_currency, rate, from_amount_wei, to_amount,
        )
        return quote

    def execute_conversion(
        self,
        quote_id: str,
        execute_fn: Optional[Any] = None,
    ) -> ConversionRecord:
        """
        Execute a previously quoted conversion.

        Args:
            quote_id: The quote to execute.
            execute_fn: Optional callable for on-chain execution.

        Returns:
            ConversionRecord of the completed conversion.

        Raises:
            ValueError: If quote not found or expired.
        """
        quote = self._quotes.get(quote_id)
        if quote is None:
            raise ValueError(f"Quote {quote_id} not found.")

        now = time.time()
        if now > quote.valid_until:
            raise ValueError(
                f"Quote {quote_id} expired {now - quote.valid_until:.0f}s ago."
            )

        # Re-fetch current rate to get actual output
        current_rate = self._get_oracle_rate(quote.from_currency, quote.to_currency)
        actual_output = int(quote.from_amount_wei * current_rate)

        # Verify slippage is within tolerance
        min_acceptable = quote.to_amount_wei
        if actual_output < min_acceptable:
            raise ValueError(
                f"Slippage exceeded: expected min {min_acceptable}, got {actual_output}."
            )

        tx_hash: Optional[str] = None
        if execute_fn is not None:
            tx_hash = execute_fn(
                quote.from_currency,
                quote.to_currency,
                quote.from_amount_wei,
                actual_output,
            )

        record = ConversionRecord(
            record_id=f"CONV-{self._counter:08d}",
            quote=quote,
            executed_at=now,
            actual_to_amount_wei=actual_output,
            tx_hash=tx_hash,
        )
        self._records.append(record)

        logger.info(
            "Conversion executed | quote=%s | actual_output=%d wei | tx=%s",
            quote_id, actual_output, tx_hash,
        )
        return record

    # ── Queries ───────────────────────────────────────────────────────

    def get_supported_currencies(self) -> set[str]:
        """Return the set of supported currencies."""
        return set(self._supported_currencies)

    def add_supported_currency(self, currency: str) -> None:
        """Add a new supported currency."""
        self._supported_currencies.add(currency.upper())
        logger.info("Added supported currency: %s", currency.upper())

    def get_exchange_rate(self, from_currency: str, to_currency: str) -> float:
        """
        Get the current exchange rate from the oracle.

        Args:
            from_currency: Source currency.
            to_currency: Target currency.

        Returns:
            Exchange rate as a float.
        """
        return self._get_oracle_rate(from_currency.upper(), to_currency.upper())

    def get_conversion_history(self, limit: int = 50) -> List[ConversionRecord]:
        """Return recent conversion records."""
        return list(reversed(self._records[-limit:]))

    # ── Internal ──────────────────────────────────────────────────────

    def _get_oracle_rate(self, from_currency: str, to_currency: str) -> float:
        """
        Fetch exchange rate from Component 11 oracle.

        Falls back to a 1:1 rate if oracle is unavailable (development only).
        """
        if self._oracle is not None:
            try:
                return self._oracle.get_price(from_currency, to_currency)
            except Exception:
                logger.exception(
                    "Oracle price fetch failed for %s/%s.", from_currency, to_currency,
                )
                raise

        # Fallback for development/testing only
        logger.warning(
            "Oracle not connected — using fallback rate for %s/%s.",
            from_currency, to_currency,
        )
        return 1.0
