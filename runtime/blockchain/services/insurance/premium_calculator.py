"""
Premium Calculator
====================

Calculates insurance premiums based on coverage type, risk profile,
and historical claims data. Includes Phase 2 injection points for
renters insurance and travel insurance products.

Designed with extension points so new products can plug in custom
risk models without modifying the core calculation engine.
"""

from __future__ import annotations

import logging
import math
import time
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any, Callable, Dict, List, Optional, Protocol

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Base premium rates per coverage type (as fraction of coverage amount)
BASE_RATES: Dict[str, Decimal] = {
    "renters": Decimal("0.020"),
    "travel": Decimal("0.015"),
    "parametric_weather": Decimal("0.025"),
    "flight_delay": Decimal("0.010"),
    "package_protection": Decimal("0.008"),
}

# Risk multiplier bounds
MIN_RISK_MULTIPLIER: Decimal = Decimal("0.5")
MAX_RISK_MULTIPLIER: Decimal = Decimal("3.0")


class RiskTier(Enum):
    """Risk classification tiers."""
    LOW = "low"
    STANDARD = "standard"
    ELEVATED = "elevated"
    HIGH = "high"


@dataclass
class RiskProfile:
    """Risk profile for a wallet/coverage combination."""
    wallet_address: str
    coverage_type: str
    risk_tier: RiskTier = RiskTier.STANDARD
    risk_multiplier: Decimal = Decimal("1.0")
    claim_count: int = 0
    total_claims_eth: Decimal = Decimal("0")
    consecutive_claim_free_months: int = 0
    location_risk_factor: Decimal = Decimal("1.0")
    tenure_discount: Decimal = Decimal("0")
    computed_at: float = field(default_factory=time.time)


@dataclass
class PremiumCalculation:
    """Result of a premium calculation."""
    wallet_address: str
    coverage_type: str
    coverage_amount_eth: Decimal
    base_rate: Decimal
    base_premium_eth: Decimal
    risk_multiplier: Decimal
    risk_tier: str
    tenure_discount: Decimal
    loyalty_discount: Decimal
    claims_surcharge: Decimal
    final_multiplier: Decimal
    premium_eth: Decimal
    premium_usd: Optional[Decimal] = None
    calculated_at: float = field(default_factory=time.time)
    breakdown: Dict[str, float] = field(default_factory=dict)


class PremiumInjectionPoint(Protocol):
    """Protocol for Phase 2 product-specific premium injection points.

    Implementors provide custom risk assessment and premium adjustments
    for specific coverage types. The calculator invokes registered
    injection points during premium computation.
    """

    def assess_risk(
        self,
        wallet_address: str,
        coverage_amount_eth: Decimal,
        base_premium_eth: Decimal,
        context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Assess risk and return premium adjustments.

        Args:
            wallet_address: The wallet being assessed.
            coverage_amount_eth: Requested coverage amount.
            base_premium_eth: The base premium before injection.
            context: Additional context (claims history, profile, etc.).

        Returns:
            Dict with keys:
                - "adjusted_premium_eth": Decimal - adjusted premium
                - "risk_factors": Dict - product-specific risk factors
                - "notes": str - explanation of adjustments
        """
        ...


class PremiumCalculator:
    """Insurance premium calculation engine with injection points.

    Computes premiums based on coverage type, risk profile, and
    historical claim data. Supports Phase 2 injection points that
    allow product-specific premium models to be plugged in without
    modifying the core engine.

    Parameters
    ----------
    policy_registry : Any
        PolicyRegistry for claims history lookups.
    eligibility_tracker : Any
        EligibilityTracker for tenure data.
    oracle_interface : Any
        Component 11 OracleInterface for ETH/USD pricing.
    base_rates : dict, optional
        Override default base rates per coverage type.
    """

    def __init__(
        self,
        policy_registry: Any = None,
        eligibility_tracker: Any = None,
        oracle_interface: Any = None,
        base_rates: Optional[Dict[str, Decimal]] = None,
    ) -> None:
        self._policies = policy_registry
        self._eligibility = eligibility_tracker
        self._oracle = oracle_interface
        self._base_rates = base_rates or dict(BASE_RATES)
        self._injection_points: Dict[str, PremiumInjectionPoint] = {}
        self._risk_profiles: Dict[str, RiskProfile] = {}
        self._calculation_history: List[PremiumCalculation] = []

        logger.info(
            "PremiumCalculator initialised with %d base rates, "
            "%d injection points",
            len(self._base_rates), len(self._injection_points),
        )

    # ------------------------------------------------------------------
    # Phase 2 Injection Points
    # ------------------------------------------------------------------

    def register_injection_point(
        self,
        coverage_type: str,
        injection: PremiumInjectionPoint,
    ) -> None:
        """Register a Phase 2 product-specific injection point.

        Injection points allow product teams to plug in custom risk
        models for specific coverage types. When a premium is calculated
        for a coverage type with a registered injection, the injection's
        assess_risk method is called after the base calculation and its
        adjustments are applied.

        Phase 2 injection points planned:
        - "renters": Location-based risk, property value, lease terms
        - "travel": Destination risk, trip duration, travel frequency

        Args:
            coverage_type: The coverage type this injection applies to.
            injection: Object implementing PremiumInjectionPoint protocol.
        """
        self._injection_points[coverage_type] = injection
        logger.info(
            "Registered Phase 2 injection point for '%s'", coverage_type,
        )

    def unregister_injection_point(self, coverage_type: str) -> bool:
        """Remove a registered injection point.

        Args:
            coverage_type: The coverage type to unregister.

        Returns:
            True if an injection point was removed.
        """
        if coverage_type in self._injection_points:
            del self._injection_points[coverage_type]
            logger.info(
                "Unregistered injection point for '%s'", coverage_type,
            )
            return True
        return False

    def get_registered_injections(self) -> List[str]:
        """Get list of coverage types with registered injection points."""
        return list(self._injection_points.keys())

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def calculate(
        self,
        wallet_address: str,
        coverage_type: str,
        coverage_amount_eth: Decimal,
        context: Optional[Dict[str, Any]] = None,
    ) -> PremiumCalculation:
        """Calculate the premium for a wallet and coverage type.

        Pipeline:
        1. Look up base rate for coverage type
        2. Build risk profile from claims history and tenure
        3. Apply risk multiplier, loyalty discounts, claims surcharges
        4. Run Phase 2 injection point if registered
        5. Compute final premium

        Args:
            wallet_address: The wallet to calculate for.
            coverage_type: Type of coverage.
            coverage_amount_eth: Coverage amount in ETH.
            context: Optional additional context for injection points.

        Returns:
            PremiumCalculation with full breakdown.
        """
        coverage_amount = Decimal(str(coverage_amount_eth))
        base_rate = self._get_base_rate(coverage_type)
        base_premium = coverage_amount * base_rate

        # Build risk profile
        profile = self._build_risk_profile(wallet_address, coverage_type)

        # Loyalty discount: 2% per claim-free month, max 20%
        loyalty_discount = min(
            Decimal(str(profile.consecutive_claim_free_months)) * Decimal("0.02"),
            Decimal("0.20"),
        )

        # Tenure discount from eligibility tracker
        tenure_discount = profile.tenure_discount

        # Claims surcharge: 15% per prior claim in last 12 months, max 60%
        claims_surcharge = min(
            Decimal(str(profile.claim_count)) * Decimal("0.15"),
            Decimal("0.60"),
        )

        # Compute final multiplier
        final_multiplier = (
            profile.risk_multiplier
            * profile.location_risk_factor
            * (Decimal("1") - loyalty_discount)
            * (Decimal("1") - tenure_discount)
            * (Decimal("1") + claims_surcharge)
        )

        # Clamp the final multiplier
        final_multiplier = max(
            MIN_RISK_MULTIPLIER,
            min(final_multiplier, MAX_RISK_MULTIPLIER),
        )

        premium = base_premium * final_multiplier

        # Run Phase 2 injection point if registered
        injection = self._injection_points.get(coverage_type)
        injection_notes = ""
        if injection:
            try:
                injection_result = injection.assess_risk(
                    wallet_address=wallet_address,
                    coverage_amount_eth=coverage_amount,
                    base_premium_eth=premium,
                    context={
                        "risk_profile": profile,
                        "base_rate": float(base_rate),
                        "final_multiplier": float(final_multiplier),
                        **(context or {}),
                    },
                )
                adjusted = injection_result.get("adjusted_premium_eth")
                if adjusted is not None:
                    premium = Decimal(str(adjusted))
                    injection_notes = injection_result.get("notes", "")
                    logger.info(
                        "Injection point '%s' adjusted premium: %.6f ETH (%s)",
                        coverage_type, premium, injection_notes,
                    )
            except Exception as exc:
                logger.warning(
                    "Injection point '%s' failed: %s (using base calculation)",
                    coverage_type, exc,
                )

        # Round to 6 decimal places
        premium = premium.quantize(Decimal("0.000001"))

        # Build breakdown
        breakdown = {
            "base_rate": float(base_rate),
            "base_premium_eth": float(base_premium),
            "risk_multiplier": float(profile.risk_multiplier),
            "location_risk_factor": float(profile.location_risk_factor),
            "loyalty_discount_pct": float(loyalty_discount * 100),
            "tenure_discount_pct": float(tenure_discount * 100),
            "claims_surcharge_pct": float(claims_surcharge * 100),
            "final_multiplier": float(final_multiplier),
            "injection_applied": injection is not None,
            "injection_notes": injection_notes,
        }

        calc = PremiumCalculation(
            wallet_address=wallet_address,
            coverage_type=coverage_type,
            coverage_amount_eth=coverage_amount,
            base_rate=base_rate,
            base_premium_eth=base_premium,
            risk_multiplier=profile.risk_multiplier,
            risk_tier=profile.risk_tier.value,
            tenure_discount=tenure_discount,
            loyalty_discount=loyalty_discount,
            claims_surcharge=claims_surcharge,
            final_multiplier=final_multiplier,
            premium_eth=premium,
            premium_usd=self._eth_to_usd(premium),
            breakdown=breakdown,
        )

        self._calculation_history.append(calc)

        logger.info(
            "Premium calculated: wallet=%s type=%s coverage=%.4f premium=%.6f ETH "
            "(tier=%s, multiplier=%.2f)",
            wallet_address, coverage_type, coverage_amount,
            premium, profile.risk_tier.value, final_multiplier,
        )

        return calc

    def get_quote(
        self,
        wallet_address: str,
        coverage_types: Optional[List[str]] = None,
        coverage_amounts: Optional[Dict[str, Decimal]] = None,
    ) -> Dict[str, PremiumCalculation]:
        """Get premium quotes for multiple coverage types.

        Args:
            wallet_address: The wallet to quote for.
            coverage_types: Types to quote (default: all).
            coverage_amounts: Override coverage amounts per type.

        Returns:
            Dict mapping coverage_type to PremiumCalculation.
        """
        types = coverage_types or list(self._base_rates.keys())
        amounts = coverage_amounts or {}
        quotes: Dict[str, PremiumCalculation] = {}

        for ctype in types:
            amount = amounts.get(ctype, self._get_default_coverage(ctype))
            calc = self.calculate(wallet_address, ctype, amount)
            quotes[ctype] = calc

        return quotes

    def get_risk_profile(
        self, wallet_address: str, coverage_type: str
    ) -> RiskProfile:
        """Get or build the risk profile for a wallet/coverage combo.

        Args:
            wallet_address: The wallet to profile.
            coverage_type: The coverage type.

        Returns:
            RiskProfile for the wallet.
        """
        return self._build_risk_profile(wallet_address, coverage_type)

    def set_base_rate(self, coverage_type: str, rate: Decimal) -> None:
        """Override the base rate for a coverage type.

        Args:
            coverage_type: The coverage type.
            rate: New base rate as a decimal fraction.
        """
        self._base_rates[coverage_type] = rate
        logger.info(
            "Base rate updated for '%s': %.4f", coverage_type, rate,
        )

    def get_calculation_history(
        self,
        wallet_address: Optional[str] = None,
        limit: int = 100,
    ) -> List[PremiumCalculation]:
        """Get recent premium calculations.

        Args:
            wallet_address: Filter by wallet (optional).
            limit: Maximum results.

        Returns:
            List of PremiumCalculation records.
        """
        results = self._calculation_history
        if wallet_address:
            results = [c for c in results if c.wallet_address == wallet_address]
        return list(reversed(results[-limit:]))

    def get_stats(self) -> Dict[str, Any]:
        """Get calculator statistics."""
        avg_premiums: Dict[str, float] = {}
        counts: Dict[str, int] = {}
        for calc in self._calculation_history:
            ctype = calc.coverage_type
            counts[ctype] = counts.get(ctype, 0) + 1
            if ctype not in avg_premiums:
                avg_premiums[ctype] = 0.0
            avg_premiums[ctype] += float(calc.premium_eth)

        for ctype in avg_premiums:
            if counts[ctype] > 0:
                avg_premiums[ctype] /= counts[ctype]

        return {
            "total_calculations": len(self._calculation_history),
            "calculations_by_type": counts,
            "average_premium_by_type_eth": avg_premiums,
            "registered_injection_points": list(self._injection_points.keys()),
            "base_rates": {k: float(v) for k, v in self._base_rates.items()},
        }

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _get_base_rate(self, coverage_type: str) -> Decimal:
        """Get the base premium rate for a coverage type."""
        rate = self._base_rates.get(coverage_type)
        if rate is None:
            logger.warning(
                "No base rate for '%s', using default 2%%", coverage_type,
            )
            return Decimal("0.02")
        return rate

    def _get_default_coverage(self, coverage_type: str) -> Decimal:
        """Get the default coverage amount for a type."""
        defaults: Dict[str, Decimal] = {
            "renters": Decimal("5.0"),
            "travel": Decimal("3.0"),
            "parametric_weather": Decimal("2.0"),
            "flight_delay": Decimal("1.0"),
            "package_protection": Decimal("0.5"),
        }
        return defaults.get(coverage_type, Decimal("1.0"))

    def _build_risk_profile(
        self, wallet_address: str, coverage_type: str
    ) -> RiskProfile:
        """Build a risk profile from claims history and eligibility data."""
        cache_key = f"{wallet_address}:{coverage_type}"
        cached = self._risk_profiles.get(cache_key)
        if cached and (time.time() - cached.computed_at) < 3600:
            return cached

        profile = RiskProfile(
            wallet_address=wallet_address,
            coverage_type=coverage_type,
        )

        # Pull claims history from policy registry
        if self._policies:
            self._populate_claims_data(profile)

        # Pull tenure from eligibility tracker
        if self._eligibility:
            self._populate_tenure_data(profile)

        # Classify risk tier
        profile.risk_tier = self._classify_risk(profile)
        profile.risk_multiplier = self._tier_to_multiplier(profile.risk_tier)

        self._risk_profiles[cache_key] = profile
        return profile

    def _populate_claims_data(self, profile: RiskProfile) -> None:
        """Populate claims data from policy registry."""
        try:
            from runtime.blockchain.services.insurance.policy_registry import (
                CoverageType as RegistryCoverageType,
            )
            policies = self._policies.get_active_policies(
                wallet_address=profile.wallet_address,
                coverage_type=RegistryCoverageType(profile.coverage_type),
            )
            for policy in policies:
                profile.claim_count += len(policy.claims)
                profile.total_claims_eth += Decimal(
                    str(policy.total_claims_paid_eth)
                )
                # Check consecutive claim-free months (approximate)
                if not policy.claims:
                    months_active = max(
                        1,
                        int((time.time() - policy.created_at) / (30 * 86400)),
                    )
                    profile.consecutive_claim_free_months = months_active
        except Exception as exc:
            logger.warning("Failed to fetch claims data: %s", exc)

    def _populate_tenure_data(self, profile: RiskProfile) -> None:
        """Populate tenure discount from eligibility tracker."""
        try:
            record = self._eligibility.get_record(profile.wallet_address)
            if record and record.consecutive_eligible_months > 0:
                # 1% discount per eligible month, max 10%
                profile.tenure_discount = min(
                    Decimal(str(record.consecutive_eligible_months))
                    * Decimal("0.01"),
                    Decimal("0.10"),
                )
        except Exception as exc:
            logger.warning("Failed to fetch tenure data: %s", exc)

    def _classify_risk(self, profile: RiskProfile) -> RiskTier:
        """Classify the risk tier based on profile data."""
        if profile.claim_count == 0 and profile.consecutive_claim_free_months >= 6:
            return RiskTier.LOW
        if profile.claim_count <= 1:
            return RiskTier.STANDARD
        if profile.claim_count <= 3:
            return RiskTier.ELEVATED
        return RiskTier.HIGH

    def _tier_to_multiplier(self, tier: RiskTier) -> Decimal:
        """Convert risk tier to a premium multiplier."""
        multipliers = {
            RiskTier.LOW: Decimal("0.80"),
            RiskTier.STANDARD: Decimal("1.00"),
            RiskTier.ELEVATED: Decimal("1.35"),
            RiskTier.HIGH: Decimal("1.75"),
        }
        return multipliers[tier]

    def _eth_to_usd(self, amount_eth: Decimal) -> Optional[Decimal]:
        """Convert ETH to USD via Component 11 oracle."""
        if not self._oracle:
            return None
        try:
            price_resp = self._oracle.get_price(
                "ETH", "USD", source_component=13,
            )
            if price_resp.value:
                return amount_eth * Decimal(str(price_resp.value))
        except Exception as exc:
            logger.warning("Failed to get ETH/USD price: %s", exc)
        return None
