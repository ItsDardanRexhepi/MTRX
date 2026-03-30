"""
Component 12 — Supply Chain Verification Service
==================================================

Records immutable chain-of-custody for ANY asset (physical or digital) on-chain.
Every step is permanently recorded; the platform covers all gas costs so usage
is completely free to end users.

Sub-modules
-----------
qr_generator         : Generates QR codes linking to full verified product history.
verification_ui      : Converts raw chain-of-custody data into plain-language timelines.
property_history     : Comprehensive property history for informed buyer decisions.
vehicle_history      : Comprehensive vehicle history (service, accident, ownership).
ownership_listener   : Subscribes to Component 4 ownership-transfer events and auto-records.
"""

from runtime.blockchain.services.supply_chain.qr_generator import QRGenerator
from runtime.blockchain.services.supply_chain.verification_ui import VerificationUI
from runtime.blockchain.services.supply_chain.property_history import PropertyHistory
from runtime.blockchain.services.supply_chain.vehicle_history import VehicleHistory
from runtime.blockchain.services.supply_chain.ownership_listener import OwnershipTransferListener

__all__ = [
    "QRGenerator",
    "VerificationUI",
    "PropertyHistory",
    "VehicleHistory",
    "OwnershipTransferListener",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 12
COMPONENT_NAME: str = "Supply Chain Verification Service"
