"""
Social Service — on-chain social posts with threading and attestations.

Part of Component 27 (Social Posts).
Handles post creation, editing, deletion, threading (replies),
EAS attestation linking, and author verification.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


@dataclass
class Post:
    """An on-chain social post."""
    post_id: str
    author: str
    content_hash: str
    content_uri: str
    parent_post_id: str              # "" for top-level posts
    created_at: float = field(default_factory=time.time)
    edited_at: float = 0.0
    version: int = 1
    deleted: bool = False
    eas_attestation_uid: str = ""
    eas_schema_resolver: str = ""


class SocialService:
    """
    Manages on-chain social posts with threading and attestations.

    Features:
    - Top-level posts and threaded replies
    - Content versioning (edit increments version)
    - Soft deletion (post marked deleted, content preserved)
    - EAS attestation linking for verified content
    - Author verification status
    """

    def __init__(
        self,
        execute_fn: Optional[Callable] = None,
    ) -> None:
        self._execute = execute_fn
        self._posts: Dict[str, Post] = {}
        self._replies: Dict[str, List[str]] = {}       # parent_id -> [post_ids]
        self._author_posts: Dict[str, List[str]] = {}  # author -> [post_ids]
        self._verified_authors: Set[str] = set()
        self._counter: int = 0
        logger.info("SocialService initialised.")

    # ── Post Creation ─────────────────────────────────────────────────

    def create_post(
        self,
        author: str,
        content_hash: str,
        content_uri: str,
        parent_post_id: str = "",
    ) -> Post:
        """
        Create a new post or reply.

        Args:
            author: Author's address.
            content_hash: Hash of the post content.
            content_uri: URI pointing to the content.
            parent_post_id: Parent post ID for replies ("" for top-level).

        Returns:
            The created Post.
        """
        if not author.startswith("0x"):
            raise ValueError("Invalid author address.")
        if not content_hash:
            raise ValueError("Content hash must not be empty.")
        if not content_uri:
            raise ValueError("Content URI must not be empty.")
        if parent_post_id:
            parent = self._posts.get(parent_post_id)
            if parent is None:
                raise ValueError(f"Parent post {parent_post_id} not found.")
            if parent.deleted:
                raise ValueError("Cannot reply to a deleted post.")

        self._counter += 1
        pid = f"POST-{self._counter:08d}"

        post = Post(
            post_id=pid,
            author=author,
            content_hash=content_hash,
            content_uri=content_uri,
            parent_post_id=parent_post_id,
        )
        self._posts[pid] = post
        self._author_posts.setdefault(author, []).append(pid)

        if parent_post_id:
            self._replies.setdefault(parent_post_id, []).append(pid)

        logger.info(
            "Post created | id=%s | author=%s | parent=%s",
            pid, author, parent_post_id or "none",
        )
        return post

    def create_verified_post(
        self,
        author: str,
        content_hash: str,
        content_uri: str,
        attestation_uid: str,
        schema_resolver: str,
        parent_post_id: str = "",
    ) -> Post:
        """Create a post with an EAS attestation already attached."""
        post = self.create_post(author, content_hash, content_uri, parent_post_id)
        post.eas_attestation_uid = attestation_uid
        post.eas_schema_resolver = schema_resolver
        logger.info(
            "Verified post created | id=%s | attestation=%s",
            post.post_id, attestation_uid,
        )
        return post

    # ── Edit / Delete ─────────────────────────────────────────────────

    def edit_post(
        self,
        post_id: str,
        caller: str,
        new_content_hash: str,
        new_content_uri: str,
    ) -> Post:
        """
        Edit a post's content. Only the author can edit.
        Increments version number and records edit timestamp.
        """
        post = self._get_post(post_id)
        if post.author != caller:
            raise ValueError("Only the author can edit.")
        if post.deleted:
            raise ValueError("Cannot edit a deleted post.")
        if not new_content_hash:
            raise ValueError("Content hash must not be empty.")

        post.content_hash = new_content_hash
        post.content_uri = new_content_uri
        post.version += 1
        post.edited_at = time.time()

        logger.info("Post edited | id=%s | version=%d", post_id, post.version)
        return post

    def delete_post(self, post_id: str, caller: str) -> Post:
        """
        Soft-delete a post. Author or platform owner can delete.
        Content is preserved but marked as deleted.
        """
        post = self._get_post(post_id)
        if post.author != caller:
            raise ValueError("Only the author can delete.")
        if post.deleted:
            raise ValueError("Post already deleted.")

        post.deleted = True
        logger.info("Post deleted | id=%s", post_id)
        return post

    # ── Attestations ──────────────────────────────────────────────────

    def link_attestation(
        self,
        post_id: str,
        caller: str,
        attestation_uid: str,
        schema_resolver: str,
    ) -> Post:
        """Link an EAS attestation to an existing post."""
        post = self._get_post(post_id)
        if post.author != caller:
            raise ValueError("Only the author can link attestations.")
        if post.deleted:
            raise ValueError("Cannot link to a deleted post.")

        post.eas_attestation_uid = attestation_uid
        post.eas_schema_resolver = schema_resolver

        logger.info(
            "Attestation linked | post=%s | uid=%s", post_id, attestation_uid,
        )
        return post

    # ── Author Verification ───────────────────────────────────────────

    def verify_author(self, author: str) -> None:
        """Mark an author as verified."""
        if not author.startswith("0x"):
            raise ValueError("Invalid address.")
        self._verified_authors.add(author)
        logger.info("Author verified | addr=%s", author)

    def unverify_author(self, author: str) -> None:
        """Remove author verification."""
        self._verified_authors.discard(author)
        logger.info("Author unverified | addr=%s", author)

    def is_post_verified(self, post_id: str) -> bool:
        """Check if a post's author is verified and has an attestation."""
        post = self._posts.get(post_id)
        if post is None:
            return False
        return (
            post.author in self._verified_authors
            and bool(post.eas_attestation_uid)
        )

    # ── Queries ───────────────────────────────────────────────────────

    def get_post(self, post_id: str) -> Optional[Post]:
        """Get post or None."""
        return self._posts.get(post_id)

    def get_replies(self, post_id: str) -> List[Post]:
        """Get all replies to a post (non-deleted only)."""
        reply_ids = self._replies.get(post_id, [])
        return [
            self._posts[rid] for rid in reply_ids
            if rid in self._posts and not self._posts[rid].deleted
        ]

    def get_author_posts(self, author: str) -> List[Post]:
        """Get all posts by an author (non-deleted only)."""
        post_ids = self._author_posts.get(author, [])
        return [
            self._posts[pid] for pid in post_ids
            if pid in self._posts and not self._posts[pid].deleted
        ]

    def get_reply_count(self, post_id: str) -> int:
        """Get number of non-deleted replies to a post."""
        return len(self.get_replies(post_id))

    # ── Internal ──────────────────────────────────────────────────────

    def _get_post(self, post_id: str) -> Post:
        """Get post or raise."""
        post = self._posts.get(post_id)
        if post is None:
            raise ValueError(f"Post {post_id} not found.")
        return post
