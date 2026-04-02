"""
Campaign Manager — orchestrates community fundraising campaigns.

Part of Component 22 (Community Fundraising).
Handles campaign creation, contributions, refunds, and fund release.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

from runtime.blockchain.services.fundraising.milestone_tracker import (
    MilestoneTracker, MilestoneStatus, VerificationMethod,
)
from runtime.blockchain.services.fundraising.vesting_engine import (
    VestingEngine, VestingType,
)

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class CampaignStatus(Enum):
    """Campaign lifecycle states."""
    ACTIVE = "active"
    FUNDED = "funded"
    FAILED = "failed"
    COMPLETED = "completed"


@dataclass
class Campaign:
    """A community fundraising campaign."""
    campaign_id: str
    recipient: str
    goal_wei: int
    deadline: float
    total_raised_wei: int = 0
    total_released_wei: int = 0
    status: CampaignStatus = CampaignStatus.ACTIVE
    vesting_type: VestingType = VestingType.IMMEDIATE
    verification_method: VerificationMethod = VerificationMethod.ORACLE
    contributor_count: int = 0
    vesting_start: float = 0.0
    vesting_duration: int = 0
    vesting_cliff: int = 0
    created_at: float = field(default_factory=time.time)


@dataclass
class Contribution:
    """A contributor's contribution to a campaign."""
    contributor: str
    campaign_id: str
    amount_wei: int
    refunded: bool = False
    contributed_at: float = field(default_factory=time.time)


class CampaignManager:
    """
    Orchestrates community fundraising campaigns.

    Architecture:
    - MilestoneTracker: milestone management and verification
    - VestingEngine: fund release scheduling
    - Contributions tracked per user for refund eligibility
    """

    def __init__(
        self,
        milestone_tracker: Optional[MilestoneTracker] = None,
        vesting_engine: Optional[VestingEngine] = None,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._milestones = milestone_tracker or MilestoneTracker()
        self._vesting = vesting_engine or VestingEngine()
        self._execute = execute_fn
        self._campaigns: Dict[str, Campaign] = {}
        # campaign_id -> { contributor_addr -> Contribution }
        self._contributions: Dict[str, Dict[str, Contribution]] = {}
        self._counter: int = 0
        logger.info("CampaignManager initialised.")

    # ── Campaign Lifecycle ────────────────────────────────────────────

    def create_campaign(
        self,
        recipient: str,
        goal_wei: int,
        deadline: float,
        vesting_type: VestingType = VestingType.IMMEDIATE,
        verification_method: VerificationMethod = VerificationMethod.ORACLE,
        vesting_duration: int = 0,
        vesting_cliff: int = 0,
    ) -> Campaign:
        """
        Create a new fundraising campaign.

        Args:
            recipient: Address that receives funds.
            goal_wei: Funding goal in wei.
            deadline: Unix timestamp deadline for contributions.
            vesting_type: How funds are released.
            verification_method: How milestones are verified.
            vesting_duration: Total vesting period in seconds.
            vesting_cliff: Cliff period before any release.

        Returns:
            The created Campaign.
        """
        if not recipient.startswith("0x"):
            raise ValueError("Invalid recipient address.")
        if goal_wei <= 0:
            raise ValueError("Goal must be positive.")
        if deadline <= time.time():
            raise ValueError("Deadline must be in the future.")

        self._counter += 1
        cid = f"CAMP-{self._counter:08d}"

        campaign = Campaign(
            campaign_id=cid,
            recipient=recipient,
            goal_wei=goal_wei,
            deadline=deadline,
            vesting_type=vesting_type,
            verification_method=verification_method,
            vesting_duration=vesting_duration,
            vesting_cliff=vesting_cliff,
        )
        self._campaigns[cid] = campaign
        self._contributions[cid] = {}

        logger.info(
            "Campaign created | id=%s | recipient=%s | goal=%d | deadline=%f",
            cid, recipient, goal_wei, deadline,
        )
        return campaign

    def add_milestone(
        self,
        campaign_id: str,
        description: str,
        release_amount_wei: int,
        vote_deadline: float = 0.0,
    ) -> None:
        """Add a milestone to a campaign (delegates to MilestoneTracker)."""
        self._get_campaign(campaign_id)  # Validate campaign exists
        self._milestones.add_milestone(
            campaign_id=campaign_id,
            description=description,
            release_amount_wei=release_amount_wei,
            vote_deadline=vote_deadline,
        )

    # ── Contributions ─────────────────────────────────────────────────

    def contribute(
        self, campaign_id: str, contributor: str, amount_wei: int,
    ) -> Campaign:
        """
        Contribute funds to a campaign.

        Args:
            contributor: Contributor's address.
            amount_wei: Contribution amount in wei.

        Returns:
            Updated campaign.

        Raises:
            ValueError: If campaign not active, deadline passed, or invalid input.
        """
        c = self._get_campaign(campaign_id)
        if c.status != CampaignStatus.ACTIVE:
            raise ValueError(f"Campaign {campaign_id} is not active.")
        if time.time() > c.deadline:
            raise ValueError("Campaign deadline has passed.")
        if not contributor.startswith("0x"):
            raise ValueError("Invalid contributor address.")
        if amount_wei <= 0:
            raise ValueError("Contribution must be positive.")

        existing = self._contributions[campaign_id].get(contributor)
        if existing:
            existing.amount_wei += amount_wei
        else:
            self._contributions[campaign_id][contributor] = Contribution(
                contributor=contributor,
                campaign_id=campaign_id,
                amount_wei=amount_wei,
            )
            c.contributor_count += 1

        c.total_raised_wei += amount_wei

        # Check if goal is met
        if c.total_raised_wei >= c.goal_wei and c.status == CampaignStatus.ACTIVE:
            c.status = CampaignStatus.FUNDED
            c.vesting_start = time.time()
            logger.info("Campaign funded | id=%s | raised=%d", campaign_id, c.total_raised_wei)

        logger.info(
            "Contribution | campaign=%s | contributor=%s | amount=%d | total=%d",
            campaign_id, contributor, amount_wei, c.total_raised_wei,
        )
        return c

    # ── Failure / Refund ──────────────────────────────────────────────

    def check_and_fail_campaign(self, campaign_id: str) -> Campaign:
        """Mark a campaign as failed if deadline passed and goal not met."""
        c = self._get_campaign(campaign_id)
        if c.status != CampaignStatus.ACTIVE:
            raise ValueError(f"Campaign is {c.status.value}, not active.")
        if time.time() <= c.deadline:
            raise ValueError("Deadline has not passed yet.")
        if c.total_raised_wei >= c.goal_wei:
            raise ValueError("Campaign met its goal.")

        c.status = CampaignStatus.FAILED
        logger.info("Campaign failed | id=%s | raised=%d / %d", campaign_id, c.total_raised_wei, c.goal_wei)
        return c

    def claim_refund(self, campaign_id: str, contributor: str) -> int:
        """
        Claim a refund from a failed campaign.

        Returns:
            Refund amount in wei.
        """
        c = self._get_campaign(campaign_id)
        if c.status != CampaignStatus.FAILED:
            raise ValueError("Can only refund from failed campaigns.")

        contrib = self._contributions[campaign_id].get(contributor)
        if contrib is None:
            raise ValueError(f"No contribution from {contributor}.")
        if contrib.refunded:
            raise ValueError("Already refunded.")

        contrib.refunded = True
        logger.info(
            "Refund claimed | campaign=%s | contributor=%s | amount=%d",
            campaign_id, contributor, contrib.amount_wei,
        )
        return contrib.amount_wei

    # ── Fund Release ──────────────────────────────────────────────────

    def release_funds(self, campaign_id: str) -> int:
        """
        Release vested funds to the campaign recipient.

        Returns:
            Amount released in wei.
        """
        c = self._get_campaign(campaign_id)
        if c.status not in (CampaignStatus.FUNDED, CampaignStatus.COMPLETED):
            raise ValueError("Campaign must be funded to release.")

        milestone_released = self._milestones.get_verified_release_total(campaign_id)

        releasable = self._vesting.compute_releasable(
            vesting_type=c.vesting_type,
            total_raised_wei=c.total_raised_wei,
            total_released_wei=c.total_released_wei,
            vesting_start=c.vesting_start,
            vesting_duration=c.vesting_duration,
            vesting_cliff=c.vesting_cliff,
            milestone_released_wei=milestone_released,
        )

        if releasable <= 0:
            raise ValueError("No funds available to release.")

        c.total_released_wei += releasable

        # Check if fully released
        if c.total_released_wei >= c.total_raised_wei:
            c.status = CampaignStatus.COMPLETED

        logger.info(
            "Funds released | campaign=%s | amount=%d | total_released=%d",
            campaign_id, releasable, c.total_released_wei,
        )
        return releasable

    # ── Queries ───────────────────────────────────────────────────────

    def get_campaign(self, campaign_id: str) -> Optional[Campaign]:
        """Get campaign by ID."""
        return self._campaigns.get(campaign_id)

    def get_contribution(self, campaign_id: str, contributor: str) -> int:
        """Get contribution amount for a contributor."""
        contrib = self._contributions.get(campaign_id, {}).get(contributor)
        return contrib.amount_wei if contrib else 0

    def get_milestones(self, campaign_id: str) -> list:
        """Get milestones for a campaign."""
        return self._milestones.get_for_campaign(campaign_id)

    def list_campaigns(
        self, status: Optional[CampaignStatus] = None,
    ) -> List[Campaign]:
        """List campaigns, optionally filtered by status."""
        campaigns = list(self._campaigns.values())
        if status is not None:
            campaigns = [c for c in campaigns if c.status == status]
        return campaigns

    def _get_campaign(self, campaign_id: str) -> Campaign:
        """Get campaign or raise."""
        c = self._campaigns.get(campaign_id)
        if c is None:
            raise ValueError(f"Campaign {campaign_id} not found.")
        return c
