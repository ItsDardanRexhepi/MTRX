"""
EAS Attestation Integration for Matrix-to-0pnMatrx Bridge.

Handles on-chain attestations for bridge exports and deployments using
the Ethereum Attestation Service (EAS) on Base mainnet. All bridge
attestations are time-critical and issued immediately (never batched).
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# ── EAS Configuration ──────────────────────────────────────────────────────────
EAS_SCHEMA_UID: int = 348
EAS_BASE_MAINNET_CONTRACT: str = "0xA1207F3BBa224E2c9c3c6D5aF63D816e64D54892"
EAS_BASE_MAINNET_RPC: str = "https://mainnet.base.org"
EAS_GRAPHQL_ENDPOINT: str = "https://base.easscan.org/graphql"

BRIDGE_ATTESTATION_NOTE: str = "bridge-validated and Dardan-approved"


@dataclass
class AttestationRecord:
    """Record of a single EAS attestation."""
    uid: Optional[str] = None
    schema_id: int = EAS_SCHEMA_UID
    component_name: str = ""
    attestation_type: str = ""  # "export" | "deployment"
    attester: str = NEOSAFE_ADDRESS
    note: str = BRIDGE_ATTESTATION_NOTE
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    tx_hash: Optional[str] = None
    success: bool = False
    error: Optional[str] = None


class EASBridgeAttestor:
    """
    Issues EAS attestations for bridge export and deployment events.

    All attestations use Schema 348 on Base mainnet and are time-critical
    (immediate, not batched).
    """

    def __init__(
        self,
        rpc_url: str = EAS_BASE_MAINNET_RPC,
        contract_address: str = EAS_BASE_MAINNET_CONTRACT,
        attester_address: str = NEOSAFE_ADDRESS,
        private_key: Optional[str] = None,
    ) -> None:
        """
        Args:
            rpc_url: Base mainnet RPC endpoint.
            contract_address: EAS contract address on Base.
            attester_address: The NeoSafe address used as attester.
            private_key: Private key for signing attestation transactions.
                         Inject via environment or secrets manager.
        """
        self.rpc_url = rpc_url
        self.contract_address = contract_address
        self.attester_address = attester_address
        self._private_key = private_key  # CREDENTIAL INJECTION POINT
        self._attestation_log: list[AttestationRecord] = []

    # ── Public API ─────────────────────────────────────────────────────────

    def attest_export(
        self, component_name: str, result: Any
    ) -> AttestationRecord:
        """
        Attest a successful bridge export on-chain.

        Args:
            component_name: The exported component name.
            result: The SanitizationResult from the sanitizer.

        Returns:
            AttestationRecord with transaction details.
        """
        record = AttestationRecord(
            component_name=component_name,
            attestation_type="export",
        )

        attestation_data = self._encode_attestation_data(
            component_name=component_name,
            event_type="export",
            sanitizer_clean=result.is_clean if hasattr(result, "is_clean") else True,
            files_scanned=result.scanned_files_count if hasattr(result, "scanned_files_count") else 0,
        )

        try:
            tx_hash = self._submit_attestation(attestation_data)
            record.tx_hash = tx_hash
            record.success = True
            record.uid = self._derive_uid(tx_hash)
            logger.info(
                "Export attestation submitted for '%s': tx=%s uid=%s",
                component_name,
                tx_hash,
                record.uid,
            )
        except Exception as exc:
            record.success = False
            record.error = str(exc)
            logger.exception("Failed to attest export for '%s'", component_name)

        self._attestation_log.append(record)
        return record

    def attest_deployment(self, component_name: str) -> AttestationRecord:
        """
        Attest a successful 0pnMatrx deployment on-chain.

        The attestation note reads: "bridge-validated and Dardan-approved"

        Args:
            component_name: The deployed component name.

        Returns:
            AttestationRecord with transaction details.
        """
        record = AttestationRecord(
            component_name=component_name,
            attestation_type="deployment",
            note=BRIDGE_ATTESTATION_NOTE,
        )

        attestation_data = self._encode_attestation_data(
            component_name=component_name,
            event_type="deployment",
            note=BRIDGE_ATTESTATION_NOTE,
        )

        try:
            tx_hash = self._submit_attestation(attestation_data)
            record.tx_hash = tx_hash
            record.success = True
            record.uid = self._derive_uid(tx_hash)
            logger.info(
                "Deployment attestation submitted for '%s': tx=%s uid=%s",
                component_name,
                tx_hash,
                record.uid,
            )
        except Exception as exc:
            record.success = False
            record.error = str(exc)
            logger.exception("Failed to attest deployment for '%s'", component_name)

        self._attestation_log.append(record)
        return record

    def verify_attestation(self, uid: str) -> Dict[str, Any]:
        """
        Verify an attestation exists on-chain via EAS GraphQL.

        Args:
            uid: The attestation UID to verify.

        Returns:
            Dict with attestation details or error information.
        """
        import requests

        query = """
        query GetAttestation($uid: String!) {
            attestation(where: { id: $uid }) {
                id
                attester
                recipient
                revoked
                schemaId
                time
                data
            }
        }
        """

        try:
            resp = requests.post(
                EAS_GRAPHQL_ENDPOINT,
                json={"query": query, "variables": {"uid": uid}},
                timeout=15,
            )
            resp.raise_for_status()
            data = resp.json()

            attestation = data.get("data", {}).get("attestation")
            if attestation:
                logger.info("Attestation %s verified on-chain", uid)
                return {
                    "verified": True,
                    "uid": attestation["id"],
                    "attester": attestation["attester"],
                    "revoked": attestation["revoked"],
                    "schema_id": attestation["schemaId"],
                    "timestamp": attestation["time"],
                }
            else:
                logger.warning("Attestation %s not found on-chain", uid)
                return {"verified": False, "uid": uid, "error": "Not found"}

        except requests.RequestException as exc:
            logger.exception("Failed to verify attestation %s", uid)
            return {"verified": False, "uid": uid, "error": str(exc)}

    # ── Internal helpers ───────────────────────────────────────────────────

    def _encode_attestation_data(self, **kwargs) -> bytes:
        """
        ABI-encode attestation data for on-chain submission.

        In production, this uses eth_abi or web3.py for proper encoding.
        """
        import json
        payload = {
            "schema_uid": EAS_SCHEMA_UID,
            "attester": self.attester_address,
            "data": kwargs,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        return json.dumps(payload).encode("utf-8")

    def _submit_attestation(self, data: bytes) -> str:
        """
        Submit the attestation transaction to Base mainnet.

        In production, this signs and sends via web3.py using the
        injected private key.
        """
        if not self._private_key:
            raise RuntimeError(
                "EAS attestation private key not configured. "
                "Inject via constructor or environment variable."
            )

        # Production implementation would use:
        # from web3 import Web3
        # w3 = Web3(Web3.HTTPProvider(self.rpc_url))
        # contract = w3.eth.contract(address=self.contract_address, abi=EAS_ABI)
        # tx = contract.functions.attest(...).build_transaction(...)
        # signed = w3.eth.account.sign_transaction(tx, self._private_key)
        # tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
        # return tx_hash.hex()

        raise NotImplementedError(
            "EAS on-chain submission requires web3.py integration. "
            "Configure private key and uncomment production code."
        )

    @staticmethod
    def _derive_uid(tx_hash: str) -> str:
        """Derive attestation UID from transaction hash (placeholder)."""
        import hashlib
        return "0x" + hashlib.sha256(tx_hash.encode()).hexdigest()[:64]
