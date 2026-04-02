"""
Coverage Manager
==================

All eligible users receive ALL coverage products simultaneously.
No partial enrollment. Coordinates between EligibilityTracker,
PolicyRegistry, and PremiumCalculator to manage full-spectrum coverage.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class CoverageProduct(Enum):
    RENTERS = "renters"
    TRAVEL = "travel"
    PARAMETRIC_WEATHER = "parametric_weather"
    FLIGHT_DELAY = "flight_delay"
    PACKAGE_PROTECTION = "package_protection"
    SMART_CONTRACT = "smart_contract"
    COLLATERAL_PROTECTION = "collateral_protection"
    STAKING_SLASHING = "staking_slashing"


DEFAULT_COVERAGE_LIMITS: Dict[CoverageProduct, Decimal] = {
    CoverageProduct.RENTERS: Decimal("20"),
    CoverageProduct.TRAVEL: Decimal("5"),
    CoverageProduct.PARAMETRIC_WEATHER: Decimal("10"),
    CoverageProduct.FLIGHT_DELAY: Decimal("3"),
    CoverageProduct.PACKAGE_PROTECTION: Decimal("2"),
    CoverageProduct.SMART_CONTRACT: Decimal("50"),
    CoverageProduct.COLLATERAL_PROTECTION: Decimal("100"),
    CoverageProduct.STAKING_SLASHING: Decimal("32"),
}


@dataclass
class WalletCoverage:
    """Full coverage state for a single wallet."""
    wallet_address: str
    active_products: List[CoverageProduct] = field(default_factory=list)
    policy_ids: Dict[str, str] = field(default_factory=dict)
    total_coverage_eth: Decimal = Decimal("0")
    total_premium_eth: Decimal = Decimal("0")
    enrolled_at: Optional[float] = None
    last_verified: float = field(default_factory=time.time)


class CoverageManager:
    """Manages simultaneous enrollment in all coverage products.

    When a wallet becomes eligible, CoverageManager ensures they
    are enrolled in ALL products at once. No partial coverage.

    Parameters
    ----------
    policy_registry : Any
        Component 13 PolicyRegistry.
    premium_calculator : Any
        Component 13 PremiumCalculator.
    eligibility_tracker : Any
        Component 13 EligibilityTracker.
    """

    def __init__(
        self,
        policy_registry: Any = None,
        premium_calculator: Any = None,
        eligibility_tracker: Any = None,
    ) -> None:
        self._registry = policy_registry
        self._calculator = premium_calculator
        self._eligibility = eligibility_tracker
        self._wallet_coverage: Dict[str, WalletCoverage] = {}
        logger.info(
            "CoverageManager initialised with %d products",
            len(CoverageProduct),
        )

    def enroll_full_coverage(self, wallet_address: str) -> WalletCoverage:
        """Enroll wallet in ALL coverage products simultaneously.

        Args:
            wallet_address: The wallet to enroll.

        Returns:
            WalletCoverage with all active products.
        """
        coverage = WalletCoverage(
            wallet_address=wallet_address,
            enrolled_at=time.time(),
        )

        for product in CoverageProduct:
            limit = DEFAULT_COVERAGE_LIMITS.get(product, Decimal("10"))
            premium = Decimal("0")

            if self._calculator:
                try:
                    calc = self._calculator.calculate(
                        wallet_address, product.value, limit,
                    )
                    premium = calc.premium_eth
                except Exception as exc:
                    logger.warning("Premium calc failed for %s: %s", product.value, exc)

            if self._registry:
                try:
                    from runtime.blockchain.services.insurance.policy_registry import CoverageType
                    policy = self._registry.register_policy(
                        wallet_address=wallet_address,
                        coverage_type=CoverageType(product.value),
                        coverage_amount_eth=float(limit),
                        premium_eth=float(premium),
                    )
                    coverage.policy_ids[product.value] = policy.policy_id
                except ValueError:
                    logger.info("Already enrolled in %s", product.value)
                except Exception as exc:
                    logger.error("Failed to register %s policy: %s", product.value, exc)

            coverage.active_products.append(product)
            coverage.total_coverage_eth += limit
            coverage.total_premium_eth += premium

        self._wallet_coverage[wallet_address] = coverage
        logger.info(
            "Full coverage enrolled: %s (%d products, %.4f ETH total coverage)",
            wallet_address, len(coverage.active_products), coverage.total_coverage_eth,
        )
        return coverage

    def disenroll_full_coverage(self, wallet_address: str) -> int:
        """Remove all coverage for a wallet.

        Args:
            wallet_address: The wallet to disenroll.

        Returns:
            Number of products disenrolled.
        """
        coverage = self._wallet_coverage.get(wallet_address)
        if not coverage:
            return 0

        count = 0
        for product_type, policy_id in coverage.policy_ids.items():
            if self._registry:
                try:
                    self._registry.deregister_policy(policy_id, reason="eligibility_lost")
                    count += 1
                except Exception as exc:
                    logger.error("Failed to deregister %s: %s", policy_id, exc)

        coverage.active_products.clear()
        logger.info("Full coverage disenrolled: %s (%d products)", wallet_address, count)
        return count

    def get_wallet_coverage(self, wallet_address: str) -> Optional[WalletCoverage]:
        """Get current coverage state for a wallet."""
        return self._wallet_coverage.get(wallet_address)

    def verify_full_coverage(self, wallet_address: str) -> Dict[str, bool]:
        """Verify that a wallet has all coverage products active.

        Returns:
            Dict mapping product name to active status.
        """
        result: Dict[str, bool] = {}
        for product in CoverageProduct:
            active = False
            if self._registry:
                try:
                    from runtime.blockchain.services.insurance.policy_registry import CoverageType
                    policies = self._registry.get_active_policies(
                        wallet_address=wallet_address,
                        coverage_type=CoverageType(product.value),
                    )
                    active = len(policies) > 0
                except Exception:
                    pass
            result[product.value] = active
        return result

    def get_all_enrolled_wallets(self) -> List[str]:
        """Get all wallets with active coverage."""
        return [
            addr for addr, cov in self._wallet_coverage.items()
            if cov.active_products
        ]

    def get_stats(self) -> Dict[str, Any]:
        """Get coverage statistics."""
        total_enrolled = sum(
            1 for c in self._wallet_coverage.values() if c.active_products
        )
        total_coverage = sum(
            c.total_coverage_eth for c in self._wallet_coverage.values()
        )
        total_premiums = sum(
            c.total_premium_eth for c in self._wallet_coverage.values()
        )
        return {
            "total_enrolled_wallets": total_enrolled,
            "total_coverage_eth": str(total_coverage),
            "total_monthly_premiums_eth": str(total_premiums),
            "products_available": len(CoverageProduct),
        }
