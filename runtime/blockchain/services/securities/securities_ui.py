"""
Securities UI — user-facing interface for securities token exchange.

Part of Component 18 (Securities Token Exchange).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from runtime.blockchain.services.securities.fee_calculator import SecuritiesFeeCalculator
from runtime.blockchain.services.securities.compliance_registry import ComplianceRegistry
from runtime.blockchain.services.securities.terms_negotiator import TermsNegotiator

logger = logging.getLogger(__name__)


@dataclass
class SecurityToken:
    """A listed security token."""
    token_address: str
    name: str
    symbol: str
    total_supply: int
    issuer: str
    asset_type: str  # e.g. "equity", "debt", "fund"
    listed_at: float = field(default_factory=time.time)
    is_active: bool = True


@dataclass
class ExchangeView:
    """Data for rendering the securities exchange UI."""
    user_address: str
    compliance_status: str
    available_tokens: List[Dict[str, Any]]
    active_negotiations: List[Dict[str, Any]]
    recent_trades: List[Dict[str, Any]]
    fee_info: Dict[str, Any]
    plain_english_summary: str


class SecuritiesUI:
    """
    User-facing interface for the securities token exchange.

    Provides listing, discovery, trade initiation, and status views.
    All trades incur a 0.25% fee calculated by SecuritiesFeeCalculator.
    """

    def __init__(
        self,
        fee_calculator: SecuritiesFeeCalculator,
        compliance_registry: ComplianceRegistry,
        terms_negotiator: TermsNegotiator,
    ) -> None:
        self._fees = fee_calculator
        self._compliance = compliance_registry
        self._negotiator = terms_negotiator
        self._tokens: Dict[str, SecurityToken] = {}
        self._trades: List[Dict[str, Any]] = []
        logger.info("SecuritiesUI initialised.")

    def list_token(
        self,
        token_address: str,
        name: str,
        symbol: str,
        total_supply: int,
        issuer: str,
        asset_type: str,
    ) -> SecurityToken:
        """
        List a new security token on the exchange.

        Args:
            token_address: Contract address of the security token.
            name: Human-readable token name.
            symbol: Token symbol.
            total_supply: Total token supply.
            issuer: Address of the issuer.
            asset_type: Type of security (equity, debt, fund).

        Returns:
            The listed SecurityToken.
        """
        if token_address in self._tokens:
            raise ValueError(f"Token {token_address} is already listed.")

        token = SecurityToken(
            token_address=token_address,
            name=name,
            symbol=symbol,
            total_supply=total_supply,
            issuer=issuer,
            asset_type=asset_type,
        )
        self._tokens[token_address] = token
        logger.info("Security token listed: %s (%s)", name, symbol)
        return token

    def delist_token(self, token_address: str) -> None:
        """Delist a security token."""
        token = self._tokens.get(token_address)
        if token is None:
            raise ValueError(f"Token {token_address} not found.")
        token.is_active = False
        logger.info("Security token delisted: %s", token.symbol)

    def get_exchange_view(self, user_address: str) -> ExchangeView:
        """
        Generate the complete exchange view for a user.

        Args:
            user_address: The user viewing the exchange.

        Returns:
            ExchangeView ready for rendering.
        """
        # Compliance status
        record = self._compliance.get_record(user_address)
        compliance_status = record.status.value if record else "unregistered"

        # Available tokens
        available = [
            {
                "address": t.token_address,
                "name": t.name,
                "symbol": t.symbol,
                "asset_type": t.asset_type,
                "issuer": t.issuer,
            }
            for t in self._tokens.values() if t.is_active
        ]

        # Active negotiations
        negotiations = self._negotiator.get_negotiations_for(user_address)
        active_negs = [
            {
                "negotiation_id": n.negotiation_id,
                "counterparty": n.counterparty if n.proposer == user_address else n.proposer,
                "token": n.current_terms.security_token,
                "quantity": n.current_terms.quantity,
                "price": n.current_terms.price_per_unit_wei,
                "status": n.status.value,
            }
            for n in negotiations
            if n.status.value in ("proposed", "counter_offered")
        ]

        # Fee info
        fee_info = {
            "rate_bps": self._fees.get_fee_rate_bps(),
            "rate_percent": self._fees.get_fee_rate_bps() / 100.0,
            "description": "0.25% fee on every securities exchange.",
        }

        # Summary
        summary = self._build_summary(user_address, compliance_status, len(available), len(active_negs))

        return ExchangeView(
            user_address=user_address,
            compliance_status=compliance_status,
            available_tokens=available,
            active_negotiations=active_negs,
            recent_trades=[t for t in self._trades if user_address in (t.get("buyer"), t.get("seller"))][-10:],
            fee_info=fee_info,
            plain_english_summary=summary,
        )

    def record_trade(
        self,
        buyer: str,
        seller: str,
        token_address: str,
        quantity: int,
        price_per_unit_wei: int,
    ) -> Dict[str, Any]:
        """Record a completed trade."""
        total = quantity * price_per_unit_wei
        fee_result = self._fees.calculate_fee(total, token_address)

        trade = {
            "buyer": buyer,
            "seller": seller,
            "token": token_address,
            "quantity": quantity,
            "price_per_unit_wei": price_per_unit_wei,
            "total_wei": total,
            "fee_wei": fee_result.fee_wei,
            "net_to_seller_wei": total - fee_result.fee_wei,
            "timestamp": time.time(),
        }
        self._trades.append(trade)
        return trade

    def _build_summary(
        self, user: str, compliance: str, token_count: int, neg_count: int,
    ) -> str:
        """Build plain English summary."""
        if compliance == "unregistered":
            return (
                "You are not yet registered for securities trading. "
                "Complete compliance verification to start trading."
            )
        if compliance != "verified":
            return f"Your compliance status is '{compliance}'. Trading may be restricted."

        parts = [f"You are verified for securities trading. {token_count} securities are available."]
        if neg_count > 0:
            parts.append(f"You have {neg_count} active negotiation(s).")
        parts.append("Each trade incurs a 0.25% exchange fee.")
        return " ".join(parts)
