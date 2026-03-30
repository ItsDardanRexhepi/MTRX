"""
Unified Dashboard — single view of all 30 MTRX components in plain English.

Part of Component 20 (Dashboard).

Design principles:
- Plain English descriptions (no jargon)
- Activity-based visibility (inactive components are hidden)
- APY exclusively from Component 16 APYCalculator
- No component computes its own summary — all summaries generated here
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


class ComponentStatus(Enum):
    """Status of a component in the dashboard."""
    ACTIVE = "active"
    IDLE = "idle"
    DEGRADED = "degraded"
    OFFLINE = "offline"


@dataclass
class ComponentSummary:
    """Summary of a single component for dashboard display."""
    component_id: int
    name: str
    status: ComponentStatus
    plain_english: str
    key_metrics: Dict[str, Any] = field(default_factory=dict)
    last_activity: Optional[float] = None
    visible: bool = True


@dataclass
class DashboardView:
    """Complete dashboard view for a user."""
    user_address: str
    visible_components: List[ComponentSummary]
    hidden_count: int
    total_components: int
    apy_summary: Optional[Dict[str, Any]] = None
    generated_at: float = field(default_factory=time.time)
    greeting: str = ""


# All 30 components with their display names
COMPONENT_NAMES: Dict[int, str] = {
    1: "Smart Contract Conversion",
    2: "Agent Identity (DID)",
    3: "NFT Valuation",
    4: "Real World Assets",
    5: "Agent Identity Management",
    6: "DAO Formation",
    7: "DeFi Collateral",
    8: "Supply Chain Tracking",
    9: "Agentic Payments",
    10: "Cross-Chain Bridge",
    11: "Oracle Data Feeds",
    12: "EAS Attestation",
    13: "Gasless Transactions",
    14: "Smart Wallet",
    15: "IP and Royalties",
    16: "Token Staking",
    17: "Payment Processing",
    18: "Securities Exchange",
    19: "Governance and Voting",
    20: "Unified Dashboard",
    21: "Decentralized Exchange",
    22: "Fundraising",
    23: "Smart Loyalty",
    24: "Marketplace",
    25: "Cashback Program",
    26: "Brand Rewards",
    27: "Subscriptions",
    28: "Social Platform",
    29: "Privacy Controls",
    30: "Dispute Resolution",
}


class UnifiedDashboard:
    """
    Unified dashboard providing a single view of all 30 MTRX components.

    Key behaviors:
    - Components with no user activity are HIDDEN by default
    - All APY data sourced from Component 16 APYCalculator (canonical)
    - Descriptions are always in plain English
    - Metrics are pre-computed and cached for performance
    """

    ACTIVITY_STALE_SECONDS: int = 30 * 86_400  # 30 days

    def __init__(
        self,
        apy_calculator: Optional[Any] = None,
    ) -> None:
        """
        Args:
            apy_calculator: Component 16 APYCalculator for APY display.
        """
        self._apy = apy_calculator

        # Component data providers: component_id -> callable() -> Dict
        self._providers: Dict[int, Callable[[], Dict[str, Any]]] = {}
        # Per-user last activity timestamps: user -> component_id -> timestamp
        self._user_activity: Dict[str, Dict[int, float]] = {}
        # Component status overrides
        self._statuses: Dict[int, ComponentStatus] = {}

        logger.info("UnifiedDashboard initialised for %d components.", len(COMPONENT_NAMES))

    # ── Provider Registration ─────────────────────────────────────────

    def register_provider(
        self,
        component_id: int,
        provider: Callable[[], Dict[str, Any]],
    ) -> None:
        """
        Register a data provider for a component.

        The provider is a callable that returns a dict with:
        - 'metrics': Dict of key metrics to display
        - 'plain_english': Optional override for the summary text

        Args:
            component_id: The component (1-30).
            provider: Callable returning component data.
        """
        if component_id not in COMPONENT_NAMES:
            raise ValueError(f"Unknown component ID: {component_id}")
        self._providers[component_id] = provider
        logger.debug("Provider registered for Component %d.", component_id)

    # ── Activity Tracking ─────────────────────────────────────────────

    def record_activity(self, user_address: str, component_id: int) -> None:
        """
        Record user activity on a component (makes it visible).

        Args:
            user_address: The user.
            component_id: The component they interacted with.
        """
        if user_address not in self._user_activity:
            self._user_activity[user_address] = {}
        self._user_activity[user_address][component_id] = time.time()

    def set_component_status(self, component_id: int, status: ComponentStatus) -> None:
        """Set the status for a component."""
        self._statuses[component_id] = status

    # ── Dashboard Generation ──────────────────────────────────────────

    def get_dashboard(
        self,
        user_address: str,
        show_all: bool = False,
    ) -> DashboardView:
        """
        Generate the complete dashboard view for a user.

        Args:
            user_address: The user to generate the dashboard for.
            show_all: If True, show all components regardless of activity.

        Returns:
            DashboardView with visible components and metrics.
        """
        user_activity = self._user_activity.get(user_address, {})
        now = time.time()
        summaries: List[ComponentSummary] = []
        hidden_count = 0

        for comp_id, comp_name in COMPONENT_NAMES.items():
            last_activity = user_activity.get(comp_id)
            is_active = (
                last_activity is not None
                and (now - last_activity) < self.ACTIVITY_STALE_SECONDS
            )
            visible = show_all or is_active

            if not visible:
                hidden_count += 1
                continue

            status = self._statuses.get(comp_id, ComponentStatus.ACTIVE if is_active else ComponentStatus.IDLE)
            metrics, custom_summary = self._fetch_metrics(comp_id)
            plain_english = custom_summary or self._default_summary(comp_id, comp_name, metrics)

            summaries.append(ComponentSummary(
                component_id=comp_id,
                name=comp_name,
                status=status,
                plain_english=plain_english,
                key_metrics=metrics,
                last_activity=last_activity,
                visible=True,
            ))

        # APY summary from canonical source
        apy_summary = self._get_apy_summary()

        greeting = self._build_greeting(user_address, len(summaries), hidden_count)

        return DashboardView(
            user_address=user_address,
            visible_components=summaries,
            hidden_count=hidden_count,
            total_components=len(COMPONENT_NAMES),
            apy_summary=apy_summary,
            greeting=greeting,
        )

    def get_component_detail(self, component_id: int) -> Dict[str, Any]:
        """
        Get detailed information for a specific component.

        Args:
            component_id: The component to detail.

        Returns:
            Dict with component details.
        """
        name = COMPONENT_NAMES.get(component_id, f"Component {component_id}")
        metrics, custom_summary = self._fetch_metrics(component_id)
        status = self._statuses.get(component_id, ComponentStatus.IDLE)

        return {
            "component_id": component_id,
            "name": name,
            "status": status.value,
            "metrics": metrics,
            "summary": custom_summary or self._default_summary(component_id, name, metrics),
        }

    # ── Internal ──────────────────────────────────────────────────────

    def _fetch_metrics(self, component_id: int) -> tuple[Dict[str, Any], str]:
        """Fetch metrics from a registered provider."""
        provider = self._providers.get(component_id)
        if provider is None:
            return {}, ""
        try:
            data = provider()
            return data.get("metrics", {}), data.get("plain_english", "")
        except Exception:
            logger.exception("Failed to fetch metrics for Component %d.", component_id)
            return {}, ""

    def _get_apy_summary(self) -> Optional[Dict[str, Any]]:
        """Get APY summary from Component 16 (canonical source)."""
        if self._apy is None:
            return None
        try:
            all_apys = self._apy.get_all_apys()
            return {
                tier.value: {
                    "apy_percent": snapshot.effective_apy_bps / 100.0,
                    "total_staked_wei": snapshot.total_staked_wei,
                }
                for tier, snapshot in all_apys.items()
            }
        except Exception:
            logger.exception("Failed to fetch APY data from Component 16.")
            return None

    def _default_summary(
        self, comp_id: int, name: str, metrics: Dict[str, Any],
    ) -> str:
        """Generate a default plain English summary."""
        if not metrics:
            return f"{name} is available but has no recent activity."
        metric_parts = [f"{k}: {v}" for k, v in list(metrics.items())[:3]]
        return f"{name} — " + ", ".join(metric_parts) + "."

    def _build_greeting(self, user: str, visible: int, hidden: int) -> str:
        """Build the dashboard greeting."""
        if visible == 0:
            return (
                "Welcome to MTRX. You have not interacted with any components yet. "
                "Start by exploring available services."
            )
        return (
            f"Your MTRX dashboard shows {visible} active component(s). "
            f"{hidden} component(s) are hidden due to no recent activity."
        )
