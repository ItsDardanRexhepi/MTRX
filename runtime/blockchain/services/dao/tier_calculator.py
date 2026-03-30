"""
Component 6 - TierCalculator

Applies the correct tiered maintenance fee based on the CURRENT treasury
value at monthly calculation time. Tiers adjust in BOTH directions --
a DAO that shrinks in treasury will pay a lower rate, and one that grows
will pay a higher rate.

Fee schedule (new conversions):
    $0   - $25M    -> 2.0 % annually
    $25M - $50M    -> 2.5 % annually
    $50M - $250M   -> 5.0 % annually
    >$250M         -> 10.0 % annually

Fee schedule (existing DAO onboarding):
    Flat 1.0 % annually regardless of treasury size.

Fee boundary: treasury fees ONLY. NOT additive with Component 1 fees.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from enum import Enum, auto
from typing import Optional

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Treasury tier boundaries (USD)
TIER1_CEILING_USD: float = 25_000_000.0      # $25M
TIER2_CEILING_USD: float = 50_000_000.0      # $50M
TIER3_CEILING_USD: float = 250_000_000.0     # $250M

# Annual maintenance rates for NEW conversions (basis points)
NEW_TIER1_BPS: int = 200    # 2.0%
NEW_TIER2_BPS: int = 250    # 2.5%
NEW_TIER3_BPS: int = 500    # 5.0%
NEW_TIER4_BPS: int = 1000   # 10.0%

# Flat annual rate for EXISTING DAO onboarding (basis points)
EXISTING_DAO_BPS: int = 100  # 1.0%

BPS_DENOMINATOR: int = 10_000
MONTHS_PER_YEAR: int = 12


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


class DAOOrigin(Enum):
    """How the DAO joined the platform."""
    NEW_CONVERSION = auto()
    EXISTING_ONBOARDING = auto()


class TreasuryTier(Enum):
    """Treasury-size tiers for new-conversion DAOs."""
    TIER_1 = "0_to_25M"
    TIER_2 = "25M_to_50M"
    TIER_3 = "50M_to_250M"
    TIER_4 = "above_250M"


@dataclass
class TierResult:
    """Result of a tier calculation."""

    dao_id: str
    origin: DAOOrigin
    treasury_value_usd: float
    tier: Optional[TreasuryTier]       # None for existing DAOs
    annual_rate_bps: int
    annual_fee_usd: float
    monthly_fee_usd: float


# ---------------------------------------------------------------------------
# TierCalculator
# ---------------------------------------------------------------------------


class TierCalculator:
    """Calculates tiered maintenance fees for DAOs.

    Fees are based on the CURRENT treasury value at the moment of
    calculation and adjust in BOTH directions. This is NOT a ratchet --
    if a DAO's treasury drops from $60M to $20M, the rate drops from
    5.0 %% to 2.0 %%.

    The calculator maintains a registry of DAO origins to distinguish
    between new conversions (tiered rates) and existing onboarding
    (flat 1 %% rate).

    Fee boundary: these treasury-based fees are the ONLY fees the DAO
    pays. They are NOT additive with Component 1 revenue-share fees.
    """

    def __init__(self) -> None:
        self._dao_origins: dict[str, DAOOrigin] = {}
        logger.info("TierCalculator initialised")

    # ------------------------------------------------------------------
    # Registry
    # ------------------------------------------------------------------

    def register_dao(self, dao_id: str, origin: DAOOrigin) -> None:
        """Register a DAO's origin for tier calculations.

        Parameters
        ----------
        dao_id : str
            Unique identifier for the DAO.
        origin : DAOOrigin
            Whether the DAO is a new conversion or existing onboarding.
        """
        self._dao_origins[dao_id] = origin
        logger.info("DAO %s registered as %s", dao_id, origin.name)

    def get_origin(self, dao_id: str) -> DAOOrigin:
        """Return the origin type of a registered DAO.

        Raises
        ------
        ValueError
            If the DAO is not registered.
        """
        origin = self._dao_origins.get(dao_id)
        if origin is None:
            raise ValueError(f"DAO not registered: {dao_id}")
        return origin

    # ------------------------------------------------------------------
    # Fee calculation
    # ------------------------------------------------------------------

    def get_annual_rate_bps(
        self,
        dao_id: str,
        treasury_value_usd: float,
    ) -> int:
        """Return the annual maintenance rate in basis points.

        For existing-onboarding DAOs this is always 100 bps (1 %%).
        For new conversions the rate depends on the current treasury
        value and adjusts BOTH directions.

        Parameters
        ----------
        dao_id : str
            DAO identifier (must be registered).
        treasury_value_usd : float
            Current treasury value in USD.

        Returns
        -------
        int
            Annual rate in basis points.
        """
        origin = self.get_origin(dao_id)

        if origin == DAOOrigin.EXISTING_ONBOARDING:
            return EXISTING_DAO_BPS

        return self._tiered_rate_bps(treasury_value_usd)

    def calculate(
        self,
        dao_id: str,
        treasury_value_usd: float,
    ) -> TierResult:
        """Full tier calculation with annual and monthly fee amounts.

        Parameters
        ----------
        dao_id : str
            DAO identifier (must be registered).
        treasury_value_usd : float
            Current treasury value in USD.

        Returns
        -------
        TierResult
            Complete calculation result.
        """
        origin = self.get_origin(dao_id)
        rate_bps = self.get_annual_rate_bps(dao_id, treasury_value_usd)
        tier = self._classify_tier(treasury_value_usd) if origin == DAOOrigin.NEW_CONVERSION else None

        annual_fee = (treasury_value_usd * rate_bps) / BPS_DENOMINATOR
        monthly_fee = annual_fee / MONTHS_PER_YEAR

        result = TierResult(
            dao_id=dao_id,
            origin=origin,
            treasury_value_usd=treasury_value_usd,
            tier=tier,
            annual_rate_bps=rate_bps,
            annual_fee_usd=annual_fee,
            monthly_fee_usd=monthly_fee,
        )

        logger.info(
            "Tier calculation for DAO %s: treasury=$%.2f tier=%s rate=%d bps "
            "annual=$%.2f monthly=$%.2f",
            dao_id,
            treasury_value_usd,
            tier.value if tier else "FLAT",
            rate_bps,
            annual_fee,
            monthly_fee,
        )

        return result

    def estimate_fee_range(
        self,
        dao_id: str,
        low_usd: float,
        high_usd: float,
    ) -> tuple[TierResult, TierResult]:
        """Estimate fees at both ends of a treasury range.

        Useful for projections showing how fees adjust in both directions.

        Parameters
        ----------
        dao_id : str
            DAO identifier (must be registered).
        low_usd : float
            Lower bound of treasury estimate.
        high_usd : float
            Upper bound of treasury estimate.

        Returns
        -------
        tuple[TierResult, TierResult]
            (low_estimate, high_estimate)
        """
        return (
            self.calculate(dao_id, low_usd),
            self.calculate(dao_id, high_usd),
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _tiered_rate_bps(treasury_value_usd: float) -> int:
        """Determine the tiered rate for new-conversion DAOs.

        Adjusts BOTH directions based on current treasury value.
        """
        if treasury_value_usd <= TIER1_CEILING_USD:
            return NEW_TIER1_BPS     # 2.0%
        if treasury_value_usd <= TIER2_CEILING_USD:
            return NEW_TIER2_BPS     # 2.5%
        if treasury_value_usd <= TIER3_CEILING_USD:
            return NEW_TIER3_BPS     # 5.0%
        return NEW_TIER4_BPS         # 10.0%

    @staticmethod
    def _classify_tier(treasury_value_usd: float) -> TreasuryTier:
        """Classify the treasury into a named tier."""
        if treasury_value_usd <= TIER1_CEILING_USD:
            return TreasuryTier.TIER_1
        if treasury_value_usd <= TIER2_CEILING_USD:
            return TreasuryTier.TIER_2
        if treasury_value_usd <= TIER3_CEILING_USD:
            return TreasuryTier.TIER_3
        return TreasuryTier.TIER_4
