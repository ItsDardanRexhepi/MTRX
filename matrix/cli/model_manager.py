#!/usr/bin/env python3
"""
Model management CLI — add, list, set primary, and test model providers.

Usage:
    python3 -m matrix.cli.model_manager list
    python3 -m matrix.cli.model_manager add nvidia
    python3 -m matrix.cli.model_manager set primary nvidia
    python3 -m matrix.cli.model_manager test
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path

GREEN = "\033[32m"
WHITE = "\033[97m"
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
YELLOW = "\033[33m"
RESET = "\033[0m"

WORKSPACE = Path(__file__).resolve().parents[2]
CONFIG_PATH = WORKSPACE / "openmatrix.config.json"

KNOWN_PROVIDERS = {
    "ollama": {
        "name": "Ollama",
        "env_key": "OLLAMA_MODEL",
        "default_model": "mistral:7b-instruct",
        "test_url": "http://localhost:11434/api/tags",
        "auth": "none",
    },
    "nvidia": {
        "name": "NVIDIA",
        "env_key": "NVIDIA_API_KEY",
        "default_model": "meta/llama-3.3-70b-instruct",
        "test_url": "https://integrate.api.nvidia.com/v1/models",
        "auth": "bearer",
    },
    "anthropic": {
        "name": "Anthropic",
        "env_key": "ANTHROPIC_API_KEY",
        "default_model": "claude-sonnet-4-20250514",
        "test_url": "https://api.anthropic.com/v1/messages",
        "auth": "anthropic",
    },
    "openai": {
        "name": "OpenAI",
        "env_key": "OPENAI_API_KEY",
        "default_model": "gpt-4o",
        "test_url": "https://api.openai.com/v1/models",
        "auth": "bearer",
    },
    "gemini": {
        "name": "Google Gemini",
        "env_key": "GOOGLE_API_KEY",
        "default_model": "gemini-2.5-pro",
        "test_url": "https://generativelanguage.googleapis.com/v1beta/models",
        "auth": "query",
    },
}


def _load_config() -> dict:
    if CONFIG_PATH.exists():
        return json.loads(CONFIG_PATH.read_text())
    return {"version": "3.0.0", "provider": {}, "channels": {}}


def _save_config(config: dict) -> None:
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")


def _test_provider(provider_id: str) -> tuple[bool, str]:
    """Test connectivity to a provider. Returns (ok, message)."""
    info = KNOWN_PROVIDERS.get(provider_id)
    if not info:
        return False, f"Unknown provider: {provider_id}"

    api_key = os.environ.get(info["env_key"], "")

    if info["auth"] == "none":
        # Ollama — just check if running
        try:
            resp = urllib.request.urlopen(info["test_url"], timeout=5)
            data = json.loads(resp.read())
            models = [m["name"] for m in data.get("models", [])]
            return True, f"Ollama running. Models: {', '.join(models[:5])}"
        except Exception as e:
            return False, f"Ollama not reachable: {e}"

    if not api_key:
        return False, f"{info['env_key']} not set in environment"

    try:
        req = urllib.request.Request(info["test_url"])
        if info["auth"] == "bearer":
            req.add_header("Authorization", f"Bearer {api_key}")
        elif info["auth"] == "anthropic":
            req.add_header("x-api-key", api_key)
            req.add_header("anthropic-version", "2023-06-01")
        elif info["auth"] == "query":
            req = urllib.request.Request(f"{info['test_url']}?key={api_key}")

        resp = urllib.request.urlopen(req, timeout=10)
        return True, f"{info['name']} connected (HTTP {resp.status})"
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return False, f"Invalid API key for {info['name']}"
        return False, f"{info['name']} error: HTTP {e.code}"
    except Exception as e:
        return False, f"{info['name']} unreachable: {e}"


def cmd_list() -> None:
    """List all configured model providers."""
    config = _load_config()
    provider_config = config.get("provider", {})
    primary = provider_config.get("primary", "none")

    print(f"\n  {BOLD}Model Providers{RESET}\n")
    print(f"  {'Provider':<15} {'Model':<35} {'Status':<10} {'Key Set'}")
    print(f"  {'-'*15} {'-'*35} {'-'*10} {'-'*10}")

    for pid, info in KNOWN_PROVIDERS.items():
        model = info["default_model"]
        key_set = "yes" if os.environ.get(info["env_key"]) or info["auth"] == "none" else "no"
        status = f"{GREEN}primary{RESET}" if pid == primary else (
            f"{DIM}fallback{RESET}" if pid == provider_config.get("fallback") else f"{DIM}---{RESET}"
        )
        print(f"  {pid:<15} {model:<35} {status:<20} {key_set}")

    print()


def cmd_add(provider_id: str) -> None:
    """Add a model provider."""
    if provider_id not in KNOWN_PROVIDERS:
        print(f"  {RED}Unknown provider: {provider_id}{RESET}")
        print(f"  Available: {', '.join(KNOWN_PROVIDERS.keys())}")
        return

    info = KNOWN_PROVIDERS[provider_id]
    config = _load_config()

    if info["auth"] != "none":
        api_key = input(f"  {info['name']} API key: ").strip()
        if not api_key:
            print(f"  {RED}No key provided. Aborting.{RESET}")
            return

        # Save to .env
        env_path = WORKSPACE / ".env"
        lines = env_path.read_text().splitlines() if env_path.exists() else []
        lines = [l for l in lines if not l.startswith(f"{info['env_key']}=")]
        lines.append(f"{info['env_key']}={api_key}")
        env_path.write_text("\n".join(lines) + "\n")
        print(f"  API key saved to .env")

    # If no primary is set, make this the primary
    if not config.get("provider", {}).get("primary"):
        config.setdefault("provider", {})["primary"] = provider_id
        config["provider"]["model"] = info["default_model"]

    _save_config(config)
    print(f"  {GREEN}{info['name']} added.{RESET}")


def cmd_set_primary(provider_id: str) -> None:
    """Set the primary model provider."""
    if provider_id not in KNOWN_PROVIDERS:
        print(f"  {RED}Unknown provider: {provider_id}{RESET}")
        return

    config = _load_config()
    old_primary = config.get("provider", {}).get("primary", "none")
    config.setdefault("provider", {})["primary"] = provider_id
    config["provider"]["model"] = KNOWN_PROVIDERS[provider_id]["default_model"]
    _save_config(config)

    print(f"  Primary changed: {old_primary} -> {GREEN}{provider_id}{RESET}")
    print(f"  Model: {KNOWN_PROVIDERS[provider_id]['default_model']}")


def cmd_test() -> None:
    """Test all configured providers."""
    config = _load_config()
    primary = config.get("provider", {}).get("primary", "")

    print(f"\n  {BOLD}Testing Model Providers{RESET}\n")

    for pid in [primary, "ollama"] if primary != "ollama" else ["ollama"]:
        if not pid:
            continue
        ok, msg = _test_provider(pid)
        icon = f"{GREEN}OK{RESET}" if ok else f"{RED}FAIL{RESET}"
        print(f"  [{icon}] {KNOWN_PROVIDERS[pid]['name']}: {msg}")

    print()


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] == "list":
        cmd_list()
    elif args[0] == "add" and len(args) > 1:
        cmd_add(args[1])
    elif args[0] == "set" and len(args) > 2 and args[1] == "primary":
        cmd_set_primary(args[2])
    elif args[0] == "test":
        cmd_test()
    else:
        print("Usage: matrix model {list|add <provider>|set primary <provider>|test}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
