"""
Migration data types — universal format for imported agents, tools, and workflows.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class ImportSource(str, Enum):
    LANGCHAIN = "langchain"
    AUTOGPT = "autogpt"
    OPENAI_ASSISTANTS = "openai_assistants"
    CREWAI = "crewai"
    ZAPIER = "zapier"
    OPENAI_COMPATIBLE = "openai_compatible"
    GENERIC = "generic"


@dataclass
class ToolDefinition:
    """A tool imported from another framework."""
    name: str
    description: str
    tool_type: str = "function"
    parameters: dict = field(default_factory=dict)
    source_config: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "description": self.description,
            "tool_type": self.tool_type,
            "parameters": self.parameters,
            "source_config": self.source_config,
        }


@dataclass
class AgentDefinition:
    """An agent imported from another framework."""
    name: str
    role: str
    system_prompt: str
    model: str = ""
    tools: List[ToolDefinition] = field(default_factory=list)
    temperature: float = 0.7
    max_tokens: int = 4096
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "role": self.role,
            "system_prompt": self.system_prompt,
            "model": self.model,
            "tools": [t.to_dict() for t in self.tools],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "metadata": self.metadata,
        }


@dataclass
class WorkflowStep:
    """A step in an imported workflow."""
    name: str
    agent: str = ""
    action: str = ""
    inputs: dict = field(default_factory=dict)
    outputs: List[str] = field(default_factory=list)
    condition: str = ""

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "agent": self.agent,
            "action": self.action,
            "inputs": self.inputs,
            "outputs": self.outputs,
            "condition": self.condition,
        }


@dataclass
class WorkflowDefinition:
    """A workflow/chain imported from another framework."""
    name: str
    description: str
    steps: List[WorkflowStep] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "description": self.description,
            "steps": [s.to_dict() for s in self.steps],
            "metadata": self.metadata,
        }


@dataclass
class ImportResult:
    """Result of a migration import."""
    source: ImportSource
    success: bool
    agents: List[AgentDefinition] = field(default_factory=list)
    tools: List[ToolDefinition] = field(default_factory=list)
    workflows: List[WorkflowDefinition] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    imported_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        return {
            "source": self.source.value,
            "success": self.success,
            "agents": [a.to_dict() for a in self.agents],
            "tools": [t.to_dict() for t in self.tools],
            "workflows": [w.to_dict() for w in self.workflows],
            "warnings": self.warnings,
            "errors": self.errors,
            "summary": {
                "agents_imported": len(self.agents),
                "tools_imported": len(self.tools),
                "workflows_imported": len(self.workflows),
            },
            "imported_at": self.imported_at,
        }
