"""
Platform Rewards — Component 23

Zero card linking, zero spending data shared.
Rewards based on verifiable on-chain activity via EAS Schema 348.
Milestone volume thresholds are INJECTION POINTS requiring Dardan's input before launch.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum, auto
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class TriggerType(Enum):
    """On-chain activity triggers for platform-native rewards."""
    FIRST_TRANSACTION = auto()
    FIRST_SMART_CONTRACT_DEPLOYED = auto()
    FIRST_GOVERNANCE_VOTE = auto()
    FIRST_DEFI_LOAN_REPAID = auto()
    FIRST_NFT_MINTED = auto()
    PLATFORM_ANNIVERSARY = auto()


@dataclass
class RewardRecord:
    """Record of a single reward distribution."""
    user_address: str
    trigger_type: TriggerType
    amount_wei: int
    tx_hash: Optional[str] = None
    eas_attestation_uid: Optional[str] = None
    distributed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


@dataclass
class MilestoneThresholds:
    """
    Milestone volume thresholds for tiered rewards.

    ALL values are INJECTION POINTS.
    """
    # INJECTION POINT: Request actual threshold values from Dardan before production launch
    tier_1: int = 0  # Placeholder — to be set by Dardan

    # INJECTION POINT: Request actual threshold values from Dardan before production launch
    tier_2: int = 0  # Placeholder — to be set by Dardan

    # INJECTION POINT: Request actual threshold values from Dardan before production launch
    tier_3: int = 0  # Placeholder — to be set by Dardan

    # INJECTION POINT: Request actual threshold values from Dardan before production launch
    tier_4: int = 0  # Placeholder — to be set by Dardan

    # INJECTION POINT: Request actual threshold values from Dardan before production launch
    tier_5: int = 0  # Placeholder — to be set by Dardan


# INJECTION POINT: Request actual reward amounts from Dardan before production launch
DEFAULT_REWARD_AMOUNTS: Dict[TriggerType, int] = {
    TriggerType.FIRST_TRANSACTION: 0,               # Placeholder
    TriggerType.FIRST_SMART_CONTRACT_DEPLOYED: 0,   # Placeholder
    TriggerType.FIRST_GOVERNANCE_VOTE: 0,            # Placeholder
    TriggerType.FIRST_DEFI_LOAN_REPAID: 0,          # Placeholder
    TriggerType.FIRST_NFT_MINTED: 0,                # Placeholder
    TriggerType.PLATFORM_ANNIVERSARY: 0,             # Placeholder
}


class PlatformRewards:
    """
    Platform-native reward system based on verifiable on-chain activity.

    Principles:
    - Zero card linking, zero spending data shared
    - All eligibility verified via EAS Schema 348 attestations
    - Rewards come from platform treasury
    - No personal data collection whatsoever

    Milestone volume thresholds are INJECTION POINTS requiring configuration
    by Dardan before production launch.
    """

    EAS_SCHEMA_ID: int = 348
    NEOSAFE: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

    def __init__(
        self,
        web3_provider: Any,
        contract_address: str,
        eas_registry: Any,
        thresholds: Optional[MilestoneThresholds] = None,
        reward_amounts: Optional[Dict[TriggerType, int]] = None,
    ) -> None:
        """
        Initialize PlatformRewards.

        Args:
            web3_provider: Web3 provider instance.
            contract_address: Deployed LoyaltyRewards contract address.
            eas_registry: EAS attestation registry client.
            thresholds: Milestone volume thresholds (INJECTION POINT).
            reward_amounts: Reward amounts per trigger type (INJECTION POINT).
        """
        self._web3 = web3_provider
        self._contract_address = contract_address
        self._eas = eas_registry
        self._thresholds = thresholds or MilestoneThresholds()
        self._reward_amounts = reward_amounts or DEFAULT_REWARD_AMOUNTS.copy()
        self._reward_history: Dict[str, List[RewardRecord]] = {}
        self._fulfilled_triggers: Dict[str, set] = {}
        logger.info(
            "PlatformRewards initialized — contract=%s, EAS schema=%d",
            contract_address,
            self.EAS_SCHEMA_ID,
        )

    # -------------------------------------------------------------------------
    #  Public API
    # -------------------------------------------------------------------------

    def check_trigger(self, user: str, trigger_type: TriggerType) -> bool:
        """
        Check whether a user has fulfilled a specific on-chain trigger.

        Verifies via EAS Schema 348 attestation — zero spending data shared,
        zero card linking, purely on-chain activity verification.

        Args:
            user: User wallet address.
            trigger_type: The trigger to check.

        Returns:
            True if the trigger condition is met and the reward has NOT
            already been distributed for this trigger.

        Raises:
            ValueError: If user address is invalid.
        """
        self._validate_address(user)
        user_lower = user.lower()

        # Already fulfilled — no double rewards
        if trigger_type in self._fulfilled_triggers.get(user_lower, set()):
            logger.debug("Trigger %s already fulfilled for %s", trigger_type.name, user)
            return False

        try:
            attestation = self._eas.get_attestation(
                schema_id=self.EAS_SCHEMA_ID,
                recipient=user,
                trigger=trigger_type.name,
            )
            if attestation is None:
                logger.debug("No EAS attestation for %s / %s", user, trigger_type.name)
                return False

            is_valid = self._eas.verify_attestation(attestation)
            if not is_valid:
                logger.warning("Invalid attestation for %s / %s", user, trigger_type.name)
                return False

            logger.info("Trigger %s verified for %s via EAS schema %d", trigger_type.name, user, self.EAS_SCHEMA_ID)
            return True

        except Exception as exc:
            logger.error("EAS check failed for %s / %s: %s", user, trigger_type.name, exc)
            raise

    def distribute_reward(self, user: str, reward: TriggerType) -> RewardRecord:
        """
        Distribute a platform-native reward to a user from treasury.

        Args:
            user: User wallet address.
            reward: The trigger type that earned the reward.

        Returns:
            RewardRecord with distribution details.

        Raises:
            ValueError: If user address invalid or trigger not met.
            RuntimeError: If distribution transaction fails.
        """
        self._validate_address(user)
        user_lower = user.lower()

        if not self.check_trigger(user, reward):
            raise ValueError(
                f"Trigger {reward.name} not met or already fulfilled for {user}"
            )

        amount = self._reward_amounts.get(reward, 0)
        if amount <= 0:
            # INJECTION POINT: Request actual reward amounts from Dardan before production launch
            raise ValueError(
                f"Reward amount for {reward.name} is zero — "
                "INJECTION POINT: configure actual amounts before launch"
            )

        try:
            tx_hash = self._execute_distribution(user, reward, amount)
            attestation_uid = self._create_reward_attestation(user, reward, amount)

            record = RewardRecord(
                user_address=user,
                trigger_type=reward,
                amount_wei=amount,
                tx_hash=tx_hash,
                eas_attestation_uid=attestation_uid,
            )

            # Mark as fulfilled
            self._fulfilled_triggers.setdefault(user_lower, set()).add(reward)
            self._reward_history.setdefault(user_lower, []).append(record)

            logger.info(
                "Reward distributed: user=%s, trigger=%s, amount=%d, tx=%s",
                user, reward.name, amount, tx_hash,
            )
            return record

        except Exception as exc:
            logger.error("Distribution failed for %s / %s: %s", user, reward.name, exc)
            raise RuntimeError(f"Reward distribution failed: {exc}") from exc

    def get_user_rewards(self, user: str) -> List[RewardRecord]:
        """
        Get all reward records for a user.

        Args:
            user: User wallet address.

        Returns:
            List of RewardRecord instances.
        """
        self._validate_address(user)
        return list(self._reward_history.get(user.lower(), []))

    def get_available_triggers(self) -> List[TriggerType]:
        """
        Get all available trigger types.

        Returns:
            List of all TriggerType enum values.
        """
        return list(TriggerType)

    def get_unfulfilled_triggers(self, user: str) -> List[TriggerType]:
        """
        Get triggers not yet fulfilled for a user.

        Args:
            user: User wallet address.

        Returns:
            List of TriggerType values the user has not yet earned.
        """
        self._validate_address(user)
        fulfilled = self._fulfilled_triggers.get(user.lower(), set())
        return [t for t in TriggerType if t not in fulfilled]

    def get_milestone_thresholds(self) -> MilestoneThresholds:
        """
        Return current milestone thresholds.

        NOTE: All values are INJECTION POINTS — request actual threshold
        values from Dardan before production launch.
        """
        return self._thresholds

    # -------------------------------------------------------------------------
    #  Internal
    # -------------------------------------------------------------------------

    def _execute_distribution(self, user: str, trigger: TriggerType, amount: int) -> str:
        """Execute on-chain reward distribution from treasury."""
        tx = self._web3.eth.contract(
            address=self._contract_address,
        ).functions.distributePlatformReward(
            user,
            trigger.value - 1,  # Solidity enum is 0-indexed
            amount,
        ).build_transaction({
            "from": self.NEOSAFE,
            "gas": 200_000,
        })
        signed = self._web3.eth.account.sign_transaction(tx)
        tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self._web3.eth.wait_for_transaction_receipt(tx_hash)
        if receipt["status"] != 1:
            raise RuntimeError(f"Transaction reverted: {tx_hash.hex()}")
        return tx_hash.hex()

    def _create_reward_attestation(self, user: str, trigger: TriggerType, amount: int) -> str:
        """Create EAS attestation for the reward distribution."""
        return self._eas.attest(
            schema_id=self.EAS_SCHEMA_ID,
            recipient=user,
            data={
                "trigger": trigger.name,
                "amount": amount,
                "source": "platform_treasury",
            },
        )

    @staticmethod
    def _validate_address(address: str) -> None:
        """Validate an Ethereum address format."""
        if not address or not isinstance(address, str):
            raise ValueError("Address must be a non-empty string")
        if not address.startswith("0x") or len(address) != 42:
            raise ValueError(f"Invalid Ethereum address: {address}")
