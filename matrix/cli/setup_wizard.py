#!/usr/bin/env python3
"""
Trinity's Setup Wizard — conversational first-time configuration.

Walks the user through provider selection, channel setup, and API keys.
Trinity speaks in character throughout.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# ANSI
GREEN = "\033[32m"
BRIGHT_GREEN = "\033[92m"
WHITE = "\033[97m"
DIM = "\033[2m"
BOLD = "\033[1m"
RED = "\033[31m"
YELLOW = "\033[33m"
RESET = "\033[0m"

WORKSPACE = Path(__file__).resolve().parents[2]
CONFIG_PATH = WORKSPACE / "openmatrix.config.json"

PROVIDERS = {
    "1": ("ollama", "Ollama (local, free)", "OLLAMA_MODEL"),
    "2": ("nvidia", "NVIDIA (hosted, fast)", "NVIDIA_API_KEY"),
    "3": ("anthropic", "Anthropic Claude", "ANTHROPIC_API_KEY"),
    "4": ("openai", "OpenAI", "OPENAI_API_KEY"),
    "5": ("gemini", "Google Gemini", "GOOGLE_API_KEY"),
}

CHANNELS = {
    "1": ("telegram", "Telegram"),
    "2": ("slack", "Slack"),
    "3": ("discord", "Discord"),
    "4": ("whatsapp", "WhatsApp"),
}

DEFAULT_MODELS = {
    "ollama": "mistral:7b-instruct",
    "nvidia": "meta/llama-3.3-70b-instruct",
    "anthropic": "claude-sonnet-4-20250514",
    "openai": "gpt-4o",
    "gemini": "gemini-2.5-pro",
}


def _trinity(msg: str) -> None:
    """Print a message as Trinity."""
    print(f"  {GREEN}{BOLD}Trinity:{RESET} {GREEN}{msg}{RESET}")


def _prompt(label: str, secret: bool = False) -> str:
    """Prompt the user for input."""
    try:
        if secret:
            import getpass
            return getpass.getpass(f"  {WHITE}{label}: {RESET}")
        return input(f"  {WHITE}{label}: {RESET}").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(0)


def _choice(options: dict, label: str = "Choose") -> str:
    """Present numbered options and get a choice."""
    print()
    for key, val in options.items():
        display = val[1] if isinstance(val, tuple) else val
        print(f"    {WHITE}{key}.{RESET} {display}")
    print()
    while True:
        pick = _prompt(label)
        if pick in options:
            return pick
        _trinity(f"That's not one of the options. Try again.")


def _test_ollama() -> bool:
    """Check if Ollama is running."""
    try:
        import urllib.request
        resp = urllib.request.urlopen("http://localhost:11434/api/tags", timeout=5)
        return resp.status == 200
    except Exception:
        return False


def _test_provider(provider: str, api_key: str) -> bool:
    """Quick connectivity test for a provider."""
    if provider == "ollama":
        return _test_ollama()

    endpoints = {
        "nvidia": "https://integrate.api.nvidia.com/v1/models",
        "openai": "https://api.openai.com/v1/models",
        "anthropic": "https://api.anthropic.com/v1/messages",
        "gemini": "https://generativelanguage.googleapis.com/v1beta/models",
    }

    url = endpoints.get(provider)
    if not url:
        return False

    try:
        import urllib.request
        req = urllib.request.Request(url)
        if provider == "anthropic":
            req.add_header("x-api-key", api_key)
            req.add_header("anthropic-version", "2023-06-01")
        elif provider == "gemini":
            url += f"?key={api_key}"
            req = urllib.request.Request(url)
        else:
            req.add_header("Authorization", f"Bearer {api_key}")
        resp = urllib.request.urlopen(req, timeout=10)
        return resp.status == 200
    except Exception:
        return False


def run_wizard() -> dict:
    """Run the interactive setup wizard. Returns the config dict."""
    # Show Trinity
    try:
        from matrix.cli.trinity_avatar import animate_greeting
        animate_greeting(first_boot=True, compact=True)
    except Exception:
        _trinity("Hello. I'm Trinity. Let's set up OpenMatrix.")
        print()

    _trinity("I'll walk you through everything. This takes about two minutes.")
    print()

    config = {
        "version": "3.0.0",
        "provider": {},
        "channels": {},
        "agents": {
            "neo": {"enabled": True},
            "trinity": {"enabled": True},
            "morpheus": {"enabled": True},
        },
    }

    # ── Step 1: Model Provider ──────────────────────────────────────
    _trinity("First, which model provider do you want to use?")
    _trinity("Ollama runs locally for free. The others need an API key.")

    provider_choice = _choice(
        {k: v[1] for k, v in PROVIDERS.items()},
        "Pick a number",
    )
    provider_id, provider_name, env_key = PROVIDERS[provider_choice]

    api_key = ""
    if provider_id == "ollama":
        _trinity("Good choice. Checking if Ollama is running...")
        if _test_ollama():
            _trinity("Ollama is running. Perfect.")
        else:
            _trinity("Ollama isn't running. Start it with: ollama serve")
            _trinity("Then pull the model: ollama pull mistral:7b-instruct")
    else:
        _trinity(f"I need your {provider_name} API key.")
        api_key = _prompt(f"{provider_name} API key", secret=True)

        _trinity("Testing the connection...")
        if _test_provider(provider_id, api_key):
            _trinity("Connected. The model is responding.")
        else:
            _trinity("I couldn't reach the provider. Check the key and try again later.")
            _trinity("I'll save it anyway so you can fix it without re-running setup.")

    config["provider"] = {
        "primary": provider_id,
        "model": DEFAULT_MODELS.get(provider_id, ""),
        "fallback": "ollama",
        "fallback_model": "mistral:7b-instruct",
    }
    if api_key:
        config["provider"]["api_key_env"] = env_key

    # ── Step 2: Communication Channel ───────────────────────────────
    print()
    _trinity("Next, how do you want to talk to Neo, Trinity, and Morpheus?")

    channel_choice = _choice(
        {k: v[1] for k, v in CHANNELS.items()},
        "Pick a number",
    )
    channel_id, channel_name = CHANNELS[channel_choice]

    _trinity(f"Setting up {channel_name}.")

    if channel_id == "telegram":
        _trinity("I need the bot tokens for each agent.")
        _trinity("Create bots via @BotFather on Telegram, then paste the tokens here.")
        print()
        neo_token = _prompt("Neo bot token", secret=True)
        trinity_token = _prompt("Trinity bot token", secret=True)
        morpheus_token = _prompt("Morpheus bot token", secret=True)
        owner_id = _prompt("Your Telegram user ID (numbers only)")

        config["channels"]["telegram"] = {
            "enabled": True,
            "bots": {
                "neo": {"token_env": "TELEGRAM_BOT_TOKEN_NEO"},
                "trinity": {"token_env": "TELEGRAM_BOT_TOKEN_TRINITY"},
                "morpheus": {"token_env": "TELEGRAM_BOT_TOKEN_MORPHEUS"},
            },
            "owner_id": owner_id,
        }

        # Write tokens to .env
        env_path = WORKSPACE / ".env"
        env_lines = []
        if env_path.exists():
            env_lines = env_path.read_text().splitlines()

        token_map = {
            "TELEGRAM_BOT_TOKEN_NEO": neo_token,
            "TELEGRAM_BOT_TOKEN_TRINITY": trinity_token,
            "TELEGRAM_BOT_TOKEN_MORPHEUS": morpheus_token,
        }
        if api_key:
            token_map[env_key] = api_key

        for key, val in token_map.items():
            if val:
                # Remove existing line if present
                env_lines = [l for l in env_lines if not l.startswith(f"{key}=")]
                env_lines.append(f"{key}={val}")

        env_path.write_text("\n".join(env_lines) + "\n")
        _trinity("Tokens saved to .env file.")

    elif channel_id == "slack":
        _trinity("I need your Slack bot token and signing secret.")
        bot_token = _prompt("Slack bot token (xoxb-...)", secret=True)
        config["channels"]["slack"] = {
            "enabled": True,
            "token_env": "SLACK_BOT_TOKEN",
        }
    elif channel_id == "discord":
        _trinity("I need your Discord bot token.")
        bot_token = _prompt("Discord bot token", secret=True)
        config["channels"]["discord"] = {
            "enabled": True,
            "token_env": "DISCORD_BOT_TOKEN",
        }
    elif channel_id == "whatsapp":
        _trinity("I need your WhatsApp Cloud API token and phone number ID.")
        api_token = _prompt("WhatsApp API token", secret=True)
        phone_id = _prompt("Phone number ID")
        config["channels"]["whatsapp"] = {
            "enabled": True,
            "token_env": "WHATSAPP_API_TOKEN",
            "phone_number_id": phone_id,
        }

    # ── Step 3: Save config ─────────────────────────────────────────
    print()
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    _trinity(f"Configuration saved to {CONFIG_PATH.name}.")

    # ── Step 4: Final message ───────────────────────────────────────
    print()
    _trinity("Setup is complete.")
    _trinity("Start the Matrix with: python3 -m matrix.cli.boot")
    _trinity("Or run: ./start.sh")
    print()
    _trinity("I'll be here when you need me.")
    print()

    return config


def main() -> int:
    run_wizard()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
