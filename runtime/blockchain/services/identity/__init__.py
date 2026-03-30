"""
Component 5 - Identity Service
================================

Self-sovereign identity management on 0pnMatrx. Users control their own
cryptographic keys and decide exactly what to share, with whom, and for how
long. The platform NEVER sees plaintext credentials.

Sub-modules
-----------
credential_vault       : Encrypted credential storage (user holds the keys).
selective_disclosure   : Time-bounded, auto-revoking credential sharing.
zkp                    : Zero-knowledge proof generation and verification.
identity_assist        : Guided identity-process navigation.
"""

from runtime.blockchain.services.identity.credential_vault import CredentialVault
from runtime.blockchain.services.identity.selective_disclosure import SelectiveDisclosure
from runtime.blockchain.services.identity.zkp import ZKPEngine
from runtime.blockchain.services.identity.identity_assist import IdentityAssist

__all__ = [
    "CredentialVault",
    "SelectiveDisclosure",
    "ZKPEngine",
    "IdentityAssist",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 5
COMPONENT_NAME: str = "Identity Service"
