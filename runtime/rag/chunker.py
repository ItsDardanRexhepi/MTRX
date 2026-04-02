"""
Document Chunker — splits documents into searchable chunks.

Supports multiple file formats. Uses overlap for context continuity.
"""

from __future__ import annotations

import csv
import io
import json
import logging
import re
from dataclasses import dataclass, field
from typing import List

logger = logging.getLogger(__name__)

DEFAULT_CHUNK_SIZE: int = 512     # Characters per chunk
DEFAULT_OVERLAP: int = 64         # Overlap between chunks


@dataclass
class Chunk:
    """A searchable chunk of a document."""
    chunk_id: str
    document_id: str
    content: str
    index: int                    # Position in document
    metadata: dict = field(default_factory=dict)


def chunk_document(
    document_id: str,
    content: str,
    filename: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_OVERLAP,
) -> List[Chunk]:
    """
    Split document content into overlapping chunks.

    Auto-detects format from filename extension and uses
    appropriate splitting strategy.
    """
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "txt"

    if ext == "json":
        text = _extract_json(content)
    elif ext == "csv":
        text = _extract_csv(content)
    elif ext == "md":
        return _chunk_markdown(document_id, content, chunk_size)
    else:
        text = content

    return _chunk_text(document_id, text, chunk_size, overlap)


def _chunk_text(
    doc_id: str, text: str, chunk_size: int, overlap: int,
) -> List[Chunk]:
    """Split plain text into overlapping chunks at sentence boundaries."""
    sentences = re.split(r'(?<=[.!?])\s+', text)
    chunks = []
    current = ""
    idx = 0

    for sentence in sentences:
        if len(current) + len(sentence) > chunk_size and current:
            chunks.append(Chunk(
                chunk_id=f"{doc_id}-C{idx:04d}",
                document_id=doc_id,
                content=current.strip(),
                index=idx,
            ))
            idx += 1
            # Keep overlap from end of current chunk
            if overlap > 0:
                current = current[-overlap:] + " " + sentence
            else:
                current = sentence
        else:
            current = (current + " " + sentence).strip()

    if current.strip():
        chunks.append(Chunk(
            chunk_id=f"{doc_id}-C{idx:04d}",
            document_id=doc_id,
            content=current.strip(),
            index=idx,
        ))

    logger.info("Chunked text | doc=%s | chunks=%d", doc_id, len(chunks))
    return chunks


def _chunk_markdown(doc_id: str, content: str, chunk_size: int) -> List[Chunk]:
    """Split markdown by headers, then by size."""
    sections = re.split(r'\n(?=#{1,3}\s)', content)
    chunks = []
    idx = 0

    for section in sections:
        section = section.strip()
        if not section:
            continue
        # Extract header for metadata
        header_match = re.match(r'^(#{1,3})\s+(.+)', section)
        header = header_match.group(2) if header_match else ""

        if len(section) <= chunk_size:
            chunks.append(Chunk(
                chunk_id=f"{doc_id}-C{idx:04d}",
                document_id=doc_id,
                content=section,
                index=idx,
                metadata={"header": header},
            ))
            idx += 1
        else:
            sub_chunks = _chunk_text(doc_id, section, chunk_size, 32)
            for sc in sub_chunks:
                sc.chunk_id = f"{doc_id}-C{idx:04d}"
                sc.metadata = {"header": header}
                chunks.append(sc)
                idx += 1

    return chunks


def _extract_json(content: str) -> str:
    """Convert JSON to readable text."""
    try:
        data = json.loads(content)
        return json.dumps(data, indent=2, ensure_ascii=False)
    except json.JSONDecodeError:
        return content


def _extract_csv(content: str) -> str:
    """Convert CSV to readable text."""
    reader = csv.reader(io.StringIO(content))
    rows = list(reader)
    if not rows:
        return content
    lines = []
    headers = rows[0] if rows else []
    for row in rows[1:]:
        parts = [f"{h}: {v}" for h, v in zip(headers, row) if v.strip()]
        lines.append(". ".join(parts))
    return "\n".join(lines)
