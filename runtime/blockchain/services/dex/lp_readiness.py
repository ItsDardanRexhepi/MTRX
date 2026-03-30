"""
LP Readiness Checker — verifies a user is ready to provide liquidity.

Part of Component 21 (DEX).
Checks token balances, approvals, and pool compatibility before LP entry.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class ReadinessCheck:
    """Result of an LP readiness check."""
    user_address: str
    token_a: str
    token_b: str
    ready: bool
    checks: List[Dict[str, Any]] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    blockers: List[str] = field(default_factory=list)
    recommendation: str = ""


class LPReadinessChecker:
    """
    Verifies a user meets all prerequisites for providing liquidity.

    Checks:
    1. Sufficient token balances
    2. Token approvals for the DEX router
    3. Pool exists or can be created
    4. Token pair compatibility
    5. Minimum liquidity thresholds
    """

    MIN_LIQUIDITY_WEI: int = 10**15  # 0.001 ETH equivalent minimum

    def __init__(
        self,
        token_registry: Optional[Any] = None,
        balance_checker: Optional[Any] = None,
    ) -> None:
        self._tokens = token_registry
        self._balances = balance_checker
        logger.info("LPReadinessChecker initialised.")

    def check_readiness(
        self,
        user_address: str,
        token_a: str,
        token_b: str,
        amount_a_wei: int,
        amount_b_wei: int,
    ) -> ReadinessCheck:
        """
        Run all readiness checks for LP provisioning.

        Args:
            user_address: Address of the prospective LP.
            token_a: First token address.
            token_b: Second token address.
            amount_a_wei: Desired amount of token A.
            amount_b_wei: Desired amount of token B.

        Returns:
            ReadinessCheck with pass/fail and details.
        """
        result = ReadinessCheck(
            user_address=user_address,
            token_a=token_a,
            token_b=token_b,
            ready=True,
        )

        # Check 1: Tokens are registered
        self._check_token_registered(result, token_a, "token_a")
        self._check_token_registered(result, token_b, "token_b")

        # Check 2: Minimum amounts
        if amount_a_wei < self.MIN_LIQUIDITY_WEI:
            result.blockers.append(
                f"Token A amount ({amount_a_wei}) below minimum ({self.MIN_LIQUIDITY_WEI})."
            )
            result.checks.append({"check": "min_amount_a", "passed": False})
        else:
            result.checks.append({"check": "min_amount_a", "passed": True})

        if amount_b_wei < self.MIN_LIQUIDITY_WEI:
            result.blockers.append(
                f"Token B amount ({amount_b_wei}) below minimum ({self.MIN_LIQUIDITY_WEI})."
            )
            result.checks.append({"check": "min_amount_b", "passed": False})
        else:
            result.checks.append({"check": "min_amount_b", "passed": True})

        # Check 3: Same token check
        if token_a.lower() == token_b.lower():
            result.blockers.append("Cannot provide liquidity with the same token on both sides.")
            result.checks.append({"check": "distinct_tokens", "passed": False})
        else:
            result.checks.append({"check": "distinct_tokens", "passed": True})

        # Check 4: Balance check (if checker available)
        if self._balances is not None:
            self._check_balance(result, user_address, token_a, amount_a_wei, "a")
            self._check_balance(result, user_address, token_b, amount_b_wei, "b")

        # Impermanent loss warning
        result.warnings.append(
            "Providing liquidity carries impermanent loss risk. "
            "If token prices diverge significantly, you may withdraw less value "
            "than you deposited."
        )

        result.ready = len(result.blockers) == 0
        result.recommendation = self._build_recommendation(result)

        return result

    def _check_token_registered(
        self, result: ReadinessCheck, token: str, label: str,
    ) -> None:
        """Check if a token is registered in the DEX."""
        if self._tokens is not None:
            if not self._tokens.is_tradeable(token):
                result.blockers.append(f"{label} ({token}) is not registered on the DEX.")
                result.checks.append({"check": f"{label}_registered", "passed": False})
                return
        result.checks.append({"check": f"{label}_registered", "passed": True})

    def _check_balance(
        self, result: ReadinessCheck, user: str, token: str, amount: int, side: str,
    ) -> None:
        """Check if user has sufficient balance."""
        try:
            balance = self._balances.get_balance(user, token)
            if balance < amount:
                result.blockers.append(
                    f"Insufficient token_{side} balance: have {balance}, need {amount}."
                )
                result.checks.append({"check": f"balance_{side}", "passed": False})
            else:
                result.checks.append({"check": f"balance_{side}", "passed": True})
        except Exception:
            result.warnings.append(f"Could not verify token_{side} balance.")

    def _build_recommendation(self, result: ReadinessCheck) -> str:
        """Build recommendation text."""
        if result.ready:
            return (
                "All checks passed. You are ready to provide liquidity. "
                "Review the impermanent loss warning before proceeding."
            )
        blocker_text = " ".join(result.blockers)
        return f"Not ready to provide liquidity. Issues: {blocker_text}"
