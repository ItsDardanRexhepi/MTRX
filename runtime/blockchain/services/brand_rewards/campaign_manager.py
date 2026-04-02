"""
Brand Campaign Manager — brand reward campaigns with multiple eligibility modes.

Part of Component 25 (Brand Rewards).
Handles campaign creation, funding, allowlist/ZKP management, and claiming.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional, Set

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class CampaignStatus(Enum):
    """Campaign lifecycle states."""
    ACTIVE = "active"
    PAUSED = "paused"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class EligibilityMode(Enum):
    """How reward eligibility is determined."""
    OPEN = "open"
    ALLOWLIST = "allowlist"
    ZKP = "zkp"


@dataclass
class BrandCampaign:
    """A brand reward campaign."""
    campaign_id: str
    brand: str
    reward_token: str
    total_budget_wei: int
    distributed_wei: int = 0
    reward_per_user_wei: int = 0
    max_claims: int = 0
    total_claims: int = 0
    start_time: float = 0.0
    end_time: float = 0.0
    eligibility_mode: EligibilityMode = EligibilityMode.OPEN
    zkp_verifier: str = ""
    status: CampaignStatus = CampaignStatus.ACTIVE
    terms_uri: str = ""
    metadata_uri: str = ""
    created_at: float = field(default_factory=time.time)


class BrandCampaignManager:
    """
    Manages brand reward campaigns.

    Eligibility modes:
    - Open: anyone can claim
    - Allowlist: only pre-approved addresses
    - ZKP: zero-knowledge proof verification (verifier injected)
    """

    def __init__(
        self,
        zkp_verify_fn: Optional[Callable[[str, str, bytes], bool]] = None,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        """
        Args:
            zkp_verify_fn: Callable(user, campaign_id, proof) -> bool.
            execute_fn: Callable for on-chain transactions.
        """
        self._zkp_verify = zkp_verify_fn
        self._execute = execute_fn
        self._campaigns: Dict[str, BrandCampaign] = {}
        self._allowlists: Dict[str, Set[str]] = {}  # campaign_id -> set of addrs
        self._claims: Dict[str, Set[str]] = {}  # campaign_id -> set of claimed addrs
        self._counter: int = 0
        logger.info("BrandCampaignManager initialised.")

    # ── Campaign Lifecycle ────────────────────────────────────────────

    def create_campaign(
        self,
        brand: str,
        reward_token: str,
        reward_per_user_wei: int,
        max_claims: int,
        start_time: float,
        end_time: float,
        eligibility_mode: EligibilityMode = EligibilityMode.OPEN,
        zkp_verifier: str = "",
        terms_uri: str = "",
        metadata_uri: str = "",
        initial_funding_wei: int = 0,
    ) -> BrandCampaign:
        """
        Create a new brand reward campaign.

        Args:
            brand: Brand's wallet address.
            reward_token: Token used for rewards.
            reward_per_user_wei: Reward amount per claim.
            max_claims: Maximum number of claims allowed.
            start_time: Campaign start unix timestamp.
            end_time: Campaign end unix timestamp.
            eligibility_mode: How eligibility is checked.
            zkp_verifier: ZKP verifier address (for ZKP mode).
            terms_uri: Terms and conditions URI.
            metadata_uri: Campaign metadata URI.
            initial_funding_wei: Initial funding amount.

        Returns:
            The created BrandCampaign.
        """
        if not brand.startswith("0x"):
            raise ValueError("Invalid brand address.")
        if reward_per_user_wei <= 0:
            raise ValueError("Reward per user must be positive.")
        if max_claims <= 0:
            raise ValueError("Max claims must be positive.")
        if end_time <= start_time:
            raise ValueError("End time must be after start time.")
        if eligibility_mode == EligibilityMode.ZKP and not zkp_verifier:
            raise ValueError("ZKP mode requires a verifier address.")

        self._counter += 1
        cid = f"BRAND-{self._counter:08d}"

        campaign = BrandCampaign(
            campaign_id=cid,
            brand=brand,
            reward_token=reward_token,
            total_budget_wei=initial_funding_wei,
            reward_per_user_wei=reward_per_user_wei,
            max_claims=max_claims,
            start_time=start_time,
            end_time=end_time,
            eligibility_mode=eligibility_mode,
            zkp_verifier=zkp_verifier,
            terms_uri=terms_uri,
            metadata_uri=metadata_uri,
        )
        self._campaigns[cid] = campaign
        self._allowlists[cid] = set()
        self._claims[cid] = set()

        logger.info(
            "Campaign created | id=%s | brand=%s | mode=%s | reward=%d",
            cid, brand, eligibility_mode.value, reward_per_user_wei,
        )
        return campaign

    def fund_campaign(
        self, campaign_id: str, caller: str, amount_wei: int,
    ) -> BrandCampaign:
        """Add funds to a campaign. Only the brand can fund."""
        c = self._get_campaign(campaign_id)
        if c.brand != caller:
            raise ValueError("Only the brand can fund the campaign.")
        if amount_wei <= 0:
            raise ValueError("Funding amount must be positive.")

        c.total_budget_wei += amount_wei
        logger.info(
            "Campaign funded | id=%s | amount=%d | total=%d",
            campaign_id, amount_wei, c.total_budget_wei,
        )
        return c

    def update_allowlist(
        self,
        campaign_id: str,
        caller: str,
        users: List[str],
        eligible: List[bool],
    ) -> None:
        """Update the allowlist for a campaign."""
        c = self._get_campaign(campaign_id)
        if c.brand != caller:
            raise ValueError("Only the brand can update the allowlist.")
        if len(users) != len(eligible):
            raise ValueError("Users and eligible lists must match in length.")

        allowlist = self._allowlists[campaign_id]
        for user, is_eligible in zip(users, eligible):
            if is_eligible:
                allowlist.add(user)
            else:
                allowlist.discard(user)

        logger.info(
            "Allowlist updated | id=%s | size=%d", campaign_id, len(allowlist),
        )

    # ── Claiming ──────────────────────────────────────────────────────

    def claim_reward(self, campaign_id: str, user: str) -> int:
        """
        Claim a reward from a campaign.

        Args:
            user: Claiming user's address.

        Returns:
            Reward amount in wei.
        """
        c = self._get_campaign(campaign_id)
        self._validate_claim(c, user)

        c.total_claims += 1
        c.distributed_wei += c.reward_per_user_wei
        self._claims[campaign_id].add(user)

        # Auto-complete if max claims reached or budget exhausted
        if c.total_claims >= c.max_claims:
            c.status = CampaignStatus.COMPLETED
        remaining = c.total_budget_wei - c.distributed_wei
        if remaining < c.reward_per_user_wei:
            c.status = CampaignStatus.COMPLETED

        logger.info(
            "Reward claimed | campaign=%s | user=%s | amount=%d",
            campaign_id, user, c.reward_per_user_wei,
        )
        return c.reward_per_user_wei

    def claim_reward_with_zkp(
        self, campaign_id: str, user: str, proof: bytes,
    ) -> int:
        """Claim with zero-knowledge proof verification."""
        c = self._get_campaign(campaign_id)
        if c.eligibility_mode != EligibilityMode.ZKP:
            raise ValueError("Campaign does not use ZKP eligibility.")
        if self._zkp_verify is None:
            raise ValueError("No ZKP verifier configured.")
        if not self._zkp_verify(user, campaign_id, proof):
            raise ValueError("ZKP verification failed.")

        return self.claim_reward(campaign_id, user)

    # ── Status Management ─────────────────────────────────────────────

    def pause_campaign(self, campaign_id: str, caller: str) -> BrandCampaign:
        """Pause an active campaign."""
        c = self._get_campaign(campaign_id)
        if c.brand != caller:
            raise ValueError("Only the brand can pause.")
        if c.status != CampaignStatus.ACTIVE:
            raise ValueError("Can only pause active campaigns.")
        c.status = CampaignStatus.PAUSED
        logger.info("Campaign paused | id=%s", campaign_id)
        return c

    def resume_campaign(self, campaign_id: str, caller: str) -> BrandCampaign:
        """Resume a paused campaign."""
        c = self._get_campaign(campaign_id)
        if c.brand != caller:
            raise ValueError("Only the brand can resume.")
        if c.status != CampaignStatus.PAUSED:
            raise ValueError("Can only resume paused campaigns.")
        c.status = CampaignStatus.ACTIVE
        logger.info("Campaign resumed | id=%s", campaign_id)
        return c

    def cancel_campaign(self, campaign_id: str, caller: str) -> BrandCampaign:
        """Cancel a campaign and return remaining funds to brand."""
        c = self._get_campaign(campaign_id)
        if c.brand != caller:
            raise ValueError("Only the brand can cancel.")
        if c.status in (CampaignStatus.COMPLETED, CampaignStatus.CANCELLED):
            raise ValueError(f"Campaign already {c.status.value}.")
        c.status = CampaignStatus.CANCELLED
        logger.info(
            "Campaign cancelled | id=%s | remaining=%d",
            campaign_id, c.total_budget_wei - c.distributed_wei,
        )
        return c

    def update_terms(
        self, campaign_id: str, caller: str, terms_uri: str,
    ) -> None:
        """Update campaign terms URI."""
        c = self._get_campaign(campaign_id)
        if c.brand != caller:
            raise ValueError("Only the brand can update terms.")
        c.terms_uri = terms_uri
        logger.info("Terms updated | id=%s", campaign_id)

    # ── Queries ───────────────────────────────────────────────────────

    def is_eligible(self, campaign_id: str, user: str) -> bool:
        """Check if a user is eligible to claim."""
        c = self._campaigns.get(campaign_id)
        if c is None:
            return False
        if user in self._claims.get(campaign_id, set()):
            return False  # Already claimed
        if c.eligibility_mode == EligibilityMode.OPEN:
            return True
        if c.eligibility_mode == EligibilityMode.ALLOWLIST:
            return user in self._allowlists.get(campaign_id, set())
        return True  # ZKP checked at claim time

    def get_campaign(self, campaign_id: str) -> Optional[BrandCampaign]:
        """Get campaign or None."""
        return self._campaigns.get(campaign_id)

    # ── Internal ──────────────────────────────────────────────────────

    def _validate_claim(self, c: BrandCampaign, user: str) -> None:
        """Validate all claim preconditions."""
        if not user.startswith("0x"):
            raise ValueError("Invalid user address.")
        if c.status != CampaignStatus.ACTIVE:
            raise ValueError(f"Campaign is {c.status.value}.")
        now = time.time()
        if now < c.start_time:
            raise ValueError("Campaign has not started yet.")
        if now > c.end_time:
            raise ValueError("Campaign has ended.")
        if c.total_claims >= c.max_claims:
            raise ValueError("All rewards have been claimed.")
        if c.distributed_wei + c.reward_per_user_wei > c.total_budget_wei:
            raise ValueError("Insufficient campaign budget.")
        if user in self._claims.get(c.campaign_id, set()):
            raise ValueError(f"User {user} already claimed.")
        if c.eligibility_mode == EligibilityMode.ALLOWLIST:
            if user not in self._allowlists.get(c.campaign_id, set()):
                raise ValueError(f"User {user} not on allowlist.")

    def _get_campaign(self, campaign_id: str) -> BrandCampaign:
        """Get campaign or raise."""
        c = self._campaigns.get(campaign_id)
        if c is None:
            raise ValueError(f"Campaign {campaign_id} not found.")
        return c
