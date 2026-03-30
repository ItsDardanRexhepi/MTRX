"""
DEX Trinity Interface — conversational interface for DEX operations.

Part of Component 21 (DEX).
Trinity guides users through swaps, LP management, and market data.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class DEXTrinityInterface:
    """
    Conversational interface for DEX operations through Trinity.

    Translates user intents into DEX operations and presents results
    in plain English.
    """

    def __init__(
        self,
        router: Optional[Any] = None,
        liquidity_manager: Optional[Any] = None,
        price_feed: Optional[Any] = None,
        token_registry: Optional[Any] = None,
    ) -> None:
        self._router = router
        self._lm = liquidity_manager
        self._prices = price_feed
        self._tokens = token_registry
        logger.info("DEXTrinityInterface initialised.")

    def explain_swap(
        self, token_in: str, token_out: str, amount_wei: int,
    ) -> Dict[str, Any]:
        """
        Explain a potential swap in plain English.

        Returns:
            Dict with explanation, fees, price impact, and warnings.
        """
        explanation: Dict[str, Any] = {
            "action": "swap",
            "token_in": token_in,
            "token_out": token_out,
            "amount_in_wei": amount_wei,
        }

        if self._router is not None:
            try:
                quote = self._router.get_quote(token_in, token_out, amount_wei)
                explanation.update({
                    "expected_output_wei": quote.expected_out_wei,
                    "minimum_output_wei": quote.min_out_wei,
                    "price_impact_bps": quote.price_impact_bps,
                    "route": quote.path,
                    "gas_estimate": quote.gas_estimate,
                    "plain_english": self._swap_description(quote),
                })
            except Exception as exc:
                explanation["error"] = str(exc)
                explanation["plain_english"] = f"Unable to quote this swap: {exc}"
        else:
            explanation["plain_english"] = (
                "DEX router not connected. Cannot generate a quote at this time."
            )

        return explanation

    def explain_lp_position(
        self,
        token_a: str,
        token_b: str,
        amount_a: int,
        amount_b: int,
    ) -> Dict[str, Any]:
        """Explain what providing liquidity means in plain English."""
        return {
            "action": "add_liquidity",
            "token_a": token_a,
            "token_b": token_b,
            "plain_english": (
                f"You are providing liquidity for {token_a}/{token_b}. "
                f"Your tokens will be used by traders who swap between these two tokens. "
                f"You earn a share of trading fees proportional to your share of the pool. "
                f"Be aware of impermanent loss: if token prices diverge significantly, "
                f"you may end up with less value than if you had simply held the tokens."
            ),
            "risks": [
                "Impermanent loss if token prices diverge.",
                "Smart contract risk.",
                "Your tokens are locked until you remove liquidity.",
            ],
        }

    def get_market_summary(self, tokens: Optional[List[str]] = None) -> Dict[str, Any]:
        """Get a plain English market summary."""
        if self._prices is None:
            return {"plain_english": "Price feed not connected."}

        if tokens is None:
            tokens = ["WETH", "USDC", "DAI"]

        summaries = []
        for token in tokens:
            try:
                summary = self._prices.get_price_summary(token)
                direction = "up" if summary.change_24h_pct > 0 else "down"
                summaries.append(
                    f"{token}: ${summary.current_price:,.2f} "
                    f"({direction} {abs(summary.change_24h_pct):.1f}% in 24h)"
                )
            except Exception:
                summaries.append(f"{token}: price unavailable")

        return {
            "tokens": tokens,
            "summaries": summaries,
            "plain_english": "Market overview: " + ". ".join(summaries) + ".",
        }

    def _swap_description(self, quote: Any) -> str:
        """Build plain English swap description from a quote."""
        impact = quote.price_impact_bps / 100.0
        warning = ""
        if impact > 1.0:
            warning = (
                f" Warning: price impact is {impact:.1f}%, which is high. "
                f"Consider splitting into smaller trades."
            )
        return (
            f"Swapping {quote.amount_in_wei / 10**18:,.6f} tokens. "
            f"Expected to receive {quote.expected_out_wei / 10**18:,.6f} tokens "
            f"(minimum {quote.min_out_wei / 10**18:,.6f} after slippage). "
            f"Estimated gas: {quote.gas_estimate:,} units.{warning}"
        )
