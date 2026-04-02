"""C28 - Social: on-chain social posts, threading, and attestations."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.social.social_service import SocialService

router = APIRouter()

_service = SocialService()


class PostRequest(BaseModel):
    author: str
    content_hash: str
    content_uri: str
    parent_post_id: str = ""


class VerifiedPostRequest(BaseModel):
    author: str
    content_hash: str
    content_uri: str
    attestation_uid: str
    schema_resolver: str
    parent_post_id: str = ""


class EditRequest(BaseModel):
    caller: str
    new_content_hash: str
    new_content_uri: str


class AttestationRequest(BaseModel):
    caller: str
    attestation_uid: str
    schema_resolver: str


@router.post("/post")
async def create_post(request: PostRequest):
    """Create a new social post or reply."""
    try:
        p = _service.create_post(request.author, request.content_hash, request.content_uri, request.parent_post_id)
        return {
            "post_id": p.post_id, "author": p.author, "parent": p.parent_post_id,
            "version": p.version, "status": "published",
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/post/verified")
async def create_verified_post(request: VerifiedPostRequest):
    """Create a post with EAS attestation attached."""
    try:
        p = _service.create_verified_post(
            request.author, request.content_hash, request.content_uri,
            request.attestation_uid, request.schema_resolver, request.parent_post_id,
        )
        return {
            "post_id": p.post_id, "author": p.author, "attestation": p.eas_attestation_uid,
            "status": "published",
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/post/{post_id}/edit")
async def edit_post(post_id: str, request: EditRequest):
    """Edit a post's content."""
    try:
        p = _service.edit_post(post_id, request.caller, request.new_content_hash, request.new_content_uri)
        return {"post_id": p.post_id, "version": p.version}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/post/{post_id}/delete")
async def delete_post(post_id: str, caller: str):
    """Delete a post."""
    try:
        p = _service.delete_post(post_id, caller)
        return {"post_id": p.post_id, "deleted": p.deleted}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/post/{post_id}/attestation")
async def link_attestation(post_id: str, request: AttestationRequest):
    """Link an EAS attestation to a post."""
    try:
        p = _service.link_attestation(post_id, request.caller, request.attestation_uid, request.schema_resolver)
        return {"post_id": p.post_id, "attestation": p.eas_attestation_uid}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/author/{address}/verify")
async def verify_author(address: str):
    """Mark an author as verified."""
    try:
        _service.verify_author(address)
        return {"address": address, "verified": True}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/post/{post_id}")
async def get_post(post_id: str):
    """Get post details."""
    p = _service.get_post(post_id)
    if p is None:
        raise HTTPException(status_code=404, detail="Post not found.")
    return {
        "post_id": p.post_id, "author": p.author,
        "content_hash": p.content_hash, "content_uri": p.content_uri,
        "parent_post_id": p.parent_post_id, "version": p.version,
        "deleted": p.deleted, "eas_attestation": p.eas_attestation_uid,
        "verified": _service.is_post_verified(post_id),
    }


@router.get("/post/{post_id}/replies")
async def get_replies(post_id: str):
    """Get replies to a post."""
    replies = _service.get_replies(post_id)
    return {
        "post_id": post_id,
        "replies": [{"post_id": r.post_id, "author": r.author} for r in replies],
        "count": len(replies),
    }


@router.get("/author/{address}/posts")
async def get_author_posts(address: str):
    """Get all posts by an author."""
    posts = _service.get_author_posts(address)
    return {
        "author": address,
        "posts": [{"post_id": p.post_id, "content_uri": p.content_uri, "version": p.version} for p in posts],
        "total": len(posts),
    }
