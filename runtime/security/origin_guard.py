"""
Origin Guard — rejects mismatched browser Origin headers.

Prevents CSRF-style attacks on trusted-proxy API endpoints
by validating that the Origin header matches allowed origins.
"""

from __future__ import annotations

import logging
from typing import FrozenSet, List, Optional, Set
from urllib.parse import urlparse

logger = logging.getLogger(__name__)

# Default allowed origins
DEFAULT_ALLOWED_ORIGINS: FrozenSet[str] = frozenset({
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:8000",
    "http://127.0.0.1",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8000",
})


class OriginGuard:
    """
    Validates Origin headers on incoming HTTP requests.

    Rejects requests where the Origin header doesn't match
    the expected origins for this server. Prevents cross-origin
    attacks on the API.
    """

    def __init__(self, allowed_origins: Optional[Set[str]] = None) -> None:
        self._allowed = set(allowed_origins or DEFAULT_ALLOWED_ORIGINS)

    def add_origin(self, origin: str) -> None:
        self._allowed.add(origin.rstrip("/"))

    def remove_origin(self, origin: str) -> None:
        self._allowed.discard(origin.rstrip("/"))

    def check_origin(self, origin: Optional[str], host: Optional[str] = None) -> bool:
        """
        Check if an Origin header is allowed.

        Args:
            origin: The Origin header value.
            host: The Host header value (for same-origin detection).

        Returns:
            True if the request should be allowed.
        """
        # No Origin header = same-origin request (not a browser CORS request)
        if not origin:
            return True

        origin = origin.rstrip("/")

        # Direct match
        if origin in self._allowed:
            return True

        # Same-origin check: Origin matches Host
        if host:
            parsed = urlparse(origin)
            if parsed.netloc == host:
                return True

        logger.warning("Origin rejected | origin=%s | allowed=%s", origin, self._allowed)
        return False

    def get_allowed_origins(self) -> List[str]:
        return sorted(self._allowed)


def origin_guard_middleware(allowed_origins: Optional[Set[str]] = None):
    """
    FastAPI middleware factory for origin validation.

    Usage:
        app.middleware("http")(origin_guard_middleware({"http://localhost:3000"}))
    """
    guard = OriginGuard(allowed_origins)

    async def middleware(request, call_next):
        origin = request.headers.get("origin")
        host = request.headers.get("host")

        if not guard.check_origin(origin, host):
            from fastapi.responses import JSONResponse
            return JSONResponse(
                status_code=403,
                content={"error": "Origin not allowed."},
            )

        response = await call_next(request)
        return response

    return middleware
