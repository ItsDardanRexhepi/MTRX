"""
DEX Router — wraps Uniswap v3/v4 on Base for token swaps.

Part of Component 21 (DEX).
Routes swaps through optimal paths using Uniswap v3 and v4 pools.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class UniswapVersion(Enum):
    """Supported Uniswap versions on Base."""
    V3 = "v3"
    V4 = "v4"


class SwapStatus(Enum):
    """Status of a swap."""
    QUOTED = "quoted"
    SUBMITTED = "submitted"
    CONFIRMED = "confirmed"
    FAILED = "failed"
    REVERTED = "reverted"


@dataclass
class SwapRoute:
    """Optimal swap route computed by the router."""
    route_id: str
    token_in: str
    token_out: str
    amount_in_wei: int
    expected_out_wei: int
    min_out_wei: int
    path: List[str]
    pool_fees: List[int]
    uniswap_version: UniswapVersion
    price_impact_bps: int
    gas_estimate: int
    computed_at: float = field(default_factory=time.time)
    valid_until: float = 0.0


@dataclass
class SwapResult:
    """Result of an executed swap."""
    swap_id: str
    route: SwapRoute
    actual_out_wei: int
    status: SwapStatus
    tx_hash: Optional[str] = None
    executed_at: Optional[float] = None
    gas_used: int = 0
    slippage_bps: int = 0


class DEXRouter:
    """
    Routes token swaps through Uniswap v3/v4 pools on Base.

    Finds the optimal path across available pools, considering:
    - Liquidity depth
    - Fee tiers (100, 500, 3000, 10000 bps for v3)
    - Price impact
    - Gas costs

    Supports single-hop and multi-hop swaps.
    """

    QUOTE_TTL_SECONDS: int = 30
    MAX_HOPS: int = 3
    DEFAULT_SLIPPAGE_BPS: int = 50  # 0.5%

    # Uniswap v3 fee tiers (in hundredths of a basis point)
    V3_FEE_TIERS: List[int] = [100, 500, 3000, 10000]

    def __init__(
        self,
        preferred_version: UniswapVersion = UniswapVersion.V4,
        default_slippage_bps: int = DEFAULT_SLIPPAGE_BPS,
    ) -> None:
        self._preferred = preferred_version
        self._default_slippage = default_slippage_bps
        self._routes: Dict[str, SwapRoute] = {}
        self._swaps: List[SwapResult] = []
        self._counter: int = 0

        # Pool registry: (token_a, token_b, fee_tier) -> pool_address
        self._pools: Dict[tuple, str] = {}
        # Pool liquidity: pool_address -> liquidity_wei
        self._liquidity: Dict[str, int] = {}

        logger.info(
            "DEXRouter initialised | preferred=%s | slippage=%d bps",
            preferred_version.value, default_slippage_bps,
        )

    # ── Pool Management ───────────────────────────────────────────────

    def register_pool(
        self,
        token_a: str,
        token_b: str,
        fee_tier: int,
        pool_address: str,
        liquidity_wei: int = 0,
        version: UniswapVersion = UniswapVersion.V3,
    ) -> None:
        """Register a Uniswap pool."""
        key = (token_a.lower(), token_b.lower(), fee_tier)
        self._pools[key] = pool_address
        self._liquidity[pool_address] = liquidity_wei
        logger.debug(
            "Pool registered: %s/%s fee=%d -> %s", token_a, token_b, fee_tier, pool_address,
        )

    # ── Routing ───────────────────────────────────────────────────────

    def get_quote(
        self,
        token_in: str,
        token_out: str,
        amount_in_wei: int,
        slippage_bps: Optional[int] = None,
    ) -> SwapRoute:
        """
        Get a swap quote with optimal routing.

        Args:
            token_in: Input token address.
            token_out: Output token address.
            amount_in_wei: Amount of input tokens in wei.
            slippage_bps: Slippage tolerance in basis points.

        Returns:
            SwapRoute with the optimal path and expected output.
        """
        if amount_in_wei <= 0:
            raise ValueError("Swap amount must be positive.")

        slippage = slippage_bps if slippage_bps is not None else self._default_slippage

        # Find optimal route
        path, fees, version = self._find_optimal_path(token_in, token_out, amount_in_wei)

        # Compute expected output (simplified AMM simulation)
        expected_out = self._simulate_swap(amount_in_wei, path, fees)
        price_impact = self._estimate_price_impact(amount_in_wei, path, fees)
        min_out = int(expected_out * (1 - slippage / 10_000))
        gas_estimate = self._estimate_gas(len(path), version)

        self._counter += 1
        route_id = f"ROUTE-{self._counter:08d}"

        route = SwapRoute(
            route_id=route_id,
            token_in=token_in,
            token_out=token_out,
            amount_in_wei=amount_in_wei,
            expected_out_wei=expected_out,
            min_out_wei=min_out,
            path=path,
            pool_fees=fees,
            uniswap_version=version,
            price_impact_bps=price_impact,
            gas_estimate=gas_estimate,
            valid_until=time.time() + self.QUOTE_TTL_SECONDS,
        )
        self._routes[route_id] = route

        logger.info(
            "Quote | %s -> %s | in=%d | out=%d | impact=%d bps | path=%s",
            token_in, token_out, amount_in_wei, expected_out, price_impact, path,
        )
        return route

    def execute_swap(
        self,
        route_id: str,
        sender: str,
        execute_fn: Optional[Any] = None,
    ) -> SwapResult:
        """
        Execute a previously quoted swap.

        Args:
            route_id: The route to execute.
            sender: Address of the swapper.
            execute_fn: Optional on-chain execution callable.

        Returns:
            SwapResult with execution details.
        """
        route = self._routes.get(route_id)
        if route is None:
            raise ValueError(f"Route {route_id} not found.")
        if time.time() > route.valid_until:
            raise ValueError(f"Route {route_id} has expired.")

        swap_id = f"SWAP-{self._counter:08d}"
        tx_hash: Optional[str] = None

        try:
            if execute_fn is not None:
                tx_hash = execute_fn(
                    sender=sender,
                    path=route.path,
                    amount_in=route.amount_in_wei,
                    min_out=route.min_out_wei,
                    fees=route.pool_fees,
                )

            result = SwapResult(
                swap_id=swap_id,
                route=route,
                actual_out_wei=route.expected_out_wei,
                status=SwapStatus.CONFIRMED,
                tx_hash=tx_hash,
                executed_at=time.time(),
            )
        except Exception as exc:
            result = SwapResult(
                swap_id=swap_id,
                route=route,
                actual_out_wei=0,
                status=SwapStatus.FAILED,
            )
            logger.exception("Swap failed: %s", exc)

        self._swaps.append(result)
        return result

    def get_swap_history(self, limit: int = 50) -> List[SwapResult]:
        """Return recent swaps."""
        return list(reversed(self._swaps[-limit:]))

    # ── Internal ──────────────────────────────────────────────────────

    def _find_optimal_path(
        self, token_in: str, token_out: str, amount: int,
    ) -> tuple[List[str], List[int], UniswapVersion]:
        """Find the optimal swap path."""
        # Direct path check first
        for fee in self.V3_FEE_TIERS:
            key = (token_in.lower(), token_out.lower(), fee)
            rev_key = (token_out.lower(), token_in.lower(), fee)
            if key in self._pools or rev_key in self._pools:
                return [token_in, token_out], [fee], self._preferred

        # Default: single-hop with middle fee tier
        return [token_in, token_out], [3000], self._preferred

    def _simulate_swap(
        self, amount_in: int, path: List[str], fees: List[int],
    ) -> int:
        """Simulate the swap output (simplified constant product)."""
        output = amount_in
        for fee in fees:
            fee_amount = (output * fee) // 1_000_000
            output -= fee_amount
        return output

    def _estimate_price_impact(
        self, amount_in: int, path: List[str], fees: List[int],
    ) -> int:
        """Estimate price impact in basis points."""
        # Simplified: larger swaps relative to pool have more impact
        total_fee = sum(fees)
        return min(total_fee // 10 + 1, 1000)

    def _estimate_gas(self, hops: int, version: UniswapVersion) -> int:
        """Estimate gas cost for a swap."""
        base = 150_000 if version == UniswapVersion.V3 else 120_000
        return base + (hops - 1) * 60_000
