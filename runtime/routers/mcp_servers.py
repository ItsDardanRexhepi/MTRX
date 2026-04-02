"""Router for MCP remote server management."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, List, Optional

from runtime.mcp import MCPRemoteClient, MCPServerConfig

router = APIRouter()
mcp_client = MCPRemoteClient()


class AddServerRequest(BaseModel):
    name: str
    url: str
    transport: str = "http"
    auth_headers: Dict[str, str] = {}
    connect_timeout: int = 10
    read_timeout: int = 60
    description: str = ""
    tags: List[str] = []

class InvokeToolRequest(BaseModel):
    qualified_name: str
    arguments: dict = {}


@router.post("/servers/add")
async def add_server(req: AddServerRequest):
    config = MCPServerConfig(
        name=req.name, url=req.url, transport=req.transport,
        auth_headers=req.auth_headers, connect_timeout=req.connect_timeout,
        read_timeout=req.read_timeout, description=req.description, tags=req.tags,
    )
    mcp_client.add_server(config)
    return config.to_dict()

@router.delete("/servers/{name}")
async def remove_server(name: str):
    if not mcp_client.remove_server(name):
        raise HTTPException(404, "Server not found.")
    return {"status": "removed"}

@router.get("/servers")
async def list_servers():
    return {"servers": [s.to_dict() for s in mcp_client.list_servers()]}

@router.post("/tools/discover")
async def discover_tools(server_name: str = ""):
    tools = await mcp_client.discover_tools(server_name)
    return {"tools": [t.to_dict() for t in tools]}

@router.get("/tools")
async def list_tools(server_name: str = ""):
    return {"tools": [t.to_dict() for t in mcp_client.list_tools(server_name)]}

@router.post("/tools/invoke")
async def invoke_tool(req: InvokeToolRequest):
    result = await mcp_client.invoke_tool(req.qualified_name, req.arguments)
    return result.to_dict()

@router.get("/stats")
async def mcp_stats():
    return mcp_client.get_stats()
