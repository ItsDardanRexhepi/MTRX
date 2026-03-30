"""
Component 7 - Stablecoin Service
==================================

Manages stablecoin operations on 0pnMatrx including lifetime balance
tracking, rate-limited free transfers, tiered fee calculation, and
fee routing to NeoSafe.

Sub-modules
-----------
wallet_tracker   : Permanent lifetime balance history per wallet.
rate_limiter     : 2-per-48hr rolling window free transfer limit.
fee_calculator   : Tiered fee calculation based on transfer amount.
fee_router       : Route all collected fees to NeoSafe.
"""

from runtime.blockchain.services.stablecoin.wallet_tracker import WalletTracker
from runtime.blockchain.services.stablecoin.rate_limiter import TransferRateLimiter
from runtime.blockchain.services.stablecoin.fee_calculator import FeeCalculator
from runtime.blockchain.services.stablecoin.fee_router import FeeRouter

__all__ = [
    "WalletTracker",
    "TransferRateLimiter",
    "FeeCalculator",
    "FeeRouter",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 7
COMPONENT_NAME: str = "Stablecoin Service"
