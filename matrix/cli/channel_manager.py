#!/usr/bin/env python3
"""
Channel management CLI — add, list, and test communication channels.

Usage:
    python3 -m matrix.cli.channel_manager list
    python3 -m matrix.cli.channel_manager add telegram
    python3 -m matrix.cli.channel_manager test
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

CHANNEL_DEFS = {
    "telegram": {
        "name": "Telegram",
        "tokens": {
            "TELEGRAM_BOT_TOKEN_NEO": "Neo bot token",
            "TELEGRAM_BOT_TOKEN_TRINITY": "Trinity bot token",
            "TELEGRAM_BOT_TOKEN_MORPHEUS": "Morpheus bot token",
        },
        "extra": {"owner_id": "Your Telegram user ID"},
    },
    "slack": {
        "name": "Slack",
        "tokens": {
            "SLACK_BOT_TOKEN": "Slack bot token (xoxb-...)",
        },
        "extra": {},
    },
    "discord": {
        "name": "Discord",
        "tokens": {
            "DISCORD_BOT_TOKEN": "Discord bot token",
        },
        "extra": {},
    },
    "whatsapp": {
        "name": "WhatsApp",
        "tokens": {
            "WHATSAPP_API_TOKEN": "WhatsApp Cloud API token",
        },
        "extra": {"phone_number_id": "Phone number ID"},
    },
}


def _load_config() -> dict:
    if CONFIG_PATH.exists():
        return json.loads(CONFIG_PATH.read_text())
    return {"version": "3.0.0", "provider": {}, "channels": {}}


def _save_config(config: dict) -> None:
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")


def _test_telegram_bot(token: str) -> tuple[bool, str]:
    """Test a Telegram bot token."""
    try:
        url = f"https://api.telegram.org/bot{token}/getMe"
        resp = urllib.request.urlopen(url, timeout=10)
        data = json.loads(resp.read())
        if data.get("ok"):
            bot = data["result"]
            return True, f"@{bot['username']} ({bot.get('first_name', '')})"
        return False, "Invalid response"
    except Exception as e:
        return False, str(e)


def cmd_list() -> None:
    """List configured channels."""
    config = _load_config()
    channels = config.get("channels", {})

    print(f"\n  {BOLD}Communication Channels{RESET}\n")
    print(f"  {'Channel':<15} {'Status':<15} {'Details'}")
    print(f"  {'-'*15} {'-'*15} {'-'*30}")

    for cid, cdef in CHANNEL_DEFS.items():
        if cid in channels and channels[cid].get("enabled"):
            # Check if tokens are set
            all_set = all(os.environ.get(t) for t in cdef["tokens"])
            status = f"{GREEN}active{RESET}" if all_set else f"{YELLOW}keys missing{RESET}"
            detail = ", ".join(cdef["tokens"].keys())
        else:
            status = f"{DIM}not configured{RESET}"
            detail = ""
        print(f"  {cdef['name']:<15} {status:<25} {detail}")

    print()


def cmd_add(channel_id: str) -> None:
    """Walk through adding a channel."""
    if channel_id not in CHANNEL_DEFS:
        print(f"  {RED}Unknown channel: {channel_id}{RESET}")
        print(f"  Available: {', '.join(CHANNEL_DEFS.keys())}")
        return

    cdef = CHANNEL_DEFS[channel_id]
    config = _load_config()

    print(f"\n  {BOLD}Setting up {cdef['name']}{RESET}\n")

    env_path = WORKSPACE / ".env"
    env_lines = env_path.read_text().splitlines() if env_path.exists() else []

    # Collect tokens
    for env_key, prompt in cdef["tokens"].items():
        import getpass
        value = getpass.getpass(f"  {prompt}: ")
        if value:
            env_lines = [l for l in env_lines if not l.startswith(f"{env_key}=")]
            env_lines.append(f"{env_key}={value}")

    # Collect extra fields
    channel_config = {"enabled": True}
    for key, prompt in cdef.get("extra", {}).items():
        value = input(f"  {prompt}: ").strip()
        if value:
            channel_config[key] = value

    env_path.write_text("\n".join(env_lines) + "\n")

    config.setdefault("channels", {})[channel_id] = channel_config
    _save_config(config)

    print(f"\n  {GREEN}{cdef['name']} configured.{RESET}")

    # Auto-test for Telegram
    if channel_id == "telegram":
        print(f"  Testing bot tokens...")
        for env_key in cdef["tokens"]:
            token = os.environ.get(env_key, "")
            # Read from the .env we just wrote
            for line in env_lines:
                if line.startswith(f"{env_key}="):
                    token = line.split("=", 1)[1]
            if token:
                ok, msg = _test_telegram_bot(token)
                agent = env_key.split("_")[-1].lower()
                icon = f"{GREEN}OK{RESET}" if ok else f"{RED}FAIL{RESET}"
                print(f"    [{icon}] {agent}: {msg}")

    print()


def cmd_test() -> None:
    """Test all configured channels."""
    config = _load_config()
    channels = config.get("channels", {})

    print(f"\n  {BOLD}Testing Channels{RESET}\n")

    if not channels:
        print(f"  {DIM}No channels configured. Run: matrix channel add <platform>{RESET}")
        print()
        return

    for cid, cconfig in channels.items():
        if not cconfig.get("enabled"):
            continue
        cdef = CHANNEL_DEFS.get(cid)
        if not cdef:
            continue

        print(f"  {BOLD}{cdef['name']}{RESET}")

        if cid == "telegram":
            for env_key, label in cdef["tokens"].items():
                token = os.environ.get(env_key, "")
                if token:
                    ok, msg = _test_telegram_bot(token)
                    icon = f"{GREEN}OK{RESET}" if ok else f"{RED}FAIL{RESET}"
                    agent = env_key.split("_")[-1].lower()
                    print(f"    [{icon}] {agent}: {msg}")
                else:
                    print(f"    [{RED}FAIL{RESET}] {env_key} not set")
        else:
            # Generic check — just verify env var is set
            for env_key in cdef["tokens"]:
                has_key = bool(os.environ.get(env_key))
                icon = f"{GREEN}OK{RESET}" if has_key else f"{RED}FAIL{RESET}"
                print(f"    [{icon}] {env_key}: {'set' if has_key else 'not set'}")

    print()


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] == "list":
        cmd_list()
    elif args[0] == "add" and len(args) > 1:
        cmd_add(args[1])
    elif args[0] == "test":
        cmd_test()
    else:
        print("Usage: matrix channel {list|add <platform>|test}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
