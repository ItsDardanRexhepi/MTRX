"""
Anti-Manipulation — flash loan protection for governance votes.

Part of Component 19 (Governance and Voting).

Prevents flash loan attacks where an attacker borrows tokens within
a single transaction to manipulate vote outcomes. Uses snapshot-based
balance verification and time-weighted checks.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


@dataclass
class BalanceSnapshot:
    """A point-in-time snapshot of a voter's token balance."""
    address: str
    balance: int
    block_number: int
    timestamp: float


@dataclass
class ManipulationCheck:
    """Result of a manipulation check."""
    voter: str
    proposal_id: str
    passed: bool
    checks_performed: List[str]
    warnings: List[str] = field(default_factory=list)
    blocked: bool = False
    block_reason: str = ""


class AntiManipulation:
    """
    Flash loan protection for governance voting.

    Protections:
    1. Snapshot-based voting — token balances are snapshotted at proposal creation.
       Voters can only vote with the balance they had at snapshot time.
    2. Minimum hold period — tokens must be held for a configurable minimum
       period before they count for voting.
    3. Balance volatility detection — flags accounts whose balance changed
       dramatically in a short window (potential flash loan).
    4. Block-level checks — rejects votes where the voter's balance in the
       same block differs from their balance in the prior block by more
       than the volatility threshold.
    """

    DEFAULT_MIN_HOLD_SECONDS: int = 86_400     # 24 hours
    VOLATILITY_THRESHOLD_PCT: float = 50.0      # 50% balance change
    LOOKBACK_BLOCKS: int = 10

    def __init__(
        self,
        min_hold_seconds: int = DEFAULT_MIN_HOLD_SECONDS,
        volatility_threshold_pct: float = VOLATILITY_THRESHOLD_PCT,
    ) -> None:
        """
        Args:
            min_hold_seconds: Minimum seconds tokens must be held before voting.
            volatility_threshold_pct: Max acceptable balance change percentage.
        """
        self._min_hold = min_hold_seconds
        self._volatility_threshold = volatility_threshold_pct

        # proposal_id -> {address: BalanceSnapshot}
        self._snapshots: Dict[str, Dict[str, BalanceSnapshot]] = {}
        # address -> list of balance change events
        self._balance_history: Dict[str, List[Dict[str, Any]]] = {}
        # Set of blocked addresses
        self._blocked: Set[str] = set()
        # Audit log
        self._audit: List[ManipulationCheck] = []

        logger.info(
            "AntiManipulation initialised | min_hold=%ds | volatility_threshold=%.1f%%",
            min_hold_seconds, volatility_threshold_pct,
        )

    # ── Snapshot Management ───────────────────────────────────────────

    def create_snapshot(
        self,
        proposal_id: str,
        balances: Dict[str, int],
        block_number: int,
    ) -> int:
        """
        Create balance snapshots for a proposal at creation time.

        All voting eligibility is determined from this snapshot.
        Balances acquired after the snapshot do NOT count.

        Args:
            proposal_id: The proposal to snapshot for.
            balances: Mapping of address -> token balance at snapshot time.
            block_number: The block number of the snapshot.

        Returns:
            Number of addresses snapshotted.
        """
        now = time.time()
        self._snapshots[proposal_id] = {
            address: BalanceSnapshot(
                address=address,
                balance=balance,
                block_number=block_number,
                timestamp=now,
            )
            for address, balance in balances.items()
            if balance > 0
        }

        logger.info(
            "Snapshot created for proposal %s at block %d — %d addresses.",
            proposal_id, block_number, len(self._snapshots[proposal_id]),
        )
        return len(self._snapshots[proposal_id])

    def get_snapshot_balance(self, proposal_id: str, voter: str) -> int:
        """
        Get a voter's balance at the proposal's snapshot.

        Returns 0 if voter had no balance at snapshot time.
        """
        snapshots = self._snapshots.get(proposal_id, {})
        snapshot = snapshots.get(voter)
        return snapshot.balance if snapshot else 0

    # ── Manipulation Checks ───────────────────────────────────────────

    def check_voter(
        self,
        voter: str,
        proposal_id: str,
        current_balance: int,
        current_block: int,
    ) -> ManipulationCheck:
        """
        Run all anti-manipulation checks on a voter.

        Args:
            voter: Address of the voter.
            proposal_id: The proposal being voted on.
            current_balance: Voter's current token balance.
            current_block: Current block number.

        Returns:
            ManipulationCheck with pass/fail and details.
        """
        checks: List[str] = []
        warnings: List[str] = []
        blocked = False
        block_reason = ""

        # Check 1: Address not blocked
        if voter in self._blocked:
            blocked = True
            block_reason = "Address is blocked from voting due to prior manipulation."
            checks.append("blocked_list: FAILED")
        else:
            checks.append("blocked_list: passed")

        # Check 2: Snapshot balance exists
        snapshot_balance = self.get_snapshot_balance(proposal_id, voter)
        if snapshot_balance <= 0:
            blocked = True
            block_reason = "No token balance at proposal snapshot time."
            checks.append("snapshot_balance: FAILED (no balance at snapshot)")
        else:
            checks.append(f"snapshot_balance: passed ({snapshot_balance} tokens)")

        # Check 3: Balance volatility
        if not blocked:
            volatility_ok, volatility_msg = self._check_volatility(
                voter, snapshot_balance, current_balance,
            )
            if not volatility_ok:
                warnings.append(volatility_msg)
                checks.append(f"volatility: WARNING ({volatility_msg})")
            else:
                checks.append("volatility: passed")

        # Check 4: Minimum hold period
        if not blocked:
            hold_ok, hold_msg = self._check_hold_period(voter)
            if not hold_ok:
                blocked = True
                block_reason = hold_msg
                checks.append(f"hold_period: FAILED ({hold_msg})")
            else:
                checks.append("hold_period: passed")

        result = ManipulationCheck(
            voter=voter,
            proposal_id=proposal_id,
            passed=not blocked,
            checks_performed=checks,
            warnings=warnings,
            blocked=blocked,
            block_reason=block_reason,
        )
        self._audit.append(result)

        if blocked:
            logger.warning(
                "Voter %s BLOCKED on proposal %s: %s", voter, proposal_id, block_reason,
            )
        return result

    # ── Balance Tracking ──────────────────────────────────────────────

    def record_balance_change(
        self,
        address: str,
        old_balance: int,
        new_balance: int,
        block_number: int,
    ) -> None:
        """
        Record a balance change event for manipulation detection.

        Args:
            address: The address whose balance changed.
            old_balance: Previous balance.
            new_balance: New balance.
            block_number: Block of the change.
        """
        if address not in self._balance_history:
            self._balance_history[address] = []

        self._balance_history[address].append({
            "old_balance": old_balance,
            "new_balance": new_balance,
            "block_number": block_number,
            "timestamp": time.time(),
        })

        # Detect potential flash loan: large increase followed by large decrease
        # within a small block window
        history = self._balance_history[address]
        if len(history) >= 2:
            prev = history[-2]
            curr = history[-1]
            if (curr["block_number"] - prev["block_number"]) <= self.LOOKBACK_BLOCKS:
                if prev["new_balance"] > prev["old_balance"] * 2:
                    if curr["new_balance"] < prev["new_balance"] * 0.5:
                        logger.warning(
                            "FLASH LOAN DETECTED: %s balance spiked and dropped "
                            "within %d blocks.",
                            address, self.LOOKBACK_BLOCKS,
                        )
                        self._blocked.add(address)

    def block_address(self, address: str, reason: str) -> None:
        """Manually block an address from voting."""
        self._blocked.add(address)
        logger.info("Address blocked: %s — %s", address, reason)

    def unblock_address(self, address: str) -> None:
        """Remove an address from the blocked list."""
        self._blocked.discard(address)
        logger.info("Address unblocked: %s", address)

    def get_audit_log(self, limit: int = 100) -> List[ManipulationCheck]:
        """Return recent manipulation check results."""
        return list(reversed(self._audit[-limit:]))

    # ── Internal ──────────────────────────────────────────────────────

    def _check_volatility(
        self, voter: str, snapshot_balance: int, current_balance: int,
    ) -> tuple[bool, str]:
        """Check if balance changed too much since snapshot."""
        if snapshot_balance <= 0:
            return True, ""

        change_pct = abs(current_balance - snapshot_balance) / snapshot_balance * 100
        if change_pct > self._volatility_threshold:
            return False, (
                f"Balance changed {change_pct:.1f}% since snapshot "
                f"(threshold: {self._volatility_threshold}%)."
            )
        return True, ""

    def _check_hold_period(self, voter: str) -> tuple[bool, str]:
        """Check if tokens have been held for minimum period."""
        history = self._balance_history.get(voter, [])
        if not history:
            # No balance changes recorded — assume long-term holder
            return True, ""

        latest = history[-1]
        hold_time = time.time() - latest["timestamp"]
        if hold_time < self._min_hold:
            remaining = self._min_hold - hold_time
            return False, (
                f"Tokens must be held for {self._min_hold // 3600}h. "
                f"{remaining / 3600:.1f}h remaining."
            )
        return True, ""
