#!/usr/bin/env python3
"""
OpenMatrix Release Preparation — scans for sensitive data and creates clean exports.

Ensures no private keys, API tokens, personal IDs, or internal security
files ever ship in a public release.

Usage:
    python3 -m matrix.cli.prepare_release scan                          # Scan this repo
    python3 -m matrix.cli.prepare_release export                         # Clean export
    python3 -m matrix.cli.prepare_release manifest                       # Public/private manifest
    python3 -m matrix.cli.prepare_release scan --workspace ~/0pnMatrx    # Scan another repo
    python3 -m matrix.cli.prepare_release full --workspace ~/0pnMatrx    # Full pipeline

The ``--workspace`` flag lets the CLI target any checkout on disk, so the
same release tooling works for both OpenMatrix (iOS) and 0pnMatrx (runtime).
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

GREEN = "\033[32m"
WHITE = "\033[97m"
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
YELLOW = "\033[33m"
RESET = "\033[0m"

WORKSPACE = Path(__file__).resolve().parents[2]

# ── Sensitive patterns to detect ───────────────────────────────────────

SENSITIVE_PATTERNS = [
    # Private keys
    (re.compile(r'0x[0-9a-fA-F]{64}'), "private key (64-char hex)"),
    (re.compile(r'-----BEGIN (RSA |EC )?PRIVATE KEY-----'), "PEM private key"),
    # API tokens
    (re.compile(r'nvapi-[A-Za-z0-9]{48,}'), "NVIDIA API key"),
    (re.compile(r'sk-[A-Za-z0-9]{32,}'), "OpenAI API key"),
    (re.compile(r'sk-ant-[A-Za-z0-9-]{80,}'), "Anthropic API key"),
    (re.compile(r'xoxb-[0-9]{10,}-[A-Za-z0-9-]+'), "Slack bot token"),
    # Telegram bot tokens
    (re.compile(r'\d{9,10}:[A-Za-z0-9_-]{35}'), "Telegram bot token"),
    # Personal identifiers
    (re.compile(r'7161847911'), "Dardan Telegram ID"),
    (re.compile(r'0x46fF491D7054A6F500026B3E81f358190f8d8Ec5'), "NeoSafe address"),
    (re.compile(r'0x45C07600825E79e36629537BFcAC64cfB285B5ae'), "NeoWrite address"),
    # Wallet seeds/mnemonics
    (re.compile(r'\b(?:abandon|ability|able)\b(?:\s+\w+){11,23}'), "mnemonic seed phrase"),
    # Generic secrets
    (re.compile(r'password\s*[=:]\s*["\'][^"\']+["\']', re.IGNORECASE), "hardcoded password"),
    (re.compile(r'secret\s*[=:]\s*["\'][^"\']+["\']', re.IGNORECASE), "hardcoded secret"),
]

# ── Files that must NEVER be included in public releases ───────────────

PRIVATE_FILES = {
    # Security internals
    "runtime/security/gate.py",
    "runtime/security/boundary.py",
    # Audit logs
    "runtime/governance_audit.jsonl",
    "runtime/protocol_enforcement_audit.jsonl",
    "runtime/protocol_enforcement_state.json",
    "runtime/tool_executor_log.jsonl",
    "runtime/tool_executor_state.json",
    # Identity and access control
    "identity/",
    # Governance internals
    "governance/",
    # Secret paths
    ".env",
    "neowrite.env",
    "secrets/",
    # Scheduler state (contains execution history)
    "runtime/scheduler_state.json",
    "runtime/scheduler_jobs.json",
    "runtime/scheduler_tick_log.jsonl",
    # Blockchain state (contains addresses)
    "runtime/blockchain_state.json",
    # Boot status
    "boot_status.json",
    # Gateway internals
    "gateway/gateway.pid",
    "gateway/gateway.log",
    "gateway/gateway.err.log",
    "gateway/status.json",
    # Telegram state (contains chat IDs)
    "telegram/state/",
    "telegram/config.json",
    # Cache (may contain responses)
    "runtime/cache/",
    # Memory (user data)
    "data/",
    # P0/P1 runtime internals
    "p0_runtime/",
    "p1_runtime/",
    # Protocol files (internal governance)
    "protocols/",
    # Usage logs
    "runtime/usage/",
    "runtime/streams/",
    # Web search logs
    "runtime/web_search_log.jsonl",
    # HiveMind (internal coordination)
    "hivemind/",
    # Memory sync
    "runtime/memory_sync/",
    # Config with tokens
    "openmatrix.config.json",
    "openclaw.json",
}

# File extensions to skip
SKIP_EXTENSIONS = {
    ".pyc", ".pyo", ".so", ".dylib", ".dll",
    ".log", ".jsonl", ".db", ".sqlite", ".sqlite3",
    ".pid", ".lock", ".tick",
}

SKIP_DIRS = {
    "__pycache__", ".git", "node_modules", ".venv", "venv",
    ".mypy_cache", ".pytest_cache", ".tox",
}


def _is_private(path: Path, workspace: Path) -> bool:
    """Check if a file path matches the private list."""
    rel = str(path.relative_to(workspace))
    for private in PRIVATE_FILES:
        if private.endswith("/"):
            if rel.startswith(private) or f"/{private}" in f"/{rel}":
                return True
        else:
            if rel == private or rel.endswith(f"/{private}"):
                return True
    return False


def _should_skip(path: Path) -> bool:
    """Check if a file should be skipped entirely."""
    if path.suffix in SKIP_EXTENSIONS:
        return True
    for skip_dir in SKIP_DIRS:
        if skip_dir in path.parts:
            return True
    return False


def cmd_scan(workspace: Path = WORKSPACE) -> list[dict]:
    """Scan the workspace for sensitive data. Returns list of findings."""
    findings = []

    print(f"\n  {BOLD}Scanning for sensitive data...{RESET}\n")

    py_files = list(workspace.rglob("*.py"))
    json_files = list(workspace.rglob("*.json"))
    env_files = list(workspace.rglob("*.env"))
    md_files = list(workspace.rglob("*.md"))
    all_files = py_files + json_files + env_files + md_files

    scanned = 0
    for fpath in all_files:
        if _should_skip(fpath):
            continue

        try:
            content = fpath.read_text(errors="ignore")
        except Exception:
            continue

        scanned += 1
        rel = str(fpath.relative_to(workspace))

        for pattern, desc in SENSITIVE_PATTERNS:
            matches = pattern.findall(content)
            if matches:
                # Redact the actual values
                for match in matches[:3]:
                    if isinstance(match, str) and len(match) > 10:
                        redacted = match[:6] + "..." + match[-4:]
                    else:
                        redacted = str(match)[:10] + "..."

                    finding = {
                        "file": rel,
                        "type": desc,
                        "match": redacted,
                    }
                    findings.append(finding)
                    print(f"  {RED}[FOUND]{RESET} {rel}")
                    print(f"         {desc}: {DIM}{redacted}{RESET}")

    if not findings:
        print(f"  {GREEN}No sensitive data found in {scanned} files.{RESET}")
    else:
        print(f"\n  {YELLOW}{len(findings)} sensitive items found in {scanned} files.{RESET}")
        print(f"  {DIM}These will be excluded from the public export.{RESET}")

    print()
    return findings


def cmd_export(workspace: Path = WORKSPACE) -> Path:
    """Create a clean export directory with only public files."""
    export_dir = workspace / "export" / f"openmatrix-{datetime.now().strftime('%Y%m%d')}"

    print(f"\n  {BOLD}Creating clean export...{RESET}\n")

    if export_dir.exists():
        shutil.rmtree(export_dir)
    export_dir.mkdir(parents=True)

    copied = 0
    skipped = 0
    private = 0

    for fpath in sorted(workspace.rglob("*")):
        if not fpath.is_file():
            continue
        if _should_skip(fpath):
            skipped += 1
            continue
        if "export/" in str(fpath):
            continue
        if _is_private(fpath, workspace):
            private += 1
            continue

        # Check for sensitive content
        if fpath.suffix in (".py", ".json", ".md", ".txt", ".sh", ".yaml", ".yml"):
            try:
                content = fpath.read_text(errors="ignore")
                has_sensitive = False
                for pattern, desc in SENSITIVE_PATTERNS:
                    if pattern.search(content):
                        has_sensitive = True
                        break
                if has_sensitive:
                    private += 1
                    continue
            except Exception:
                pass

        # Copy to export
        rel = fpath.relative_to(workspace)
        dest = export_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(fpath, dest)
        copied += 1

    print(f"  {GREEN}Exported: {copied} files{RESET}")
    print(f"  {YELLOW}Private (excluded): {private} files{RESET}")
    print(f"  {DIM}Skipped (binary/cache): {skipped} files{RESET}")
    print(f"  {DIM}Export: {export_dir}{RESET}")
    print()

    return export_dir


def cmd_manifest(workspace: Path = WORKSPACE) -> None:
    """Generate a MANIFEST of public vs private files."""
    print(f"\n  {BOLD}Generating release manifest...{RESET}\n")

    public_files = []
    private_files = []

    for fpath in sorted(workspace.rglob("*")):
        if not fpath.is_file():
            continue
        if _should_skip(fpath):
            continue
        if "export/" in str(fpath):
            continue

        rel = str(fpath.relative_to(workspace))

        if _is_private(fpath, workspace):
            private_files.append(rel)
        else:
            # Check content for sensitive data
            has_sensitive = False
            if fpath.suffix in (".py", ".json", ".md", ".txt", ".sh"):
                try:
                    content = fpath.read_text(errors="ignore")
                    for pattern, _ in SENSITIVE_PATTERNS:
                        if pattern.search(content):
                            has_sensitive = True
                            break
                except Exception:
                    pass

            if has_sensitive:
                private_files.append(rel)
            else:
                public_files.append(rel)

    # Write manifest
    manifest_path = workspace / "RELEASE_MANIFEST.md"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    lines = [
        "# OpenMatrix Release Manifest",
        f"",
        f"**Generated:** {now}",
        f"**Public files:** {len(public_files)}",
        f"**Private files (excluded):** {len(private_files)}",
        "",
        "---",
        "",
        "## Public Files",
        "",
    ]
    for f in public_files:
        lines.append(f"- `{f}`")

    lines.extend([
        "",
        "---",
        "",
        "## Private Files (Never Released)",
        "",
    ])
    for f in private_files:
        lines.append(f"- `{f}`")

    manifest_path.write_text("\n".join(lines) + "\n")
    print(f"  {GREEN}Manifest saved: {manifest_path.name}{RESET}")
    print(f"  Public: {len(public_files)} files")
    print(f"  Private: {len(private_files)} files")
    print()


def _resolve_workspace(raw: str | None) -> Path:
    """Resolve the --workspace argument to an absolute, existing directory."""
    if raw is None:
        return WORKSPACE
    path = Path(raw).expanduser().resolve()
    if not path.is_dir():
        raise SystemExit(f"error: workspace not found: {path}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="prepare_release",
        description="OpenMatrix release preparation: scan, export, manifest.",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="scan",
        choices=("scan", "export", "manifest", "full"),
        help="Which step to run (default: scan)",
    )
    parser.add_argument(
        "--workspace",
        "-w",
        default=None,
        help="Target repository to scan/export. Defaults to the OpenMatrix repo "
             "that contains this CLI. Useful for pointing at 0pnMatrx or any "
             "other checkout.",
    )
    ns = parser.parse_args()

    workspace = _resolve_workspace(ns.workspace)
    print(f"  {DIM}Workspace: {workspace}{RESET}")

    if ns.command == "scan":
        cmd_scan(workspace)
    elif ns.command == "export":
        cmd_scan(workspace)
        cmd_export(workspace)
    elif ns.command == "manifest":
        cmd_manifest(workspace)
    elif ns.command == "full":
        cmd_scan(workspace)
        cmd_export(workspace)
        cmd_manifest(workspace)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
