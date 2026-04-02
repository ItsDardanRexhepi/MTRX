"""
Inline Code Execution — agents write code, run it, show results in conversation.

Sandboxed execution with resource limits, output capture, and
support for Python, JavaScript (via Node), and shell scripts.
"""

from runtime.execution.sandbox import CodeSandbox, ExecutionResult, Language

__all__ = ["CodeSandbox", "ExecutionResult", "Language"]
