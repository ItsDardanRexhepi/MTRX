"""C29 - Privacy: privacy commitment registry, violation reporting, and compliance."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.privacy.commitment_registry import CommitmentRegistry
from runtime.blockchain.services.privacy.violation_tracker import ViolationTracker, ViolationStatus
from runtime.blockchain.services.privacy.compliance_manager import ComplianceManager

router = APIRouter()

_commitments = CommitmentRegistry()
_violations = ViolationTracker()
_compliance = ComplianceManager()


class CommitmentRequest(BaseModel):
    commitment_hash: str
    commitment_uri: str
    registered_by: str


class ViolationReportRequest(BaseModel):
    reporter: str
    violator: str
    commitment_id: str
    evidence_uri: str
    evidence_hash: str
    affected_users: list[str] = []


class InvestigateRequest(BaseModel):
    investigator: str


class VerifyRequest(BaseModel):
    investigator: str
    compensation_wei: int


class ComplianceAttestRequest(BaseModel):
    buyer: str
    commitment_ids: list[str]
    proof_uri: str


class EscrowRequest(BaseModel):
    entity: str
    token: str
    amount_wei: int


@router.post("/commitment/register")
async def register_commitment(request: CommitmentRequest):
    """Register a privacy commitment."""
    try:
        c = _commitments.register(request.commitment_hash, request.commitment_uri, request.registered_by)
        return {"commitment_id": c.commitment_id, "active": c.active}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/commitment/{commitment_id}")
async def get_commitment(commitment_id: str):
    """Get commitment details."""
    c = _commitments.get(commitment_id)
    if c is None:
        raise HTTPException(status_code=404, detail="Commitment not found.")
    return {
        "commitment_id": c.commitment_id, "commitment_hash": c.commitment_hash,
        "commitment_uri": c.commitment_uri, "registered_by": c.registered_by, "active": c.active,
    }


@router.post("/violation/report")
async def report_violation(request: ViolationReportRequest):
    """Report a privacy violation."""
    try:
        v = _violations.report_violation(
            request.reporter, request.violator, request.commitment_id,
            request.evidence_uri, request.evidence_hash, request.affected_users,
        )
        return {"violation_id": v.violation_id, "status": v.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/violation/{violation_id}/investigate")
async def investigate_violation(violation_id: str, request: InvestigateRequest):
    """Start investigating a violation."""
    try:
        v = _violations.investigate(violation_id, request.investigator)
        return {"violation_id": v.violation_id, "status": v.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/violation/{violation_id}/verify")
async def verify_violation(violation_id: str, request: VerifyRequest):
    """Verify a violation and set compensation."""
    try:
        v = _violations.verify(violation_id, request.investigator, request.compensation_wei)
        return {"violation_id": v.violation_id, "status": v.status.value, "compensation_wei": v.compensation_amount_wei}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/violation/{violation_id}/dismiss")
async def dismiss_violation(violation_id: str, request: InvestigateRequest):
    """Dismiss a violation."""
    try:
        v = _violations.dismiss(violation_id, request.investigator)
        return {"violation_id": v.violation_id, "status": v.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/violation/{violation_id}/compensate")
async def execute_compensation(violation_id: str, token: str):
    """Execute compensation from escrow to affected users."""
    try:
        amount = _violations.execute_compensation(violation_id, token)
        return {"violation_id": violation_id, "compensated_wei": amount}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/violation/{violation_id}")
async def get_violation(violation_id: str):
    """Get violation details."""
    v = _violations.get_violation(violation_id)
    if v is None:
        raise HTTPException(status_code=404, detail="Violation not found.")
    return {
        "violation_id": v.violation_id, "reporter": v.reporter, "violator": v.violator,
        "status": v.status.value, "compensation_wei": v.compensation_amount_wei,
        "affected_users": len(v.affected_users),
    }


@router.post("/escrow/deposit")
async def escrow_deposit(request: EscrowRequest):
    """Deposit revenue into escrow for compensation."""
    try:
        balance = _violations.escrow_revenue(request.entity, request.token, request.amount_wei)
        return {"entity": request.entity, "token": request.token, "balance_wei": balance}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/compliance/attest")
async def attest_compliance(request: ComplianceAttestRequest):
    """Attest buyer compliance with privacy commitments."""
    try:
        c = _compliance.attest_compliance(request.buyer, request.commitment_ids, request.proof_uri)
        return {"compliance_id": c.compliance_id, "buyer": c.buyer, "status": c.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/compliance/{buyer}/revoke")
async def revoke_compliance(buyer: str):
    """Revoke buyer compliance."""
    try:
        c = _compliance.revoke_compliance(buyer)
        return {"buyer": c.buyer, "status": c.status.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/compliance/{buyer}")
async def check_compliance(buyer: str):
    """Check if a buyer is compliant."""
    return {"buyer": buyer, "compliant": _compliance.is_compliant(buyer)}


@router.post("/investigator/add")
async def add_investigator(address: str):
    """Add an authorized investigator."""
    _violations.add_investigator(address)
    return {"address": address, "status": "added"}
