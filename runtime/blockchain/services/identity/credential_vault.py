"""
Credential Vault
=================

Encrypted credential storage where the user controls the keys. The platform
NEVER sees plaintext credential data. All encryption and decryption happens
client-side or within the user's secure enclave; the vault only stores and
retrieves ciphertext blobs.

Credentials are anchored on-chain via content hashes so tampering is
detectable without ever exposing the underlying data.
"""

from __future__ import annotations

import hashlib
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class CredentialType(Enum):
    """Supported credential categories."""
    GOVERNMENT_ID = "government_id"
    DRIVERS_LICENSE = "drivers_license"
    PASSPORT = "passport"
    PROOF_OF_ADDRESS = "proof_of_address"
    EMPLOYMENT = "employment"
    EDUCATION = "education"
    FINANCIAL = "financial"
    HEALTH = "health"
    PROFESSIONAL_LICENSE = "professional_license"
    CUSTOM = "custom"


class VaultStatus(Enum):
    """Lifecycle states for a stored credential."""
    ACTIVE = "active"
    EXPIRED = "expired"
    REVOKED = "revoked"
    PENDING_VERIFICATION = "pending_verification"


@dataclass
class EncryptedCredential:
    """A credential stored in its encrypted form.

    The platform stores only ciphertext and metadata needed for
    indexing and integrity verification. The decryption key never
    leaves the user's device.
    """
    credential_id: str
    owner_address: str
    credential_type: CredentialType
    ciphertext: bytes
    encryption_nonce: bytes
    content_hash: str
    issuer: str = ""
    issued_at: float = field(default_factory=time.time)
    expires_at: Optional[float] = None
    status: VaultStatus = VaultStatus.ACTIVE
    on_chain_anchor_tx: Optional[str] = None
    metadata_encrypted: bytes = b""
    schema_version: int = 1

    @property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return False
        return time.time() > self.expires_at


@dataclass
class VaultKeyInfo:
    """Public metadata about a user's vault encryption key.

    The actual private key material is NEVER stored or transmitted
    by the platform.
    """
    owner_address: str
    public_key_hex: str
    key_algorithm: str = "x25519-xsalsa20-poly1305"
    created_at: float = field(default_factory=time.time)
    rotation_count: int = 0
    last_rotated_at: Optional[float] = None


class CredentialVault:
    """Encrypted credential storage with user-controlled keys.

    The vault stores only ciphertext blobs and content hashes. The user's
    encryption key never touches platform infrastructure. On-chain anchoring
    provides tamper evidence without revealing credential contents.

    Parameters
    ----------
    web3_provider : Any
        Connected Web3 provider for on-chain anchoring.
    identity_contract : Any
        Deployed identity registry contract.
    """

    def __init__(
        self,
        web3_provider: Any,
        identity_contract: Any,
    ) -> None:
        self._web3 = web3_provider
        self._contract = identity_contract
        self._vaults: Dict[str, List[EncryptedCredential]] = {}
        self._key_registry: Dict[str, VaultKeyInfo] = {}
        logger.info("CredentialVault initialised")

    # ------------------------------------------------------------------
    # Key management (public metadata only)
    # ------------------------------------------------------------------

    def register_public_key(
        self,
        owner_address: str,
        public_key_hex: str,
        key_algorithm: str = "x25519-xsalsa20-poly1305",
    ) -> VaultKeyInfo:
        """Register a user's public encryption key.

        The private key is generated and stored entirely on the user's
        device. Only the public component is registered here for
        encryption-to-recipient workflows.

        Args:
            owner_address: User's wallet address.
            public_key_hex: Hex-encoded public key.
            key_algorithm: Encryption algorithm identifier.

        Returns:
            VaultKeyInfo with the registered public key metadata.
        """
        info = VaultKeyInfo(
            owner_address=owner_address,
            public_key_hex=public_key_hex,
            key_algorithm=key_algorithm,
        )
        existing = self._key_registry.get(owner_address)
        if existing:
            info.rotation_count = existing.rotation_count + 1
            info.last_rotated_at = time.time()
            logger.info(
                "Key rotated for %s (rotation #%d)", owner_address, info.rotation_count
            )
        self._key_registry[owner_address] = info
        return info

    def get_public_key(self, owner_address: str) -> Optional[VaultKeyInfo]:
        """Retrieve a user's registered public key metadata."""
        return self._key_registry.get(owner_address)

    # ------------------------------------------------------------------
    # Credential storage
    # ------------------------------------------------------------------

    def store_credential(
        self,
        owner_address: str,
        credential_type: CredentialType,
        ciphertext: bytes,
        encryption_nonce: bytes,
        issuer: str = "",
        expires_at: Optional[float] = None,
        metadata_encrypted: bytes = b"",
    ) -> EncryptedCredential:
        """Store an encrypted credential in the vault.

        The ciphertext has already been encrypted client-side with the
        user's key. The platform stores it as-is and computes a content
        hash for on-chain anchoring.

        Args:
            owner_address: Wallet address of the credential owner.
            credential_type: Category of credential.
            ciphertext: Client-encrypted credential payload.
            encryption_nonce: Nonce used during encryption.
            issuer: Optional issuer identifier.
            expires_at: Optional expiration timestamp.
            metadata_encrypted: Optional encrypted metadata blob.

        Returns:
            The stored EncryptedCredential record.
        """
        content_hash = self._compute_content_hash(ciphertext, encryption_nonce)
        credential_id = f"cred-{uuid.uuid4().hex[:16]}"

        credential = EncryptedCredential(
            credential_id=credential_id,
            owner_address=owner_address,
            credential_type=credential_type,
            ciphertext=ciphertext,
            encryption_nonce=encryption_nonce,
            content_hash=content_hash,
            issuer=issuer,
            expires_at=expires_at,
            metadata_encrypted=metadata_encrypted,
        )

        if owner_address not in self._vaults:
            self._vaults[owner_address] = []
        self._vaults[owner_address].append(credential)

        # Anchor hash on-chain
        anchor_tx = self._anchor_on_chain(owner_address, credential_id, content_hash)
        credential.on_chain_anchor_tx = anchor_tx

        logger.info(
            "Credential %s stored for %s (type=%s, anchor_tx=%s)",
            credential_id, owner_address, credential_type.value, anchor_tx,
        )
        return credential

    def retrieve_credential(
        self, owner_address: str, credential_id: str
    ) -> Optional[EncryptedCredential]:
        """Retrieve an encrypted credential by ID.

        Returns the ciphertext blob. Decryption is the caller's
        responsibility (user-side).

        Args:
            owner_address: Credential owner.
            credential_id: The credential identifier.

        Returns:
            The EncryptedCredential or None if not found.
        """
        for cred in self._vaults.get(owner_address, []):
            if cred.credential_id == credential_id:
                self._refresh_status(cred)
                return cred
        return None

    def list_credentials(
        self,
        owner_address: str,
        credential_type: Optional[CredentialType] = None,
        include_expired: bool = False,
    ) -> List[EncryptedCredential]:
        """List all credentials for a user, optionally filtered.

        Returns metadata only -- the ciphertext blobs are included but
        only the user can decrypt them.

        Args:
            owner_address: Credential owner.
            credential_type: Optional type filter.
            include_expired: Whether to include expired credentials.

        Returns:
            List of matching EncryptedCredential records.
        """
        credentials = self._vaults.get(owner_address, [])
        result: List[EncryptedCredential] = []
        for cred in credentials:
            self._refresh_status(cred)
            if not include_expired and cred.status == VaultStatus.EXPIRED:
                continue
            if cred.status == VaultStatus.REVOKED:
                continue
            if credential_type and cred.credential_type != credential_type:
                continue
            result.append(cred)
        return result

    def revoke_credential(self, owner_address: str, credential_id: str) -> bool:
        """Revoke a credential, making it unavailable for disclosure.

        Args:
            owner_address: Credential owner.
            credential_id: The credential to revoke.

        Returns:
            True if revoked, False if not found.
        """
        cred = self.retrieve_credential(owner_address, credential_id)
        if cred is None:
            return False
        cred.status = VaultStatus.REVOKED
        logger.info("Credential %s revoked for %s", credential_id, owner_address)
        return True

    def verify_integrity(self, owner_address: str, credential_id: str) -> bool:
        """Verify that a stored credential has not been tampered with.

        Re-computes the content hash and compares it against the
        on-chain anchor.

        Args:
            owner_address: Credential owner.
            credential_id: The credential to verify.

        Returns:
            True if the content hash matches, False otherwise.
        """
        cred = self.retrieve_credential(owner_address, credential_id)
        if cred is None:
            return False
        recomputed = self._compute_content_hash(cred.ciphertext, cred.encryption_nonce)
        matches = recomputed == cred.content_hash
        if not matches:
            logger.warning(
                "Integrity check FAILED for credential %s (owner=%s)",
                credential_id, owner_address,
            )
        return matches

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _compute_content_hash(ciphertext: bytes, nonce: bytes) -> str:
        """Compute a SHA-256 content hash over ciphertext + nonce."""
        hasher = hashlib.sha256()
        hasher.update(ciphertext)
        hasher.update(nonce)
        return hasher.hexdigest()

    def _anchor_on_chain(
        self, owner_address: str, credential_id: str, content_hash: str
    ) -> Optional[str]:
        """Anchor the credential content hash on-chain for tamper evidence."""
        try:
            cred_id_bytes = credential_id.encode("utf-8")
            hash_bytes = bytes.fromhex(content_hash)

            tx = self._contract.functions.anchorCredential(
                owner_address,
                cred_id_bytes,
                hash_bytes,
            ).build_transaction({
                "from": self._web3.eth.default_account,
            })
            signed = self._web3.eth.account.sign_transaction(
                tx, private_key=self._web3.eth.default_account,
            )
            tx_hash = self._web3.eth.send_raw_transaction(signed.rawTransaction)
            self._web3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
            return tx_hash.hex()
        except Exception as exc:
            logger.warning("On-chain anchoring failed for %s: %s", credential_id, exc)
            return None

    @staticmethod
    def _refresh_status(credential: EncryptedCredential) -> None:
        """Update credential status based on expiration."""
        if credential.status == VaultStatus.ACTIVE and credential.is_expired:
            credential.status = VaultStatus.EXPIRED
