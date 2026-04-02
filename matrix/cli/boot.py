#!/usr/bin/env python3
"""
OpenMatrix Boot — clean startup with Trinity's greeting and status summary.

Shows Trinity's avatar, displays welcome or greeting, boots all subsystems,
and shows a clean status summary. Targets under 5 seconds to agents responding.
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

GREEN = "\033[32m"
BRIGHT_GREEN = "\033[92m"
WHITE = "\033[97m"
BOLD = "\033[1m"
DIM = "\033[2m"
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"

WORKSPACE = Path(__file__).resolve().parents[2]
BOOT_MARKER = WORKSPACE / "data" / ".first_boot_complete"


def _is_first_boot() -> bool:
    return not BOOT_MARKER.exists()


def _mark_booted() -> None:
    BOOT_MARKER.parent.mkdir(parents=True, exist_ok=True)
    BOOT_MARKER.write_text(time.strftime("%Y-%m-%dT%H:%M:%SZ"))


def _show_trinity(first_boot: bool) -> None:
    """Show Trinity's avatar with appropriate greeting."""
    try:
        from matrix.cli.trinity_avatar import animate_greeting
        animate_greeting(first_boot=first_boot, compact=True)
    except Exception:
        if first_boot:
            print(f"\n  {GREEN}{BOLD}Welcome to OpenMatrix.{RESET}")
            print(f"  {GREEN}Trinity here. All systems initializing.{RESET}\n")
        else:
            print(f"\n  {GREEN}{BOLD}OpenMatrix starting...{RESET}\n")


def _load_subsystems() -> list[tuple[str, bool, str]]:
    """Load and verify all subsystems. Returns list of (name, ok, detail)."""
    results = []
    start = time.time()

    # Protocols
    try:
        sys.path.insert(0, str(WORKSPACE))
        sys.path.insert(0, str(WORKSPACE.parent))
        from matrix.runtime.protocol_loader import ProtocolLoader
        loader = ProtocolLoader(WORKSPACE.parent)
        protocols = loader.load_all()
        results.append(("Protocols", True, f"{len(protocols)} loaded"))
    except Exception as e:
        results.append(("Protocols", False, str(e)))

    # Blockchain
    try:
        from matrix.runtime.blockchain_registry import BlockchainRegistry
        reg = BlockchainRegistry(WORKSPACE.parent)
        results.append(("Blockchain", True, f"{len(reg.components)} components"))
    except Exception as e:
        results.append(("Blockchain", False, str(e)))

    # Phase 3 subsystems
    phase3_modules = [
        ("Memory", "runtime.memory", "UserMemoryStore"),
        ("Goals", "runtime.goals", "GoalEngine"),
        ("RAG", "runtime.rag", "DocumentStore"),
        ("Automation", "runtime.automation", "TriggerEngine"),
        ("Execution", "runtime.execution", "CodeSandbox"),
        ("Proactive", "runtime.proactive", "CheckInEngine"),
        ("Models", "runtime.models", "ModelMarketplace"),
        ("Migration", "runtime.migration", "MigrationEngine"),
    ]
    ok_count = 0
    for name, mod, cls in phase3_modules:
        try:
            m = __import__(mod, fromlist=[cls])
            getattr(m, cls)
            ok_count += 1
        except Exception:
            pass
    results.append(("Subsystems", ok_count == len(phase3_modules), f"{ok_count}/{len(phase3_modules)} active"))

    # Tasks
    try:
        from runtime.tasks import TaskLedger
        results.append(("Tasks", True, "SQLite ledger ready"))
    except Exception:
        results.append(("Tasks", False, "not loaded"))

    # Skills
    try:
        from runtime.skills import SkillsRegistry
        sr = SkillsRegistry(str(WORKSPACE / "skills"))
        results.append(("Skills", True, f"{len(sr._skills)} loaded"))
    except Exception:
        results.append(("Skills", False, "not loaded"))

    elapsed = time.time() - start
    results.append(("Boot time", True, f"{elapsed:.1f}s"))

    return results


def _print_status(results: list[tuple[str, bool, str]]) -> None:
    """Print a clean status summary."""
    print(f"  {BOLD}{'Component':<18} {'Status':<10} {'Detail'}{RESET}")
    print(f"  {'-'*18} {'-'*10} {'-'*30}")

    for name, ok, detail in results:
        if ok:
            icon = f"{GREEN}ready{RESET}"
        else:
            icon = f"{YELLOW}warn{RESET}"
        print(f"  {name:<18} {icon:<20} {detail}")

    print()


def _show_agents() -> None:
    """Show which agents are online."""
    agents = [
        ("Neo", "The Architect"),
        ("Trinity", "The Guide"),
        ("Morpheus", "The Philosopher"),
    ]
    print(f"  {BOLD}Agents{RESET}")
    for name, role in agents:
        print(f"  {GREEN}  {name}{RESET} {DIM}— {role}{RESET}")
    print()


def main() -> int:
    boot_start = time.time()
    first_boot = _is_first_boot()

    # Show Trinity
    _show_trinity(first_boot)

    if first_boot:
        print(f"  {WHITE}{BOLD}Welcome to OpenMatrix{RESET}")
        print(f"  {DIM}First boot — initializing all systems...{RESET}")
        print()
    else:
        print(f"  {DIM}Initializing...{RESET}")
        print()

    # Load subsystems
    results = _load_subsystems()

    # Print status
    _print_status(results)

    # Show agents
    _show_agents()

    # Model info
    provider = os.environ.get("MATRIX_MODEL_PROVIDER", "ollama")
    model = os.environ.get("NVIDIA_MODEL", os.environ.get("OLLAMA_MODEL", "mistral:7b-instruct"))
    print(f"  {DIM}Model: {provider}/{model}{RESET}")

    total = time.time() - boot_start
    print(f"  {DIM}Ready in {total:.1f}s{RESET}")
    print()

    # Mark first boot complete
    if first_boot:
        _mark_booted()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
