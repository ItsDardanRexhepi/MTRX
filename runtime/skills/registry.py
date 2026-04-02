"""
Skills Registry — auto-discovers and loads Python skill files.

A skill is any Python file in the skills directory that follows
the standard interface:

    SKILL_NAME = "my_skill"
    SKILL_DESCRIPTION = "What this skill does"
    SKILL_VERSION = "1.0"
    SKILL_AGENT = "all"  # or "neo", "trinity", "morpheus"

    async def execute(context: dict) -> dict:
        # Do the thing
        return {"result": "done"}

No SDK, no build step, no registration. Just drop it in and go.
"""

from __future__ import annotations

import importlib.util
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class Skill:
    """A loaded skill."""
    name: str
    description: str
    version: str = "1.0"
    agent: str = "all"                 # all, neo, trinity, morpheus
    file_path: str = ""
    execute_fn: Optional[Callable] = None
    loaded_at: float = field(default_factory=time.time)
    call_count: int = 0
    last_error: str = ""
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "agent": self.agent,
            "file_path": self.file_path,
            "loaded_at": self.loaded_at,
            "call_count": self.call_count,
            "last_error": self.last_error,
            "tags": self.tags,
        }


class SkillsRegistry:
    """
    Auto-discovers and manages Python skill files.

    Skills are Python files in the skills directory. They are
    automatically loaded on startup and reloadable at runtime.
    Any agent can use any skill (unless restricted by SKILL_AGENT).
    """

    def __init__(self, skills_dir: str = "") -> None:
        if not skills_dir:
            skills_dir = str(
                Path(__file__).resolve().parent.parent.parent / "skills"
            )
        self._skills_dir = Path(skills_dir)
        self._skills_dir.mkdir(parents=True, exist_ok=True)
        self._skills: Dict[str, Skill] = {}
        self._load_all()
        logger.info("SkillsRegistry initialised | dir=%s | skills=%d",
                     self._skills_dir, len(self._skills))

    def reload(self) -> int:
        """Reload all skills from disk."""
        self._skills.clear()
        self._load_all()
        return len(self._skills)

    def list_skills(self, agent: str = "") -> List[dict]:
        """List available skills, optionally filtered by agent."""
        skills = list(self._skills.values())
        if agent:
            skills = [s for s in skills if s.agent in ("all", agent)]
        return [s.to_dict() for s in skills]

    def get_skill(self, name: str) -> Optional[Skill]:
        return self._skills.get(name)

    async def execute_skill(
        self, name: str, context: dict, agent: str = "",
    ) -> dict:
        """
        Execute a skill by name.

        Args:
            name: Skill name.
            context: Execution context (user_id, input, etc.).
            agent: Which agent is calling.

        Returns:
            Result dict from the skill.
        """
        skill = self._skills.get(name)
        if skill is None:
            return {"error": f"Skill '{name}' not found.", "success": False}

        if agent and skill.agent not in ("all", agent):
            return {
                "error": f"Skill '{name}' is only available to {skill.agent}.",
                "success": False,
            }

        if skill.execute_fn is None:
            return {"error": f"Skill '{name}' has no execute function.", "success": False}

        try:
            import asyncio
            if asyncio.iscoroutinefunction(skill.execute_fn):
                result = await skill.execute_fn(context)
            else:
                result = skill.execute_fn(context)
            skill.call_count += 1
            skill.last_error = ""
            return {"result": result, "success": True, "skill": name}
        except Exception as exc:
            skill.last_error = str(exc)
            logger.exception("Skill execution failed | skill=%s", name)
            return {"error": str(exc), "success": False, "skill": name}

    def get_stats(self) -> dict:
        return {
            "total_skills": len(self._skills),
            "by_agent": {
                agent: sum(1 for s in self._skills.values() if s.agent == agent)
                for agent in set(s.agent for s in self._skills.values())
            },
            "total_calls": sum(s.call_count for s in self._skills.values()),
        }

    # ── Internal ─────────────────────────────────────────────────────

    def _load_all(self) -> None:
        """Discover and load all .py files in the skills directory."""
        for py_file in self._skills_dir.glob("*.py"):
            if py_file.name.startswith("_"):
                continue
            try:
                self._load_skill(py_file)
            except Exception:
                logger.exception("Failed to load skill | file=%s", py_file)

    def _load_skill(self, file_path: Path) -> None:
        """Load a single skill file."""
        module_name = f"matrix_skill_{file_path.stem}"

        spec = importlib.util.spec_from_file_location(module_name, str(file_path))
        if spec is None or spec.loader is None:
            return

        module = importlib.util.module_from_spec(spec)
        # Don't pollute sys.modules permanently
        try:
            spec.loader.exec_module(module)
        except Exception as exc:
            logger.warning("Failed to load skill %s: %s", file_path.stem, exc)
            return

        name = getattr(module, "SKILL_NAME", file_path.stem)
        description = getattr(module, "SKILL_DESCRIPTION", "")
        version = getattr(module, "SKILL_VERSION", "1.0")
        agent = getattr(module, "SKILL_AGENT", "all")
        tags = getattr(module, "SKILL_TAGS", [])
        execute_fn = getattr(module, "execute", None)

        if not description:
            # Try to get from module docstring
            description = (module.__doc__ or "").strip().split("\n")[0]

        skill = Skill(
            name=name,
            description=description,
            version=version,
            agent=agent,
            file_path=str(file_path),
            execute_fn=execute_fn,
            tags=tags,
        )
        self._skills[name] = skill
        logger.info("Skill loaded | name=%s | agent=%s | file=%s",
                     name, agent, file_path.name)
