"""
ERC-8004 Agent Identity Service
================================

Provides on-chain identity management for agents deployed on 0pnMatrx.
Every agent automatically receives an ERC-8004 identity upon first deployment
with no user action required.

Includes:
- Agent registration and identity lifecycle
- On-chain reputation tracking
- Automated ERC-8004 standard update monitoring and application
- Safety validation pipeline: UpdateSafetyValidator -> RexhepiGate -> UpdateExecutor
"""

from runtime.blockchain.services.agent_identity.registration import AgentRegistration
from runtime.blockchain.services.agent_identity.reputation import AgentReputation
from runtime.blockchain.services.agent_identity.update_monitor import UpdateMonitor
from runtime.blockchain.services.agent_identity.update_safety import UpdateSafetyValidator
from runtime.blockchain.services.agent_identity.rexhepi_gate import RexhepiGateConnector
from runtime.blockchain.services.agent_identity.update_executor import UpdateExecutor

__all__ = [
    "AgentRegistration",
    "AgentReputation",
    "UpdateMonitor",
    "UpdateSafetyValidator",
    "RexhepiGateConnector",
    "UpdateExecutor",
]
