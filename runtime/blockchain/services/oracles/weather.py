"""
Weather Oracle
===============

Provides weather data for parametric insurance triggers. Monitors
wind speed, rainfall, temperature, and other metrics for specified
locations. When thresholds are crossed, triggers are emitted for
the insurance system (Component 13).
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


class WeatherMetric(Enum):
    """Supported weather metrics."""
    WIND_SPEED_MPH = "wind_speed_mph"
    WIND_SPEED_KPH = "wind_speed_kph"
    RAINFALL_INCHES = "rainfall_inches"
    RAINFALL_MM = "rainfall_mm"
    TEMPERATURE_F = "temperature_f"
    TEMPERATURE_C = "temperature_c"
    HUMIDITY_PERCENT = "humidity_percent"
    PRESSURE_HPA = "pressure_hpa"
    SNOW_INCHES = "snow_inches"
    FLOOD_LEVEL_FT = "flood_level_ft"


class TriggerCondition(Enum):
    """Condition operators for weather triggers."""
    ABOVE = "above"
    BELOW = "below"
    EQUALS = "equals"


@dataclass
class WeatherDataPoint:
    """A single weather measurement."""
    location: str
    metric: WeatherMetric
    value: float
    timestamp: float = field(default_factory=time.time)
    source: str = ""
    confidence: float = 1.0


@dataclass
class WeatherTrigger:
    """A parametric weather trigger definition."""
    trigger_id: str
    location: str
    metric: WeatherMetric
    condition: TriggerCondition
    threshold: float
    policy_id: Optional[str] = None
    active: bool = True
    created_at: float = field(default_factory=time.time)
    last_checked_at: Optional[float] = None
    triggered: bool = False
    triggered_at: Optional[float] = None
    triggered_value: Optional[float] = None


@dataclass
class TriggerEvent:
    """An emitted trigger event for the insurance system."""
    event_id: str
    trigger_id: str
    location: str
    metric: WeatherMetric
    threshold: float
    actual_value: float
    policy_id: Optional[str] = None
    timestamp: float = field(default_factory=time.time)


class WeatherOracle:
    """Weather data provider for parametric insurance.

    Fetches weather data from external APIs and evaluates parametric
    triggers. When a trigger condition is met, a TriggerEvent is
    emitted for consumption by Component 13 (Insurance).

    Parameters
    ----------
    api_credentials : dict, optional
        API keys for weather data providers.
    trigger_callback : callable, optional
        Called when a trigger fires with the TriggerEvent.
    """

    def __init__(
        self,
        api_credentials: Optional[Dict[str, str]] = None,
        trigger_callback: Any = None,
    ) -> None:
        self._credentials = api_credentials or {}
        self._trigger_callback = trigger_callback
        self._triggers: Dict[str, WeatherTrigger] = {}
        self._data_history: Dict[str, List[WeatherDataPoint]] = {}
        self._trigger_events: List[TriggerEvent] = []
        logger.info("WeatherOracle initialised")

    # ------------------------------------------------------------------
    # OracleInterface integration
    # ------------------------------------------------------------------

    def fetch(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Fetch weather data (called by OracleInterface).

        Args:
            parameters: Must contain 'location' and 'metric'.

        Returns:
            Dict with weather data for aggregation.
        """
        location = parameters.get("location", "")
        metric_str = parameters.get("metric", "temperature_f")

        try:
            metric = WeatherMetric(metric_str)
        except ValueError:
            metric = WeatherMetric.TEMPERATURE_F

        data_point = self.get_current(location, metric)

        return {
            "value": data_point.value,
            "location": location,
            "metric": metric.value,
            "timestamp": data_point.timestamp,
            "source": data_point.source,
            "confidence": data_point.confidence,
        }

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_current(
        self, location: str, metric: WeatherMetric
    ) -> WeatherDataPoint:
        """Get the current weather reading for a location and metric.

        Args:
            location: Geographic location string.
            metric: The weather metric to read.

        Returns:
            WeatherDataPoint with the current reading.
        """
        data_point = self._fetch_weather_data(location, metric)

        # Store in history
        key = f"{location}:{metric.value}"
        if key not in self._data_history:
            self._data_history[key] = []
        self._data_history[key].append(data_point)

        # Check triggers
        self._evaluate_triggers(location, metric, data_point.value)

        return data_point

    def register_trigger(
        self,
        location: str,
        metric: WeatherMetric,
        condition: TriggerCondition,
        threshold: float,
        policy_id: Optional[str] = None,
    ) -> WeatherTrigger:
        """Register a parametric weather trigger.

        Args:
            location: Location to monitor.
            metric: Weather metric to watch.
            condition: Trigger condition (above/below/equals).
            threshold: Threshold value.
            policy_id: Associated insurance policy ID.

        Returns:
            The registered WeatherTrigger.
        """
        trigger_id = f"wtrig-{uuid.uuid4().hex[:10]}"
        trigger = WeatherTrigger(
            trigger_id=trigger_id,
            location=location,
            metric=metric,
            condition=condition,
            threshold=threshold,
            policy_id=policy_id,
        )
        self._triggers[trigger_id] = trigger
        logger.info(
            "Weather trigger registered: %s %s %s %.1f at %s",
            trigger_id, metric.value, condition.value, threshold, location,
        )
        return trigger

    def deactivate_trigger(self, trigger_id: str) -> bool:
        """Deactivate a weather trigger."""
        trigger = self._triggers.get(trigger_id)
        if trigger is None:
            return False
        trigger.active = False
        return True

    def get_trigger_events(
        self, policy_id: Optional[str] = None
    ) -> List[TriggerEvent]:
        """Get trigger events, optionally filtered by policy."""
        if policy_id is None:
            return list(self._trigger_events)
        return [e for e in self._trigger_events if e.policy_id == policy_id]

    def get_history(
        self, location: str, metric: WeatherMetric, limit: int = 100
    ) -> List[WeatherDataPoint]:
        """Get historical weather data."""
        key = f"{location}:{metric.value}"
        history = self._data_history.get(key, [])
        return list(reversed(history[-limit:]))

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _fetch_weather_data(
        self, location: str, metric: WeatherMetric
    ) -> WeatherDataPoint:
        """Fetch current weather data from external API.

        In production, calls to OpenWeatherMap, WeatherAPI, or similar.
        """
        # Placeholder: production implementation calls external weather API
        # using self._credentials for authentication
        return WeatherDataPoint(
            location=location,
            metric=metric,
            value=0.0,
            source="weather_api",
            confidence=0.95,
        )

    def _evaluate_triggers(
        self, location: str, metric: WeatherMetric, value: float
    ) -> None:
        """Evaluate all active triggers for a location/metric pair."""
        for trigger in self._triggers.values():
            if not trigger.active or trigger.triggered:
                continue
            if trigger.location != location or trigger.metric != metric:
                continue

            trigger.last_checked_at = time.time()
            fired = False

            if trigger.condition == TriggerCondition.ABOVE and value > trigger.threshold:
                fired = True
            elif trigger.condition == TriggerCondition.BELOW and value < trigger.threshold:
                fired = True
            elif trigger.condition == TriggerCondition.EQUALS and abs(value - trigger.threshold) < 0.01:
                fired = True

            if fired:
                trigger.triggered = True
                trigger.triggered_at = time.time()
                trigger.triggered_value = value

                event = TriggerEvent(
                    event_id=f"wevt-{uuid.uuid4().hex[:10]}",
                    trigger_id=trigger.trigger_id,
                    location=location,
                    metric=metric,
                    threshold=trigger.threshold,
                    actual_value=value,
                    policy_id=trigger.policy_id,
                )
                self._trigger_events.append(event)

                logger.info(
                    "Weather trigger FIRED: %s %s=%f (threshold=%f) at %s",
                    trigger.trigger_id, metric.value, value, trigger.threshold, location,
                )

                if self._trigger_callback:
                    try:
                        self._trigger_callback(event)
                    except Exception as exc:
                        logger.error("Trigger callback failed: %s", exc)
