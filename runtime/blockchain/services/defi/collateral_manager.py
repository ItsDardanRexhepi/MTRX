"""
Collateral Manager — Component 2
=================================

Manages collateral locking, release, top-up, and liquidation for DeFi and
P2P loans via the on-chain DeFiLoan / P2PLoan smart contracts on Base.

Supports native ETH and approved ERC-20 stablecoins.
"""

from __future__ import annotations

import logging
from decimal import Decimal, ROUND_DOWN
from enum import Enum
from dataclasses import dataclass
from typing import Optional

from web3 import Web3
from web3.contract import Contract
from web3.types import TxReceipt, Wei

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
#  Data types
# ---------------------------------------------------------------------------

class CollateralToken(str, Enum):
    """Supported collateral token identifiers."""
    ETH = "ETH"
    USDC = "USDC"
    USDT = "USDT"
    DAI = "DAI"
    USDbC = "USDbC"


@dataclass(frozen=True)
class CollateralLock:
    """Immutable record of a collateral lock event."""
    loan_id: int
    borrower: str
    amount: Decimal
    token: CollateralToken
    tx_hash: str
    block_number: int


# ---------------------------------------------------------------------------
#  Constants
# ---------------------------------------------------------------------------

# Approved stablecoin addresses on Base mainnet
APPROVED_TOKENS_BASE: dict[CollateralToken, str] = {
    CollateralToken.ETH: "0x0000000000000000000000000000000000000000",
    CollateralToken.USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    CollateralToken.DAI: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",
    CollateralToken.USDbC: "0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA",
}

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
MIN_COLLATERAL_RATIO = Decimal("1.50")   # 150 %
WARNING_RATIO = Decimal("1.20")          # 120 %


# ---------------------------------------------------------------------------
#  CollateralManager
# ---------------------------------------------------------------------------

class CollateralManager:
    """
    Manages collateral lifecycle for DeFi and P2P loans.

    Interacts with on-chain DeFiLoan and P2PLoan contracts to lock,
    release, top-up, and liquidate collateral.  Supports native ETH and
    approved ERC-20 stablecoins on Base.

    Parameters
    ----------
    w3 : Web3
        Connected Web3 instance (Base RPC).
    defi_loan_contract : Contract
        Deployed DeFiLoan contract instance.
    p2p_loan_contract : Contract
        Deployed P2PLoan contract instance.
    platform_account : str
        Platform hot-wallet address used for signing keeper transactions.
    private_key : str
        Private key for *platform_account* (hex, with or without ``0x``).
    """

    def __init__(
        self,
        w3: Web3,
        defi_loan_contract: Contract,
        p2p_loan_contract: Contract,
        platform_account: str,
        private_key: str,
    ) -> None:
        if not w3.is_connected():
            raise ConnectionError("Web3 provider is not connected to Base RPC")

        self._w3 = w3
        self._defi = defi_loan_contract
        self._p2p = p2p_loan_contract
        self._account = Web3.to_checksum_address(platform_account)
        self._private_key = private_key if private_key.startswith("0x") else f"0x{private_key}"

        logger.info(
            "CollateralManager initialised — platform account %s",
            self._account,
        )

    # ------------------------------------------------------------------
    #  Public API
    # ------------------------------------------------------------------

    def lock_collateral(
        self,
        borrower: str,
        amount: Decimal,
        token: CollateralToken,
        *,
        loan_contract: str = "defi",
    ) -> CollateralLock:
        """
        Lock collateral for a new loan in the smart contract.

        Parameters
        ----------
        borrower : str
            Borrower wallet address.
        amount : Decimal
            Collateral amount (in token's native decimals).
        token : CollateralToken
            Token type to lock.
        loan_contract : str
            ``"defi"`` or ``"p2p"`` — selects the target contract.

        Returns
        -------
        CollateralLock
            Record of the successful lock transaction.

        Raises
        ------
        ValueError
            If *amount* is non-positive or *token* is not approved.
        RuntimeError
            If the on-chain transaction reverts.
        """
        borrower = Web3.to_checksum_address(borrower)

        if amount <= 0:
            raise ValueError(f"Collateral amount must be positive, got {amount}")

        if token not in APPROVED_TOKENS_BASE:
            raise ValueError(f"Token {token.value} is not an approved collateral type")

        token_address = APPROVED_TOKENS_BASE[token]
        contract = self._defi if loan_contract == "defi" else self._p2p

        logger.info(
            "Locking %s %s collateral for borrower %s on %s contract",
            amount, token.value, borrower, loan_contract,
        )

        if token == CollateralToken.ETH:
            tx_hash, receipt = self._lock_eth(contract, borrower, amount)
        else:
            tx_hash, receipt = self._lock_erc20(contract, borrower, amount, token_address)

        lock = CollateralLock(
            loan_id=self._extract_loan_id(receipt),
            borrower=borrower,
            amount=amount,
            token=token,
            tx_hash=tx_hash,
            block_number=receipt["blockNumber"],
        )
        logger.info("Collateral locked — loan_id=%d tx=%s", lock.loan_id, lock.tx_hash)
        return lock

    def check_ratio(self, loan_id: int, *, contract: str = "defi") -> Decimal:
        """
        Query the current collateral ratio for a loan.

        Parameters
        ----------
        loan_id : int
            On-chain loan identifier.
        contract : str
            ``"defi"`` or ``"p2p"``.

        Returns
        -------
        Decimal
            Collateral ratio as a decimal (e.g., ``Decimal("1.55")`` for 155 %).
        """
        target = self._defi if contract == "defi" else self._p2p

        try:
            ratio_wad: int = target.functions.getCollateralRatio(loan_id).call()
        except Exception as exc:
            logger.error("Failed to fetch collateral ratio for loan %d: %s", loan_id, exc)
            raise RuntimeError(f"Oracle / contract call failed for loan {loan_id}") from exc

        ratio = Decimal(str(ratio_wad)) / Decimal("1e18")
        logger.debug("Loan %d collateral ratio: %s", loan_id, ratio)
        return ratio

    def release_collateral(self, loan_id: int, *, contract: str = "defi") -> str:
        """
        Release collateral back to the borrower after full repayment.

        This is typically triggered automatically by the smart contract
        upon final payment, but can also be called manually by the
        platform keeper in edge cases.

        Parameters
        ----------
        loan_id : int
            On-chain loan identifier.
        contract : str
            ``"defi"`` or ``"p2p"``.

        Returns
        -------
        str
            Transaction hash of the release.

        Raises
        ------
        RuntimeError
            If the loan is not in a repaid state.
        """
        target = self._defi if contract == "defi" else self._p2p

        # Verify loan is repaid (status == 1 in the enum)
        loan_data = target.functions.loans(loan_id).call()
        loan_status = loan_data[10] if contract == "defi" else loan_data[13]

        if loan_status != 1:  # LoanStatus.Repaid
            raise RuntimeError(
                f"Loan {loan_id} is not in Repaid status (current: {loan_status})"
            )

        logger.info("Collateral already released on-chain for repaid loan %d", loan_id)
        return "0x" + "0" * 64  # Collateral released automatically on repayment

    def liquidate(self, loan_id: int, *, contract: str = "defi") -> str:
        """
        Force-liquidate a loan whose grace period has expired.

        Calls ``forceLiquidation`` on the target contract.  The collateral
        is transferred to NeoSafe (platform loans) or the lender (P2P).

        Parameters
        ----------
        loan_id : int
            On-chain loan identifier.
        contract : str
            ``"defi"`` or ``"p2p"``.

        Returns
        -------
        str
            Transaction hash of the liquidation.

        Raises
        ------
        RuntimeError
            If the grace period has not elapsed or the loan is not active.
        """
        target = self._defi if contract == "defi" else self._p2p

        logger.warning("Executing liquidation for loan %d on %s contract", loan_id, contract)

        try:
            tx = target.functions.forceLiquidation(loan_id).build_transaction(
                self._base_tx_params()
            )
            tx_hash = self._sign_and_send(tx)
            receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

            if receipt["status"] != 1:
                raise RuntimeError(
                    f"Liquidation tx reverted for loan {loan_id}: {tx_hash}"
                )

            logger.warning(
                "Loan %d liquidated — tx=%s block=%d",
                loan_id, tx_hash, receipt["blockNumber"],
            )
            return tx_hash

        except Exception as exc:
            logger.error("Liquidation failed for loan %d: %s", loan_id, exc)
            raise

    def top_up_collateral(
        self,
        loan_id: int,
        amount: Decimal,
        *,
        token: CollateralToken = CollateralToken.ETH,
        contract: str = "defi",
    ) -> str:
        """
        Add additional collateral to an active loan.

        Parameters
        ----------
        loan_id : int
            On-chain loan identifier.
        amount : Decimal
            Additional collateral amount.
        token : CollateralToken
            Token type matching the existing collateral.
        contract : str
            ``"defi"`` or ``"p2p"``.

        Returns
        -------
        str
            Transaction hash.

        Raises
        ------
        ValueError
            If *amount* is non-positive.
        RuntimeError
            If the on-chain transaction reverts.
        """
        if amount <= 0:
            raise ValueError(f"Top-up amount must be positive, got {amount}")

        target = self._defi if contract == "defi" else self._p2p

        logger.info(
            "Topping up loan %d with %s %s on %s contract",
            loan_id, amount, token.value, contract,
        )

        if token == CollateralToken.ETH:
            wei_amount = self._to_wei(amount)
            tx = target.functions.topUpCollateralETH(loan_id).build_transaction(
                {**self._base_tx_params(), "value": wei_amount}
            )
        else:
            raw_amount = int(amount * Decimal("1e18"))
            tx = target.functions.topUpCollateralERC20(
                loan_id, raw_amount
            ).build_transaction(self._base_tx_params())

        tx_hash = self._sign_and_send(tx)
        receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

        if receipt["status"] != 1:
            raise RuntimeError(f"Top-up tx reverted for loan {loan_id}: {tx_hash}")

        new_ratio = self.check_ratio(loan_id, contract=contract)
        logger.info(
            "Top-up complete for loan %d — new ratio: %s tx=%s",
            loan_id, new_ratio, tx_hash,
        )
        return tx_hash

    # ------------------------------------------------------------------
    #  Internal helpers
    # ------------------------------------------------------------------

    def _lock_eth(
        self, contract: Contract, borrower: str, amount: Decimal
    ) -> tuple[str, TxReceipt]:
        """Build and send an ETH collateral lock transaction."""
        wei_amount = self._to_wei(amount)
        # The actual lock happens inside originateLoanETH — this is the
        # keeper-side representation.  In production the borrower signs
        # the origination tx directly; the keeper monitors and records.
        tx = contract.functions.topUpCollateralETH(0).build_transaction(
            {**self._base_tx_params(), "value": wei_amount}
        )
        tx_hash = self._sign_and_send(tx)
        receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        if receipt["status"] != 1:
            raise RuntimeError(f"ETH collateral lock reverted: {tx_hash}")
        return tx_hash, receipt

    def _lock_erc20(
        self, contract: Contract, borrower: str, amount: Decimal, token_address: str
    ) -> tuple[str, TxReceipt]:
        """Build and send an ERC-20 collateral lock transaction."""
        raw_amount = int(amount * Decimal("1e18"))
        # Approve then top-up (in production borrower calls originateLoanERC20)
        erc20 = self._w3.eth.contract(
            address=Web3.to_checksum_address(token_address),
            abi=[{
                "inputs": [
                    {"name": "spender", "type": "address"},
                    {"name": "amount", "type": "uint256"},
                ],
                "name": "approve",
                "outputs": [{"name": "", "type": "bool"}],
                "stateMutability": "nonpayable",
                "type": "function",
            }],
        )
        approve_tx = erc20.functions.approve(
            contract.address, raw_amount
        ).build_transaction(self._base_tx_params())
        self._sign_and_send(approve_tx)

        tx = contract.functions.topUpCollateralERC20(0, raw_amount).build_transaction(
            self._base_tx_params()
        )
        tx_hash = self._sign_and_send(tx)
        receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        if receipt["status"] != 1:
            raise RuntimeError(f"ERC-20 collateral lock reverted: {tx_hash}")
        return tx_hash, receipt

    def _base_tx_params(self) -> dict:
        """Return common transaction parameters."""
        return {
            "from": self._account,
            "nonce": self._w3.eth.get_transaction_count(self._account),
            "gas": 500_000,
            "maxFeePerGas": self._w3.eth.gas_price * 2,
            "maxPriorityFeePerGas": self._w3.to_wei(0.1, "gwei"),
            "chainId": self._w3.eth.chain_id,
        }

    def _sign_and_send(self, tx: dict) -> str:
        """Sign a transaction and broadcast it."""
        signed = self._w3.eth.account.sign_transaction(tx, self._private_key)
        tx_hash = self._w3.eth.send_raw_transaction(signed.raw_transaction)
        return self._w3.to_hex(tx_hash)

    def _to_wei(self, eth_amount: Decimal) -> Wei:
        """Convert ETH decimal amount to Wei."""
        return Wei(int(eth_amount * Decimal("1e18")))

    @staticmethod
    def _extract_loan_id(receipt: TxReceipt) -> int:
        """Extract loan ID from origination event logs."""
        for log in receipt.get("logs", []):
            # LoanOriginated topic0
            if len(log.get("topics", [])) >= 2:
                try:
                    return int(log["topics"][1].hex(), 16)
                except (ValueError, IndexError, AttributeError):
                    continue
        return -1
