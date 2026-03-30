"""
Identity Assist
================

Helps users navigate identification processes on 0pnMatrx. Provides
guided workflows for credential acquisition, verification, and
management. Supports step-by-step onboarding for users unfamiliar
with self-sovereign identity concepts.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
DARDAN_TELEGRAM_ID: int = 7161847911


class WorkflowType(Enum):
    """Supported identity workflow types."""
    ONBOARDING = "onboarding"
    CREDENTIAL_IMPORT = "credential_import"
    CREDENTIAL_VERIFICATION = "credential_verification"
    KEY_SETUP = "key_setup"
    KEY_ROTATION = "key_rotation"
    DISCLOSURE_WALKTHROUGH = "disclosure_walkthrough"
    ZKP_TUTORIAL = "zkp_tutorial"
    RECOVERY = "recovery"


class StepStatus(Enum):
    """Status of a single workflow step."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    SKIPPED = "skipped"
    FAILED = "failed"
    NEEDS_USER_ACTION = "needs_user_action"


@dataclass
class WorkflowStep:
    """A single step in a guided identity workflow."""
    step_id: str
    title: str
    description: str
    instructions: List[str]
    status: StepStatus = StepStatus.PENDING
    requires_user_action: bool = False
    estimated_seconds: int = 60
    completed_at: Optional[float] = None
    error: Optional[str] = None
    result_data: Dict[str, Any] = field(default_factory=dict)


@dataclass
class IdentityWorkflow:
    """A guided identity workflow session."""
    workflow_id: str
    workflow_type: WorkflowType
    user_address: str
    steps: List[WorkflowStep] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    completed_at: Optional[float] = None
    current_step_index: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def is_complete(self) -> bool:
        return all(
            s.status in (StepStatus.COMPLETED, StepStatus.SKIPPED)
            for s in self.steps
        )

    @property
    def progress_percent(self) -> float:
        if not self.steps:
            return 0.0
        done = sum(
            1 for s in self.steps
            if s.status in (StepStatus.COMPLETED, StepStatus.SKIPPED)
        )
        return (done / len(self.steps)) * 100.0

    @property
    def current_step(self) -> Optional[WorkflowStep]:
        if 0 <= self.current_step_index < len(self.steps):
            return self.steps[self.current_step_index]
        return None


@dataclass
class AssistResponse:
    """Response from the identity assist system."""
    message: str
    next_action: Optional[str] = None
    workflow_id: Optional[str] = None
    step_id: Optional[str] = None
    suggestions: List[str] = field(default_factory=list)
    requires_user_input: bool = False


class IdentityAssist:
    """Guided identity process navigation.

    Provides step-by-step workflows for common identity tasks.
    Designed for users who may not be familiar with self-sovereign
    identity, zero-knowledge proofs, or credential management.

    Parameters
    ----------
    credential_vault : Any
        CredentialVault for credential operations.
    selective_disclosure : Any
        SelectiveDisclosure for sharing operations.
    zkp_engine : Any
        ZKPEngine for proof-related guidance.
    notification_service : Any, optional
        Service for sending Telegram notifications.
    """

    def __init__(
        self,
        credential_vault: Any,
        selective_disclosure: Any = None,
        zkp_engine: Any = None,
        notification_service: Any = None,
    ) -> None:
        self._vault = credential_vault
        self._disclosure = selective_disclosure
        self._zkp = zkp_engine
        self._notifications = notification_service
        self._workflows: Dict[str, IdentityWorkflow] = {}
        logger.info("IdentityAssist initialised")

    # ------------------------------------------------------------------
    # Workflow creation
    # ------------------------------------------------------------------

    def start_onboarding(self, user_address: str) -> IdentityWorkflow:
        """Start a new-user onboarding workflow.

        Guides the user through key generation, first credential
        import, and understanding selective disclosure.

        Args:
            user_address: The new user's wallet address.

        Returns:
            The created IdentityWorkflow.
        """
        steps = [
            WorkflowStep(
                step_id="welcome",
                title="Welcome to 0pnMatrx Identity",
                description="Introduction to self-sovereign identity on the platform.",
                instructions=[
                    "Your identity data is encrypted with YOUR keys.",
                    "The platform never sees your plaintext credentials.",
                    "You decide what to share, with whom, and for how long.",
                ],
                estimated_seconds=30,
            ),
            WorkflowStep(
                step_id="key_gen",
                title="Generate Your Encryption Keys",
                description="Create the cryptographic keys that protect your credentials.",
                instructions=[
                    "Generate a new encryption keypair on your device.",
                    "The private key stays on YOUR device -- we never see it.",
                    "Register your public key so others can send you encrypted data.",
                ],
                requires_user_action=True,
                estimated_seconds=120,
            ),
            WorkflowStep(
                step_id="first_credential",
                title="Import Your First Credential",
                description="Add an identity credential to your vault.",
                instructions=[
                    "Choose a credential type (e.g. government ID, passport).",
                    "Your credential is encrypted locally before upload.",
                    "A content hash is anchored on-chain for tamper detection.",
                ],
                requires_user_action=True,
                estimated_seconds=180,
            ),
            WorkflowStep(
                step_id="disclosure_intro",
                title="Understand Selective Disclosure",
                description="Learn how to share credentials safely.",
                instructions=[
                    "Choose who sees your data and for how long.",
                    "Disclosures auto-revoke when the time window closes.",
                    "You can manually revoke any disclosure at any time.",
                ],
                estimated_seconds=60,
            ),
            WorkflowStep(
                step_id="zkp_intro",
                title="Zero-Knowledge Proofs",
                description="Prove facts without revealing data.",
                instructions=[
                    "Prove 'I am over 21' without showing your birthdate.",
                    "Prove 'My income is above $50k' without exact figures.",
                    "Proofs are cryptographic -- they cannot be faked.",
                ],
                estimated_seconds=60,
            ),
            WorkflowStep(
                step_id="complete",
                title="Setup Complete",
                description="Your identity vault is ready to use.",
                instructions=[
                    "You can now store, share, and prove credentials.",
                    "All actions are recorded on-chain for your audit trail.",
                    "Visit the Identity dashboard to manage everything.",
                ],
                estimated_seconds=15,
            ),
        ]
        return self._create_workflow(
            WorkflowType.ONBOARDING, user_address, steps
        )

    def start_credential_import(
        self, user_address: str, credential_type: str
    ) -> IdentityWorkflow:
        """Start a guided credential import workflow.

        Args:
            user_address: The user's wallet address.
            credential_type: The type of credential being imported.

        Returns:
            The created IdentityWorkflow.
        """
        steps = [
            WorkflowStep(
                step_id="select_type",
                title=f"Importing: {credential_type}",
                description="Confirm the credential type and prepare your document.",
                instructions=[
                    f"You are importing a {credential_type} credential.",
                    "Have the original document ready for scanning or upload.",
                ],
                estimated_seconds=30,
            ),
            WorkflowStep(
                step_id="encrypt",
                title="Encrypt Credential",
                description="Your device encrypts the credential locally.",
                instructions=[
                    "Encryption happens entirely on your device.",
                    "Only the encrypted version is sent to the vault.",
                    "The platform cannot read your credential data.",
                ],
                requires_user_action=True,
                estimated_seconds=60,
            ),
            WorkflowStep(
                step_id="store",
                title="Store in Vault",
                description="Upload the encrypted credential to your vault.",
                instructions=[
                    "The encrypted credential is stored securely.",
                    "A content hash is anchored on-chain for integrity.",
                ],
                estimated_seconds=30,
            ),
            WorkflowStep(
                step_id="verify",
                title="Verify Storage",
                description="Confirm the credential was stored correctly.",
                instructions=[
                    "Retrieve the credential and verify the content hash.",
                    "Ensure the on-chain anchor matches.",
                ],
                estimated_seconds=15,
            ),
        ]
        return self._create_workflow(
            WorkflowType.CREDENTIAL_IMPORT, user_address, steps,
            metadata={"credential_type": credential_type},
        )

    def start_key_rotation(self, user_address: str) -> IdentityWorkflow:
        """Start a guided key rotation workflow.

        Args:
            user_address: The user's wallet address.

        Returns:
            The created IdentityWorkflow.
        """
        steps = [
            WorkflowStep(
                step_id="backup_current",
                title="Backup Current Credentials",
                description="Ensure all credentials are backed up before key rotation.",
                instructions=[
                    "Decrypt all credentials with your current key.",
                    "Keep the decrypted data temporarily in secure memory.",
                ],
                requires_user_action=True,
                estimated_seconds=120,
            ),
            WorkflowStep(
                step_id="generate_new_key",
                title="Generate New Encryption Key",
                description="Create a new keypair on your device.",
                instructions=[
                    "Generate a fresh encryption keypair.",
                    "Securely store the new private key.",
                ],
                requires_user_action=True,
                estimated_seconds=60,
            ),
            WorkflowStep(
                step_id="re_encrypt",
                title="Re-encrypt All Credentials",
                description="Encrypt all credentials with the new key.",
                instructions=[
                    "Each credential is re-encrypted with the new key.",
                    "New content hashes are computed and anchored on-chain.",
                ],
                requires_user_action=True,
                estimated_seconds=300,
            ),
            WorkflowStep(
                step_id="register_key",
                title="Register New Public Key",
                description="Update the platform with your new public key.",
                instructions=[
                    "Register the new public key on the platform.",
                    "Revoke the old public key.",
                ],
                estimated_seconds=30,
            ),
            WorkflowStep(
                step_id="verify_rotation",
                title="Verify Key Rotation",
                description="Confirm all credentials are accessible with the new key.",
                instructions=[
                    "Attempt to decrypt a credential with the new key.",
                    "Verify the on-chain anchors are updated.",
                ],
                requires_user_action=True,
                estimated_seconds=60,
            ),
        ]
        return self._create_workflow(
            WorkflowType.KEY_ROTATION, user_address, steps,
        )

    def start_recovery(self, user_address: str) -> IdentityWorkflow:
        """Start a guided account/key recovery workflow.

        Args:
            user_address: The user's wallet address.

        Returns:
            The created IdentityWorkflow.
        """
        steps = [
            WorkflowStep(
                step_id="verify_ownership",
                title="Verify Account Ownership",
                description="Confirm you own this wallet address.",
                instructions=[
                    "Sign a challenge message with your wallet.",
                    "This proves you control the private key.",
                ],
                requires_user_action=True,
                estimated_seconds=60,
            ),
            WorkflowStep(
                step_id="social_recovery",
                title="Social Recovery Check",
                description="Attempt recovery via trusted guardians.",
                instructions=[
                    "Contact your designated recovery guardians.",
                    "Collect threshold signatures for key recovery.",
                ],
                requires_user_action=True,
                estimated_seconds=600,
            ),
            WorkflowStep(
                step_id="new_key",
                title="Establish New Encryption Key",
                description="Generate a new encryption key for the recovered account.",
                instructions=[
                    "Generate a new keypair.",
                    "Re-encrypt credentials if backup data is available.",
                ],
                requires_user_action=True,
                estimated_seconds=180,
            ),
        ]
        return self._create_workflow(
            WorkflowType.RECOVERY, user_address, steps,
        )

    # ------------------------------------------------------------------
    # Workflow progression
    # ------------------------------------------------------------------

    def advance_step(
        self,
        workflow_id: str,
        result_data: Optional[Dict[str, Any]] = None,
    ) -> AssistResponse:
        """Complete the current step and advance to the next one.

        Args:
            workflow_id: The active workflow.
            result_data: Optional data produced by the completed step.

        Returns:
            AssistResponse with guidance for the next step.
        """
        workflow = self._workflows.get(workflow_id)
        if workflow is None:
            return AssistResponse(message="Workflow not found.")

        current = workflow.current_step
        if current is None:
            return AssistResponse(message="Workflow already complete.")

        # Mark current step completed
        current.status = StepStatus.COMPLETED
        current.completed_at = time.time()
        if result_data:
            current.result_data = result_data

        # Advance index
        workflow.current_step_index += 1
        next_step = workflow.current_step

        if next_step is None:
            workflow.completed_at = time.time()
            logger.info("Workflow %s completed", workflow_id)
            return AssistResponse(
                message="Workflow complete! All steps have been finished.",
                workflow_id=workflow_id,
            )

        next_step.status = StepStatus.IN_PROGRESS

        return AssistResponse(
            message=f"Step: {next_step.title}\n{next_step.description}",
            next_action=next_step.instructions[0] if next_step.instructions else None,
            workflow_id=workflow_id,
            step_id=next_step.step_id,
            suggestions=next_step.instructions,
            requires_user_input=next_step.requires_user_action,
        )

    def skip_step(self, workflow_id: str) -> AssistResponse:
        """Skip the current step and move to the next one."""
        workflow = self._workflows.get(workflow_id)
        if workflow is None:
            return AssistResponse(message="Workflow not found.")

        current = workflow.current_step
        if current is None:
            return AssistResponse(message="Workflow already complete.")

        current.status = StepStatus.SKIPPED
        workflow.current_step_index += 1
        return self.advance_step(workflow_id)

    def get_workflow_status(self, workflow_id: str) -> Optional[IdentityWorkflow]:
        """Retrieve the current state of a workflow."""
        return self._workflows.get(workflow_id)

    def list_active_workflows(self, user_address: str) -> List[IdentityWorkflow]:
        """List all active workflows for a user."""
        return [
            wf for wf in self._workflows.values()
            if wf.user_address == user_address and not wf.is_complete
        ]

    def get_help(self, topic: str) -> AssistResponse:
        """Get contextual help on an identity topic.

        Args:
            topic: The topic to get help on.

        Returns:
            AssistResponse with guidance.
        """
        help_topics: Dict[str, AssistResponse] = {
            "encryption": AssistResponse(
                message="Your credentials are encrypted with your personal key. "
                "The platform stores only ciphertext.",
                suggestions=[
                    "Generate keys with 'Key Setup' workflow.",
                    "Rotate keys periodically for security.",
                ],
            ),
            "disclosure": AssistResponse(
                message="Selective disclosure lets you share specific credentials "
                "with specific parties for limited time windows.",
                suggestions=[
                    "Set a short time window for sensitive data.",
                    "Use ZKP if you only need to prove a fact.",
                    "You can revoke any disclosure instantly.",
                ],
            ),
            "zkp": AssistResponse(
                message="Zero-knowledge proofs let you prove facts about your "
                "data without revealing the data itself.",
                suggestions=[
                    "Use 'age_over' to prove you meet an age requirement.",
                    "Use 'income_above' for financial thresholds.",
                    "Proofs expire automatically for safety.",
                ],
            ),
            "recovery": AssistResponse(
                message="If you lose your encryption key, social recovery allows "
                "trusted guardians to help restore access.",
                suggestions=[
                    "Set up recovery guardians proactively.",
                    "Store key backups in a hardware wallet.",
                ],
            ),
        }
        response = help_topics.get(topic.lower())
        if response:
            return response
        return AssistResponse(
            message=f"No specific help available for '{topic}'.",
            suggestions=list(help_topics.keys()),
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _create_workflow(
        self,
        workflow_type: WorkflowType,
        user_address: str,
        steps: List[WorkflowStep],
        metadata: Optional[Dict[str, Any]] = None,
    ) -> IdentityWorkflow:
        workflow_id = f"wf-{uuid.uuid4().hex[:12]}"
        workflow = IdentityWorkflow(
            workflow_id=workflow_id,
            workflow_type=workflow_type,
            user_address=user_address,
            steps=steps,
            metadata=metadata or {},
        )
        if steps:
            steps[0].status = StepStatus.IN_PROGRESS
        self._workflows[workflow_id] = workflow
        logger.info(
            "Workflow %s (%s) created for %s with %d steps",
            workflow_id, workflow_type.value, user_address, len(steps),
        )
        return workflow
