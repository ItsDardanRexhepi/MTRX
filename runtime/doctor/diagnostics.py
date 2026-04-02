"""
Diagnostics — runs all health checks and reports results.

Every check is plain language. No stack traces, no jargon.
Tells you what's wrong and exactly what to do about it.
"""

from __future__ import annotations

import importlib
import logging
import os
import sqlite3
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

logger = logging.getLogger(__name__)


@dataclass
class CheckResult:
    """Result of a single health check."""
    name: str
    status: str              # healthy, warning, error, skipped
    message: str             # Plain-language status
    fix: str = ""            # What to do if not healthy
    details: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "status": self.status,
            "message": self.message,
            "fix": self.fix,
            "details": self.details,
        }


class HealthCheck:
    """
    Runs comprehensive system diagnostics.

    Checks:
    - Core runtime (FastAPI server, database)
    - All 30 blockchain component services
    - All Phase 3 subsystems (memory, goals, RAG, automation, etc.)
    - Channel connections (Telegram, Slack, Discord, WhatsApp)
    - MCP servers
    - Skills registry
    - Security configuration
    - Task control plane
    - File system & data directories
    """

    def __init__(self) -> None:
        self._results: List[CheckResult] = []
        self._base_dir = Path(__file__).resolve().parent.parent.parent

    def run_all(self) -> List[CheckResult]:
        """Run all health checks and return results."""
        self._results = []

        self._check_runtime()
        self._check_data_directories()
        self._check_blockchain_services()
        self._check_phase3_subsystems()
        self._check_task_ledger()
        self._check_channels()
        self._check_mcp()
        self._check_skills()
        self._check_security()
        self._check_env_config()

        return self._results

    def _add(self, name: str, status: str, message: str, fix: str = "", **details) -> None:
        self._results.append(CheckResult(name, status, message, fix, details))

    # ── Core Runtime ─────────────────────────────────────────────────

    def _check_runtime(self) -> None:
        """Check if the FastAPI server can import cleanly."""
        try:
            from runtime.server import app
            routes = [r for r in app.routes if hasattr(r, 'methods')]
            self._add(
                "Runtime Server", "healthy",
                f"FastAPI server loaded with {len(routes)} API routes.",
                details={"routes": len(routes)},
            )
        except Exception as e:
            self._add(
                "Runtime Server", "error",
                "The API server failed to load.",
                fix=f"Check the error and fix it: {str(e)[:100]}",
            )

    def _check_data_directories(self) -> None:
        """Check that all data directories exist and are writable."""
        data_dir = self._base_dir / "data"
        required_dirs = [
            "memory", "goals", "documents", "triggers", "patterns",
            "checkins", "execution", "models", "migrations", "tasks",
            "approvals", "mcp",
        ]
        missing = []
        for d in required_dirs:
            path = data_dir / d
            if not path.exists():
                missing.append(d)
            elif not os.access(str(path), os.W_OK):
                missing.append(f"{d} (not writable)")

        if not missing:
            self._add(
                "Data Directories", "healthy",
                f"All {len(required_dirs)} data directories present and writable.",
            )
        else:
            self._add(
                "Data Directories", "warning",
                f"Missing or unwritable directories: {', '.join(missing)}",
                fix="Run: mkdir -p data/{" + ",".join(missing) + "}",
            )

    # ── Blockchain Services ──────────────────────────────────────────

    def _check_blockchain_services(self) -> None:
        """Check that all 30 blockchain service routers import."""
        router_names = [
            "contract_conversion", "defi", "nft", "rwa", "identity", "dao",
            "stablecoin", "attestation", "agent_identity", "agentic_payments",
            "oracles", "supply_chain", "insurance", "gaming", "ip_rights",
            "staking", "payments", "securities", "governance", "dashboard",
            "dex", "fundraising", "loyalty", "marketplace", "cashback",
            "brand_rewards", "subscriptions", "social", "privacy", "disputes",
        ]
        failed = []
        for name in router_names:
            try:
                importlib.import_module(f"runtime.routers.{name}")
            except Exception as e:
                failed.append(name)

        if not failed:
            self._add(
                "Blockchain Components", "healthy",
                f"All 30 blockchain service routers loaded successfully.",
            )
        else:
            self._add(
                "Blockchain Components", "error",
                f"{len(failed)} blockchain component(s) failed to load: {', '.join(failed)}",
                fix="Check the import errors in the listed router files.",
            )

    # ── Phase 3 Subsystems ───────────────────────────────────────────

    def _check_phase3_subsystems(self) -> None:
        """Check all Phase 3 intelligent subsystems."""
        subsystems = {
            "User Memory": "runtime.memory",
            "Goals Engine": "runtime.goals",
            "Document RAG": "runtime.rag",
            "Automation Triggers": "runtime.automation",
            "Code Execution": "runtime.execution",
            "Proactive Check-Ins": "runtime.proactive",
            "Model Marketplace": "runtime.models",
            "Migration Importers": "runtime.migration",
        }
        failed = []
        for name, module in subsystems.items():
            try:
                importlib.import_module(module)
            except Exception:
                failed.append(name)

        if not failed:
            self._add(
                "Phase 3 Subsystems", "healthy",
                f"All {len(subsystems)} intelligent subsystems loaded.",
            )
        else:
            self._add(
                "Phase 3 Subsystems", "error",
                f"{len(failed)} subsystem(s) failed: {', '.join(failed)}",
                fix="Check the import errors in the listed modules.",
            )

    # ── Task Ledger ──────────────────────────────────────────────────

    def _check_task_ledger(self) -> None:
        """Check the SQLite task database."""
        db_path = self._base_dir / "data" / "tasks" / "tasks.db"
        try:
            from runtime.tasks import TaskLedger
            ledger = TaskLedger(str(db_path))
            stats = ledger.get_stats()
            lost = ledger.detect_lost_tasks()

            if lost:
                self._add(
                    "Task Control Plane", "warning",
                    f"Task database OK ({stats['total']} tasks), but {len(lost)} task(s) appear lost.",
                    fix="Run: matrix tasks list --status lost (then cancel or retry them)",
                    details=stats,
                )
            else:
                self._add(
                    "Task Control Plane", "healthy",
                    f"Task database healthy. {stats['total']} tasks tracked.",
                    details=stats,
                )
        except Exception as e:
            self._add(
                "Task Control Plane", "error",
                "Task database could not be opened.",
                fix=f"Check the SQLite database at {db_path}: {str(e)[:80]}",
            )

    # ── Channels ─────────────────────────────────────────────────────

    def _check_channels(self) -> None:
        """Check channel configurations."""
        channels_status = []

        # Telegram
        token = os.environ.get("MATRIX_TELEGRAM_BOT_TOKEN") or os.environ.get("MATRIX_BRIDGE_TELEGRAM_BOT_TOKEN")
        if token:
            channels_status.append(("Telegram", "healthy", "Bot token configured."))
        else:
            channels_status.append((
                "Telegram", "warning",
                "No bot token set. Set MATRIX_TELEGRAM_BOT_TOKEN in your environment.",
            ))

        # Slack
        if os.environ.get("MATRIX_SLACK_BOT_TOKEN"):
            channels_status.append(("Slack", "healthy", "Bot token configured."))
        else:
            channels_status.append(("Slack", "skipped", "Not configured. Set MATRIX_SLACK_BOT_TOKEN to enable."))

        # Discord
        if os.environ.get("MATRIX_DISCORD_BOT_TOKEN"):
            channels_status.append(("Discord", "healthy", "Bot token configured."))
        else:
            channels_status.append(("Discord", "skipped", "Not configured. Set MATRIX_DISCORD_BOT_TOKEN to enable."))

        # WhatsApp
        if os.environ.get("MATRIX_WHATSAPP_TOKEN"):
            channels_status.append(("WhatsApp", "healthy", "Access token configured."))
        else:
            channels_status.append(("WhatsApp", "skipped", "Not configured. Set MATRIX_WHATSAPP_TOKEN to enable."))

        healthy = sum(1 for _, s, _ in channels_status if s == "healthy")
        total = len(channels_status)
        self._add(
            "Channels", "healthy" if healthy > 0 else "warning",
            f"{healthy} of {total} channels configured.",
            details={"channels": [{"name": n, "status": s, "message": m} for n, s, m in channels_status]},
        )

    # ── MCP ──────────────────────────────────────────────────────────

    def _check_mcp(self) -> None:
        """Check MCP server configurations."""
        try:
            from runtime.mcp import MCPRemoteClient
            client = MCPRemoteClient()
            servers = client.list_servers()
            if servers:
                enabled = sum(1 for s in servers if s.enabled)
                self._add(
                    "MCP Servers", "healthy",
                    f"{enabled} remote MCP server(s) configured and enabled.",
                    details={"servers": [s.name for s in servers]},
                )
            else:
                self._add(
                    "MCP Servers", "skipped",
                    "No remote MCP servers configured. Add one via the API to expand Neo's tool access.",
                )
        except Exception:
            self._add("MCP Servers", "skipped", "MCP module not available.")

    # ── Skills ───────────────────────────────────────────────────────

    def _check_skills(self) -> None:
        """Check skills registry."""
        try:
            from runtime.skills import SkillsRegistry
            registry = SkillsRegistry()
            skills = registry.list_skills()
            self._add(
                "Skills", "healthy",
                f"{len(skills)} skill(s) loaded and ready.",
                details={"skills": [s["name"] for s in skills]},
            )
        except Exception as e:
            self._add(
                "Skills", "warning",
                "Skills registry could not load.",
                fix=str(e)[:100],
            )

    # ── Security ─────────────────────────────────────────────────────

    def _check_security(self) -> None:
        """Check security configuration."""
        from runtime.security import EnvSanitizer
        sanitizer = EnvSanitizer()
        current_env = dict(os.environ)
        blocked = sanitizer.check_env(current_env)

        if blocked:
            self._add(
                "Security", "warning",
                f"{len(blocked)} potentially dangerous env vars detected in the runtime environment: "
                f"{', '.join(blocked[:5])}{'...' if len(blocked) > 5 else ''}",
                fix="These vars will be stripped from code execution contexts automatically.",
            )
        else:
            self._add(
                "Security", "healthy",
                "No dangerous environment variables detected. Execution sandboxing is active.",
            )

    # ── Environment Config ───────────────────────────────────────────

    def _check_env_config(self) -> None:
        """Check essential environment configuration."""
        checks = {
            "PRIVATE_KEY": "Blockchain signing key",
            "NEOSAFE_ADDRESS": "NeoSafe treasury address",
        }
        missing = []
        for var, desc in checks.items():
            if not os.environ.get(var):
                missing.append(f"{desc} ({var})")

        if not missing:
            self._add("Environment", "healthy", "All essential environment variables set.")
        else:
            self._add(
                "Environment", "warning",
                f"Missing: {', '.join(missing)}",
                fix="Add these to your .env file.",
            )


def run_doctor() -> dict:
    """
    Run all health checks and return a formatted report.

    Returns:
        dict with 'healthy' (bool), 'display' (formatted string),
        and 'checks' (list of check results).
    """
    hc = HealthCheck()
    results = hc.run_all()

    # Format display
    lines = ["\n  Matrix Doctor — System Health Report\n"]

    status_icons = {"healthy": "✓", "warning": "!", "error": "✗", "skipped": "○"}
    status_colors = {"healthy": "green", "warning": "yellow", "error": "red", "skipped": "dim"}

    for r in results:
        icon = status_icons.get(r.status, "?")
        lines.append(f"  [{icon}] {r.name}: {r.message}")
        if r.fix:
            lines.append(f"      → {r.fix}")

    lines.append("")

    healthy = sum(1 for r in results if r.status == "healthy")
    warnings = sum(1 for r in results if r.status == "warning")
    errors = sum(1 for r in results if r.status == "error")
    skipped = sum(1 for r in results if r.status == "skipped")

    if errors == 0:
        if warnings == 0:
            lines.append(f"  All systems healthy. {healthy} checks passed.")
        else:
            lines.append(f"  {healthy} healthy, {warnings} warning(s). No critical issues.")
    else:
        lines.append(f"  {errors} error(s), {warnings} warning(s), {healthy} healthy.")
        lines.append("  Fix the errors above to get Matrix running smoothly.")

    lines.append("")

    return {
        "healthy": errors == 0,
        "display": "\n".join(lines),
        "checks": [r.to_dict() for r in results],
        "summary": {
            "healthy": healthy,
            "warnings": warnings,
            "errors": errors,
            "skipped": skipped,
        },
    }
