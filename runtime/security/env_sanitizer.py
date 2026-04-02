"""
Environment Variable Sanitizer — blocks dangerous env var overrides.

Prevents code execution from setting proxy, TLS, Docker, or
Python package index variables that could redirect traffic or
install malicious packages.
"""

from __future__ import annotations

import logging
import os
import re
from typing import Dict, FrozenSet, List, Set

logger = logging.getLogger(__name__)

# Environment variables that must NEVER be set by user/agent code
BLOCKED_ENV_VARS: FrozenSet[str] = frozenset({
    # Proxy overrides — could redirect traffic through attacker
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
    "http_proxy", "https_proxy", "all_proxy", "no_proxy",
    "FTP_PROXY", "ftp_proxy", "SOCKS_PROXY", "socks_proxy",

    # TLS/SSL overrides — could disable certificate verification
    "SSL_CERT_FILE", "SSL_CERT_DIR", "CURL_CA_BUNDLE",
    "REQUESTS_CA_BUNDLE", "NODE_TLS_REJECT_UNAUTHORIZED",
    "NODE_EXTRA_CA_CERTS", "GIT_SSL_NO_VERIFY",
    "PYTHONHTTPSVERIFY",

    # Docker endpoint — could hijack container runtime
    "DOCKER_HOST", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH",
    "DOCKER_CONFIG", "CONTAINER_HOST",

    # Python package index — could install malicious packages
    "PIP_INDEX_URL", "PIP_EXTRA_INDEX_URL", "PIP_TRUSTED_HOST",
    "PIP_FIND_LINKS", "PIP_NO_INDEX",
    "PIPENV_PYPI_MIRROR", "UV_INDEX_URL", "UV_EXTRA_INDEX_URL",
    "CONDA_CHANNELS", "CONDA_DEFAULT_CHANNELS",

    # Node package registry
    "NPM_CONFIG_REGISTRY", "YARN_REGISTRY", "npm_config_registry",

    # Cloud credentials — should never leak to user code
    "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
    "GOOGLE_APPLICATION_CREDENTIALS", "AZURE_CLIENT_SECRET",

    # API keys
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY",

    # System manipulation
    "LD_PRELOAD", "LD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH", "PYTHONPATH", "NODE_PATH",
    "PYTHONSTARTUP", "PYTHONWARNINGS",
})

# Patterns that match dangerous env var names
BLOCKED_PATTERNS: List[re.Pattern] = [
    re.compile(r"^(HTTP|HTTPS|FTP|SOCKS|ALL)_PROXY$", re.IGNORECASE),
    re.compile(r"^PIP_(INDEX|EXTRA_INDEX|TRUSTED|FIND_LINKS)", re.IGNORECASE),
    re.compile(r"^(AWS|AZURE|GCP|GOOGLE)_", re.IGNORECASE),
    re.compile(r".*_(SECRET|TOKEN|PASSWORD|CREDENTIAL|KEY)$", re.IGNORECASE),
]


class EnvSanitizer:
    """
    Sanitizes environment variables for subprocess execution.

    Removes dangerous variables that could:
    - Redirect network traffic through a proxy
    - Disable TLS certificate verification
    - Hijack package installation sources
    - Leak cloud credentials to user code
    """

    def __init__(self, extra_blocked: Set[str] = None) -> None:
        self._blocked = set(BLOCKED_ENV_VARS)
        if extra_blocked:
            self._blocked.update(extra_blocked)

    def sanitize(self, env: Dict[str, str]) -> Dict[str, str]:
        """
        Remove blocked variables from an environment dict.

        Returns a new dict with dangerous variables removed.
        """
        clean = {}
        blocked_count = 0
        for key, value in env.items():
            if self._is_blocked(key):
                blocked_count += 1
                continue
            clean[key] = value

        if blocked_count > 0:
            logger.info("Sanitized %d blocked env vars from execution context.", blocked_count)

        return clean

    def sanitize_current_env(self) -> Dict[str, str]:
        """Sanitize the current process environment for subprocess use."""
        return self.sanitize(dict(os.environ))

    def check_env(self, env: Dict[str, str]) -> List[str]:
        """Check which blocked variables are present without removing them."""
        return [key for key in env if self._is_blocked(key)]

    def _is_blocked(self, key: str) -> bool:
        if key in self._blocked:
            return True
        for pattern in BLOCKED_PATTERNS:
            if pattern.match(key):
                return True
        return False

    @staticmethod
    def get_blocked_list() -> List[str]:
        """Get the list of all explicitly blocked variable names."""
        return sorted(BLOCKED_ENV_VARS)
