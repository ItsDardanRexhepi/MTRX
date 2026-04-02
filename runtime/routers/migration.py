"""Router for universal migration importers."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.migration import MigrationEngine, ImportSource

router = APIRouter()
migration_engine = MigrationEngine()


class ImportRequest(BaseModel):
    source: str
    config: dict
    user_id: str = ""


@router.post("/import")
async def import_config(req: ImportRequest):
    try:
        source = ImportSource(req.source)
    except ValueError:
        raise HTTPException(400, f"Unsupported source: {req.source}")
    result = migration_engine.import_config(source, req.config, req.user_id)
    return result.to_dict()

@router.get("/sources")
async def supported_sources():
    return {"sources": migration_engine.get_supported_sources()}

@router.get("/history")
async def import_history(limit: int = 20):
    return {"imports": migration_engine.get_history(limit)}
