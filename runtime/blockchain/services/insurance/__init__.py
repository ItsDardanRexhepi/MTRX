"""
Component 13 - Insurance Service
===================================

Parametric insurance on 0pnMatrx. Eligible users (0.5 ETH monthly
circulation) are automatically enrolled in all coverage products
simultaneously. Claims are processed automatically with zero human
steps. All oracle data routes through Component 11 interface.

Sub-modules
-----------
eligibility_tracker  : Monthly circulation threshold monitoring.
fee_engine           : 10% of circulated ETH up to 10 ETH cap.
trigger_manager      : Consume Component 11 oracle triggers, fire payouts.
reserve_fund         : 60/40 split, $500k floor, advisory alerts.
policy_registry      : Track all active insurance policies.
claims_processor     : Automatic zero-human-step payout processing.
coverage             : All products simultaneously for eligible users.
premium_calculator   : Injection points for renters, travel, Phase 2.
"""

from runtime.blockchain.services.insurance.eligibility_tracker import EligibilityTracker
from runtime.blockchain.services.insurance.fee_engine import InsuranceFeeEngine
from runtime.blockchain.services.insurance.trigger_manager import TriggerManager
from runtime.blockchain.services.insurance.reserve_fund import ReserveFund
from runtime.blockchain.services.insurance.policy_registry import PolicyRegistry
from runtime.blockchain.services.insurance.claims_processor import ClaimsProcessor
from runtime.blockchain.services.insurance.coverage import CoverageManager
from runtime.blockchain.services.insurance.premium_calculator import PremiumCalculator

__all__ = [
    "EligibilityTracker",
    "InsuranceFeeEngine",
    "TriggerManager",
    "ReserveFund",
    "PolicyRegistry",
    "ClaimsProcessor",
    "CoverageManager",
    "PremiumCalculator",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 13
COMPONENT_NAME: str = "Insurance Service"
