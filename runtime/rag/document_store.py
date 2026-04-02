"""
Document Store — manages uploaded documents with chunking and retrieval.

Persists documents to disk, chunks them for search, and provides
a unified interface for agents to query user-uploaded files.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from runtime.rag.chunker import Chunk, chunk_document
from runtime.rag.retriever import Retriever

logger = logging.getLogger(__name__)

SUPPORTED_EXTENSIONS = {".txt", ".md", ".csv", ".json", ".py", ".js", ".sol", ".yaml", ".yml", ".toml", ".log"}


@dataclass
class Document:
    """A stored document."""
    document_id: str
    user_id: str
    filename: str
    content_hash: str
    size_bytes: int
    chunk_count: int = 0
    uploaded_at: float = field(default_factory=time.time)
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "document_id": self.document_id,
            "user_id": self.user_id,
            "filename": self.filename,
            "content_hash": self.content_hash,
            "size_bytes": self.size_bytes,
            "chunk_count": self.chunk_count,
            "uploaded_at": self.uploaded_at,
            "metadata": self.metadata,
        }


class DocumentStore:
    """
    Manages document upload, storage, chunking, and retrieval.

    Documents are stored as files on disk. An in-memory BM25 index
    enables fast semantic search across all uploaded documents.
    """

    def __init__(self, storage_dir: str = "") -> None:
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "documents"
            )
        self._storage_dir = Path(storage_dir)
        self._docs_dir = self._storage_dir / "files"
        self._index_dir = self._storage_dir / "index"
        self._docs_dir.mkdir(parents=True, exist_ok=True)
        self._index_dir.mkdir(parents=True, exist_ok=True)

        self._documents: Dict[str, Document] = {}
        self._retriever = Retriever()
        self._counter: int = 0
        self._load_index()
        logger.info("DocumentStore initialised | dir=%s", self._storage_dir)

    def upload(
        self,
        user_id: str,
        filename: str,
        content: str,
        metadata: Optional[dict] = None,
    ) -> Document:
        """
        Upload and index a document.

        Args:
            user_id: Owner of the document.
            filename: Original filename.
            content: Document text content.
            metadata: Optional metadata.

        Returns:
            The created Document.
        """
        ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ".txt"
        if ext not in SUPPORTED_EXTENSIONS:
            raise ValueError(f"Unsupported file type: {ext}")
        if not content.strip():
            raise ValueError("Document content is empty.")

        content_hash = hashlib.sha256(content.encode()).hexdigest()[:16]

        # Check for duplicate
        for doc in self._documents.values():
            if doc.user_id == user_id and doc.content_hash == content_hash:
                logger.info("Duplicate document skipped | hash=%s", content_hash)
                return doc

        self._counter += 1
        doc_id = f"DOC-{self._counter:08d}"

        # Store file
        file_path = self._docs_dir / f"{doc_id}{ext}"
        file_path.write_text(content, encoding="utf-8")

        # Chunk and index
        chunks = chunk_document(doc_id, content, filename)
        self._retriever.index_chunks(chunks)

        doc = Document(
            document_id=doc_id,
            user_id=user_id,
            filename=filename,
            content_hash=content_hash,
            size_bytes=len(content.encode()),
            chunk_count=len(chunks),
            metadata=metadata or {},
        )
        self._documents[doc_id] = doc
        self._save_index()

        logger.info(
            "Document uploaded | id=%s | file=%s | chunks=%d | size=%d",
            doc_id, filename, len(chunks), doc.size_bytes,
        )
        return doc

    def delete(self, document_id: str) -> bool:
        """Delete a document and remove from index."""
        doc = self._documents.get(document_id)
        if doc is None:
            return False

        self._retriever.remove_document(document_id)
        del self._documents[document_id]

        # Remove file
        for f in self._docs_dir.glob(f"{document_id}.*"):
            f.unlink(missing_ok=True)

        self._save_index()
        logger.info("Document deleted | id=%s", document_id)
        return True

    def search(
        self,
        query: str,
        user_id: Optional[str] = None,
        document_id: Optional[str] = None,
        top_k: int = 5,
    ) -> List[Tuple[Chunk, float]]:
        """Search across all documents or filter by user/document."""
        if user_id and not document_id:
            # Search across all user's documents
            results = []
            for doc in self._documents.values():
                if doc.user_id == user_id:
                    results.extend(
                        self._retriever.search(query, top_k=top_k, document_id=doc.document_id)
                    )
            results.sort(key=lambda x: x[1], reverse=True)
            return results[:top_k]

        return self._retriever.search(query, top_k=top_k, document_id=document_id)

    def get_context(
        self,
        query: str,
        user_id: Optional[str] = None,
        document_id: Optional[str] = None,
        top_k: int = 3,
        max_chars: int = 2000,
    ) -> str:
        """Get formatted context for agent prompt injection."""
        if user_id and not document_id:
            results = self.search(query, user_id=user_id, top_k=top_k)
            if not results:
                return ""
            lines = ["[Document Context]"]
            for chunk, score in results:
                doc = self._documents.get(chunk.document_id)
                fname = doc.filename if doc else "unknown"
                lines.append(f"- [{fname}] {chunk.content}")
            return "\n".join(lines)[:max_chars]
        return self._retriever.get_context(query, top_k=top_k, document_id=document_id, max_chars=max_chars)

    def get_document(self, document_id: str) -> Optional[Document]:
        """Get document metadata."""
        return self._documents.get(document_id)

    def get_document_content(self, document_id: str) -> Optional[str]:
        """Read document content from disk."""
        for f in self._docs_dir.glob(f"{document_id}.*"):
            return f.read_text(encoding="utf-8")
        return None

    def list_documents(self, user_id: Optional[str] = None) -> List[Document]:
        """List documents, optionally filtered by user."""
        docs = list(self._documents.values())
        if user_id:
            docs = [d for d in docs if d.user_id == user_id]
        return docs

    def get_stats(self) -> dict:
        """Get store statistics."""
        return {
            "total_documents": len(self._documents),
            "retriever": self._retriever.get_stats(),
        }

    def _save_index(self) -> None:
        """Save document metadata index."""
        path = self._index_dir / "documents.json"
        data = {doc_id: doc.to_dict() for doc_id, doc in self._documents.items()}
        try:
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
        except Exception:
            logger.exception("Failed to save document index.")

    def _load_index(self) -> None:
        """Load document metadata and rebuild search index."""
        path = self._index_dir / "documents.json"
        if not path.exists():
            return
        try:
            with open(path) as f:
                data = json.load(f)
            for doc_id, doc_data in data.items():
                doc = Document(**doc_data)
                self._documents[doc_id] = doc
                num = int(doc_id.split("-")[1])
                self._counter = max(self._counter, num)
                # Re-chunk and index from file
                content = self.get_document_content(doc_id)
                if content:
                    chunks = chunk_document(doc_id, content, doc.filename)
                    self._retriever.index_chunks(chunks)
            logger.info("Loaded %d documents from index.", len(self._documents))
        except Exception:
            logger.exception("Failed to load document index.")
