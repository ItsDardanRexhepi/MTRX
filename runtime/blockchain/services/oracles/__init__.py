"""
Component 11 - Oracle Service
================================

Single entry point for ALL oracle data requests platform-wide. Every
component that needs external data routes through the Component 11
interface. Multi-source consensus eliminates manipulation risk.

Sub-modules
-----------
interface          : Single entry point for all oracle requests.
chainlink_prices   : ETH, USDC, and all supported asset price feeds.
weather            : Parametric insurance weather triggers.
sports             : Sports event outcome data.
flights            : Travel insurance flight status.
delivery           : Package protection delivery status.
aggregator         : Multi-source consensus engine.
"""

from runtime.blockchain.services.oracles.interface import OracleInterface
from runtime.blockchain.services.oracles.chainlink_prices import ChainlinkPriceFeed
from runtime.blockchain.services.oracles.weather import WeatherOracle
from runtime.blockchain.services.oracles.sports import SportsOracle
from runtime.blockchain.services.oracles.flights import FlightOracle
from runtime.blockchain.services.oracles.delivery import DeliveryOracle
from runtime.blockchain.services.oracles.aggregator import OracleAggregator

__all__ = [
    "OracleInterface",
    "ChainlinkPriceFeed",
    "WeatherOracle",
    "SportsOracle",
    "FlightOracle",
    "DeliveryOracle",
    "OracleAggregator",
]

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
COMPONENT_ID: int = 11
COMPONENT_NAME: str = "Oracle Service"
