"""
Token Registry — manages approved tokens for DEX trading.

Part of Component 21 (DEX).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class RegisteredToken:
    """A token approved for trading on the DEX."""
    address: str
    name: str
    symbol: str
    decimals: int
    is_verified: bool = False
    is_active: bool = True
    added_at: float = field(default_factory=time.time)
    logo_uri: str = ""
    coingecko_id: str = ""


class TokenRegistry:
    """
    Registry of approved tokens for the MTRX DEX.

    Only registered tokens can be traded. Tokens can be verified
    (vetted by the platform) or unverified (user-added, with warnings).
    """

    def __init__(self) -> None:
        self._tokens: Dict[str, RegisteredToken] = {}
        self._symbols: Dict[str, str] = {}  # symbol -> address
        self._register_defaults()
        logger.info("TokenRegistry initialised with %d default tokens.", len(self._tokens))

    def register_token(
        self,
        address: str,
        name: str,
        symbol: str,
        decimals: int = 18,
        is_verified: bool = False,
        logo_uri: str = "",
    ) -> RegisteredToken:
        """Register a new token."""
        address = address.lower()
        if address in self._tokens:
            raise ValueError(f"Token {address} already registered.")

        token = RegisteredToken(
            address=address,
            name=name,
            symbol=symbol.upper(),
            decimals=decimals,
            is_verified=is_verified,
            logo_uri=logo_uri,
        )
        self._tokens[address] = token
        self._symbols[symbol.upper()] = address
        logger.info("Token registered: %s (%s) verified=%s", name, symbol, is_verified)
        return token

    def get_token(self, address: str) -> Optional[RegisteredToken]:
        """Get token by address."""
        return self._tokens.get(address.lower())

    def get_by_symbol(self, symbol: str) -> Optional[RegisteredToken]:
        """Get token by symbol."""
        address = self._symbols.get(symbol.upper())
        return self._tokens.get(address) if address else None

    def list_tokens(self, verified_only: bool = False) -> List[RegisteredToken]:
        """List all active tokens."""
        tokens = [t for t in self._tokens.values() if t.is_active]
        if verified_only:
            tokens = [t for t in tokens if t.is_verified]
        return tokens

    def verify_token(self, address: str) -> None:
        """Mark a token as verified."""
        token = self._tokens.get(address.lower())
        if token is None:
            raise ValueError(f"Token {address} not found.")
        token.is_verified = True
        logger.info("Token verified: %s", token.symbol)

    def deactivate_token(self, address: str) -> None:
        """Deactivate a token (remove from trading)."""
        token = self._tokens.get(address.lower())
        if token is None:
            raise ValueError(f"Token {address} not found.")
        token.is_active = False
        logger.info("Token deactivated: %s", token.symbol)

    def is_tradeable(self, address: str) -> bool:
        """Check if a token is active and tradeable."""
        token = self._tokens.get(address.lower())
        return token is not None and token.is_active

    def _register_defaults(self) -> None:
        """Register default Base network tokens."""
        defaults = [
            ("0x4200000000000000000000000000000000000006", "Wrapped Ether", "WETH", 18),
            ("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", "USD Coin", "USDC", 6),
            ("0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb", "Dai Stablecoin", "DAI", 18),
        ]
        for addr, name, symbol, decimals in defaults:
            self._tokens[addr.lower()] = RegisteredToken(
                address=addr.lower(),
                name=name,
                symbol=symbol,
                decimals=decimals,
                is_verified=True,
            )
            self._symbols[symbol] = addr.lower()
