"""
Oracle Interface
==================

Single entry point for ALL oracle data requests platform-wide. Every
component that needs external data -- prices, weather, sports, flights,
deliveries -- routes through this interface. The interface delegates to
specialised oracle providers and applies multi-source consensus via
the aggregator.

This is the ONLY module other components should import for oracle data.
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"


class OracleDataType(Enum):
    """Supported oracle data categories."""
    PRICE = "price"
    WEATHER = "weather"
    SPORTS = "sports"
    FLIGHT = "flight"
    DELIVERY = "delivery"
    CUSTOM = "custom"


class RequestStatus(Enum):
    """Oracle request lifecycle states."""
    PENDING = "pending"
    FETCHING = "fetching"
    AGGREGATING = "aggregating"
    FULFILLED = "fulfilled"
    FAILED = "failed"
    STALE = "stale"


@dataclass
class OracleRequest:
    """An oracle data request."""
    request_id: str
    data_type: OracleDataType
    parameters: Dict[str, Any]
    source_component: int
    requester: str
    created_at: float = field(default_factory=time.time)
    status: RequestStatus = RequestStatus.PENDING
    priority: str = "normal"


@dataclass
class OracleResponse:
    """Response from the oracle system."""
    request_id: str
    data_type: OracleDataType
    value: Any
    confidence: float
    sources_used: int
    sources_agreed: int
    timestamp: float = field(default_factory=time.time)
    stale_after: Optional[float] = None
    raw_sources: List[Dict[str, Any]] = field(default_factory=list)
    error: Optional[str] = None

    @property
    def is_stale(self) -> bool:
        if self.stale_after is None:
            return False
        return time.time() > self.stale_after

    @property
    def is_consensus(self) -> bool:
        return self.sources_agreed > self.sources_used / 2


class OracleInterface:
    """Single entry point for all oracle data requests platform-wide.

    ALL external data requests from ANY component route through this
    interface. The interface delegates to specialised providers and
    applies multi-source consensus via the aggregator.

    Parameters
    ----------
    chainlink_prices : Any
        ChainlinkPriceFeed provider.
    weather_oracle : Any
        WeatherOracle provider.
    sports_oracle : Any
        SportsOracle provider.
    flight_oracle : Any
        FlightOracle provider.
    delivery_oracle : Any
        DeliveryOracle provider.
    aggregator : Any
        OracleAggregator for multi-source consensus.
    """

    def __init__(
        self,
        chainlink_prices: Any = None,
        weather_oracle: Any = None,
        sports_oracle: Any = None,
        flight_oracle: Any = None,
        delivery_oracle: Any = None,
        aggregator: Any = None,
    ) -> None:
        self._providers: Dict[OracleDataType, Any] = {}
        if chainlink_prices:
            self._providers[OracleDataType.PRICE] = chainlink_prices
        if weather_oracle:
            self._providers[OracleDataType.WEATHER] = weather_oracle
        if sports_oracle:
            self._providers[OracleDataType.SPORTS] = sports_oracle
        if flight_oracle:
            self._providers[OracleDataType.FLIGHT] = flight_oracle
        if delivery_oracle:
            self._providers[OracleDataType.DELIVERY] = delivery_oracle

        self._aggregator = aggregator
        self._request_log: List[OracleRequest] = []
        self._response_cache: Dict[str, OracleResponse] = {}
        logger.info(
            "OracleInterface initialised with %d providers", len(self._providers)
        )

    # ------------------------------------------------------------------
    # Public API - The single entry point
    # ------------------------------------------------------------------

    def request_data(
        self,
        data_type: OracleDataType,
        parameters: Dict[str, Any],
        source_component: int,
        requester: str = "",
        use_cache: bool = True,
        max_staleness_seconds: int = 60,
    ) -> OracleResponse:
        """Request oracle data. This is the single entry point.

        ALL oracle requests from ANY component go through this method.

        Args:
            data_type: Type of data being requested.
            parameters: Query parameters specific to the data type.
            source_component: Component ID making the request.
            requester: Optional requester identifier.
            use_cache: Whether to use cached responses.
            max_staleness_seconds: Maximum acceptable data age.

        Returns:
            OracleResponse with the requested data.

        Examples:
            # Price data
            response = oracle.request_data(
                OracleDataType.PRICE,
                {"asset": "ETH", "currency": "USD"},
                source_component=13,
            )

            # Weather data for insurance
            response = oracle.request_data(
                OracleDataType.WEATHER,
                {"location": "Miami, FL", "metric": "wind_speed"},
                source_component=13,
            )

            # Flight status
            response = oracle.request_data(
                OracleDataType.FLIGHT,
                {"flight_number": "AA100", "date": "2026-03-30"},
                source_component=13,
            )
        """
        request_id = f"oracle-{uuid.uuid4().hex[:12]}"
        request = OracleRequest(
            request_id=request_id,
            data_type=data_type,
            parameters=parameters,
            source_component=source_component,
            requester=requester,
        )
        self._request_log.append(request)

        # Check cache
        if use_cache:
            cached = self._check_cache(data_type, parameters, max_staleness_seconds)
            if cached:
                logger.debug("Cache hit for %s request from component %d", data_type.value, source_component)
                return cached

        # Fetch from provider
        request.status = RequestStatus.FETCHING
        provider = self._providers.get(data_type)
        if provider is None:
            request.status = RequestStatus.FAILED
            return OracleResponse(
                request_id=request_id,
                data_type=data_type,
                value=None,
                confidence=0.0,
                sources_used=0,
                sources_agreed=0,
                error=f"No provider registered for {data_type.value}",
            )

        try:
            raw_data = provider.fetch(parameters)
        except Exception as exc:
            request.status = RequestStatus.FAILED
            logger.error("Provider fetch failed for %s: %s", data_type.value, exc)
            return OracleResponse(
                request_id=request_id,
                data_type=data_type,
                value=None,
                confidence=0.0,
                sources_used=0,
                sources_agreed=0,
                error=str(exc),
            )

        # Aggregate for consensus
        request.status = RequestStatus.AGGREGATING
        if self._aggregator:
            response = self._aggregator.aggregate(request_id, data_type, raw_data)
        else:
            response = OracleResponse(
                request_id=request_id,
                data_type=data_type,
                value=raw_data.get("value") if isinstance(raw_data, dict) else raw_data,
                confidence=1.0,
                sources_used=1,
                sources_agreed=1,
                stale_after=time.time() + max_staleness_seconds,
            )

        # Cache the response
        cache_key = self._cache_key(data_type, parameters)
        self._response_cache[cache_key] = response

        request.status = RequestStatus.FULFILLED
        logger.info(
            "Oracle request fulfilled: type=%s, component=%d, confidence=%.2f",
            data_type.value, source_component, response.confidence,
        )
        return response

    # Convenience methods for common requests

    def get_price(
        self, asset: str, currency: str = "USD", source_component: int = 0
    ) -> OracleResponse:
        """Get asset price. Convenience wrapper."""
        return self.request_data(
            OracleDataType.PRICE,
            {"asset": asset, "currency": currency},
            source_component=source_component,
        )

    def get_weather(
        self, location: str, metric: str, source_component: int = 0
    ) -> OracleResponse:
        """Get weather data. Convenience wrapper."""
        return self.request_data(
            OracleDataType.WEATHER,
            {"location": location, "metric": metric},
            source_component=source_component,
        )

    def get_flight_status(
        self, flight_number: str, date: str, source_component: int = 0
    ) -> OracleResponse:
        """Get flight status. Convenience wrapper."""
        return self.request_data(
            OracleDataType.FLIGHT,
            {"flight_number": flight_number, "date": date},
            source_component=source_component,
        )

    def get_delivery_status(
        self, tracking_number: str, carrier: str, source_component: int = 0
    ) -> OracleResponse:
        """Get delivery status. Convenience wrapper."""
        return self.request_data(
            OracleDataType.DELIVERY,
            {"tracking_number": tracking_number, "carrier": carrier},
            source_component=source_component,
        )

    def get_sports_outcome(
        self, event_id: str, sport: str, source_component: int = 0
    ) -> OracleResponse:
        """Get sports event outcome. Convenience wrapper."""
        return self.request_data(
            OracleDataType.SPORTS,
            {"event_id": event_id, "sport": sport},
            source_component=source_component,
        )

    # ------------------------------------------------------------------
    # Provider management
    # ------------------------------------------------------------------

    def register_provider(self, data_type: OracleDataType, provider: Any) -> None:
        """Register or replace an oracle data provider."""
        self._providers[data_type] = provider
        logger.info("Provider registered for %s", data_type.value)

    def get_request_log(self, limit: int = 100) -> List[OracleRequest]:
        """Return recent oracle requests."""
        return list(reversed(self._request_log[-limit:]))

    def clear_cache(self) -> int:
        """Clear the response cache. Returns entries cleared."""
        count = len(self._response_cache)
        self._response_cache.clear()
        return count

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _check_cache(
        self,
        data_type: OracleDataType,
        parameters: Dict[str, Any],
        max_staleness: int,
    ) -> Optional[OracleResponse]:
        key = self._cache_key(data_type, parameters)
        cached = self._response_cache.get(key)
        if cached is None:
            return None
        if cached.is_stale:
            del self._response_cache[key]
            return None
        age = time.time() - cached.timestamp
        if age > max_staleness:
            return None
        return cached

    @staticmethod
    def _cache_key(data_type: OracleDataType, parameters: Dict[str, Any]) -> str:
        param_str = "&".join(f"{k}={v}" for k, v in sorted(parameters.items()))
        return f"{data_type.value}:{param_str}"
