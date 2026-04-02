"""
Model Marketplace — browse, compare, load, and track models.

Pre-populates with known models from major providers.
Supports adding custom/self-hosted models.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Dict, List, Optional

from runtime.models.model_types import (
    Model, ModelCapabilities, ModelCategory, ModelPricing,
    ModelProvider, ModelStatus, ModelUsageRecord,
)

logger = logging.getLogger(__name__)


# Pre-populated model catalog
_DEFAULT_MODELS = [
    # OpenAI
    {
        "name": "GPT-4o", "provider": "openai", "provider_model_id": "gpt-4o",
        "category": "multimodal", "description": "OpenAI's flagship multimodal model",
        "pricing": {"input_per_million": 2.50, "output_per_million": 10.00},
        "capabilities": {"max_context": 128000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["flagship", "multimodal", "fast"],
    },
    {
        "name": "GPT-4o Mini", "provider": "openai", "provider_model_id": "gpt-4o-mini",
        "category": "chat", "description": "Small, fast, affordable model",
        "pricing": {"input_per_million": 0.15, "output_per_million": 0.60},
        "capabilities": {"max_context": 128000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["fast", "cheap", "mini"],
    },
    {
        "name": "o3", "provider": "openai", "provider_model_id": "o3",
        "category": "reasoning", "description": "OpenAI reasoning model",
        "pricing": {"input_per_million": 10.00, "output_per_million": 40.00},
        "capabilities": {"max_context": 200000, "supports_functions": True, "supports_json_mode": True},
        "tags": ["reasoning", "smart"],
    },
    # Anthropic
    {
        "name": "Claude Opus 4", "provider": "anthropic", "provider_model_id": "claude-opus-4-20250514",
        "category": "reasoning", "description": "Anthropic's most capable model for complex reasoning",
        "pricing": {"input_per_million": 15.00, "output_per_million": 75.00},
        "capabilities": {"max_context": 200000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["flagship", "reasoning", "coding"],
    },
    {
        "name": "Claude Sonnet 4", "provider": "anthropic", "provider_model_id": "claude-sonnet-4-20250514",
        "category": "chat", "description": "High performance with balanced speed and intelligence",
        "pricing": {"input_per_million": 3.00, "output_per_million": 15.00},
        "capabilities": {"max_context": 200000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["balanced", "fast", "coding"],
    },
    {
        "name": "Claude Haiku 3.5", "provider": "anthropic", "provider_model_id": "claude-haiku-4-5-20251001",
        "category": "chat", "description": "Fast, compact model for quick tasks",
        "pricing": {"input_per_million": 0.80, "output_per_million": 4.00},
        "capabilities": {"max_context": 200000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["fast", "cheap", "mini"],
    },
    # Google
    {
        "name": "Gemini 2.5 Pro", "provider": "google", "provider_model_id": "gemini-2.5-pro",
        "category": "multimodal", "description": "Google's most capable thinking model",
        "pricing": {"input_per_million": 1.25, "output_per_million": 10.00},
        "capabilities": {"max_context": 1000000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["flagship", "long-context", "multimodal"],
    },
    {
        "name": "Gemini 2.5 Flash", "provider": "google", "provider_model_id": "gemini-2.5-flash",
        "category": "chat", "description": "Fast, efficient workhorse model",
        "pricing": {"input_per_million": 0.15, "output_per_million": 0.60},
        "capabilities": {"max_context": 1000000, "supports_functions": True, "supports_vision": True, "supports_json_mode": True},
        "tags": ["fast", "cheap", "long-context"],
    },
    # Ollama (local)
    {
        "name": "Llama 3.1 70B", "provider": "ollama", "provider_model_id": "llama3.1:70b",
        "category": "chat", "description": "Meta's open-source 70B parameter model (local)",
        "pricing": {},
        "capabilities": {"max_context": 131072, "supports_functions": True},
        "tags": ["open-source", "local", "free"],
    },
    {
        "name": "Mistral Large", "provider": "ollama", "provider_model_id": "mistral-large:latest",
        "category": "chat", "description": "Mistral's large model (local via Ollama)",
        "pricing": {},
        "capabilities": {"max_context": 128000, "supports_functions": True},
        "tags": ["open-source", "local", "free"],
    },
    {
        "name": "DeepSeek R1", "provider": "ollama", "provider_model_id": "deepseek-r1:latest",
        "category": "reasoning", "description": "DeepSeek's reasoning model (local)",
        "pricing": {},
        "capabilities": {"max_context": 65536},
        "tags": ["open-source", "local", "reasoning", "free"],
    },
    # Together AI
    {
        "name": "Llama 3.1 405B (Together)", "provider": "together", "provider_model_id": "meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
        "category": "chat", "description": "Meta's largest open model via Together AI",
        "pricing": {"input_per_million": 3.50, "output_per_million": 3.50},
        "capabilities": {"max_context": 131072, "supports_functions": True},
        "tags": ["open-source", "large", "hosted"],
    },
    # Groq
    {
        "name": "Llama 3.3 70B (Groq)", "provider": "groq", "provider_model_id": "llama-3.3-70b-versatile",
        "category": "chat", "description": "Llama 3.3 70B on Groq inference hardware",
        "pricing": {"input_per_million": 0.59, "output_per_million": 0.79},
        "capabilities": {"max_context": 131072, "supports_functions": True, "supports_json_mode": True},
        "tags": ["fast", "open-source", "groq"],
    },
]


class ModelMarketplace:
    """
    Model marketplace for browsing, comparing, and loading models.

    Pre-populated with major provider models. Supports custom models,
    usage tracking, cost calculation, and performance metrics.
    """

    def __init__(self, storage_dir: str = "") -> None:
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "models"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._models: Dict[str, Model] = {}
        self._loaded: Dict[str, str] = {}  # user_id -> model_id currently loaded
        self._usage: List[ModelUsageRecord] = []
        self._counter: int = 0
        self._usage_counter: int = 0
        self._load_catalog()
        logger.info("ModelMarketplace initialised | models=%d", len(self._models))

    # ── Browsing ─────────────────────────────────────────────────────

    def list_models(
        self,
        provider: Optional[ModelProvider] = None,
        category: Optional[ModelCategory] = None,
        tags: Optional[List[str]] = None,
        search: str = "",
        sort_by: str = "name",
    ) -> List[Model]:
        """Browse available models with optional filters."""
        models = list(self._models.values())

        if provider:
            models = [m for m in models if m.provider == provider]
        if category:
            models = [m for m in models if m.category == category]
        if tags:
            models = [m for m in models if any(t in m.tags for t in tags)]
        if search:
            q = search.lower()
            models = [
                m for m in models
                if q in m.name.lower() or q in m.description.lower()
                or q in m.provider_model_id.lower()
                or any(q in t for t in m.tags)
            ]

        if sort_by == "price":
            models.sort(key=lambda m: m.pricing.input_per_million)
        elif sort_by == "context":
            models.sort(key=lambda m: m.capabilities.max_context, reverse=True)
        elif sort_by == "popular":
            models.sort(key=lambda m: m.total_requests, reverse=True)
        elif sort_by == "rating":
            models.sort(key=lambda m: m.rating, reverse=True)
        else:
            models.sort(key=lambda m: m.name)

        return models

    def get_model(self, model_id: str) -> Optional[Model]:
        return self._models.get(model_id)

    def get_model_by_provider_id(self, provider_model_id: str) -> Optional[Model]:
        """Look up model by provider's model ID (e.g., 'gpt-4o')."""
        for m in self._models.values():
            if m.provider_model_id == provider_model_id:
                return m
        return None

    def compare_models(self, model_ids: List[str]) -> List[dict]:
        """Compare multiple models side by side."""
        comparison = []
        for mid in model_ids:
            model = self._models.get(mid)
            if model:
                comparison.append({
                    "model_id": model.model_id,
                    "name": model.name,
                    "provider": model.provider.value,
                    "category": model.category.value,
                    "max_context": model.capabilities.max_context,
                    "input_price": model.pricing.input_per_million,
                    "output_price": model.pricing.output_per_million,
                    "supports_vision": model.capabilities.supports_vision,
                    "supports_functions": model.capabilities.supports_functions,
                    "avg_latency_ms": model.avg_latency_ms,
                    "total_requests": model.total_requests,
                    "rating": model.rating,
                })
        return comparison

    # ── Loading ───────────────────────────────────────────────────────

    def load_model(self, user_id: str, model_id: str) -> Model:
        """Set a model as the active model for a user."""
        model = self._models.get(model_id)
        if model is None:
            raise ValueError(f"Model {model_id} not found.")
        if model.status == ModelStatus.DEPRECATED:
            raise ValueError(f"Model {model.name} is deprecated.")

        self._loaded[user_id] = model_id
        model.status = ModelStatus.LOADED
        logger.info("Model loaded | user=%s | model=%s (%s)",
                     user_id, model.name, model.provider_model_id)
        return model

    def get_loaded_model(self, user_id: str) -> Optional[Model]:
        """Get the currently loaded model for a user."""
        model_id = self._loaded.get(user_id)
        if model_id:
            return self._models.get(model_id)
        return None

    def unload_model(self, user_id: str) -> bool:
        if user_id in self._loaded:
            del self._loaded[user_id]
            return True
        return False

    # ── Custom Models ────────────────────────────────────────────────

    def add_model(
        self,
        name: str,
        provider: ModelProvider,
        provider_model_id: str,
        category: ModelCategory,
        description: str = "",
        pricing: Optional[ModelPricing] = None,
        capabilities: Optional[ModelCapabilities] = None,
        tags: Optional[List[str]] = None,
        metadata: Optional[dict] = None,
    ) -> Model:
        """Add a custom model to the marketplace."""
        self._counter += 1
        model_id = f"MDL-{self._counter:08d}"

        model = Model(
            model_id=model_id,
            name=name,
            provider=provider,
            provider_model_id=provider_model_id,
            category=category,
            description=description,
            pricing=pricing or ModelPricing(),
            capabilities=capabilities or ModelCapabilities(),
            tags=tags or [],
            metadata=metadata or {},
        )
        self._models[model_id] = model
        self._save_catalog()
        logger.info("Custom model added | id=%s | name=%s", model_id, name)
        return model

    def remove_model(self, model_id: str) -> bool:
        if model_id in self._models:
            del self._models[model_id]
            self._save_catalog()
            return True
        return False

    # ── Usage Tracking ───────────────────────────────────────────────

    def record_usage(
        self,
        model_id: str,
        user_id: str,
        input_tokens: int = 0,
        output_tokens: int = 0,
        latency_ms: float = 0.0,
        success: bool = True,
        error: str = "",
    ) -> ModelUsageRecord:
        """Record a model usage event."""
        model = self._models.get(model_id)

        # Calculate cost
        cost = 0.0
        if model:
            cost = (
                input_tokens * model.pricing.input_per_million / 1_000_000
                + output_tokens * model.pricing.output_per_million / 1_000_000
                + model.pricing.per_request
            )

        self._usage_counter += 1
        record = ModelUsageRecord(
            record_id=f"USE-{self._usage_counter:08d}",
            model_id=model_id,
            user_id=user_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=latency_ms,
            success=success,
            error=error,
            cost_usd=cost,
        )
        self._usage.append(record)
        if len(self._usage) > 10000:
            self._usage = self._usage[-5000:]

        # Update model stats
        if model:
            model.total_requests += 1
            model.total_tokens += input_tokens + output_tokens
            # Running average latency
            if model.total_requests == 1:
                model.avg_latency_ms = latency_ms
            else:
                model.avg_latency_ms = (
                    model.avg_latency_ms * 0.95 + latency_ms * 0.05
                )
            # Error rate
            if not success:
                total = model.total_requests
                model.error_rate = (model.error_rate * (total - 1) + 1.0) / total

        return record

    def get_usage(
        self, user_id: str = "", model_id: str = "", limit: int = 50,
    ) -> List[dict]:
        records = self._usage
        if user_id:
            records = [r for r in records if r.user_id == user_id]
        if model_id:
            records = [r for r in records if r.model_id == model_id]
        return [r.to_dict() for r in records[-limit:]]

    def get_cost_summary(self, user_id: str = "") -> dict:
        records = self._usage
        if user_id:
            records = [r for r in records if r.user_id == user_id]
        total_cost = sum(r.cost_usd for r in records)
        total_tokens = sum(r.input_tokens + r.output_tokens for r in records)
        by_model = {}
        for r in records:
            if r.model_id not in by_model:
                by_model[r.model_id] = {"cost": 0.0, "requests": 0}
            by_model[r.model_id]["cost"] += r.cost_usd
            by_model[r.model_id]["requests"] += 1
        return {
            "total_cost_usd": round(total_cost, 4),
            "total_tokens": total_tokens,
            "total_requests": len(records),
            "by_model": by_model,
        }

    # ── Stats ────────────────────────────────────────────────────────

    def get_stats(self) -> dict:
        by_provider = {}
        for m in self._models.values():
            by_provider[m.provider.value] = by_provider.get(m.provider.value, 0) + 1
        return {
            "total_models": len(self._models),
            "by_provider": by_provider,
            "loaded_users": len(self._loaded),
            "total_usage_records": len(self._usage),
        }

    # ── Persistence ──────────────────────────────────────────────────

    def _save_catalog(self) -> None:
        path = self._storage_dir / "catalog.json"
        data = {mid: m.to_dict() for mid, m in self._models.items()}
        try:
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
        except Exception:
            logger.exception("Failed to save model catalog.")

    def _load_catalog(self) -> None:
        path = self._storage_dir / "catalog.json"
        if path.exists():
            try:
                with open(path) as f:
                    data = json.load(f)
                for mid, mdata in data.items():
                    self._models[mid] = Model.from_dict(mdata)
                    num = int(mid.split("-")[1])
                    self._counter = max(self._counter, num)
                logger.info("Loaded %d models from catalog.", len(self._models))
                return
            except Exception:
                logger.exception("Failed to load catalog, using defaults.")

        # Populate with defaults
        for i, mdef in enumerate(_DEFAULT_MODELS, 1):
            mid = f"MDL-{i:08d}"
            self._counter = i
            model = Model(
                model_id=mid,
                name=mdef["name"],
                provider=ModelProvider(mdef["provider"]),
                provider_model_id=mdef["provider_model_id"],
                category=ModelCategory(mdef["category"]),
                description=mdef.get("description", ""),
                pricing=ModelPricing.from_dict(mdef.get("pricing", {})),
                capabilities=ModelCapabilities.from_dict(mdef.get("capabilities", {})),
                tags=mdef.get("tags", []),
            )
            self._models[mid] = model
        self._save_catalog()
        logger.info("Populated default model catalog with %d models.", len(self._models))
