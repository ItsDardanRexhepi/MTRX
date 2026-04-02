"""
Security Hardening — blocks dangerous environment variables, validates origins,
and manages session revocation.

Mirrors and improves on OpenClaw's security fixes:
- Block proxy, TLS, and Docker endpoint env overrides in host execution
- Block Python package index override variables
- Reject mismatched browser Origin headers on trusted-proxy requests
- Disconnect active device sessions after token rotation
- Keep owner-only tools off HTTP invoke paths
"""

from runtime.security.env_sanitizer import EnvSanitizer
from runtime.security.origin_guard import OriginGuard
from runtime.security.session_manager import SessionManager

__all__ = ["EnvSanitizer", "OriginGuard", "SessionManager"]
