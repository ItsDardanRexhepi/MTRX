"""
Component 2 — DeFi Loans and P2P Lending
=========================================

Production runtime services for the 0pnMatrx DeFi lending platform deployed
on Base L2.  This package provides:

* **CollateralManager** — lock, release, top-up, and liquidate collateral
  held in the DeFiLoan / P2PLoan smart contracts.
* **RatioMonitor** — real-time collateral-ratio surveillance with Telegram
  alerts at the 120 % warning threshold and auto-liquidation after 48 h.
* **WhitelistGovernance** — propose / approve deployment-destination changes
  with mandatory Telegram approval from Dardan (ID 7161847911).
* **InterestEngine** — market-aware interest-rate calculation with an
  immutable 2.5 % floor.
* **LenderReputation** — ERC-8004 on-chain reputation scoring for P2P
  lenders.
* **LoanDashboard** — aggregated view of active loans, P2P marketplace
  listings, and platform statistics.
* **DisputeConnector** — routes ALL bilateral loan disputes to Component 30.
  Component 19 is NEVER used for loan disputes.

All modules integrate with EAS schema 348 for on-chain attestation of
origination, payment, and liquidation events.

NeoSafe treasury: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
"""

from __future__ import annotations

from runtime.blockchain.services.defi.collateral_manager import CollateralManager
from runtime.blockchain.services.defi.ratio_monitor import RatioMonitor, CollateralStatus
from runtime.blockchain.services.defi.whitelist_governance import WhitelistGovernance
from runtime.blockchain.services.defi.interest_engine import InterestEngine
from runtime.blockchain.services.defi.lender_reputation import LenderReputation, ReputationScore
from runtime.blockchain.services.defi.loan_dashboard import LoanDashboard
from runtime.blockchain.services.defi.dispute_connector import DisputeConnector

__all__ = [
    "CollateralManager",
    "RatioMonitor",
    "CollateralStatus",
    "WhitelistGovernance",
    "InterestEngine",
    "LenderReputation",
    "ReputationScore",
    "LoanDashboard",
    "DisputeConnector",
]
