"""
Oracle Aggregator
==================

Multi-source consensus engine to eliminate data manipulation. When
multiple oracle sources provide data, the aggregator compares results
and only accepts values that achieve consensus. Outliers are flagged
and logged for investigation.
"""

from __future__ import annotations

import logging
import statistics
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Consensus thresholds
DEFAULT_MIN_SOURCES: int = 2
DEFAULT_MAX_DEVIATION_PERCENT: float = 2.0  # 2% max deviation for consensus


class ConsensusStatus(Enum):
    """Aggregation consensus outcome."""
    CONSENSUS = "consensus"
    PARTIAL_CONSENSUS = "partial_consensus"
    NO_CONSENSUS = "no_consensus"
    SINGLE_SOURCE = "single_source"
    INSUFFICIENT_SOURCES = "insufficient_sources"


@dataclass
class SourceResult:
    """Result from a single oracle source."""
    source_name: str
    value: Any
    timestamp: float = field(default_factory=time.time)
    confidence: float = 1.0
    response_time_ms: float = 0.0
    is_outlier: bool = False
    deviation_percent: float = 0.0


@dataclass
class AggregationResult:
    """Result of multi-source aggregation."""
    request_id: str
    consensus_status: ConsensusStatus
    final_value: Any
    confidence: float
    sources: List[SourceResult] = field(default_factory=list)
    sources_used: int = 0
    sources_agreed: int = 0
    median_value: Optional[float] = None
    mean_value: Optional[float] = None
    std_deviation: Optional[float] = None
    aggregated_at: float = field(default_factory=time.time)
    outliers: List[SourceResult] = field(default_factory=list)


class OracleAggregator:
    """Multi-source consensus engine for oracle data.

    Compares results from multiple oracle sources and only accepts
    values that achieve consensus. Outliers are flagged for
    investigation. Supports both numeric and categorical data.

    Parameters
    ----------
    min_sources : int
        Minimum sources required for consensus (default 2).
    max_deviation_percent : float
        Maximum allowed deviation from median for numeric data (default 2%).
    source_weights : dict, optional
        Weight multipliers for trusted sources.
    """

    def __init__(
        self,
        min_sources: int = DEFAULT_MIN_SOURCES,
        max_deviation_percent: float = DEFAULT_MAX_DEVIATION_PERCENT,
        source_weights: Optional[Dict[str, float]] = None,
    ) -> None:
        self._min_sources = min_sources
        self._max_deviation = max_deviation_percent
        self._weights = source_weights or {}
        self._aggregation_log: List[AggregationResult] = []
        logger.info(
            "OracleAggregator initialised (min_sources=%d, max_deviation=%.1f%%)",
            min_sources, max_deviation_percent,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def aggregate(
        self,
        request_id: str,
        data_type: Any,
        primary_data: Dict[str, Any],
        additional_sources: Optional[List[Dict[str, Any]]] = None,
    ) -> Any:
        """Aggregate data from multiple sources.

        Args:
            request_id: The oracle request ID.
            data_type: OracleDataType for context.
            primary_data: Data from the primary provider.
            additional_sources: Additional source data for cross-validation.

        Returns:
            OracleResponse-compatible object with consensus result.
        """
        all_sources: List[SourceResult] = []

        # Add primary source
        all_sources.append(SourceResult(
            source_name=primary_data.get("source", "primary"),
            value=primary_data.get("value"),
            confidence=primary_data.get("confidence", 1.0),
        ))

        # Add additional sources
        if additional_sources:
            for src in additional_sources:
                all_sources.append(SourceResult(
                    source_name=src.get("source", "additional"),
                    value=src.get("value"),
                    confidence=src.get("confidence", 0.8),
                ))

        # Determine consensus
        result = self._compute_consensus(request_id, all_sources)
        self._aggregation_log.append(result)

        # Build response compatible with OracleInterface
        from runtime.blockchain.services.oracles.interface import OracleResponse
        return OracleResponse(
            request_id=request_id,
            data_type=data_type,
            value=result.final_value,
            confidence=result.confidence,
            sources_used=result.sources_used,
            sources_agreed=result.sources_agreed,
            stale_after=time.time() + 60,
            raw_sources=[
                {"source": s.source_name, "value": s.value, "confidence": s.confidence}
                for s in result.sources
            ],
        )

    def aggregate_numeric(
        self, request_id: str, values: List[SourceResult]
    ) -> AggregationResult:
        """Aggregate numeric values with outlier detection."""
        return self._compute_consensus(request_id, values)

    def get_aggregation_log(self, limit: int = 100) -> List[AggregationResult]:
        """Return recent aggregation results."""
        return list(reversed(self._aggregation_log[-limit:]))

    def update_source_weight(self, source_name: str, weight: float) -> None:
        """Update the trust weight for a source."""
        self._weights[source_name] = weight
        logger.info("Source weight updated: %s = %.2f", source_name, weight)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _compute_consensus(
        self, request_id: str, sources: List[SourceResult]
    ) -> AggregationResult:
        """Compute consensus across sources."""
        if not sources:
            return AggregationResult(
                request_id=request_id,
                consensus_status=ConsensusStatus.INSUFFICIENT_SOURCES,
                final_value=None,
                confidence=0.0,
            )

        if len(sources) == 1:
            return AggregationResult(
                request_id=request_id,
                consensus_status=ConsensusStatus.SINGLE_SOURCE,
                final_value=sources[0].value,
                confidence=sources[0].confidence * 0.8,
                sources=sources,
                sources_used=1,
                sources_agreed=1,
            )

        # Check if values are numeric
        numeric_values = []
        for s in sources:
            try:
                numeric_values.append(float(s.value))
            except (TypeError, ValueError):
                pass

        if len(numeric_values) == len(sources):
            return self._numeric_consensus(request_id, sources, numeric_values)
        else:
            return self._categorical_consensus(request_id, sources)

    def _numeric_consensus(
        self,
        request_id: str,
        sources: List[SourceResult],
        values: List[float],
    ) -> AggregationResult:
        """Compute consensus for numeric data using median and deviation."""
        median = statistics.median(values)
        mean = statistics.mean(values)
        std_dev = statistics.stdev(values) if len(values) > 1 else 0.0

        agreed: List[SourceResult] = []
        outliers: List[SourceResult] = []

        for source, val in zip(sources, values):
            if median != 0:
                deviation = abs(val - median) / abs(median) * 100
            else:
                deviation = 0.0

            source.deviation_percent = deviation

            if deviation <= self._max_deviation:
                agreed.append(source)
            else:
                source.is_outlier = True
                outliers.append(source)
                logger.warning(
                    "Outlier detected: %s reported %.4f (deviation=%.1f%% from median %.4f)",
                    source.source_name, val, deviation, median,
                )

        # Determine consensus status
        if len(agreed) == len(sources):
            status = ConsensusStatus.CONSENSUS
        elif len(agreed) > len(sources) / 2:
            status = ConsensusStatus.PARTIAL_CONSENSUS
        elif len(sources) < self._min_sources:
            status = ConsensusStatus.INSUFFICIENT_SOURCES
        else:
            status = ConsensusStatus.NO_CONSENSUS

        # Weighted final value
        if agreed:
            weighted_sum = sum(
                float(s.value) * self._weights.get(s.source_name, 1.0)
                for s in agreed
            )
            weight_total = sum(
                self._weights.get(s.source_name, 1.0) for s in agreed
            )
            final = weighted_sum / weight_total
        else:
            final = median

        confidence = len(agreed) / len(sources) if sources else 0.0

        return AggregationResult(
            request_id=request_id,
            consensus_status=status,
            final_value=final,
            confidence=confidence,
            sources=sources,
            sources_used=len(sources),
            sources_agreed=len(agreed),
            median_value=median,
            mean_value=mean,
            std_deviation=std_dev,
            outliers=outliers,
        )

    def _categorical_consensus(
        self, request_id: str, sources: List[SourceResult]
    ) -> AggregationResult:
        """Compute consensus for categorical (non-numeric) data by majority vote."""
        vote_counts: Dict[str, int] = {}
        for s in sources:
            key = str(s.value)
            vote_counts[key] = vote_counts.get(key, 0) + 1

        if not vote_counts:
            return AggregationResult(
                request_id=request_id,
                consensus_status=ConsensusStatus.NO_CONSENSUS,
                final_value=None,
                confidence=0.0,
                sources=sources,
                sources_used=len(sources),
                sources_agreed=0,
            )

        winner = max(vote_counts, key=vote_counts.get)  # type: ignore
        winner_count = vote_counts[winner]
        total = len(sources)

        # Mark outliers
        agreed = []
        outliers = []
        for s in sources:
            if str(s.value) == winner:
                agreed.append(s)
            else:
                s.is_outlier = True
                outliers.append(s)

        if winner_count == total:
            status = ConsensusStatus.CONSENSUS
        elif winner_count > total / 2:
            status = ConsensusStatus.PARTIAL_CONSENSUS
        else:
            status = ConsensusStatus.NO_CONSENSUS

        # Try to convert winner back to original type
        final_value: Any = winner
        for s in agreed:
            final_value = s.value
            break

        return AggregationResult(
            request_id=request_id,
            consensus_status=status,
            final_value=final_value,
            confidence=winner_count / total,
            sources=sources,
            sources_used=total,
            sources_agreed=winner_count,
            outliers=outliers,
        )
