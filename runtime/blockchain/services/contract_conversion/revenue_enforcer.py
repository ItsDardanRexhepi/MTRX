"""
Revenue Enforcer — Real-Time Revenue Monitoring & NeoSafe Routing
=================================================================

Monitors all active contracts deployed through Component 1, applies the
correct tier-based revenue share **plus** the perpetual 2.5 % Platform
Access Contribution (PAC), and routes the combined amount to the NeoSafe
multi-sig wallet.

Revenue-share schedule:
    Tier 1  (<2 ETH rolling 12-month)  -> 10 %  + 2.5 % PAC
    Tier 2  (2-5 ETH)                  ->  5 %  + 2.5 % PAC
    Tier 3  (>5 ETH)                   ->  2.5 % + 2.5 % PAC
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from decimal import Decimal, ROUND_DOWN
from enum import IntEnum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Basis-point constants (1 bp = 0.01 %).
TIER1_SHARE_BPS = 1000   # 10 %
TIER2_SHARE_BPS = 500    #  5 %
TIER3_SHARE_BPS = 250    #  2.5 %
PAC_BPS = 250            #  2.5 %
BPS_DENOMINATOR = 10_000


class Tier(IntEnum):
    """Matches the on-chain Tier enum."""
    TIER_1 = 0
    TIER_2 = 1
    TIER_3 = 2


# Map each tier to its share in basis points.
_TIER_BPS: Dict[Tier, int] = {
    Tier.TIER_1: TIER1_SHARE_BPS,
    Tier.TIER_2: TIER2_SHARE_BPS,
    Tier.TIER_3: TIER3_SHARE_BPS,
}


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------

@dataclass
class MonitoredContract:
    """Represents an actively monitored on-chain contract."""
    contract_address: str
    creator_address: str
    deployed_at: float = field(default_factory=time.time)
    total_revenue: Decimal = Decimal("0")
    total_routed_to_neosafe: Decimal = Decimal("0")
    is_active: bool = True
    last_checked: float = 0.0
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class EnforcementResult:
    """Result of a single revenue-enforcement action."""
    user_address: str
    gross_revenue: Decimal
    tier: Tier
    tier_share: Decimal
    pac_share: Decimal
    total_deducted: Decimal
    net_to_user: Decimal
    routed_to_neosafe: bool
    tx_hash: Optional[str] = None
    error: Optional[str] = None
    timestamp: float = field(default_factory=time.time)


@dataclass
class TransactionInfo:
    """Minimal representation of an on-chain transaction."""
    tx_hash: str
    from_address: str
    to_address: str
    value_wei: int
    block_number: int
    timestamp: float


# ---------------------------------------------------------------------------
# Revenue Enforcer
# ---------------------------------------------------------------------------

class RevenueEnforcer:
    """
    Monitors deployed contracts and enforces tier-based revenue sharing
    plus the 2.5 % Platform Access Contribution on every revenue event.

    All deducted amounts are routed to the NeoSafe wallet at
    ``0x46fF491D7054A6F500026B3E81f358190f8d8Ec5``.

    Usage::

        enforcer = RevenueEnforcer(web3_provider=w3, tier_manager=tm)
        await enforcer.monitor_contract("0xabc...")
        result = enforcer.enforce_revenue_split(tx)
    """

    def __init__(
        self,
        web3_provider: Any = None,
        tier_manager: Any = None,
        poll_interval_seconds: int = 15,
    ) -> None:
        """
        Parameters
        ----------
        web3_provider
            A ``web3.Web3`` instance (or compatible) for chain interaction.
        tier_manager
            A ``TierManager`` instance for tier lookups and updates.
        poll_interval_seconds
            How often (in seconds) the background monitor polls for new
            revenue events on watched contracts.
        """
        self._w3 = web3_provider
        self._tier_manager = tier_manager
        self._poll_interval = poll_interval_seconds
        self._monitored: Dict[str, MonitoredContract] = {}
        self._enforcement_log: List[EnforcementResult] = []
        self._running: bool = False

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def monitor_contract(self, contract_address: str) -> MonitoredContract:
        """
        Begin monitoring a deployed contract for revenue events.

        Parameters
        ----------
        contract_address : str
            The ``0x``-prefixed address of the contract to watch.

        Returns
        -------
        MonitoredContract
            The newly registered monitoring record.

        Raises
        ------
        ValueError
            If the address is invalid or the contract is already monitored.
        """
        address = self._normalise_address(contract_address)

        if address in self._monitored:
            raise ValueError(f"Contract {address} is already being monitored.")

        creator = await self._resolve_creator(address)

        mc = MonitoredContract(
            contract_address=address,
            creator_address=creator,
        )
        self._monitored[address] = mc

        logger.info("Now monitoring contract %s (creator: %s)", address, creator)
        return mc

    def calculate_tier_share(
        self, user_address: str, revenue: Decimal
    ) -> Decimal:
        """
        Calculate the tier-based revenue share for *user_address*.

        Parameters
        ----------
        user_address : str
            The user's Ethereum address.
        revenue : Decimal
            The gross revenue amount (in ETH or wei depending on context).

        Returns
        -------
        Decimal
            The tier share amount to be sent to NeoSafe.
        """
        tier = self.get_user_tier(user_address)
        bps = _TIER_BPS[tier]
        share = (revenue * Decimal(bps)) / Decimal(BPS_DENOMINATOR)
        return share.quantize(Decimal("0.000000000000000001"), rounding=ROUND_DOWN)

    def calculate_platform_contribution(self, revenue: Decimal) -> Decimal:
        """
        Calculate the flat 2.5 % Platform Access Contribution.

        Parameters
        ----------
        revenue : Decimal
            The gross revenue amount.

        Returns
        -------
        Decimal
            The PAC amount.
        """
        pac = (revenue * Decimal(PAC_BPS)) / Decimal(BPS_DENOMINATOR)
        return pac.quantize(Decimal("0.000000000000000001"), rounding=ROUND_DOWN)

    def route_to_neosafe(self, amount: Decimal) -> Optional[str]:
        """
        Route *amount* to the NeoSafe wallet on-chain.

        Parameters
        ----------
        amount : Decimal
            Amount in ETH to transfer.

        Returns
        -------
        str or None
            Transaction hash on success, ``None`` if no web3 provider is
            configured (dry-run / offline mode).

        Raises
        ------
        RuntimeError
            If the on-chain transfer fails.
        """
        if amount <= 0:
            logger.warning("route_to_neosafe called with non-positive amount: %s", amount)
            return None

        if self._w3 is None:
            logger.info(
                "[DRY-RUN] Would route %s ETH to NeoSafe (%s)",
                amount, NEOSAFE_ADDRESS,
            )
            return None

        try:
            wei_amount = int(amount * Decimal("1e18"))
            tx = {
                "to": NEOSAFE_ADDRESS,
                "value": wei_amount,
                "gas": 21_000,
            }
            # Assumes the provider has an unlocked default account.
            tx_hash = self._w3.eth.send_transaction(tx)
            hex_hash = tx_hash.hex() if hasattr(tx_hash, "hex") else str(tx_hash)
            logger.info(
                "Routed %s ETH to NeoSafe — tx: %s", amount, hex_hash
            )
            return hex_hash
        except Exception as exc:
            logger.error("Failed to route to NeoSafe: %s", exc)
            raise RuntimeError(f"NeoSafe routing failed: {exc}") from exc

    def get_user_tier(self, user_address: str) -> Tier:
        """
        Look up the current tier for *user_address*.

        Delegates to the injected ``TierManager`` when available;
        otherwise defaults to ``Tier.TIER_1``.

        Parameters
        ----------
        user_address : str
            Ethereum address of the user.

        Returns
        -------
        Tier
        """
        if self._tier_manager is not None:
            try:
                tier_info = self._tier_manager.get_user_tier(user_address)
                return Tier(tier_info.current_tier)
            except Exception:
                logger.warning(
                    "TierManager lookup failed for %s; defaulting to TIER_1",
                    user_address,
                )
        return Tier.TIER_1

    def enforce_revenue_split(self, transaction: TransactionInfo) -> EnforcementResult:
        """
        Enforce the full revenue split for a single transaction.

        1. Look up the user's tier.
        2. Calculate tier share.
        3. Calculate PAC (2.5 %).
        4. Route the combined amount to NeoSafe.
        5. Log the enforcement result.

        Parameters
        ----------
        transaction : TransactionInfo
            The revenue-generating transaction to process.

        Returns
        -------
        EnforcementResult
        """
        user = transaction.from_address
        gross = Decimal(transaction.value_wei) / Decimal("1e18")
        tier = self.get_user_tier(user)
        tier_share = self.calculate_tier_share(user, gross)
        pac_share = self.calculate_platform_contribution(gross)
        total_deducted = tier_share + pac_share
        net = gross - total_deducted

        tx_hash: Optional[str] = None
        error: Optional[str] = None
        routed = False

        try:
            tx_hash = self.route_to_neosafe(total_deducted)
            routed = True
        except RuntimeError as exc:
            error = str(exc)
            logger.error("Enforcement failed for tx %s: %s", transaction.tx_hash, exc)

        # Update monitoring records.
        contract_addr = transaction.to_address
        if contract_addr in self._monitored:
            mc = self._monitored[contract_addr]
            mc.total_revenue += gross
            mc.total_routed_to_neosafe += total_deducted if routed else Decimal("0")
            mc.last_checked = time.time()

        # Update tier manager cumulative revenue.
        if self._tier_manager is not None:
            try:
                self._tier_manager.update_revenue(user, gross)
            except Exception as tm_exc:
                logger.error("TierManager update failed: %s", tm_exc)

        result = EnforcementResult(
            user_address=user,
            gross_revenue=gross,
            tier=tier,
            tier_share=tier_share,
            pac_share=pac_share,
            total_deducted=total_deducted,
            net_to_user=net,
            routed_to_neosafe=routed,
            tx_hash=tx_hash,
            error=error,
        )
        self._enforcement_log.append(result)

        logger.info(
            "Enforced split for %s: gross=%s tier=%s share=%s pac=%s total=%s net=%s",
            user, gross, tier.name, tier_share, pac_share, total_deducted, net,
        )
        return result

    # ------------------------------------------------------------------
    # Background Monitor
    # ------------------------------------------------------------------

    async def start_monitoring_loop(self) -> None:
        """
        Run the background polling loop that watches all monitored contracts
        for new revenue events.  Call ``stop_monitoring_loop()`` to halt.
        """
        self._running = True
        logger.info("Revenue monitoring loop started (interval=%ds)", self._poll_interval)

        while self._running:
            for address, mc in list(self._monitored.items()):
                if not mc.is_active:
                    continue
                try:
                    await self._poll_contract(mc)
                except Exception as exc:
                    logger.error("Error polling %s: %s", address, exc)

            await asyncio.sleep(self._poll_interval)

    def stop_monitoring_loop(self) -> None:
        """Signal the background monitoring loop to stop."""
        self._running = False
        logger.info("Revenue monitoring loop stop requested.")

    # ------------------------------------------------------------------
    # Query helpers
    # ------------------------------------------------------------------

    def get_monitored_contracts(self) -> List[MonitoredContract]:
        """Return all currently monitored contracts."""
        return list(self._monitored.values())

    def get_enforcement_log(self) -> List[EnforcementResult]:
        """Return the full enforcement history."""
        return list(self._enforcement_log)

    def get_total_routed(self) -> Decimal:
        """Return the aggregate amount routed to NeoSafe."""
        return sum(
            (mc.total_routed_to_neosafe for mc in self._monitored.values()),
            Decimal("0"),
        )

    # ------------------------------------------------------------------
    # Private Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _normalise_address(address: str) -> str:
        """Validate and normalise an Ethereum address to checksummed form."""
        addr = address.strip()
        if not addr.startswith("0x") or len(addr) != 42:
            raise ValueError(f"Invalid Ethereum address: {addr}")
        return addr  # In production, use web3.toChecksumAddress

    async def _resolve_creator(self, contract_address: str) -> str:
        """Resolve the creator / deployer of a contract."""
        if self._w3 is not None:
            try:
                # Heuristic: look at the first transaction to the address.
                code = self._w3.eth.get_code(contract_address)
                if code and len(code) > 2:
                    return "resolved-via-chain"
            except Exception:
                pass
        return "unknown"

    async def _poll_contract(self, mc: MonitoredContract) -> None:
        """
        Poll a single contract for new ``RevenueRecorded`` events since
        the last check and enforce the revenue split on each.
        """
        if self._w3 is None:
            return

        try:
            # Build a minimal event filter for RevenueRecorded(address,uint256,uint8).
            event_sig = self._w3.keccak(
                text="RevenueRecorded(address,uint256,uint8)"
            )
            from_block = "latest"  # In production: track last processed block.

            logs = self._w3.eth.get_logs({
                "address": mc.contract_address,
                "topics": [event_sig],
                "fromBlock": from_block,
            })

            for log_entry in logs:
                # Decode minimal fields.
                user = "0x" + log_entry["topics"][1].hex()[-40:]
                value_wei = int(log_entry["data"][:66], 16) if log_entry.get("data") else 0

                if value_wei > 0:
                    tx_info = TransactionInfo(
                        tx_hash=log_entry.get("transactionHash", b"").hex(),
                        from_address=user,
                        to_address=mc.contract_address,
                        value_wei=value_wei,
                        block_number=log_entry.get("blockNumber", 0),
                        timestamp=time.time(),
                    )
                    self.enforce_revenue_split(tx_info)

            mc.last_checked = time.time()

        except Exception as exc:
            logger.error("Poll error for %s: %s", mc.contract_address, exc)
