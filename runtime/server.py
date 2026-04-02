"""MTRX Runtime API Server — exposes 30 blockchain components + 8 Phase 3 subsystems."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI(
    title="MTRX Runtime API",
    description="API for 30 blockchain components + 8 intelligent subsystems + 6 OpenClaw-parity features",
    version="3.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Import and include routers for each component service
from runtime.routers import (
    contract_conversion,
    defi,
    nft,
    rwa,
    identity,
    dao,
    stablecoin,
    attestation,
    agent_identity,
    agentic_payments,
    oracles,
    supply_chain,
    insurance,
    gaming,
    ip_rights,
    staking,
    payments,
    securities,
    governance,
    dashboard,
    dex,
    fundraising,
    loyalty,
    marketplace,
    cashback,
    brand_rewards,
    subscriptions,
    social,
    privacy,
    disputes,
)
from runtime.routers import (
    memory as memory_router,
    goals as goals_router,
    documents as documents_router,
    automation as automation_router,
    execution as execution_router,
    checkins as checkins_router,
    models as models_router,
    migration as migration_router,
)
from runtime.routers import (
    tasks as tasks_router,
    channels as channels_router,
    mcp_servers as mcp_router,
    approvals as approvals_router,
    skills as skills_router,
    doctor as doctor_router,
)

# Register all routers with prefixes
app.include_router(contract_conversion.router, prefix="/api/v1/contracts", tags=["C1 - Contract Conversion"])
app.include_router(defi.router, prefix="/api/v1/defi", tags=["C2 - DeFi Lending"])
app.include_router(nft.router, prefix="/api/v1/nft", tags=["C3 - NFT"])
app.include_router(rwa.router, prefix="/api/v1/rwa", tags=["C4 - RWA"])
app.include_router(identity.router, prefix="/api/v1/identity", tags=["C5 - Identity"])
app.include_router(dao.router, prefix="/api/v1/dao", tags=["C6 - DAO"])
app.include_router(stablecoin.router, prefix="/api/v1/stablecoin", tags=["C7 - Stablecoin"])
app.include_router(attestation.router, prefix="/api/v1/attestation", tags=["C8 - Attestation"])
app.include_router(agent_identity.router, prefix="/api/v1/agent-identity", tags=["C9 - Agent Identity"])
app.include_router(agentic_payments.router, prefix="/api/v1/agentic-payments", tags=["C10 - Agentic Payments"])
app.include_router(oracles.router, prefix="/api/v1/oracles", tags=["C11 - Oracles"])
app.include_router(supply_chain.router, prefix="/api/v1/supply-chain", tags=["C12 - Supply Chain"])
app.include_router(insurance.router, prefix="/api/v1/insurance", tags=["C13 - Insurance"])
app.include_router(gaming.router, prefix="/api/v1/gaming", tags=["C14 - Gaming"])
app.include_router(ip_rights.router, prefix="/api/v1/ip", tags=["C15 - IP Rights"])
app.include_router(staking.router, prefix="/api/v1/staking", tags=["C16 - Staking"])
app.include_router(payments.router, prefix="/api/v1/payments", tags=["C17 - Payments"])
app.include_router(securities.router, prefix="/api/v1/securities", tags=["C18 - Securities"])
app.include_router(governance.router, prefix="/api/v1/governance", tags=["C19 - Governance"])
app.include_router(dashboard.router, prefix="/api/v1/dashboard", tags=["C20 - Dashboard"])
app.include_router(dex.router, prefix="/api/v1/dex", tags=["C21 - DEX"])
app.include_router(fundraising.router, prefix="/api/v1/fundraising", tags=["C22 - Fundraising"])
app.include_router(loyalty.router, prefix="/api/v1/loyalty", tags=["C23 - Loyalty"])
app.include_router(marketplace.router, prefix="/api/v1/marketplace", tags=["C24 - Marketplace"])
app.include_router(cashback.router, prefix="/api/v1/cashback", tags=["C25 - Cashback"])
app.include_router(brand_rewards.router, prefix="/api/v1/brand-rewards", tags=["C26 - Brand Rewards"])
app.include_router(subscriptions.router, prefix="/api/v1/subscriptions", tags=["C27 - Subscriptions"])
app.include_router(social.router, prefix="/api/v1/social", tags=["C28 - Social"])
app.include_router(privacy.router, prefix="/api/v1/privacy", tags=["C29 - Privacy"])
app.include_router(disputes.router, prefix="/api/v1/disputes", tags=["C30 - Disputes"])

# Phase 3 — Intelligent Subsystems
app.include_router(memory_router.router, prefix="/api/v1/memory", tags=["P3 - User Memory"])
app.include_router(goals_router.router, prefix="/api/v1/goals", tags=["P3 - Goals Engine"])
app.include_router(documents_router.router, prefix="/api/v1/documents", tags=["P3 - Document RAG"])
app.include_router(automation_router.router, prefix="/api/v1/automation", tags=["P3 - Automation Triggers"])
app.include_router(execution_router.router, prefix="/api/v1/execution", tags=["P3 - Code Execution"])
app.include_router(checkins_router.router, prefix="/api/v1/checkins", tags=["P3 - Proactive Check-Ins"])
app.include_router(models_router.router, prefix="/api/v1/models", tags=["P3 - Model Marketplace"])
app.include_router(migration_router.router, prefix="/api/v1/migration", tags=["P3 - Migration Importers"])

# OpenClaw Parity Features
app.include_router(tasks_router.router, prefix="/api/v1/tasks", tags=["OC - Task Control Plane"])
app.include_router(channels_router.router, prefix="/api/v1/channels", tags=["OC - Multi-Channel"])
app.include_router(mcp_router.router, prefix="/api/v1/mcp", tags=["OC - MCP Servers"])
app.include_router(approvals_router.router, prefix="/api/v1/approvals", tags=["OC - Exec Approvals"])
app.include_router(skills_router.router, prefix="/api/v1/skills", tags=["OC - Skills Marketplace"])
app.include_router(doctor_router.router, prefix="/api/v1/doctor", tags=["OC - Health Diagnostics"])


@app.get("/", response_class=HTMLResponse)
async def root():
    return """<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MTRX Runtime API</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#e0e0e0;display:flex;justify-content:center;padding:40px 20px}
.container{max-width:720px;width:100%}
h1{font-size:2rem;margin-bottom:4px;color:#fff}
.sub{color:#888;margin-bottom:32px;font-size:0.95rem}
a{color:#58a6ff;text-decoration:none}a:hover{text-decoration:underline}
.card{background:#161616;border:1px solid #2a2a2a;border-radius:12px;padding:20px;margin-bottom:12px}
.card h3{font-size:0.85rem;color:#888;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:12px}
.row{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #1e1e1e;font-size:0.9rem}
.row:last-child{border:none}
.tag{background:#1a2a1a;color:#4ade80;padding:2px 8px;border-radius:4px;font-size:0.75rem;font-weight:600}
.tag.blue{background:#1a1a2e;color:#60a5fa}
</style></head>
<body><div class="container">
<h1>MTRX</h1>
<p class="sub">Runtime API — 30 blockchain + 8 intelligent + 6 platform features on Base &middot; <a href="/docs">Swagger Docs</a> &middot; <a href="/health">Health</a> &middot; <a href="/api/v1/doctor/check">Doctor</a></p>
<div class="card"><h3>Components</h3>
<div class="row"><span>C1 Contract Conversion</span><a href="/api/v1/contracts">/api/v1/contracts</a></div>
<div class="row"><span>C2 DeFi Lending</span><a href="/api/v1/defi">/api/v1/defi</a></div>
<div class="row"><span>C3 NFT</span><a href="/api/v1/nft">/api/v1/nft</a></div>
<div class="row"><span>C4 RWA Tokenization</span><a href="/api/v1/rwa">/api/v1/rwa</a></div>
<div class="row"><span>C5 Identity</span><a href="/api/v1/identity">/api/v1/identity</a></div>
<div class="row"><span>C6 DAO</span><a href="/api/v1/dao">/api/v1/dao</a></div>
<div class="row"><span>C7 Stablecoin</span><a href="/api/v1/stablecoin">/api/v1/stablecoin</a></div>
<div class="row"><span>C8 Attestation</span><a href="/api/v1/attestation">/api/v1/attestation</a></div>
<div class="row"><span>C9 Agent Identity</span><a href="/api/v1/agent-identity">/api/v1/agent-identity</a></div>
<div class="row"><span>C10 Agentic Payments</span><a href="/api/v1/agentic-payments">/api/v1/agentic-payments</a></div>
<div class="row"><span>C11 Oracles</span><a href="/api/v1/oracles">/api/v1/oracles</a></div>
<div class="row"><span>C12 Supply Chain</span><a href="/api/v1/supply-chain">/api/v1/supply-chain</a></div>
<div class="row"><span>C13 Insurance</span><a href="/api/v1/insurance">/api/v1/insurance</a></div>
<div class="row"><span>C14 Gaming</span><a href="/api/v1/gaming">/api/v1/gaming</a></div>
<div class="row"><span>C15 IP Rights</span><a href="/api/v1/ip">/api/v1/ip</a></div>
<div class="row"><span>C16 Staking</span><a href="/api/v1/staking">/api/v1/staking</a></div>
<div class="row"><span>C17 Payments</span><a href="/api/v1/payments">/api/v1/payments</a></div>
<div class="row"><span>C18 Securities</span><a href="/api/v1/securities">/api/v1/securities</a></div>
<div class="row"><span>C19 Governance</span><a href="/api/v1/governance">/api/v1/governance</a></div>
<div class="row"><span>C20 Dashboard</span><a href="/api/v1/dashboard">/api/v1/dashboard</a></div>
<div class="row"><span>C21 DEX</span><a href="/api/v1/dex">/api/v1/dex</a></div>
<div class="row"><span>C22 Fundraising</span><a href="/api/v1/fundraising">/api/v1/fundraising</a></div>
<div class="row"><span>C23 Loyalty</span><a href="/api/v1/loyalty">/api/v1/loyalty</a></div>
<div class="row"><span>C24 Marketplace</span><a href="/api/v1/marketplace">/api/v1/marketplace</a></div>
<div class="row"><span>C25 Cashback</span><a href="/api/v1/cashback">/api/v1/cashback</a></div>
<div class="row"><span>C26 Brand Rewards</span><a href="/api/v1/brand-rewards">/api/v1/brand-rewards</a></div>
<div class="row"><span>C27 Subscriptions</span><a href="/api/v1/subscriptions">/api/v1/subscriptions</a></div>
<div class="row"><span>C28 Social</span><a href="/api/v1/social">/api/v1/social</a></div>
<div class="row"><span>C29 Privacy</span><a href="/api/v1/privacy">/api/v1/privacy</a></div>
<div class="row"><span>C30 Disputes</span><a href="/api/v1/disputes">/api/v1/disputes</a></div>
</div>
<div class="card"><h3>Phase 3 — Intelligent Subsystems</h3>
<div class="row"><span>User Memory</span><a href="/api/v1/memory">/api/v1/memory</a></div>
<div class="row"><span>Goals Engine</span><a href="/api/v1/goals">/api/v1/goals</a></div>
<div class="row"><span>Document RAG</span><a href="/api/v1/documents">/api/v1/documents</a></div>
<div class="row"><span>Automation Triggers</span><a href="/api/v1/automation">/api/v1/automation</a></div>
<div class="row"><span>Code Execution</span><a href="/api/v1/execution">/api/v1/execution</a></div>
<div class="row"><span>Proactive Check-Ins</span><a href="/api/v1/checkins">/api/v1/checkins</a></div>
<div class="row"><span>Model Marketplace</span><a href="/api/v1/models">/api/v1/models</a></div>
<div class="row"><span>Migration Importers</span><a href="/api/v1/migration">/api/v1/migration</a></div>
</div>
<div class="card"><h3>OpenClaw Parity Features</h3>
<div class="row"><span>Task Control Plane</span><a href="/api/v1/tasks">/api/v1/tasks</a></div>
<div class="row"><span>Multi-Channel</span><a href="/api/v1/channels">/api/v1/channels</a></div>
<div class="row"><span>MCP Servers</span><a href="/api/v1/mcp">/api/v1/mcp</a></div>
<div class="row"><span>Exec Approvals</span><a href="/api/v1/approvals">/api/v1/approvals</a></div>
<div class="row"><span>Skills Marketplace</span><a href="/api/v1/skills">/api/v1/skills</a></div>
<div class="row"><span>Health Doctor</span><a href="/api/v1/doctor/check">/api/v1/doctor</a></div>
</div>
<div class="card"><h3>Status</h3>
<div class="row"><span>Network</span><span class="tag">Base (8453)</span></div>
<div class="row"><span>NeoSafe</span><span style="font-family:monospace;font-size:0.8rem">0x46fF...8Ec5</span></div>
<div class="row"><span>API Docs</span><a href="/docs">Interactive Swagger UI</a></div>
</div>
</div></body></html>"""


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "blockchain_components": 30,
        "phase3_subsystems": 8,
        "openclaw_parity_features": 6,
        "network": "base",
    }


if __name__ == "__main__":
    uvicorn.run("runtime.server:app", host="0.0.0.0", port=8000, reload=True)
