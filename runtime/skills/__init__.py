"""
Skills Marketplace — drop-in Python skills for all three agents.

Better than OpenClaw: no SDK required, no build step.
Just a Python file with a standard interface, dropped in the skills folder,
and immediately available to Neo, Trinity, and Morpheus.
"""

from runtime.skills.registry import SkillsRegistry, Skill

__all__ = ["SkillsRegistry", "Skill"]
