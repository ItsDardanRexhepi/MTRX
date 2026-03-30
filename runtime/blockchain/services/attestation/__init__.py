"""
Component 8 - Attestation Service
====================================

On-chain attestation management via EAS (Ethereum Attestation Service).
Classifies attestations as time-critical or batchable, routes accordingly,
and provides user-facing history and shareable proof links.

Sub-modules
-----------
dispatcher         : Classify and route attestations.
batch_processor    : Group batchable attestations for gas efficiency.
immediate_handler  : Process time-critical attestations immediately.
viewer             : User attestation history and shareable proof links.
proof_generator    : Plain-language human-readable proof summaries.
"""

from runtime.blockchain.services.attestation.dispatcher import AttestationDispatcher
from runtime.blockchain.services.attestation.batch_processor import BatchProcessor
from runtime.blockchain.services.attestation.immediate_handler import ImmediateHandler
from runtime.blockchain.services.attestation.viewer import AttestationViewer
from runtime.blockchain.services.attestation.proof_generator import ProofGenerator

__all__ = [
    "AttestationDispatcher",
    "BatchProcessor",
    "ImmediateHandler",
    "AttestationViewer",
    "ProofGenerator",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 8
COMPONENT_NAME: str = "Attestation Service"
