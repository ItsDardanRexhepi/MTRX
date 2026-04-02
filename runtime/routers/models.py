"""Router for model marketplace."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from runtime.models import ModelMarketplace, ModelProvider, ModelCategory

router = APIRouter()
marketplace = ModelMarketplace()


class LoadModelRequest(BaseModel):
    user_id: str
    model_id: str

class AddModelRequest(BaseModel):
    name: str
    provider: str
    provider_model_id: str
    category: str
    description: str = ""
    tags: List[str] = []

class RecordUsageRequest(BaseModel):
    model_id: str
    user_id: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_ms: float = 0.0
    success: bool = True
    error: str = ""


@router.get("/list")
async def list_models(
    provider: Optional[str] = None,
    category: Optional[str] = None,
    search: str = "",
    sort_by: str = "name",
):
    p = ModelProvider(provider) if provider else None
    c = ModelCategory(category) if category else None
    models = marketplace.list_models(provider=p, category=c, search=search, sort_by=sort_by)
    return {"models": [m.to_dict() for m in models]}

@router.get("/model/{model_id}")
async def get_model(model_id: str):
    model = marketplace.get_model(model_id)
    if model is None:
        raise HTTPException(404, "Model not found.")
    return model.to_dict()

@router.get("/lookup/{provider_model_id:path}")
async def lookup_model(provider_model_id: str):
    model = marketplace.get_model_by_provider_id(provider_model_id)
    if model is None:
        raise HTTPException(404, "Model not found.")
    return model.to_dict()

@router.post("/compare")
async def compare_models(model_ids: List[str]):
    return {"comparison": marketplace.compare_models(model_ids)}

@router.post("/load")
async def load_model(req: LoadModelRequest):
    try:
        model = marketplace.load_model(req.user_id, req.model_id)
        return {"status": "loaded", "model": model.to_dict()}
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.get("/loaded/{user_id}")
async def get_loaded(user_id: str):
    model = marketplace.get_loaded_model(user_id)
    if model is None:
        return {"model": None}
    return {"model": model.to_dict()}

@router.post("/unload/{user_id}")
async def unload(user_id: str):
    ok = marketplace.unload_model(user_id)
    return {"status": "unloaded" if ok else "no_model_loaded"}

@router.post("/add")
async def add_model(req: AddModelRequest):
    model = marketplace.add_model(
        name=req.name, provider=ModelProvider(req.provider),
        provider_model_id=req.provider_model_id,
        category=ModelCategory(req.category),
        description=req.description, tags=req.tags,
    )
    return model.to_dict()

@router.delete("/{model_id}")
async def remove_model(model_id: str):
    ok = marketplace.remove_model(model_id)
    if not ok:
        raise HTTPException(404, "Model not found.")
    return {"status": "removed"}

@router.post("/usage")
async def record_usage(req: RecordUsageRequest):
    record = marketplace.record_usage(
        model_id=req.model_id, user_id=req.user_id,
        input_tokens=req.input_tokens, output_tokens=req.output_tokens,
        latency_ms=req.latency_ms, success=req.success, error=req.error,
    )
    return record.to_dict()

@router.get("/usage/history")
async def usage_history(user_id: str = "", model_id: str = "", limit: int = 50):
    return {"usage": marketplace.get_usage(user_id, model_id, limit)}

@router.get("/costs")
async def cost_summary(user_id: str = ""):
    return marketplace.get_cost_summary(user_id)

@router.get("/stats/summary")
async def model_stats():
    return marketplace.get_stats()
