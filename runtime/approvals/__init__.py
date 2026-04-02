"""
Exec Approvals — human-in-the-loop approval for agent actions.

When Neo wants to execute something requiring approval, the request
goes to Dardan with a plain-language description, yes/no buttons,
and a 30-minute approval window.

Better than OpenClaw: approval requests are readable by someone
who is not a developer.
"""

from runtime.approvals.approval_manager import ApprovalManager, ApprovalRequest, ApprovalStatus

__all__ = ["ApprovalManager", "ApprovalRequest", "ApprovalStatus"]
