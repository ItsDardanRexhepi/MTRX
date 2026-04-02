"""
Model data types for the marketplace.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional


class ModelProvider(str, Enum):
    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    GOOGLE = "google"
    OLLAMA = "ollama"
    HUGGINGFACE = "huggingface"
    TOGETHER = "together"
    GROQ = "groq"
    OPENROUTER = "openrouter"
    CUSTOM = "custom"


class ModelCategory(str, Enum):
    CHAT = "chat"
    COMPLETION = "completion"
    EMBEDDING = "embedding"
    IMAGE = "image"
    CODE = "code"
    AUDIO = "audio"
    MULTIMODAL = "multimodal"
    REASONING = "reasoning"


class ModelStatus(str, Enum):
    AVAILABLE = "available"
    LOADING = "loading"
    LOADED = "loaded"
    ERROR = "error"
    DEPRECATED = "deprecated"
    UNAVAILABLE = "unavailable"


@dataclass
class ModelPricing:
    """Pricing per 1M tokens (or per request for image models)."""
    input_per_million: float = 0.0
    output_per_million: float = 0.0
    per_request: float = 0.0
    currency: str = "USD"

    def to_dict(self) -> dict:
        return {
            "input_per_million": self.input_per_million,
            "output_per_million": self.output_per_million,
            "per_request": self.per_request,
            "currency": self.currency,
        }

    @classmethod
    def from_dict(cls, data: dict) -> ModelPricing:
        return cls(**{k: data[k] for k in data if k in cls.__dataclass_fields__})


@dataclass
class ModelCapabilities:
    """What a model can do."""
    max_context: int = 4096
    supports_streaming: bool = True
    supports_functions: bool = False
    supports_vision: bool = False
    supports_json_mode: bool = False
    supports_system_prompt: bool = True
    languages: List[str] = field(default_factory=lambda: ["en"])

    def to_dict(self) -> dict:
        return {
            "max_context": self.max_context,
            "supports_streaming": self.supports_streaming,
            "supports_functions": self.supports_functions,
            "supports_vision": self.supports_vision,
            "supports_json_mode": self.supports_json_mode,
            "supports_system_prompt": self.supports_system_prompt,
            "languages": self.languages,
        }

    @classmethod
    def from_dict(cls, data: dict) -> ModelCapabilities:
        return cls(**{k: data[k] for k in data if k in cls.__dataclass_fields__})


@dataclass
class Model:
    """A model available in the marketplace."""
    model_id: str
    name: str
    provider: ModelProvider
    provider_model_id: str         # e.g. "gpt-4o", "claude-sonnet-4-20250514"
    category: ModelCategory
    description: str = ""
    status: ModelStatus = ModelStatus.AVAILABLE
    pricing: ModelPricing = field(default_factory=ModelPricing)
    capabilities: ModelCapabilities = field(default_factory=ModelCapabilities)
    tags: List[str] = field(default_factory=list)
    added_at: float = field(default_factory=time.time)
    total_requests: int = 0
    total_tokens: int = 0
    avg_latency_ms: float = 0.0
    error_rate: float = 0.0
    rating: float = 0.0
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "model_id": self.model_id,
            "name": self.name,
            "provider": self.provider.value,
            "provider_model_id": self.provider_model_id,
            "category": self.category.value,
            "description": self.description,
            "status": self.status.value,
            "pricing": self.pricing.to_dict(),
            "capabilities": self.capabilities.to_dict(),
            "tags": self.tags,
            "added_at": self.added_at,
            "total_requests": self.total_requests,
            "total_tokens": self.total_tokens,
            "avg_latency_ms": round(self.avg_latency_ms, 1),
            "error_rate": round(self.error_rate, 4),
            "rating": round(self.rating, 2),
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, data: dict) -> Model:
        return cls(
            model_id=data["model_id"],
            name=data["name"],
            provider=ModelProvider(data["provider"]),
            provider_model_id=data["provider_model_id"],
            category=ModelCategory(data["category"]),
            description=data.get("description", ""),
            status=ModelStatus(data.get("status", "available")),
            pricing=ModelPricing.from_dict(data.get("pricing", {})),
            capabilities=ModelCapabilities.from_dict(data.get("capabilities", {})),
            tags=data.get("tags", []),
            added_at=data.get("added_at", time.time()),
            total_requests=data.get("total_requests", 0),
            total_tokens=data.get("total_tokens", 0),
            avg_latency_ms=data.get("avg_latency_ms", 0.0),
            error_rate=data.get("error_rate", 0.0),
            rating=data.get("rating", 0.0),
            metadata=data.get("metadata", {}),
        )


@dataclass
class ModelUsageRecord:
    """Record of a model usage event."""
    record_id: str
    model_id: str
    user_id: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_ms: float = 0.0
    success: bool = True
    error: str = ""
    cost_usd: float = 0.0
    timestamp: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        return {
            "record_id": self.record_id,
            "model_id": self.model_id,
            "user_id": self.user_id,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "latency_ms": round(self.latency_ms, 1),
            "success": self.success,
            "error": self.error,
            "cost_usd": round(self.cost_usd, 6),
            "timestamp": self.timestamp,
        }
