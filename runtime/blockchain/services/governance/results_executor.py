"""
Results Executor — executes the outcomes of governance votes.

Part of Component 19 (Governance and Voting).
Creates EAS attestations for every executed result.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


class ExecutionStatus(Enum):
    """Status of a vote result execution."""
    PENDING = "pending"
    EXECUTING = "executing"
    COMPLETED = "completed"
    FAILED = "failed"
    VETOED = "vetoed"


@dataclass
class ExecutionRecord:
    """Record of an executed governance result."""
    execution_id: str
    proposal_id: str
    passed: bool
    execution_status: ExecutionStatus
    actions_taken: List[str] = field(default_factory=list)
    executed_at: Optional[float] = None
    executed_by: str = ""
    eas_attestation_uid: Optional[str] = None
    error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class ResultsExecutor:
    """
    Executes governance vote results and records EAS attestations.

    When a proposal passes:
    1. Validates the vote result
    2. Executes registered actions (on-chain calls, parameter changes, etc.)
    3. Creates an EAS attestation recording the result permanently
    4. Updates execution status

    When a proposal fails:
    1. Records the failure with attestation
    2. No actions are executed
    """

    def __init__(
        self,
        eas_attestor: Optional[Any] = None,
        action_registry: Optional[Dict[str, Callable]] = None,
    ) -> None:
        """
        Args:
            eas_attestor: EAS attestation service for recording results.
            action_registry: Mapping of action_type -> callable for execution.
        """
        self._eas = eas_attestor
        self._actions = action_registry or {}
        self._executions: Dict[str, ExecutionRecord] = {}
        self._counter: int = 0
        logger.info("ResultsExecutor initialised.")

    def execute_result(
        self,
        proposal_id: str,
        vote_result: Dict[str, Any],
        executor_address: str,
        actions: Optional[List[Dict[str, Any]]] = None,
    ) -> ExecutionRecord:
        """
        Execute the result of a governance vote.

        Args:
            proposal_id: The proposal whose result is being executed.
            vote_result: Dict from VotingEngine.get_result().
            executor_address: Address of the account executing.
            actions: List of actions to execute if proposal passed.

        Returns:
            ExecutionRecord with outcome details.
        """
        self._counter += 1
        exec_id = f"EXEC-{self._counter:08d}"
        passed = vote_result.get("passed", False)

        record = ExecutionRecord(
            execution_id=exec_id,
            proposal_id=proposal_id,
            passed=passed,
            execution_status=ExecutionStatus.PENDING,
            executed_by=executor_address,
        )

        if not passed:
            record.execution_status = ExecutionStatus.COMPLETED
            record.executed_at = time.time()
            record.actions_taken.append("Proposal did not pass — no actions taken.")
            self._create_attestation(record, vote_result)
            self._executions[exec_id] = record
            logger.info("Proposal %s did not pass — result recorded.", proposal_id)
            return record

        # Execute actions for passed proposals
        record.execution_status = ExecutionStatus.EXECUTING
        try:
            for action in (actions or []):
                action_type = action.get("type", "unknown")
                action_params = action.get("params", {})

                handler = self._actions.get(action_type)
                if handler is not None:
                    handler(**action_params)
                    record.actions_taken.append(f"Executed: {action_type}")
                else:
                    record.actions_taken.append(f"Skipped (no handler): {action_type}")
                    logger.warning("No handler for action type: %s", action_type)

            record.execution_status = ExecutionStatus.COMPLETED
            record.executed_at = time.time()

        except Exception as exc:
            record.execution_status = ExecutionStatus.FAILED
            record.error = str(exc)
            logger.exception("Execution failed for proposal %s.", proposal_id)

        self._create_attestation(record, vote_result)
        self._executions[exec_id] = record

        logger.info(
            "Execution %s | proposal=%s | passed=%s | status=%s | actions=%d",
            exec_id, proposal_id, passed, record.execution_status.value,
            len(record.actions_taken),
        )
        return record

    def register_action_handler(
        self, action_type: str, handler: Callable,
    ) -> None:
        """Register a handler for an action type."""
        self._actions[action_type] = handler
        logger.info("Action handler registered: %s", action_type)

    def get_execution(self, execution_id: str) -> Optional[ExecutionRecord]:
        """Get an execution record by ID."""
        return self._executions.get(execution_id)

    def get_executions_for_proposal(self, proposal_id: str) -> List[ExecutionRecord]:
        """Get all execution records for a proposal."""
        return [e for e in self._executions.values() if e.proposal_id == proposal_id]

    def _create_attestation(
        self, record: ExecutionRecord, vote_result: Dict[str, Any],
    ) -> None:
        """Create an EAS attestation for the execution."""
        if self._eas is None:
            return
        try:
            uid = self._eas.attest(
                schema="governance_result",
                data={
                    "proposal_id": record.proposal_id,
                    "passed": record.passed,
                    "votes_for": vote_result.get("votes_for", 0),
                    "votes_against": vote_result.get("votes_against", 0),
                    "execution_status": record.execution_status.value,
                    "actions": record.actions_taken,
                },
            )
            record.eas_attestation_uid = uid
        except Exception:
            logger.exception("EAS attestation failed for execution %s.", record.execution_id)
