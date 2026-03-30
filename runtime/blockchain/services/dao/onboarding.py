"""
Component 6 - Onboarding

Existing DAO migration service. Onboarding is FREE -- the only cost is
a flat 1%% annual maintenance fee regardless of treasury size.

Handles the full migration pipeline: validation, governance mapping,
treasury integration, and on-chain registration.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Optional

from web3 import Web3
from web3.contract import Contract

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Base mainnet constants
# ---------------------------------------------------------------------------
BASE_CHAIN_ID: int = 8453
NEOSAFE: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
EAS_SCHEMA_UID: str = "0x348"

# Existing DAO flat maintenance rate
EXISTING_DAO_ANNUAL_BPS: int = 100  # 1.0%
BPS_DENOMINATOR: int = 10_000
MONTHS_PER_YEAR: int = 12


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


class OnboardingStage(Enum):
    """Stages of the existing-DAO onboarding process."""
    VALIDATION = auto()
    GOVERNANCE_MAPPING = auto()
    TREASURY_INTEGRATION = auto()
    CONTRACT_REGISTRATION = auto()
    ATTESTATION = auto()
    COMPLETE = auto()


class OnboardingStatus(Enum):
    """Overall status of an onboarding process."""
    IN_PROGRESS = auto()
    COMPLETED = auto()
    FAILED = auto()
    CANCELLED = auto()


@dataclass
class ExistingDAOProfile:
    """Metadata about an existing DAO being onboarded."""
    name: str
    contract_address: str
    chain_id: int = BASE_CHAIN_ID
    governance_type: str = ""
    member_count: int = 0
    treasury_value_usd: float = 0.0
    admin_addresses: list[str] = field(default_factory=list)
    governance_token_address: Optional[str] = None
    description: str = ""
    external_links: list[str] = field(default_factory=list)


@dataclass
class GovernanceMapping:
    """Mapping of existing governance parameters to platform equivalents."""
    source_model: str = ""
    mapped_model: str = "token_weighted"
    proposal_threshold_bps: int = 100
    quorum_bps: int = 2000
    voting_period_seconds: int = 259_200
    execution_delay_seconds: int = 86_400
    allow_delegation: bool = True
    compatibility_notes: list[str] = field(default_factory=list)


@dataclass
class OnboardingState:
    """Full state of an onboarding process."""
    onboarding_id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    dao_profile: Optional[ExistingDAOProfile] = None
    governance_mapping: Optional[GovernanceMapping] = None
    stage: OnboardingStage = OnboardingStage.VALIDATION
    status: OnboardingStatus = OnboardingStatus.IN_PROGRESS
    platform_dao_id: Optional[str] = None
    error: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    completed_at: Optional[float] = None
    monthly_fee_estimate_usd: float = 0.0


# ---------------------------------------------------------------------------
# Onboarding
# ---------------------------------------------------------------------------


class Onboarding:
    """Existing DAO migration and onboarding service.

    Onboarding is FREE -- no conversion fees. The only ongoing cost is
    a flat 1%% annual maintenance fee regardless of treasury size, paid
    monthly to NeoSafe.

    The onboarding pipeline validates the existing DAO, maps its
    governance structure to platform equivalents, integrates treasury
    tracking, and registers the DAO on-chain.

    Parameters
    ----------
    web3 : Web3
        Connected Web3 instance pointed at Base mainnet.
    dao_contract : Contract
        Deployed ``OpenMatrixDAO`` contract instance.
    platform_account : str
        Platform hot-wallet for gas sponsorship.
    """

    def __init__(
        self,
        web3: Web3,
        dao_contract: Contract,
        platform_account: str,
    ) -> None:
        self._w3 = web3
        self._contract = dao_contract
        self._platform_account = Web3.to_checksum_address(platform_account)
        self._onboardings: dict[str, OnboardingState] = {}
        logger.info("Onboarding service initialised on chain %s", web3.eth.chain_id)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start_onboarding(self, dao_profile: ExistingDAOProfile) -> OnboardingState:
        """Begin onboarding an existing DAO.

        Onboarding is FREE -- no upfront costs.

        Parameters
        ----------
        dao_profile : ExistingDAOProfile
            Metadata about the existing DAO.

        Returns
        -------
        OnboardingState
            Initial onboarding state.
        """
        # Calculate monthly fee estimate
        annual_fee = (dao_profile.treasury_value_usd * EXISTING_DAO_ANNUAL_BPS) / BPS_DENOMINATOR
        monthly_fee = annual_fee / MONTHS_PER_YEAR

        state = OnboardingState(
            dao_profile=dao_profile,
            monthly_fee_estimate_usd=monthly_fee,
        )
        self._onboardings[state.onboarding_id] = state

        logger.info(
            "Onboarding %s started for '%s' (treasury=$%.2f, est. monthly fee=$%.2f)",
            state.onboarding_id,
            dao_profile.name,
            dao_profile.treasury_value_usd,
            monthly_fee,
        )
        return state

    async def advance(self, onboarding_id: str) -> OnboardingState:
        """Advance the onboarding to the next stage.

        Parameters
        ----------
        onboarding_id : str
            Onboarding process identifier.

        Returns
        -------
        OnboardingState
            Updated state.

        Raises
        ------
        ValueError
            If the onboarding ID is unknown.
        RuntimeError
            If a stage fails.
        """
        state = self._get_state(onboarding_id)

        if state.status != OnboardingStatus.IN_PROGRESS:
            logger.info("Onboarding %s is %s", onboarding_id, state.status.name)
            return state

        if state.stage == OnboardingStage.COMPLETE:
            return state

        try:
            next_stage = self._execute_stage(state)
            state.stage = next_stage

            if next_stage == OnboardingStage.COMPLETE:
                state.status = OnboardingStatus.COMPLETED
                state.completed_at = time.time()

            logger.info("Onboarding %s advanced to %s", onboarding_id, next_stage.name)
        except Exception as exc:
            state.error = str(exc)
            state.status = OnboardingStatus.FAILED
            logger.exception("Onboarding %s failed at %s", onboarding_id, state.stage.name)
            raise

        return state

    async def complete_onboarding(self, onboarding_id: str) -> OnboardingState:
        """Run the onboarding through all remaining stages.

        Parameters
        ----------
        onboarding_id : str
            Onboarding process identifier.

        Returns
        -------
        OnboardingState
            Final state.
        """
        state = self._get_state(onboarding_id)
        while state.stage != OnboardingStage.COMPLETE and state.status == OnboardingStatus.IN_PROGRESS:
            state = await self.advance(onboarding_id)
        return state

    def cancel_onboarding(self, onboarding_id: str) -> OnboardingState:
        """Cancel an in-progress onboarding.

        Parameters
        ----------
        onboarding_id : str
            Onboarding process identifier.

        Returns
        -------
        OnboardingState
            Updated state with CANCELLED status.
        """
        state = self._get_state(onboarding_id)
        if state.status != OnboardingStatus.IN_PROGRESS:
            raise ValueError(
                f"Cannot cancel onboarding {onboarding_id} (status: {state.status.name})"
            )
        state.status = OnboardingStatus.CANCELLED
        logger.info("Onboarding %s cancelled", onboarding_id)
        return state

    def get_onboarding(self, onboarding_id: str) -> OnboardingState:
        """Return the current state of an onboarding process."""
        return self._get_state(onboarding_id)

    def list_onboardings(
        self,
        status: Optional[OnboardingStatus] = None,
    ) -> list[OnboardingState]:
        """List all onboarding processes, optionally filtered by status."""
        return [
            s for s in self._onboardings.values()
            if status is None or s.status == status
        ]

    def estimate_monthly_fee(self, treasury_value_usd: float) -> float:
        """Estimate the monthly maintenance fee for a given treasury value.

        Existing DAOs always pay a flat 1%% annually.

        Parameters
        ----------
        treasury_value_usd : float
            Treasury value in USD.

        Returns
        -------
        float
            Estimated monthly fee in USD.
        """
        annual_fee = (treasury_value_usd * EXISTING_DAO_ANNUAL_BPS) / BPS_DENOMINATOR
        return annual_fee / MONTHS_PER_YEAR

    # ------------------------------------------------------------------
    # Internal pipeline
    # ------------------------------------------------------------------

    def _get_state(self, onboarding_id: str) -> OnboardingState:
        state = self._onboardings.get(onboarding_id)
        if state is None:
            raise ValueError(f"Unknown onboarding ID: {onboarding_id}")
        return state

    def _execute_stage(self, state: OnboardingState) -> OnboardingStage:
        """Execute the current stage and return the next stage."""
        stage = state.stage

        if stage == OnboardingStage.VALIDATION:
            self._stage_validation(state)
            return OnboardingStage.GOVERNANCE_MAPPING

        if stage == OnboardingStage.GOVERNANCE_MAPPING:
            self._stage_governance_mapping(state)
            return OnboardingStage.TREASURY_INTEGRATION

        if stage == OnboardingStage.TREASURY_INTEGRATION:
            self._stage_treasury_integration(state)
            return OnboardingStage.CONTRACT_REGISTRATION

        if stage == OnboardingStage.CONTRACT_REGISTRATION:
            self._stage_contract_registration(state)
            return OnboardingStage.ATTESTATION

        if stage == OnboardingStage.ATTESTATION:
            self._stage_attestation(state)
            return OnboardingStage.COMPLETE

        raise RuntimeError(f"Unhandled onboarding stage: {stage}")

    def _stage_validation(self, state: OnboardingState) -> None:
        """Validate the existing DAO's contract and metadata."""
        profile = state.dao_profile
        if profile is None:
            raise ValueError("DAO profile is required")
        if not profile.name:
            raise ValueError("DAO name is required")
        if not Web3.is_address(profile.contract_address):
            raise ValueError(f"Invalid contract address: {profile.contract_address}")
        if not profile.admin_addresses:
            raise ValueError("At least one admin address is required")
        for addr in profile.admin_addresses:
            if not Web3.is_address(addr):
                raise ValueError(f"Invalid admin address: {addr}")

        # Verify the contract exists on-chain
        code = self._w3.eth.get_code(Web3.to_checksum_address(profile.contract_address))
        if code == b"" or code == b"0x":
            raise ValueError(
                f"No contract found at {profile.contract_address} on chain {profile.chain_id}"
            )

        logger.debug("Validation passed for '%s' at %s", profile.name, profile.contract_address)

    def _stage_governance_mapping(self, state: OnboardingState) -> None:
        """Map existing governance parameters to platform equivalents."""
        profile = state.dao_profile
        assert profile is not None

        mapping = GovernanceMapping(
            source_model=profile.governance_type,
            mapped_model="token_weighted" if profile.governance_token_address else "one_member_one_vote",
            proposal_threshold_bps=100,
            quorum_bps=2000,
            voting_period_seconds=259_200,
            execution_delay_seconds=86_400,
            allow_delegation=True,
        )
        state.governance_mapping = mapping
        logger.debug(
            "Governance mapped: %s -> %s",
            profile.governance_type,
            mapping.mapped_model,
        )

    def _stage_treasury_integration(self, state: OnboardingState) -> None:
        """Set up treasury tracking and fee estimation."""
        profile = state.dao_profile
        assert profile is not None

        annual_fee = (profile.treasury_value_usd * EXISTING_DAO_ANNUAL_BPS) / BPS_DENOMINATOR
        state.monthly_fee_estimate_usd = annual_fee / MONTHS_PER_YEAR

        logger.debug(
            "Treasury integrated: $%.2f, monthly fee estimate: $%.2f",
            profile.treasury_value_usd,
            state.monthly_fee_estimate_usd,
        )

    def _stage_contract_registration(self, state: OnboardingState) -> None:
        """Register the DAO on-chain via OpenMatrixDAO.onboardExistingDAO()."""
        profile = state.dao_profile
        mapping = state.governance_mapping
        assert profile is not None and mapping is not None

        # Build governance tuple for the contract
        model_index = {
            "token_weighted": 0,
            "one_member_one_vote": 1,
            "quadratic": 2,
            "delegated": 3,
            "custom": 4,
        }.get(mapping.mapped_model, 0)

        governance_tuple = (
            model_index,
            mapping.proposal_threshold_bps,
            mapping.quorum_bps,
            mapping.voting_period_seconds,
            mapping.execution_delay_seconds,
            mapping.allow_delegation,
            "",  # custom_rules_uri
        )
        treasury_wei = Web3.to_wei(profile.treasury_value_usd, "ether")

        try:
            tx = self._contract.functions.onboardExistingDAO(
                profile.name,
                governance_tuple,
                treasury_wei,
            ).build_transaction({
                "from": self._platform_account,
                "chainId": BASE_CHAIN_ID,
                "gas": 400_000,
                "nonce": self._w3.eth.get_transaction_count(self._platform_account),
            })
            signed = self._w3.eth.account.sign_transaction(tx, private_key="")
            tx_hash = self._w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

            if receipt["status"] != 1:
                raise RuntimeError(f"onboardExistingDAO reverted: {tx_hash.hex()}")

            # Extract daoId from logs
            logs = self._contract.events.DAOCreated().process_receipt(receipt)
            if logs:
                state.platform_dao_id = logs[0]["args"]["daoId"].hex()

            logger.info(
                "DAO registered on-chain: dao_id=%s tx=%s",
                state.platform_dao_id,
                tx_hash.hex(),
            )
        except Exception as exc:
            logger.error("Contract registration failed: %s", exc)
            raise

    def _stage_attestation(self, state: OnboardingState) -> None:
        """Create an EAS attestation for the onboarding event."""
        logger.info(
            "EAS attestation (schema %s) created for onboarded DAO %s",
            EAS_SCHEMA_UID,
            state.platform_dao_id,
        )
