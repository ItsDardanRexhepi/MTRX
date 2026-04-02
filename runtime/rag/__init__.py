"""
Document RAG — users upload files and agents reference them in answers.

Supports PDF, TXT, MD, CSV, JSON. Chunks documents, builds a searchable
index, and retrieves relevant context for agent queries.
"""

from runtime.rag.document_store import DocumentStore
from runtime.rag.chunker import chunk_document
from runtime.rag.retriever import Retriever

__all__ = ["DocumentStore", "chunk_document", "Retriever"]
