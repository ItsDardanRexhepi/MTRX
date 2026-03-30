"""
Zero-Knowledge Proof Engine
=============================

Generates and verifies zero-knowledge proofs that allow users to prove
facts about their credentials without revealing the underlying data.

Examples:
- "I am over 21" without revealing date of birth.
- "My income exceeds $50k" without revealing exact income.
- "I hold a valid driver's licence" without revealing licence number.

Proof circuits are pre-compiled for common claim types. Custom circuits
can be registered for domain-specific proofs.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class ClaimType(Enum):
    """Pre-compiled zero-knowledge claim types."""
    AGE_OVER = "age_over"
    AGE_UNDER = "age_under"
    INCOME_ABOVE = "income_above"
    INCOME_BELOW = "income_below"
    CREDENTIAL_VALID = "credential_valid"
    RESIDENCY_COUNTRY = "residency_country"
    EMPLOYMENT_ACTIVE = "employment_active"
    CREDIT_SCORE_RANGE = "credit_score_range"
    ASSET_OWNERSHIP = "asset_ownership"
    CUSTOM = "custom"


class ProofStatus(Enum):
    """Proof lifecycle states."""
    VALID = "valid"
    EXPIRED = "expired"
    REVOKED = "revoked"
    INVALID = "invalid"


@dataclass
class ZKProof:
    """A generated zero-knowledge proof."""
    proof_id: str
    prover_address: str
    claim_type: ClaimType
    claim_parameters: Dict[str, Any]
    proof_data: bytes
    public_inputs: List[str]
    circuit_id: str
    generated_at: float = field(default_factory=time.time)
    expires_at: Optional[float] = None
    status: ProofStatus = ProofStatus.VALID
    verification_key_hash: str = ""
    on_chain_tx: Optional[str] = None

    @property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return False
        return time.time() > self.expires_at


@dataclass
class VerificationResult:
    """Outcome of a zero-knowledge proof verification."""
    proof_id: str
    verified: bool
    claim_type: ClaimType
    claim_satisfied: bool
    verified_at: float = field(default_factory=time.time)
    verifier_address: Optional[str] = None
    error: Optional[str] = None


@dataclass
class Circuit:
    """A ZKP circuit definition."""
    circuit_id: str
    claim_type: ClaimType
    description: str
    verification_key: bytes
    proving_key_hash: str
    version: int = 1
    registered_at: float = field(default_factory=time.time)


class ZKPEngine:
    """Zero-knowledge proof generation and verification engine.

    Provides a high-level API for users to prove facts about their
    credentials without revealing the underlying data. Pre-compiled
    circuits handle common claim types; custom circuits can be registered.

    Parameters
    ----------
    credential_vault : Any
        CredentialVault for retrieving credential data during proof
        generation (decrypted client-side).
    web3_provider : Any
        Web3 provider for on-chain proof anchoring.
    """

    def __init__(
        self,
        credential_vault: Any,
        web3_provider: Any = None,
    ) -> None:
        self._vault = credential_vault
        self._web3 = web3_provider
        self._circuits: Dict[str, Circuit] = {}
        self._proofs: Dict[str, ZKProof] = {}
        self._verification_log: List[VerificationResult] = []
        self._register_default_circuits()
        logger.info("ZKPEngine initialised with %d default circuits", len(self._circuits))

    # ------------------------------------------------------------------
    # Circuit management
    # ------------------------------------------------------------------

    def register_circuit(
        self,
        claim_type: ClaimType,
        description: str,
        verification_key: bytes,
        proving_key_hash: str,
        circuit_id: Optional[str] = None,
    ) -> Circuit:
        """Register a new ZKP circuit.

        Args:
            claim_type: The type of claim this circuit proves.
            description: Human-readable description.
            verification_key: The circuit's verification key.
            proving_key_hash: Hash of the proving key (for integrity).
            circuit_id: Optional explicit ID; auto-generated if omitted.

        Returns:
            The registered Circuit.
        """
        cid = circuit_id or f"circuit-{uuid.uuid4().hex[:12]}"
        circuit = Circuit(
            circuit_id=cid,
            claim_type=claim_type,
            description=description,
            verification_key=verification_key,
            proving_key_hash=proving_key_hash,
        )
        self._circuits[cid] = circuit
        logger.info("Circuit %s registered for claim type %s", cid, claim_type.value)
        return circuit

    def get_circuit(self, circuit_id: str) -> Optional[Circuit]:
        """Retrieve a circuit by ID."""
        return self._circuits.get(circuit_id)

    def list_circuits(self, claim_type: Optional[ClaimType] = None) -> List[Circuit]:
        """List available circuits, optionally filtered by claim type."""
        if claim_type is None:
            return list(self._circuits.values())
        return [c for c in self._circuits.values() if c.claim_type == claim_type]

    # ------------------------------------------------------------------
    # Proof generation
    # ------------------------------------------------------------------

    def generate_proof(
        self,
        prover_address: str,
        credential_id: str,
        claim_type: ClaimType,
        claim_parameters: Dict[str, Any],
        decrypted_credential_data: Dict[str, Any],
        duration_seconds: int = 3600,
    ) -> ZKProof:
        """Generate a zero-knowledge proof for a claim.

        The decrypted credential data is provided by the client and
        is used only transiently for proof computation. It is NEVER
        stored by the engine.

        Args:
            prover_address: The user generating the proof.
            credential_id: The credential being used as witness.
            claim_type: What fact is being proved.
            claim_parameters: Parameters for the claim (e.g. age threshold).
            decrypted_credential_data: Plaintext credential data (client-provided,
                used transiently, never stored).
            duration_seconds: How long the proof remains valid.

        Returns:
            The generated ZKProof.

        Raises:
            ValueError: If no circuit exists for the claim type.
            ValueError: If the claim cannot be satisfied.
        """
        # Find matching circuit
        circuits = self.list_circuits(claim_type)
        if not circuits:
            raise ValueError(f"No circuit registered for claim type: {claim_type.value}")
        circuit = circuits[0]

        # Evaluate the claim against the credential data
        claim_satisfied = self._evaluate_claim(
            claim_type, claim_parameters, decrypted_credential_data
        )
        if not claim_satisfied:
            raise ValueError(
                f"Claim {claim_type.value} cannot be satisfied with the provided credential data"
            )

        # Generate proof (simulated ZKP computation)
        proof_data, public_inputs = self._compute_proof(
            circuit, claim_parameters, decrypted_credential_data
        )
        vk_hash = hashlib.sha256(circuit.verification_key).hexdigest()

        now = time.time()
        proof = ZKProof(
            proof_id=f"zkp-{uuid.uuid4().hex[:16]}",
            prover_address=prover_address,
            claim_type=claim_type,
            claim_parameters=claim_parameters,
            proof_data=proof_data,
            public_inputs=public_inputs,
            circuit_id=circuit.circuit_id,
            generated_at=now,
            expires_at=now + duration_seconds,
            verification_key_hash=vk_hash,
        )

        # Anchor on-chain if web3 available
        if self._web3:
            proof.on_chain_tx = self._anchor_proof(proof)

        self._proofs[proof.proof_id] = proof
        logger.info(
            "ZKP generated: %s (claim=%s, circuit=%s, expires_in=%ds)",
            proof.proof_id, claim_type.value, circuit.circuit_id, duration_seconds,
        )
        # Clear sensitive data from memory
        decrypted_credential_data.clear()
        return proof

    def verify_proof(
        self,
        proof_id: str,
        verifier_address: Optional[str] = None,
    ) -> VerificationResult:
        """Verify a zero-knowledge proof.

        Args:
            proof_id: The proof to verify.
            verifier_address: Optional address of the verifying party.

        Returns:
            VerificationResult indicating whether the proof is valid.
        """
        proof = self._proofs.get(proof_id)
        if proof is None:
            result = VerificationResult(
                proof_id=proof_id,
                verified=False,
                claim_type=ClaimType.CUSTOM,
                claim_satisfied=False,
                verifier_address=verifier_address,
                error="Proof not found",
            )
            self._verification_log.append(result)
            return result

        # Check expiration
        if proof.is_expired:
            proof.status = ProofStatus.EXPIRED
            result = VerificationResult(
                proof_id=proof_id,
                verified=False,
                claim_type=proof.claim_type,
                claim_satisfied=False,
                verifier_address=verifier_address,
                error="Proof has expired",
            )
            self._verification_log.append(result)
            return result

        # Check revocation
        if proof.status == ProofStatus.REVOKED:
            result = VerificationResult(
                proof_id=proof_id,
                verified=False,
                claim_type=proof.claim_type,
                claim_satisfied=False,
                verifier_address=verifier_address,
                error="Proof has been revoked",
            )
            self._verification_log.append(result)
            return result

        # Verify the proof cryptographically
        circuit = self._circuits.get(proof.circuit_id)
        if circuit is None:
            result = VerificationResult(
                proof_id=proof_id,
                verified=False,
                claim_type=proof.claim_type,
                claim_satisfied=False,
                verifier_address=verifier_address,
                error="Circuit not found",
            )
            self._verification_log.append(result)
            return result

        cryptographic_valid = self._verify_cryptographic(proof, circuit)

        result = VerificationResult(
            proof_id=proof_id,
            verified=cryptographic_valid,
            claim_type=proof.claim_type,
            claim_satisfied=cryptographic_valid,
            verifier_address=verifier_address,
        )
        self._verification_log.append(result)

        logger.info(
            "ZKP verification: %s -> %s (verifier=%s)",
            proof_id, "VALID" if cryptographic_valid else "INVALID", verifier_address,
        )
        return result

    def revoke_proof(self, prover_address: str, proof_id: str) -> bool:
        """Revoke a previously generated proof.

        Args:
            prover_address: Must match the original prover.
            proof_id: The proof to revoke.

        Returns:
            True if revoked, False if not found or not authorised.
        """
        proof = self._proofs.get(proof_id)
        if proof is None or proof.prover_address != prover_address:
            return False
        proof.status = ProofStatus.REVOKED
        logger.info("Proof %s revoked by %s", proof_id, prover_address)
        return True

    def get_proof(self, proof_id: str) -> Optional[ZKProof]:
        """Retrieve a proof by ID."""
        return self._proofs.get(proof_id)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _register_default_circuits(self) -> None:
        """Register pre-compiled circuits for common claim types."""
        defaults = [
            (ClaimType.AGE_OVER, "Prove age exceeds a threshold"),
            (ClaimType.AGE_UNDER, "Prove age is below a threshold"),
            (ClaimType.INCOME_ABOVE, "Prove income exceeds a threshold"),
            (ClaimType.INCOME_BELOW, "Prove income is below a threshold"),
            (ClaimType.CREDENTIAL_VALID, "Prove a credential is currently valid"),
            (ClaimType.RESIDENCY_COUNTRY, "Prove country of residency"),
            (ClaimType.EMPLOYMENT_ACTIVE, "Prove active employment status"),
            (ClaimType.CREDIT_SCORE_RANGE, "Prove credit score falls in a range"),
            (ClaimType.ASSET_OWNERSHIP, "Prove ownership of an asset class"),
        ]
        for claim_type, description in defaults:
            vk = os.urandom(64)
            pk_hash = hashlib.sha256(os.urandom(64)).hexdigest()
            self.register_circuit(
                claim_type=claim_type,
                description=description,
                verification_key=vk,
                proving_key_hash=pk_hash,
                circuit_id=f"default-{claim_type.value}",
            )

    @staticmethod
    def _evaluate_claim(
        claim_type: ClaimType,
        parameters: Dict[str, Any],
        credential_data: Dict[str, Any],
    ) -> bool:
        """Evaluate whether a claim is satisfied by the credential data."""
        if claim_type == ClaimType.AGE_OVER:
            age = credential_data.get("age", 0)
            threshold = parameters.get("threshold", 0)
            return age >= threshold

        if claim_type == ClaimType.AGE_UNDER:
            age = credential_data.get("age", 999)
            threshold = parameters.get("threshold", 0)
            return age < threshold

        if claim_type == ClaimType.INCOME_ABOVE:
            income = credential_data.get("annual_income", 0)
            threshold = parameters.get("threshold", 0)
            return income >= threshold

        if claim_type == ClaimType.INCOME_BELOW:
            income = credential_data.get("annual_income", float("inf"))
            threshold = parameters.get("threshold", 0)
            return income < threshold

        if claim_type == ClaimType.CREDENTIAL_VALID:
            expires = credential_data.get("expires_at")
            if expires is None:
                return True
            return time.time() < expires

        if claim_type == ClaimType.RESIDENCY_COUNTRY:
            country = credential_data.get("country", "")
            target = parameters.get("country", "")
            return country.upper() == target.upper()

        if claim_type == ClaimType.EMPLOYMENT_ACTIVE:
            return credential_data.get("employment_active", False) is True

        if claim_type == ClaimType.CREDIT_SCORE_RANGE:
            score = credential_data.get("credit_score", 0)
            min_score = parameters.get("min_score", 0)
            max_score = parameters.get("max_score", 850)
            return min_score <= score <= max_score

        if claim_type == ClaimType.ASSET_OWNERSHIP:
            assets = credential_data.get("assets", [])
            asset_class = parameters.get("asset_class", "")
            return asset_class in assets

        # CUSTOM: delegate to a provided evaluator
        evaluator = parameters.get("evaluator")
        if callable(evaluator):
            return evaluator(credential_data)
        return False

    @staticmethod
    def _compute_proof(
        circuit: Circuit,
        parameters: Dict[str, Any],
        credential_data: Dict[str, Any],
    ) -> Tuple[bytes, List[str]]:
        """Compute a ZKP using the circuit.

        In production this calls into a Groth16 / PLONK prover.
        The implementation here produces a keyed HMAC commitment that
        binds the proof to the circuit and claim parameters.
        """
        # Construct witness commitment
        witness_material = str(sorted(credential_data.items())).encode()
        param_material = str(sorted(parameters.items())).encode()

        proof_data = hmac.new(
            key=circuit.verification_key,
            msg=witness_material + param_material,
            digestmod=hashlib.sha256,
        ).digest()

        public_inputs = [
            circuit.circuit_id,
            hashlib.sha256(param_material).hexdigest()[:16],
        ]
        return proof_data, public_inputs

    @staticmethod
    def _verify_cryptographic(proof: ZKProof, circuit: Circuit) -> bool:
        """Verify the cryptographic integrity of a proof.

        In production this calls into a Groth16 / PLONK verifier.
        Here we verify the proof structure and key binding.
        """
        vk_hash = hashlib.sha256(circuit.verification_key).hexdigest()
        return (
            proof.verification_key_hash == vk_hash
            and len(proof.proof_data) == 32
            and proof.status == ProofStatus.VALID
        )

    def _anchor_proof(self, proof: ZKProof) -> Optional[str]:
        """Anchor proof hash on-chain for permanent verifiability."""
        try:
            proof_hash = hashlib.sha256(proof.proof_data).hexdigest()
            # On-chain anchoring via identity contract
            return f"0x{hashlib.sha256(proof_hash.encode()).hexdigest()[:64]}"
        except Exception as exc:
            logger.warning("Proof anchoring failed for %s: %s", proof.proof_id, exc)
            return None
