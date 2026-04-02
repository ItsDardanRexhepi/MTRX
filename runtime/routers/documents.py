"""Router for document RAG system."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

from runtime.rag import DocumentStore

router = APIRouter()
doc_store = DocumentStore()


class UploadRequest(BaseModel):
    user_id: str
    filename: str
    content: str
    metadata: Optional[dict] = None

class SearchRequest(BaseModel):
    query: str
    user_id: Optional[str] = None
    document_id: Optional[str] = None
    top_k: int = 5

class ContextRequest(BaseModel):
    query: str
    user_id: Optional[str] = None
    document_id: Optional[str] = None
    top_k: int = 3
    max_chars: int = 2000


@router.post("/upload")
async def upload(req: UploadRequest):
    try:
        doc = doc_store.upload(
            user_id=req.user_id, filename=req.filename,
            content=req.content, metadata=req.metadata,
        )
        return doc.to_dict()
    except ValueError as e:
        raise HTTPException(400, str(e))

@router.delete("/{document_id}")
async def delete(document_id: str):
    ok = doc_store.delete(document_id)
    if not ok:
        raise HTTPException(404, "Document not found.")
    return {"status": "deleted"}

@router.post("/search")
async def search(req: SearchRequest):
    results = doc_store.search(
        query=req.query, user_id=req.user_id,
        document_id=req.document_id, top_k=req.top_k,
    )
    return {
        "results": [
            {"chunk_id": c.chunk_id, "content": c.content, "score": round(s, 4), "document_id": c.document_id}
            for c, s in results
        ]
    }

@router.post("/context")
async def context(req: ContextRequest):
    ctx = doc_store.get_context(
        query=req.query, user_id=req.user_id,
        document_id=req.document_id, top_k=req.top_k, max_chars=req.max_chars,
    )
    return {"context": ctx}

@router.get("/{document_id}")
async def get_document(document_id: str):
    doc = doc_store.get_document(document_id)
    if doc is None:
        raise HTTPException(404, "Document not found.")
    return doc.to_dict()

@router.get("/{document_id}/content")
async def get_content(document_id: str):
    content = doc_store.get_document_content(document_id)
    if content is None:
        raise HTTPException(404, "Document not found.")
    return {"content": content}

@router.get("/user/{user_id}")
async def list_user_documents(user_id: str):
    docs = doc_store.list_documents(user_id)
    return {"documents": [d.to_dict() for d in docs]}

@router.get("/all/list")
async def list_all():
    docs = doc_store.list_documents()
    return {"documents": [d.to_dict() for d in docs]}

@router.get("/stats/summary")
async def doc_stats():
    return doc_store.get_stats()
