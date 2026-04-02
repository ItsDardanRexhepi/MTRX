"""
Retriever — searches document chunks using TF-IDF similarity.

No external vector DB dependency. Uses in-memory inverted index
with BM25-inspired scoring for fast retrieval.
"""

from __future__ import annotations

import logging
import math
import re
from collections import Counter, defaultdict
from typing import Dict, List, Optional, Tuple

from runtime.rag.chunker import Chunk

logger = logging.getLogger(__name__)


def _tokenize(text: str) -> List[str]:
    """Simple whitespace + punctuation tokenizer with lowercasing."""
    return re.findall(r'\b[a-z0-9]+\b', text.lower())


class Retriever:
    """
    BM25-based document chunk retriever.

    Maintains an inverted index of all indexed chunks.
    No external dependencies — pure Python implementation.
    """

    # BM25 parameters
    K1: float = 1.5
    B: float = 0.75

    def __init__(self) -> None:
        self._chunks: Dict[str, Chunk] = {}
        self._index: Dict[str, set] = defaultdict(set)  # term -> set of chunk_ids
        self._doc_freqs: Dict[str, int] = defaultdict(int)  # term -> num docs containing
        self._chunk_lengths: Dict[str, int] = {}
        self._chunk_terms: Dict[str, Counter] = {}
        self._avg_length: float = 0.0
        self._total_chunks: int = 0
        logger.info("Retriever initialised.")

    def index_chunks(self, chunks: List[Chunk]) -> int:
        """
        Add chunks to the search index.

        Returns:
            Number of chunks indexed.
        """
        for chunk in chunks:
            if chunk.chunk_id in self._chunks:
                continue
            self._chunks[chunk.chunk_id] = chunk
            tokens = _tokenize(chunk.content)
            term_counts = Counter(tokens)
            self._chunk_terms[chunk.chunk_id] = term_counts
            self._chunk_lengths[chunk.chunk_id] = len(tokens)

            for term in set(tokens):
                self._index[term].add(chunk.chunk_id)
                self._doc_freqs[term] += 1

        self._total_chunks = len(self._chunks)
        if self._total_chunks > 0:
            self._avg_length = sum(self._chunk_lengths.values()) / self._total_chunks

        logger.info("Indexed %d chunks | total=%d", len(chunks), self._total_chunks)
        return len(chunks)

    def remove_document(self, document_id: str) -> int:
        """Remove all chunks for a document from the index."""
        to_remove = [
            cid for cid, c in self._chunks.items()
            if c.document_id == document_id
        ]
        for cid in to_remove:
            terms = self._chunk_terms.pop(cid, Counter())
            for term in terms:
                self._index[term].discard(cid)
                self._doc_freqs[term] = max(0, self._doc_freqs[term] - 1)
            self._chunk_lengths.pop(cid, None)
            del self._chunks[cid]

        self._total_chunks = len(self._chunks)
        if self._total_chunks > 0:
            self._avg_length = sum(self._chunk_lengths.values()) / self._total_chunks
        else:
            self._avg_length = 0.0

        logger.info("Removed %d chunks for doc=%s", len(to_remove), document_id)
        return len(to_remove)

    def search(
        self,
        query: str,
        top_k: int = 5,
        document_id: Optional[str] = None,
        min_score: float = 0.0,
    ) -> List[Tuple[Chunk, float]]:
        """
        Search for chunks relevant to a query using BM25 scoring.

        Args:
            query: Search query.
            top_k: Maximum results.
            document_id: Restrict to a specific document.
            min_score: Minimum relevance score.

        Returns:
            List of (Chunk, score) tuples sorted by relevance.
        """
        query_terms = _tokenize(query)
        if not query_terms:
            return []

        scores: Dict[str, float] = defaultdict(float)
        n = self._total_chunks
        if n == 0:
            return []

        for term in query_terms:
            if term not in self._index:
                continue
            df = self._doc_freqs[term]
            idf = math.log((n - df + 0.5) / (df + 0.5) + 1.0)

            for cid in self._index[term]:
                if document_id and self._chunks[cid].document_id != document_id:
                    continue
                tf = self._chunk_terms[cid][term]
                dl = self._chunk_lengths[cid]
                numerator = tf * (self.K1 + 1)
                denominator = tf + self.K1 * (1 - self.B + self.B * dl / max(self._avg_length, 1))
                scores[cid] += idf * (numerator / denominator)

        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        results = []
        for cid, score in ranked[:top_k]:
            if score >= min_score:
                results.append((self._chunks[cid], score))

        return results

    def get_context(
        self,
        query: str,
        top_k: int = 3,
        document_id: Optional[str] = None,
        max_chars: int = 2000,
    ) -> str:
        """
        Get formatted context string for injecting into agent prompts.

        Args:
            query: The user's question.
            top_k: Number of chunks to include.
            document_id: Restrict to specific document.
            max_chars: Maximum output length.

        Returns:
            Formatted context string.
        """
        results = self.search(query, top_k=top_k, document_id=document_id)
        if not results:
            return ""

        lines = ["[Document Context]"]
        total = 0
        for chunk, score in results:
            header = chunk.metadata.get("header", "")
            prefix = f"[{header}] " if header else ""
            entry = f"- {prefix}{chunk.content}"
            if total + len(entry) > max_chars:
                break
            lines.append(entry)
            total += len(entry)

        return "\n".join(lines)

    def get_stats(self) -> dict:
        """Get index statistics."""
        return {
            "total_chunks": self._total_chunks,
            "unique_terms": len(self._index),
            "avg_chunk_length": round(self._avg_length, 1),
        }
