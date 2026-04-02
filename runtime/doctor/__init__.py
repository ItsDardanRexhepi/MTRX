"""
Matrix Doctor — comprehensive system health diagnostics.

Checks the health of every system: blockchain components, Phase 3 subsystems,
channels, cron jobs, model routing, security, and more.

Reports in plain language: what's healthy, what needs attention,
and exactly what to do to fix anything broken.
"""

from runtime.doctor.diagnostics import run_doctor, HealthCheck, CheckResult

__all__ = ["run_doctor", "HealthCheck", "CheckResult"]
