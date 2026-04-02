"""
Migration Engine — parses and imports configurations from other AI frameworks.

Supports LangChain, AutoGPT, OpenAI Assistants, CrewAI, Zapier,
and generic OpenAI-compatible formats.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from runtime.migration.formats import (
    AgentDefinition, ImportResult, ImportSource, ToolDefinition,
    WorkflowDefinition, WorkflowStep,
)

logger = logging.getLogger(__name__)


class MigrationEngine:
    """
    Universal migration engine.

    Import agents, tools, and workflows from:
    - LangChain (chain configs, agent configs, tool specs)
    - AutoGPT (agent.json, ai_settings.yaml)
    - OpenAI Assistants (assistant objects from API)
    - CrewAI (crew configs, agent/task definitions)
    - Zapier (zap definitions, action mappings)
    - Generic OpenAI-compatible (function calling schema)
    """

    def __init__(self, storage_dir: str = "") -> None:
        if not storage_dir:
            storage_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "migrations"
            )
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._history: List[ImportResult] = []
        self._importers = {
            ImportSource.LANGCHAIN: self._import_langchain,
            ImportSource.AUTOGPT: self._import_autogpt,
            ImportSource.OPENAI_ASSISTANTS: self._import_openai_assistants,
            ImportSource.CREWAI: self._import_crewai,
            ImportSource.ZAPIER: self._import_zapier,
            ImportSource.OPENAI_COMPATIBLE: self._import_openai_compatible,
            ImportSource.GENERIC: self._import_generic,
        }
        logger.info("MigrationEngine initialised.")

    def import_config(
        self,
        source: ImportSource,
        config: dict,
        user_id: str = "",
    ) -> ImportResult:
        """
        Import a configuration from a supported source.

        Args:
            source: The source framework.
            config: The configuration data (parsed JSON/YAML).
            user_id: Who is importing.

        Returns:
            ImportResult with imported agents, tools, workflows.
        """
        importer = self._importers.get(source)
        if importer is None:
            return ImportResult(
                source=source, success=False,
                errors=[f"Unsupported source: {source.value}"],
            )

        try:
            result = importer(config)
        except Exception as exc:
            logger.exception("Import failed | source=%s", source.value)
            result = ImportResult(
                source=source, success=False,
                errors=[f"Import error: {str(exc)}"],
            )

        # Persist result
        self._history.append(result)
        self._persist_result(result, user_id)

        logger.info(
            "Import completed | source=%s | agents=%d | tools=%d | workflows=%d | success=%s",
            source.value, len(result.agents), len(result.tools),
            len(result.workflows), result.success,
        )
        return result

    def import_from_file(
        self,
        source: ImportSource,
        file_path: str,
        user_id: str = "",
    ) -> ImportResult:
        """Import from a JSON file."""
        try:
            with open(file_path) as f:
                config = json.load(f)
        except Exception as exc:
            return ImportResult(
                source=source, success=False,
                errors=[f"Failed to read file: {str(exc)}"],
            )
        return self.import_config(source, config, user_id)

    def get_history(self, limit: int = 20) -> List[dict]:
        return [r.to_dict() for r in self._history[-limit:]]

    def get_supported_sources(self) -> List[dict]:
        return [
            {"source": s.value, "description": d}
            for s, d in [
                (ImportSource.LANGCHAIN, "LangChain chains, agents, and tools"),
                (ImportSource.AUTOGPT, "AutoGPT agent configurations"),
                (ImportSource.OPENAI_ASSISTANTS, "OpenAI Assistants API objects"),
                (ImportSource.CREWAI, "CrewAI crew, agent, and task definitions"),
                (ImportSource.ZAPIER, "Zapier zap definitions and actions"),
                (ImportSource.OPENAI_COMPATIBLE, "OpenAI function calling schemas"),
                (ImportSource.GENERIC, "Generic agent/tool/workflow definitions"),
            ]
        ]

    # ── LangChain Importer ───────────────────────────────────────────

    def _import_langchain(self, config: dict) -> ImportResult:
        """Import LangChain chain/agent configurations."""
        agents = []
        tools = []
        workflows = []
        warnings = []

        # Import agent configs
        if "agent" in config:
            agent_cfg = config["agent"]
            agent = AgentDefinition(
                name=agent_cfg.get("name", "LangChain Agent"),
                role=agent_cfg.get("agent_type", "conversational"),
                system_prompt=agent_cfg.get("system_message", agent_cfg.get("prefix", "")),
                model=self._extract_model(agent_cfg),
                temperature=agent_cfg.get("temperature", 0.7),
                metadata={"source": "langchain", "agent_type": agent_cfg.get("agent_type", "")},
            )
            agents.append(agent)

        # Import tools
        for tool_cfg in config.get("tools", []):
            tool = ToolDefinition(
                name=tool_cfg.get("name", "unknown"),
                description=tool_cfg.get("description", ""),
                tool_type=tool_cfg.get("type", "function"),
                parameters=tool_cfg.get("args_schema", tool_cfg.get("parameters", {})),
                source_config=tool_cfg,
            )
            tools.append(tool)

        # Import chains as workflows
        if "chain" in config:
            chain = config["chain"]
            wf = self._chain_to_workflow(chain)
            workflows.append(wf)

        for chain_cfg in config.get("chains", []):
            workflows.append(self._chain_to_workflow(chain_cfg))

        # Import retriever config
        if "retriever" in config:
            warnings.append("Retriever config detected — Matrix uses built-in BM25 retrieval; "
                          "vector store settings will need manual migration.")

        # Import memory config
        if "memory" in config:
            warnings.append("Memory config detected — Matrix has built-in persistent memory; "
                          "LangChain memory settings mapped to Matrix memory system.")

        return ImportResult(
            source=ImportSource.LANGCHAIN,
            success=True,
            agents=agents,
            tools=tools,
            workflows=workflows,
            warnings=warnings,
        )

    def _chain_to_workflow(self, chain_cfg: dict) -> WorkflowDefinition:
        """Convert a LangChain chain config to a workflow."""
        steps = []
        for i, step in enumerate(chain_cfg.get("steps", chain_cfg.get("chains", []))):
            ws = WorkflowStep(
                name=step.get("name", f"step_{i+1}"),
                action=step.get("type", step.get("_type", "llm_chain")),
                inputs=step.get("input_variables", {}),
                outputs=step.get("output_variables", step.get("output_key", [])),
            )
            if isinstance(ws.outputs, str):
                ws.outputs = [ws.outputs]
            steps.append(ws)

        return WorkflowDefinition(
            name=chain_cfg.get("name", "Imported Chain"),
            description=chain_cfg.get("description", "Imported from LangChain"),
            steps=steps,
            metadata={"source": "langchain", "chain_type": chain_cfg.get("_type", "")},
        )

    # ── AutoGPT Importer ─────────────────────────────────────────────

    def _import_autogpt(self, config: dict) -> ImportResult:
        """Import AutoGPT agent.json / ai_settings configuration."""
        agents = []
        tools = []
        warnings = []

        name = config.get("ai_name", config.get("name", "AutoGPT Agent"))
        role = config.get("ai_role", config.get("role", "general assistant"))
        goals = config.get("ai_goals", config.get("goals", []))

        # Build system prompt from AutoGPT format
        prompt_parts = [f"You are {name}. Your role: {role}."]
        if goals:
            prompt_parts.append("Your goals:")
            for i, goal in enumerate(goals, 1):
                prompt_parts.append(f"{i}. {goal}")

        constraints = config.get("constraints", [])
        if constraints:
            prompt_parts.append("\nConstraints:")
            for c in constraints:
                prompt_parts.append(f"- {c}")

        agent = AgentDefinition(
            name=name,
            role=role,
            system_prompt="\n".join(prompt_parts),
            model=config.get("model", config.get("llm_model", "")),
            temperature=config.get("temperature", 0.5),
            metadata={
                "source": "autogpt",
                "goals": goals,
                "budget": config.get("budget", None),
            },
        )

        # Import commands as tools
        for cmd in config.get("commands", config.get("allowed_commands", [])):
            if isinstance(cmd, str):
                tool = ToolDefinition(name=cmd, description=f"AutoGPT command: {cmd}")
            elif isinstance(cmd, dict):
                tool = ToolDefinition(
                    name=cmd.get("name", "unknown"),
                    description=cmd.get("description", ""),
                    parameters=cmd.get("parameters", {}),
                    source_config=cmd,
                )
            else:
                continue
            tools.append(tool)
            agent.tools.append(tool)

        agents.append(agent)

        if config.get("plugins"):
            warnings.append(f"AutoGPT plugins detected ({len(config['plugins'])}). "
                          "Plugins require manual integration.")

        return ImportResult(
            source=ImportSource.AUTOGPT,
            success=True,
            agents=agents,
            tools=tools,
            warnings=warnings,
        )

    # ── OpenAI Assistants Importer ───────────────────────────────────

    def _import_openai_assistants(self, config: dict) -> ImportResult:
        """Import OpenAI Assistants API format."""
        agents = []
        tools = []
        warnings = []

        # Single assistant or list
        assistants = config.get("assistants", [config] if "id" in config or "name" in config else [])

        for asst in assistants:
            asst_tools = []
            for tool_cfg in asst.get("tools", []):
                tool_type = tool_cfg.get("type", "")
                if tool_type == "function":
                    fn = tool_cfg.get("function", {})
                    tool = ToolDefinition(
                        name=fn.get("name", "unknown"),
                        description=fn.get("description", ""),
                        parameters=fn.get("parameters", {}),
                        source_config=tool_cfg,
                    )
                    tools.append(tool)
                    asst_tools.append(tool)
                elif tool_type == "code_interpreter":
                    warnings.append("Code interpreter tool detected — Matrix has built-in code execution.")
                elif tool_type == "file_search":
                    warnings.append("File search tool detected — Matrix has built-in document RAG.")

            agent = AgentDefinition(
                name=asst.get("name", "OpenAI Assistant"),
                role=asst.get("description", "assistant"),
                system_prompt=asst.get("instructions", ""),
                model=asst.get("model", ""),
                tools=asst_tools,
                temperature=asst.get("temperature", 1.0),
                metadata={
                    "source": "openai_assistants",
                    "assistant_id": asst.get("id", ""),
                    "file_ids": asst.get("file_ids", []),
                    "response_format": asst.get("response_format", None),
                },
            )
            agents.append(agent)

        return ImportResult(
            source=ImportSource.OPENAI_ASSISTANTS,
            success=True,
            agents=agents,
            tools=tools,
            warnings=warnings,
        )

    # ── CrewAI Importer ──────────────────────────────────────────────

    def _import_crewai(self, config: dict) -> ImportResult:
        """Import CrewAI crew/agent/task definitions."""
        agents = []
        tools = []
        workflows = []
        warnings = []

        # Import agents
        for agent_cfg in config.get("agents", []):
            agent_tools = []
            for tool_name in agent_cfg.get("tools", []):
                if isinstance(tool_name, str):
                    tool = ToolDefinition(name=tool_name, description=f"CrewAI tool: {tool_name}")
                elif isinstance(tool_name, dict):
                    tool = ToolDefinition(
                        name=tool_name.get("name", "unknown"),
                        description=tool_name.get("description", ""),
                        parameters=tool_name.get("parameters", {}),
                    )
                else:
                    continue
                tools.append(tool)
                agent_tools.append(tool)

            agent = AgentDefinition(
                name=agent_cfg.get("name", agent_cfg.get("role", "Agent")),
                role=agent_cfg.get("role", ""),
                system_prompt=agent_cfg.get("backstory", agent_cfg.get("goal", "")),
                model=agent_cfg.get("llm", ""),
                tools=agent_tools,
                metadata={
                    "source": "crewai",
                    "goal": agent_cfg.get("goal", ""),
                    "allow_delegation": agent_cfg.get("allow_delegation", True),
                    "verbose": agent_cfg.get("verbose", False),
                },
            )
            agents.append(agent)

        # Import tasks as workflow
        tasks = config.get("tasks", [])
        if tasks:
            steps = []
            for i, task in enumerate(tasks):
                step = WorkflowStep(
                    name=task.get("description", f"Task {i+1}")[:80],
                    agent=task.get("agent", ""),
                    action="execute_task",
                    inputs={"expected_output": task.get("expected_output", "")},
                    outputs=[task.get("output_key", f"task_{i+1}_output")],
                )
                steps.append(step)

            wf = WorkflowDefinition(
                name=config.get("name", "Imported Crew"),
                description=config.get("description", "Imported from CrewAI"),
                steps=steps,
                metadata={
                    "source": "crewai",
                    "process": config.get("process", "sequential"),
                },
            )
            workflows.append(wf)

        return ImportResult(
            source=ImportSource.CREWAI,
            success=True,
            agents=agents,
            tools=tools,
            workflows=workflows,
            warnings=warnings,
        )

    # ── Zapier Importer ──────────────────────────────────────────────

    def _import_zapier(self, config: dict) -> ImportResult:
        """Import Zapier zap definitions."""
        tools = []
        workflows = []
        warnings = []

        # Import zaps as workflows
        zaps = config.get("zaps", [config] if "trigger" in config else [])

        for zap in zaps:
            steps = []

            # Trigger as first step
            trigger = zap.get("trigger", {})
            if trigger:
                step = WorkflowStep(
                    name=trigger.get("label", "Trigger"),
                    action=trigger.get("app", "trigger"),
                    inputs=trigger.get("params", {}),
                    outputs=["trigger_data"],
                )
                steps.append(step)

                # Create a tool from the trigger
                tool = ToolDefinition(
                    name=f"zapier_{trigger.get('app', 'unknown')}_{trigger.get('action', 'trigger')}",
                    description=trigger.get("label", "Zapier trigger"),
                    tool_type="webhook",
                    source_config=trigger,
                )
                tools.append(tool)

            # Actions as subsequent steps
            for i, action in enumerate(zap.get("actions", [])):
                step = WorkflowStep(
                    name=action.get("label", f"Action {i+1}"),
                    action=action.get("app", "action"),
                    inputs=action.get("params", {}),
                    outputs=[f"action_{i+1}_result"],
                )
                steps.append(step)

                tool = ToolDefinition(
                    name=f"zapier_{action.get('app', 'unknown')}_{action.get('action', 'do')}",
                    description=action.get("label", "Zapier action"),
                    tool_type="api_call",
                    source_config=action,
                )
                tools.append(tool)

            wf = WorkflowDefinition(
                name=zap.get("name", zap.get("title", "Imported Zap")),
                description=zap.get("description", "Imported from Zapier"),
                steps=steps,
                metadata={"source": "zapier", "zap_id": zap.get("id", "")},
            )
            workflows.append(wf)

        warnings.append("Zapier app connections require separate authentication setup in Matrix.")

        return ImportResult(
            source=ImportSource.ZAPIER,
            success=True,
            tools=tools,
            workflows=workflows,
            warnings=warnings,
        )

    # ── OpenAI Compatible Importer ───────────────────────────────────

    def _import_openai_compatible(self, config: dict) -> ImportResult:
        """Import generic OpenAI function calling schemas."""
        tools = []
        agents = []
        warnings = []

        # Import function definitions
        functions = config.get("functions", config.get("tools", []))
        for fn in functions:
            # Handle both formats: direct function def or wrapped in {"type": "function", "function": {...}}
            if "function" in fn and isinstance(fn["function"], dict):
                fn_def = fn["function"]
            else:
                fn_def = fn

            tool = ToolDefinition(
                name=fn_def.get("name", "unknown"),
                description=fn_def.get("description", ""),
                parameters=fn_def.get("parameters", {}),
                source_config=fn_def,
            )
            tools.append(tool)

        # Import model config as agent
        if config.get("model") or config.get("messages"):
            system_msg = ""
            for msg in config.get("messages", []):
                if msg.get("role") == "system":
                    system_msg = msg.get("content", "")
                    break

            agent = AgentDefinition(
                name=config.get("name", "OpenAI Agent"),
                role="assistant",
                system_prompt=system_msg,
                model=config.get("model", ""),
                tools=tools,
                temperature=config.get("temperature", 0.7),
                max_tokens=config.get("max_tokens", 4096),
                metadata={"source": "openai_compatible"},
            )
            agents.append(agent)

        return ImportResult(
            source=ImportSource.OPENAI_COMPATIBLE,
            success=True,
            agents=agents,
            tools=tools,
            warnings=warnings,
        )

    # ── Generic Importer ─────────────────────────────────────────────

    def _import_generic(self, config: dict) -> ImportResult:
        """Import a generic agent/tool/workflow definition."""
        agents = []
        tools = []
        workflows = []
        warnings = []

        # Import agents
        for agent_cfg in config.get("agents", []):
            agent = AgentDefinition(
                name=agent_cfg.get("name", "Agent"),
                role=agent_cfg.get("role", "assistant"),
                system_prompt=agent_cfg.get("system_prompt", agent_cfg.get("instructions", "")),
                model=agent_cfg.get("model", ""),
                temperature=agent_cfg.get("temperature", 0.7),
                metadata=agent_cfg.get("metadata", {}),
            )
            for tool_cfg in agent_cfg.get("tools", []):
                tool = ToolDefinition(
                    name=tool_cfg.get("name", "unknown"),
                    description=tool_cfg.get("description", ""),
                    parameters=tool_cfg.get("parameters", {}),
                )
                tools.append(tool)
                agent.tools.append(tool)
            agents.append(agent)

        # Import standalone tools
        for tool_cfg in config.get("tools", []):
            tool = ToolDefinition(
                name=tool_cfg.get("name", "unknown"),
                description=tool_cfg.get("description", ""),
                tool_type=tool_cfg.get("type", "function"),
                parameters=tool_cfg.get("parameters", {}),
            )
            tools.append(tool)

        # Import workflows
        for wf_cfg in config.get("workflows", []):
            steps = []
            for step_cfg in wf_cfg.get("steps", []):
                step = WorkflowStep(
                    name=step_cfg.get("name", "Step"),
                    agent=step_cfg.get("agent", ""),
                    action=step_cfg.get("action", ""),
                    inputs=step_cfg.get("inputs", {}),
                    outputs=step_cfg.get("outputs", []),
                    condition=step_cfg.get("condition", ""),
                )
                steps.append(step)
            wf = WorkflowDefinition(
                name=wf_cfg.get("name", "Workflow"),
                description=wf_cfg.get("description", ""),
                steps=steps,
            )
            workflows.append(wf)

        return ImportResult(
            source=ImportSource.GENERIC,
            success=True,
            agents=agents,
            tools=tools,
            workflows=workflows,
            warnings=warnings,
        )

    # ── Helpers ───────────────────────────────────────────────────────

    def _extract_model(self, config: dict) -> str:
        """Extract model name from various config formats."""
        for key in ("model", "model_name", "llm", "llm_model"):
            val = config.get(key)
            if val:
                if isinstance(val, dict):
                    return val.get("model_name", val.get("model", ""))
                return str(val)
        return ""

    def _persist_result(self, result: ImportResult, user_id: str) -> None:
        filename = f"import_{result.source.value}_{int(result.imported_at)}.json"
        path = self._storage_dir / filename
        try:
            data = result.to_dict()
            data["user_id"] = user_id
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
        except Exception:
            logger.exception("Failed to persist import result.")
