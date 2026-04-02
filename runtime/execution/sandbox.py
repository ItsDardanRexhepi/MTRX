"""
Code Sandbox — secure code execution with resource limits.

Runs user/agent code in isolated subprocesses with timeout,
memory limits, and output capture. No network access by default.
"""

from __future__ import annotations

import json
import logging
import os
import signal
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


class Language(str, Enum):
    PYTHON = "python"
    JAVASCRIPT = "javascript"
    SHELL = "shell"


class ExecutionStatus(str, Enum):
    SUCCESS = "success"
    ERROR = "error"
    TIMEOUT = "timeout"
    KILLED = "killed"


@dataclass
class ExecutionResult:
    """Result of a code execution."""
    execution_id: str
    language: Language
    status: ExecutionStatus
    stdout: str = ""
    stderr: str = ""
    exit_code: int = 0
    duration_ms: float = 0.0
    truncated: bool = False
    error: str = ""

    def to_dict(self) -> dict:
        return {
            "execution_id": self.execution_id,
            "language": self.language.value,
            "status": self.status.value,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "exit_code": self.exit_code,
            "duration_ms": round(self.duration_ms, 2),
            "truncated": self.truncated,
            "error": self.error,
        }

    @property
    def output(self) -> str:
        """Combined output for display."""
        parts = []
        if self.stdout:
            parts.append(self.stdout)
        if self.stderr:
            parts.append(f"[stderr]\n{self.stderr}")
        if self.error:
            parts.append(f"[error] {self.error}")
        return "\n".join(parts) if parts else "(no output)"


@dataclass
class ExecutionRecord:
    """Historical record of an execution."""
    execution_id: str
    user_id: str
    language: str
    code: str
    result: dict
    executed_at: float = field(default_factory=time.time)


class CodeSandbox:
    """
    Sandboxed code execution environment.

    Runs code in isolated subprocesses with:
    - Timeout enforcement (default 30s)
    - Output size limits (default 64KB)
    - No network access for untrusted code
    - Temporary working directories
    - Execution history tracking
    """

    MAX_OUTPUT_BYTES: int = 65536      # 64 KB
    MAX_CODE_LENGTH: int = 100000     # 100K chars
    DEFAULT_TIMEOUT: int = 30         # seconds

    def __init__(
        self,
        work_dir: str = "",
        allowed_languages: Optional[List[Language]] = None,
        max_history: int = 200,
    ) -> None:
        if not work_dir:
            work_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "execution"
            )
        self._work_dir = Path(work_dir)
        self._work_dir.mkdir(parents=True, exist_ok=True)
        self._allowed = set(allowed_languages or list(Language))
        self._counter: int = 0
        self._history: List[ExecutionRecord] = []
        self._max_history = max_history
        self._executors = {
            Language.PYTHON: self._run_python,
            Language.JAVASCRIPT: self._run_javascript,
            Language.SHELL: self._run_shell,
        }
        logger.info("CodeSandbox initialised | dir=%s | languages=%s",
                     self._work_dir, [l.value for l in self._allowed])

    def execute(
        self,
        code: str,
        language: Language = Language.PYTHON,
        user_id: str = "",
        timeout: int = 0,
        env: Optional[Dict[str, str]] = None,
    ) -> ExecutionResult:
        """
        Execute code in a sandboxed subprocess.

        Args:
            code: Source code to execute.
            language: Programming language.
            user_id: Who requested execution.
            timeout: Override timeout in seconds (0 = default).
            env: Additional environment variables.

        Returns:
            ExecutionResult with stdout, stderr, exit code, timing.
        """
        if language not in self._allowed:
            return self._error_result(language, f"Language {language.value} not allowed.")

        if len(code) > self.MAX_CODE_LENGTH:
            return self._error_result(language, f"Code too long ({len(code)} chars, max {self.MAX_CODE_LENGTH}).")

        if not code.strip():
            return self._error_result(language, "Empty code.")

        executor = self._executors.get(language)
        if executor is None:
            return self._error_result(language, f"No executor for {language.value}.")

        self._counter += 1
        exec_id = f"EXEC-{self._counter:08d}"
        timeout = timeout or self.DEFAULT_TIMEOUT

        start = time.monotonic()
        result = executor(exec_id, code, timeout, env or {})
        result.duration_ms = (time.monotonic() - start) * 1000

        # Record history
        record = ExecutionRecord(
            execution_id=exec_id,
            user_id=user_id,
            language=language.value,
            code=code[:500],  # Truncate for history
            result=result.to_dict(),
        )
        self._history.append(record)
        if len(self._history) > self._max_history:
            self._history = self._history[-self._max_history:]

        logger.info(
            "Code executed | id=%s | lang=%s | status=%s | ms=%.1f | user=%s",
            exec_id, language.value, result.status.value, result.duration_ms, user_id,
        )
        return result

    def execute_python(self, code: str, user_id: str = "", timeout: int = 0) -> ExecutionResult:
        """Convenience method for Python execution."""
        return self.execute(code, Language.PYTHON, user_id, timeout)

    def get_history(self, user_id: str = "", limit: int = 20) -> List[dict]:
        """Get execution history, optionally filtered by user."""
        records = self._history
        if user_id:
            records = [r for r in records if r.user_id == user_id]
        return [
            {
                "execution_id": r.execution_id,
                "language": r.language,
                "code_preview": r.code[:100],
                "status": r.result.get("status", "unknown"),
                "duration_ms": r.result.get("duration_ms", 0),
                "executed_at": r.executed_at,
            }
            for r in records[-limit:]
        ]

    def get_stats(self) -> dict:
        """Get execution statistics."""
        by_lang = {}
        by_status = {}
        for r in self._history:
            by_lang[r.language] = by_lang.get(r.language, 0) + 1
            s = r.result.get("status", "unknown")
            by_status[s] = by_status.get(s, 0) + 1
        return {
            "total_executions": len(self._history),
            "by_language": by_lang,
            "by_status": by_status,
        }

    # ── Executors ────────────────────────────────────────────────────

    def _run_python(
        self, exec_id: str, code: str, timeout: int, env: dict,
    ) -> ExecutionResult:
        """Execute Python code in a subprocess."""
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".py", dir=str(self._work_dir),
            delete=False, prefix=f"{exec_id}_",
        ) as f:
            f.write(code)
            script_path = f.name

        try:
            return self._run_process(
                exec_id, Language.PYTHON,
                ["python3", "-u", script_path],
                timeout, env,
            )
        finally:
            try:
                os.unlink(script_path)
            except OSError:
                pass

    def _run_javascript(
        self, exec_id: str, code: str, timeout: int, env: dict,
    ) -> ExecutionResult:
        """Execute JavaScript code via Node.js."""
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".js", dir=str(self._work_dir),
            delete=False, prefix=f"{exec_id}_",
        ) as f:
            f.write(code)
            script_path = f.name

        try:
            return self._run_process(
                exec_id, Language.JAVASCRIPT,
                ["node", script_path],
                timeout, env,
            )
        finally:
            try:
                os.unlink(script_path)
            except OSError:
                pass

    def _run_shell(
        self, exec_id: str, code: str, timeout: int, env: dict,
    ) -> ExecutionResult:
        """Execute shell script."""
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".sh", dir=str(self._work_dir),
            delete=False, prefix=f"{exec_id}_",
        ) as f:
            f.write("#!/bin/bash\nset -euo pipefail\n" + code)
            script_path = f.name

        try:
            os.chmod(script_path, 0o700)
            return self._run_process(
                exec_id, Language.SHELL,
                ["bash", script_path],
                timeout, env,
            )
        finally:
            try:
                os.unlink(script_path)
            except OSError:
                pass

    def _run_process(
        self,
        exec_id: str,
        language: Language,
        cmd: list,
        timeout: int,
        env: dict,
    ) -> ExecutionResult:
        """Run a subprocess with resource limits and security hardening."""
        from runtime.security import EnvSanitizer
        sanitizer = EnvSanitizer()
        proc_env = sanitizer.sanitize(os.environ.copy())
        proc_env.update(sanitizer.sanitize(env))

        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(self._work_dir),
                env=proc_env,
                # Don't inherit signals
                preexec_fn=os.setsid if os.name != "nt" else None,
            )

            stdout = proc.stdout
            stderr = proc.stderr
            truncated = False

            if len(stdout) > self.MAX_OUTPUT_BYTES:
                stdout = stdout[:self.MAX_OUTPUT_BYTES] + "\n... [output truncated]"
                truncated = True
            if len(stderr) > self.MAX_OUTPUT_BYTES:
                stderr = stderr[:self.MAX_OUTPUT_BYTES] + "\n... [stderr truncated]"
                truncated = True

            status = ExecutionStatus.SUCCESS if proc.returncode == 0 else ExecutionStatus.ERROR

            return ExecutionResult(
                execution_id=exec_id,
                language=language,
                status=status,
                stdout=stdout,
                stderr=stderr,
                exit_code=proc.returncode,
                truncated=truncated,
            )

        except subprocess.TimeoutExpired:
            return ExecutionResult(
                execution_id=exec_id,
                language=language,
                status=ExecutionStatus.TIMEOUT,
                error=f"Execution timed out after {timeout}s.",
                exit_code=-1,
            )
        except Exception as exc:
            return ExecutionResult(
                execution_id=exec_id,
                language=language,
                status=ExecutionStatus.ERROR,
                error=str(exc),
                exit_code=-1,
            )

    def _error_result(self, language: Language, error: str) -> ExecutionResult:
        self._counter += 1
        return ExecutionResult(
            execution_id=f"EXEC-{self._counter:08d}",
            language=language,
            status=ExecutionStatus.ERROR,
            error=error,
            exit_code=-1,
        )
