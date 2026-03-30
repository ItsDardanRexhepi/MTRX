"""
ERC-8004 Agent Registration
============================

Every agent on 0pnMatrx automatically gets an ERC-8004 on-chain identity
on first deployment. No user action required.

NeoSafe: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class IdentityStatus(Enum):
    """Lifecycle states for an ERC-8004 agent identity."""
    PENDING = "pending"
    ACTIVE = "active"
    SUSPENDED = "suspended"
    REVOKED = "revoked"


@dataclass
class AgentConfig:
    """Configuration payload supplied when deploying an agent."""
    name: str
    description: str
    agent_type: str
    owner_address: str
    capabilities: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentIdentity:
    """On-chain ERC-8004 identity record for an agent."""
    agent_id: str
    erc8004_token_id: str
    name: str
    description: str
    agent_type: str
    owner_address: str
    capabilities: List[str]
    status: IdentityStatus
    registered_at: datetime
    updated_at: datetime
    chain_id: int = 8453  # Base
    contract_address: str = NEOSAFE_ADDRESS
    metadata: Dict[str, Any] = field(default_factory=dict)
    tx_hash: Optional[str] = None


class AgentRegistration:
    """Manages ERC-8004 on-chain identity lifecycle for 0pnMatrx agents.

    Every agent deployed on the platform automatically receives an ERC-8004
    on-chain identity. No user action is required — registration is triggered
    internally at first deployment.
    """

    def __init__(self, rpc_url: Optional[str] = None) -> None:
        self._rpc_url: str = rpc_url or ""
        self._identities: Dict[str, AgentIdentity] = {}
        logger.info("AgentRegistration initialised (NeoSafe=%s)", NEOSAFE_ADDRESS)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def register_agent(self, agent_config: AgentConfig) -> AgentIdentity:
        """Register a new agent and mint its ERC-8004 on-chain identity.

        Called automatically on first deployment — no user action required.

        Args:
            agent_config: Deployment configuration for the agent.

        Returns:
            The newly created ``AgentIdentity``.

        Raises:
            ValueError: If required fields are missing from *agent_config*.
            RuntimeError: If the on-chain minting transaction fails.
        """
        self._validate_config(agent_config)

        agent_id = self._generate_agent_id(agent_config)
        if agent_id in self._identities:
            logger.warning("Agent %s already registered — returning existing identity", agent_id)
            return self._identities[agent_id]

        now = datetime.now(timezone.utc)
        token_id = self._mint_erc8004_token(agent_config, agent_id)

        identity = AgentIdentity(
            agent_id=agent_id,
            erc8004_token_id=token_id,
            name=agent_config.name,
            description=agent_config.description,
            agent_type=agent_config.agent_type,
            owner_address=agent_config.owner_address,
            capabilities=list(agent_config.capabilities),
            status=IdentityStatus.ACTIVE,
            registered_at=now,
            updated_at=now,
            metadata=dict(agent_config.metadata),
        )

        self._identities[agent_id] = identity
        logger.info("Agent %s registered with ERC-8004 token %s", agent_id, token_id)
        return identity

    def get_agent_identity(self, agent_id: str) -> AgentIdentity:
        """Retrieve an agent's ERC-8004 on-chain identity.

        Args:
            agent_id: Unique agent identifier.

        Returns:
            The matching ``AgentIdentity``.

        Raises:
            KeyError: If *agent_id* is not found.
        """
        if agent_id not in self._identities:
            raise KeyError(f"Agent identity not found: {agent_id}")
        return self._identities[agent_id]

    def update_identity(self, agent_id: str, updates: Dict[str, Any]) -> AgentIdentity:
        """Apply updates to an existing ERC-8004 identity.

        Args:
            agent_id: Unique agent identifier.
            updates: Key/value pairs to merge into the identity.

        Returns:
            The updated ``AgentIdentity``.

        Raises:
            KeyError: If *agent_id* is not found.
            ValueError: If attempting to change immutable fields.
            RuntimeError: If on-chain update transaction fails.
        """
        identity = self.get_agent_identity(agent_id)

        immutable_fields = {"agent_id", "erc8004_token_id", "registered_at", "contract_address", "chain_id"}
        conflicts = immutable_fields & set(updates.keys())
        if conflicts:
            raise ValueError(f"Cannot modify immutable fields: {conflicts}")

        self._update_on_chain(identity, updates)

        for key, value in updates.items():
            if hasattr(identity, key):
                setattr(identity, key, value)
            else:
                identity.metadata[key] = value

        identity.updated_at = datetime.now(timezone.utc)
        logger.info("Agent %s identity updated: %s", agent_id, list(updates.keys()))
        return identity

    def revoke_identity(self, agent_id: str) -> AgentIdentity:
        """Revoke an agent's ERC-8004 identity, permanently deactivating it.

        Args:
            agent_id: Unique agent identifier.

        Returns:
            The revoked ``AgentIdentity``.

        Raises:
            KeyError: If *agent_id* is not found.
            RuntimeError: If on-chain revocation fails.
        """
        identity = self.get_agent_identity(agent_id)

        if identity.status == IdentityStatus.REVOKED:
            logger.warning("Agent %s is already revoked", agent_id)
            return identity

        self._revoke_on_chain(identity)

        identity.status = IdentityStatus.REVOKED
        identity.updated_at = datetime.now(timezone.utc)
        logger.info("Agent %s identity revoked", agent_id)
        return identity

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _validate_config(config: AgentConfig) -> None:
        """Ensure all required fields are present and non-empty."""
        if not config.name or not config.name.strip():
            raise ValueError("agent_config.name is required")
        if not config.agent_type or not config.agent_type.strip():
            raise ValueError("agent_config.agent_type is required")
        if not config.owner_address or not config.owner_address.strip():
            raise ValueError("agent_config.owner_address is required")

    @staticmethod
    def _generate_agent_id(config: AgentConfig) -> str:
        """Deterministic agent ID from config + entropy."""
        return f"agent-{uuid.uuid5(uuid.NAMESPACE_DNS, f'{config.name}-{config.owner_address}-{time.time_ns()}')}"

    def _mint_erc8004_token(self, config: AgentConfig, agent_id: str) -> str:
        """Mint an ERC-8004 identity token on Base via NeoSafe.

        Returns:
            The hex token ID.

        Raises:
            RuntimeError: If the mint transaction fails.
        """
        try:
            # TODO: Replace with actual Web3 contract call to NeoSafe
            # contract = w3.eth.contract(address=NEOSAFE_ADDRESS, abi=ERC8004_ABI)
            # tx = contract.functions.mint(agent_id, config.name, config.owner_address).transact()
            token_id = f"0x{uuid.uuid4().hex}"
            logger.debug("Minted ERC-8004 token %s for agent %s", token_id, agent_id)
            return token_id
        except Exception as exc:
            logger.error("Failed to mint ERC-8004 token for agent %s: %s", agent_id, exc)
            raise RuntimeError(f"ERC-8004 minting failed for agent {agent_id}") from exc

    def _update_on_chain(self, identity: AgentIdentity, updates: Dict[str, Any]) -> None:
        """Push identity updates to the on-chain ERC-8004 record.

        Raises:
            RuntimeError: If the on-chain transaction fails.
        """
        try:
            # TODO: Replace with actual Web3 contract call
            logger.debug("On-chain update for token %s: %s", identity.erc8004_token_id, list(updates.keys()))
        except Exception as exc:
            logger.error("On-chain update failed for %s: %s", identity.agent_id, exc)
            raise RuntimeError(f"On-chain update failed for {identity.agent_id}") from exc

    def _revoke_on_chain(self, identity: AgentIdentity) -> None:
        """Burn / revoke the ERC-8004 token on-chain.

        Raises:
            RuntimeError: If the revocation transaction fails.
        """
        try:
            # TODO: Replace with actual Web3 contract call
            logger.debug("On-chain revocation for token %s", identity.erc8004_token_id)
        except Exception as exc:
            logger.error("On-chain revocation failed for %s: %s", identity.agent_id, exc)
            raise RuntimeError(f"On-chain revocation failed for {identity.agent_id}") from exc
