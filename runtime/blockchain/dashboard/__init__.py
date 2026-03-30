"""
Component 20 — Unified Dashboard

Provides a single unified view of all 30 MTRX components in plain English.
Activity-based visibility: components with no activity are hidden.
APY data sourced exclusively from Component 16 APYCalculator.
"""

from runtime.blockchain.dashboard.dashboard import UnifiedDashboard

__all__ = ["UnifiedDashboard"]
