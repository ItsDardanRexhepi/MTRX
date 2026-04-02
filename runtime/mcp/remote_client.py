"""
MCP Remote Client — connects to remote MCP servers via HTTP/SSE.

Handles tool discovery, invocation, and streaming responses from
remote MCP servers. Supports auth headers and connection timeouts.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator, Dict, List, Optional

import httpx

logger = logging.getLogger(__name__)


@dataclass
class MCPServerConfig:
    """Configuration for a remote MCP server."""
    name: str
    url: str                           # Base URL of the MCP server
    transport: str = "http"            # http or sse
    auth_headers: Dict[str, str] = field(default_factory=dict)
    connect_timeout: int = 10          # seconds
    read_timeout: int = 60             # seconds
    enabled: bool = True
    description: str = ""
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "url": self.url,
            "transport": self.transport,
            "auth_headers": {k: "***" for k in self.auth_headers},  # Redact
            "connect_timeout": self.connect_timeout,
            "read_timeout": self.read_timeout,
            "enabled": self.enabled,
            "description": self.description,
            "tags": self.tags,
        }


@dataclass
class MCPTool:
    """A tool discovered from a remote MCP server."""
    name: str
    server_name: str
    description: str = ""
    input_schema: dict = field(default_factory=dict)
    qualified_name: str = ""    # serverName__toolName

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "server_name": self.server_name,
            "qualified_name": self.qualified_name,
            "description": self.description,
            "input_schema": self.input_schema,
        }


@dataclass
class MCPToolResult:
    """Result from invoking an MCP tool."""
    tool_name: str
    server_name: str
    content: List[dict] = field(default_factory=list)
    is_error: bool = False
    error: str = ""
    latency_ms: float = 0.0

    def to_dict(self) -> dict:
        return {
            "tool_name": self.tool_name,
            "server_name": self.server_name,
            "content": self.content,
            "is_error": self.is_error,
            "error": self.error,
            "latency_ms": round(self.latency_ms, 1),
        }

    @property
    def text(self) -> str:
        """Extract text content from result."""
        parts = []
        for item in self.content:
            if item.get("type") == "text":
                parts.append(item.get("text", ""))
        return "\n".join(parts)


class MCPRemoteClient:
    """
    Client for connecting to remote MCP servers.

    Discovers tools, invokes them, and handles streaming responses.
    All tools are namespaced as serverName__toolName to avoid conflicts.
    """

    def __init__(self, config_dir: str = "") -> None:
        if not config_dir:
            config_dir = str(
                Path(__file__).resolve().parent.parent.parent / "data" / "mcp"
            )
        self._config_dir = Path(config_dir)
        self._config_dir.mkdir(parents=True, exist_ok=True)
        self._servers: Dict[str, MCPServerConfig] = {}
        self._tools: Dict[str, MCPTool] = {}        # qualified_name -> tool
        self._clients: Dict[str, httpx.AsyncClient] = {}
        self._load_configs()
        logger.info("MCPRemoteClient initialised | servers=%d", len(self._servers))

    # ── Server Management ────────────────────────────────────────────

    def add_server(self, config: MCPServerConfig) -> MCPServerConfig:
        """Add a remote MCP server."""
        self._servers[config.name] = config
        self._save_configs()
        logger.info("MCP server added | name=%s | url=%s", config.name, config.url)
        return config

    def remove_server(self, name: str) -> bool:
        if name in self._servers:
            del self._servers[name]
            self._tools = {
                k: v for k, v in self._tools.items()
                if v.server_name != name
            }
            self._save_configs()
            return True
        return False

    def list_servers(self) -> List[MCPServerConfig]:
        return list(self._servers.values())

    def get_server(self, name: str) -> Optional[MCPServerConfig]:
        return self._servers.get(name)

    # ── Tool Discovery ───────────────────────────────────────────────

    async def discover_tools(self, server_name: str = "") -> List[MCPTool]:
        """Discover tools from remote MCP server(s)."""
        servers = [self._servers[server_name]] if server_name else list(self._servers.values())
        all_tools = []

        for server in servers:
            if not server.enabled:
                continue
            try:
                tools = await self._discover_server_tools(server)
                all_tools.extend(tools)
                logger.info("Discovered %d tools from %s", len(tools), server.name)
            except Exception as exc:
                logger.exception("Failed to discover tools from %s: %s", server.name, exc)

        return all_tools

    async def _discover_server_tools(self, server: MCPServerConfig) -> List[MCPTool]:
        """Discover tools from a single server."""
        client = await self._get_client(server)

        # MCP protocol: POST /tools/list
        payload = {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}

        resp = await client.post(server.url, json=payload)
        data = resp.json()

        tools = []
        result = data.get("result", {})
        for tool_def in result.get("tools", []):
            qualified = f"{server.name}__{tool_def['name']}"
            tool = MCPTool(
                name=tool_def["name"],
                server_name=server.name,
                description=tool_def.get("description", ""),
                input_schema=tool_def.get("inputSchema", {}),
                qualified_name=qualified,
            )
            self._tools[qualified] = tool
            tools.append(tool)

        return tools

    # ── Tool Invocation ──────────────────────────────────────────────

    async def invoke_tool(
        self,
        qualified_name: str,
        arguments: Optional[dict] = None,
    ) -> MCPToolResult:
        """Invoke a tool on a remote MCP server."""
        tool = self._tools.get(qualified_name)
        if tool is None:
            return MCPToolResult(
                tool_name=qualified_name, server_name="unknown",
                is_error=True, error=f"Tool {qualified_name} not found.",
            )

        server = self._servers.get(tool.server_name)
        if server is None:
            return MCPToolResult(
                tool_name=tool.name, server_name=tool.server_name,
                is_error=True, error=f"Server {tool.server_name} not configured.",
            )

        start = time.monotonic()
        try:
            client = await self._get_client(server)
            payload = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {
                    "name": tool.name,
                    "arguments": arguments or {},
                },
            }

            resp = await client.post(server.url, json=payload)
            data = resp.json()
            latency = (time.monotonic() - start) * 1000

            if "error" in data:
                return MCPToolResult(
                    tool_name=tool.name, server_name=server.name,
                    is_error=True, error=data["error"].get("message", str(data["error"])),
                    latency_ms=latency,
                )

            result = data.get("result", {})
            return MCPToolResult(
                tool_name=tool.name,
                server_name=server.name,
                content=result.get("content", []),
                is_error=result.get("isError", False),
                latency_ms=latency,
            )

        except httpx.TimeoutException:
            return MCPToolResult(
                tool_name=tool.name, server_name=server.name,
                is_error=True, error="Request timed out.",
                latency_ms=(time.monotonic() - start) * 1000,
            )
        except Exception as exc:
            return MCPToolResult(
                tool_name=tool.name, server_name=server.name,
                is_error=True, error=str(exc),
                latency_ms=(time.monotonic() - start) * 1000,
            )

    # ── SSE Streaming ────────────────────────────────────────────────

    async def invoke_tool_streaming(
        self,
        qualified_name: str,
        arguments: Optional[dict] = None,
    ) -> AsyncIterator[str]:
        """Invoke a tool and stream the response via SSE."""
        tool = self._tools.get(qualified_name)
        if tool is None:
            yield f"Error: Tool {qualified_name} not found."
            return

        server = self._servers.get(tool.server_name)
        if server is None or server.transport != "sse":
            # Fall back to non-streaming
            result = await self.invoke_tool(qualified_name, arguments)
            yield result.text or result.error
            return

        client = await self._get_client(server)
        payload = {
            "jsonrpc": "2.0", "id": 1,
            "method": "tools/call",
            "params": {"name": tool.name, "arguments": arguments or {}},
        }

        async with client.stream("POST", server.url, json=payload) as resp:
            async for line in resp.aiter_lines():
                if line.startswith("data: "):
                    data = line[6:]
                    if data == "[DONE]":
                        return
                    try:
                        chunk = json.loads(data)
                        content = chunk.get("result", {}).get("content", [])
                        for item in content:
                            if item.get("type") == "text":
                                yield item["text"]
                    except json.JSONDecodeError:
                        yield data

    # ── Queries ──────────────────────────────────────────────────────

    def list_tools(self, server_name: str = "") -> List[MCPTool]:
        tools = list(self._tools.values())
        if server_name:
            tools = [t for t in tools if t.server_name == server_name]
        return tools

    def get_tool(self, qualified_name: str) -> Optional[MCPTool]:
        return self._tools.get(qualified_name)

    def get_stats(self) -> dict:
        return {
            "servers": len(self._servers),
            "enabled_servers": sum(1 for s in self._servers.values() if s.enabled),
            "tools": len(self._tools),
            "tools_by_server": {
                s.name: sum(1 for t in self._tools.values() if t.server_name == s.name)
                for s in self._servers.values()
            },
        }

    # ── Internal ─────────────────────────────────────────────────────

    async def _get_client(self, server: MCPServerConfig) -> httpx.AsyncClient:
        if server.name not in self._clients:
            self._clients[server.name] = httpx.AsyncClient(
                timeout=httpx.Timeout(
                    connect=server.connect_timeout,
                    read=server.read_timeout,
                    write=30.0,
                    pool=30.0,
                ),
                headers=server.auth_headers,
            )
        return self._clients[server.name]

    def _save_configs(self) -> None:
        path = self._config_dir / "servers.json"
        data = {}
        for name, server in self._servers.items():
            d = server.to_dict()
            d["auth_headers"] = server.auth_headers  # Save actual headers
            data[name] = d
        try:
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
        except Exception:
            logger.exception("Failed to save MCP configs.")

    def _load_configs(self) -> None:
        path = self._config_dir / "servers.json"
        if not path.exists():
            return
        try:
            with open(path) as f:
                data = json.load(f)
            for name, sdata in data.items():
                self._servers[name] = MCPServerConfig(
                    name=sdata["name"],
                    url=sdata["url"],
                    transport=sdata.get("transport", "http"),
                    auth_headers=sdata.get("auth_headers", {}),
                    connect_timeout=sdata.get("connect_timeout", 10),
                    read_timeout=sdata.get("read_timeout", 60),
                    enabled=sdata.get("enabled", True),
                    description=sdata.get("description", ""),
                    tags=sdata.get("tags", []),
                )
        except Exception:
            logger.exception("Failed to load MCP configs.")

    async def close(self) -> None:
        for client in self._clients.values():
            await client.aclose()
        self._clients.clear()
