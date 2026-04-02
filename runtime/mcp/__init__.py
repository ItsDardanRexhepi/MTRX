"""
MCP Remote Server Support — connect Neo to any remote MCP server via URL.

Supports HTTP/SSE transport with auth headers and connection timeouts.
Massively expands what tools Neo can use without local installation.
"""

from runtime.mcp.remote_client import MCPRemoteClient, MCPServerConfig, MCPTool

__all__ = ["MCPRemoteClient", "MCPServerConfig", "MCPTool"]
