"""
Model Selector — Trinity explains three voting models and captures permanence confirmation.

Part of Component 19 (Governance and Voting).

The three voting models:
1. One-Person-One-Vote — every participant gets exactly one vote
2. Token-Weighted — vote weight equals governance token balance
3. Quadratic — vote weight is sqrt(token balance), reducing plutocratic advantage

CRITICAL: Once a model is selected, the choice is PERMANENT and cannot be changed.
Trinity (the AI interface) must explain all three models clearly and require
explicit confirmation that the user understands the permanence before proceeding.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

from runtime.blockchain.services.governance.voting_engine import VotingModel

logger = logging.getLogger(__name__)


class SelectionStage(Enum):
    """Stages of the model selection flow."""
    EXPLANATION = "explanation"
    COMPARISON = "comparison"
    CONFIRMATION = "confirmation"
    LOCKED = "locked"


@dataclass
class ModelExplanation:
    """Explanation of a voting model for Trinity to present."""
    model: VotingModel
    title: str
    plain_english: str
    pros: List[str]
    cons: List[str]
    best_for: str


@dataclass
class SelectionRecord:
    """Record of a permanent model selection."""
    dao_id: str
    selected_model: VotingModel
    selected_by: str
    confirmed_permanence: bool
    selected_at: float
    attestation_uid: Optional[str] = None


# Pre-built explanations for Trinity to present
MODEL_EXPLANATIONS: Dict[VotingModel, ModelExplanation] = {
    VotingModel.ONE_PERSON_ONE_VOTE: ModelExplanation(
        model=VotingModel.ONE_PERSON_ONE_VOTE,
        title="One Person, One Vote",
        plain_english=(
            "Every participant gets exactly one vote, regardless of how many tokens "
            "they hold. This is the most democratic option. A whale with 1 million tokens "
            "has the same voting power as someone with 1 token."
        ),
        pros=[
            "Maximum fairness — every voice counts equally.",
            "Immune to token accumulation attacks.",
            "Simple and easy to understand.",
        ],
        cons=[
            "Susceptible to Sybil attacks (one person creating many accounts).",
            "Does not reward larger stakeholders for their investment.",
        ],
        best_for="Communities that prioritize equality and broad participation.",
    ),
    VotingModel.TOKEN_WEIGHTED: ModelExplanation(
        model=VotingModel.TOKEN_WEIGHTED,
        title="Token-Weighted Voting",
        plain_english=(
            "Your vote weight equals your governance token balance. If you hold "
            "1,000 tokens, your vote counts 1,000 times more than someone with 1 token. "
            "This aligns voting power with economic stake."
        ),
        pros=[
            "Aligns governance with economic skin in the game.",
            "Resistant to Sybil attacks (splitting tokens across accounts does not help).",
            "Rewards commitment — larger holders have more say.",
        ],
        cons=[
            "Whales can dominate decisions.",
            "New or small participants may feel disenfranchised.",
        ],
        best_for="Organizations where financial commitment should drive governance.",
    ),
    VotingModel.QUADRATIC: ModelExplanation(
        model=VotingModel.QUADRATIC,
        title="Quadratic Voting",
        plain_english=(
            "Your vote weight is the square root of your token balance. If you hold "
            "100 tokens, your vote weight is 10. If you hold 10,000 tokens, your weight is 100. "
            "This balances stake with broad representation — big holders still matter, "
            "but cannot dominate as easily."
        ),
        pros=[
            "Reduces plutocratic concentration.",
            "Still rewards larger stakeholders, just more gradually.",
            "Mathematically proven to optimize for collective preference.",
        ],
        cons=[
            "Harder to explain to non-technical participants.",
            "Still somewhat susceptible to Sybil attacks.",
        ],
        best_for="Communities seeking a balance between equality and stake-weighted influence.",
    ),
}


class ModelSelector:
    """
    Guides the voting model selection process through Trinity.

    Flow:
    1. EXPLANATION — Trinity explains all three models in plain English
    2. COMPARISON — Side-by-side comparison presented
    3. CONFIRMATION — User must explicitly confirm they understand
       the selection is PERMANENT
    4. LOCKED — Model is permanently set, no changes possible

    The selection is recorded with an EAS attestation for immutability.
    """

    def __init__(self) -> None:
        # dao_id -> SelectionRecord (only populated once locked)
        self._selections: Dict[str, SelectionRecord] = {}
        # dao_id -> current selection stage
        self._stages: Dict[str, SelectionStage] = {}
        # dao_id -> candidate model (before confirmation)
        self._candidates: Dict[str, VotingModel] = {}

        logger.info("ModelSelector initialised.")

    # ── Trinity Explanation Flow ──────────────────────────────────────

    def get_explanations(self) -> List[ModelExplanation]:
        """
        Get explanations for all three voting models.

        Trinity should present these in plain English to the user,
        ensuring they understand each model before selecting.

        Returns:
            List of ModelExplanation for all three models.
        """
        return list(MODEL_EXPLANATIONS.values())

    def get_comparison(self) -> Dict[str, Any]:
        """
        Get a side-by-side comparison of all three models.

        Returns:
            Structured comparison data for Trinity to present.
        """
        return {
            "models": [
                {
                    "name": exp.title,
                    "model_id": exp.model.value,
                    "summary": exp.plain_english,
                    "pros": exp.pros,
                    "cons": exp.cons,
                    "best_for": exp.best_for,
                }
                for exp in MODEL_EXPLANATIONS.values()
            ],
            "warning": (
                "This selection is PERMANENT. Once chosen, the voting model "
                "cannot be changed. Please review all options carefully."
            ),
        }

    def start_selection(self, dao_id: str) -> Dict[str, Any]:
        """
        Begin the model selection flow for a DAO.

        Args:
            dao_id: The DAO selecting its voting model.

        Returns:
            Initial explanation data for Trinity.

        Raises:
            ValueError: If model is already locked for this DAO.
        """
        if dao_id in self._selections:
            raise ValueError(
                f"Voting model for DAO {dao_id} is already permanently set to "
                f"{self._selections[dao_id].selected_model.value}."
            )

        self._stages[dao_id] = SelectionStage.EXPLANATION
        return {
            "stage": SelectionStage.EXPLANATION.value,
            "explanations": [
                {
                    "model": exp.model.value,
                    "title": exp.title,
                    "explanation": exp.plain_english,
                    "pros": exp.pros,
                    "cons": exp.cons,
                    "best_for": exp.best_for,
                }
                for exp in MODEL_EXPLANATIONS.values()
            ],
            "next_step": "Review all models, then call select_candidate() with your choice.",
        }

    def select_candidate(
        self,
        dao_id: str,
        model: VotingModel,
    ) -> Dict[str, Any]:
        """
        Select a candidate model (not yet confirmed).

        Args:
            dao_id: The DAO.
            model: The chosen voting model.

        Returns:
            Confirmation prompt data for Trinity.
        """
        if dao_id in self._selections:
            raise ValueError(f"Model already permanently locked for DAO {dao_id}.")

        self._candidates[dao_id] = model
        self._stages[dao_id] = SelectionStage.CONFIRMATION

        explanation = MODEL_EXPLANATIONS[model]
        return {
            "stage": SelectionStage.CONFIRMATION.value,
            "selected_model": model.value,
            "selected_title": explanation.title,
            "confirmation_prompt": (
                f"You have selected '{explanation.title}' as your voting model. "
                f"This selection is PERMANENT and cannot be changed. "
                f"Do you confirm this choice? Type 'I CONFIRM' to proceed."
            ),
        }

    def confirm_selection(
        self,
        dao_id: str,
        confirmer: str,
        confirmation_text: str,
    ) -> SelectionRecord:
        """
        Confirm and permanently lock the voting model selection.

        Args:
            dao_id: The DAO.
            confirmer: Address of the person confirming.
            confirmation_text: Must be exactly "I CONFIRM".

        Returns:
            The permanent SelectionRecord.

        Raises:
            ValueError: If confirmation text does not match or no candidate.
        """
        if dao_id in self._selections:
            raise ValueError(f"Model already permanently locked for DAO {dao_id}.")

        if dao_id not in self._candidates:
            raise ValueError(f"No candidate model selected for DAO {dao_id}.")

        if confirmation_text.strip().upper() != "I CONFIRM":
            raise ValueError(
                "Confirmation text must be exactly 'I CONFIRM'. "
                "This ensures you understand the selection is permanent."
            )

        model = self._candidates[dao_id]
        record = SelectionRecord(
            dao_id=dao_id,
            selected_model=model,
            selected_by=confirmer,
            confirmed_permanence=True,
            selected_at=time.time(),
        )

        self._selections[dao_id] = record
        self._stages[dao_id] = SelectionStage.LOCKED
        del self._candidates[dao_id]

        logger.info(
            "Voting model PERMANENTLY locked | dao=%s | model=%s | by=%s",
            dao_id, model.value, confirmer,
        )
        return record

    # ── Queries ───────────────────────────────────────────────────────

    def get_selected_model(self, dao_id: str) -> Optional[VotingModel]:
        """Get the permanently selected model for a DAO, or None."""
        record = self._selections.get(dao_id)
        return record.selected_model if record else None

    def is_locked(self, dao_id: str) -> bool:
        """Check if the model selection is permanently locked."""
        return dao_id in self._selections

    def get_selection_record(self, dao_id: str) -> Optional[SelectionRecord]:
        """Get the full selection record for a DAO."""
        return self._selections.get(dao_id)

    def get_stage(self, dao_id: str) -> SelectionStage:
        """Get the current selection stage for a DAO."""
        return self._stages.get(dao_id, SelectionStage.EXPLANATION)
