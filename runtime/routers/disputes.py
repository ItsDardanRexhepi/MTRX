"""C30 - Disputes: on-chain dispute resolution, arbitration, and escrow release."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from runtime.blockchain.services.disputes.dispute_manager import (
    DisputeManager, DisputePhase,
)
from runtime.blockchain.services.disputes.juror_pool import JurorPool
from runtime.blockchain.services.disputes.voting import VotingEngine, Vote

router = APIRouter()

# Singleton service instances
_juror_pool = JurorPool()
_voting = VotingEngine()
_manager = DisputeManager(
    juror_pool=_juror_pool,
    voting_engine=_voting,
)


class DisputeRequest(BaseModel):
    claimant_address: str
    respondent_address: str
    stake_token: str
    bond_wei: int
    juror_fee_wei: int
    claim_uri: str
    juror_count: int = 3
    contract_to_freeze: str = ""


class RespondRequest(BaseModel):
    respondent_address: str
    bond_wei: int


class EvidenceRequest(BaseModel):
    submitter: str
    evidence_uri: str
    evidence_hash: str


class VoteCommitRequest(BaseModel):
    juror: str
    commit_hash: str


class VoteRevealRequest(BaseModel):
    juror: str
    vote: str  # "claimant" or "respondent"
    salt: str


class AppealRequest(BaseModel):
    appellant: str
    extra_bond_wei: int
    extra_fee_wei: int


class JurorRegisterRequest(BaseModel):
    address: str
    amount_wei: int


@router.post("/create")
async def create_dispute(request: DisputeRequest):
    """Open a new dispute for arbitration."""
    try:
        d = _manager.file_dispute(
            claimant=request.claimant_address,
            respondent=request.respondent_address,
            stake_token=request.stake_token,
            bond_wei=request.bond_wei,
            juror_fee_wei=request.juror_fee_wei,
            claim_uri=request.claim_uri,
            juror_count=request.juror_count,
            contract_to_freeze=request.contract_to_freeze,
        )
        return {
            "dispute_id": d.dispute_id,
            "phase": d.phase.value,
            "claimant": d.claimant,
            "respondent": d.respondent,
            "claimant_bond_wei": d.claimant_bond_wei,
            "evidence_deadline": d.evidence_deadline,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/respond")
async def respond_to_dispute(dispute_id: str, request: RespondRequest):
    """Respondent posts their bond."""
    try:
        d = _manager.respond_to_dispute(dispute_id, request.respondent_address, request.bond_wei)
        return {"dispute_id": d.dispute_id, "respondent_bond_wei": d.respondent_bond_wei, "phase": d.phase.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/evidence")
async def submit_evidence(dispute_id: str, request: EvidenceRequest):
    """Submit evidence for a dispute."""
    try:
        _manager.submit_evidence(dispute_id, request.submitter, request.evidence_uri, request.evidence_hash)
        return {"dispute_id": dispute_id, "status": "submitted"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/end-evidence")
async def end_evidence_phase(dispute_id: str):
    """End evidence phase and move to jury selection."""
    try:
        d = _manager.end_evidence_phase(dispute_id)
        return {"dispute_id": d.dispute_id, "phase": d.phase.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/select-jury")
async def select_jury(dispute_id: str):
    """Select jurors from the pool."""
    try:
        jurors = _manager.select_jury(dispute_id)
        return {"dispute_id": dispute_id, "jurors": jurors, "count": len(jurors)}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/commit-vote")
async def commit_vote(dispute_id: str, request: VoteCommitRequest):
    """Juror commits their vote hash."""
    try:
        _manager.commit_vote(dispute_id, request.juror, request.commit_hash)
        return {"dispute_id": dispute_id, "juror": request.juror, "status": "committed"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/begin-reveal")
async def begin_reveal(dispute_id: str):
    """Transition to reveal phase."""
    try:
        d = _manager.begin_reveal_phase(dispute_id)
        return {"dispute_id": d.dispute_id, "phase": d.phase.value, "reveal_deadline": d.reveal_deadline}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/reveal-vote")
async def reveal_vote(dispute_id: str, request: VoteRevealRequest):
    """Juror reveals their vote."""
    try:
        vote = Vote.CLAIMANT if request.vote == "claimant" else Vote.RESPONDENT
        _manager.reveal_vote(dispute_id, request.juror, vote, request.salt)
        return {"dispute_id": dispute_id, "juror": request.juror, "vote": request.vote}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/resolve")
async def resolve_dispute(dispute_id: str):
    """Tally votes and resolve the dispute."""
    try:
        d = _manager.resolve_dispute(dispute_id)
        return {"dispute_id": d.dispute_id, "outcome": d.outcome.value, "phase": d.phase.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/appeal")
async def appeal_dispute(dispute_id: str, request: AppealRequest):
    """Appeal a resolved dispute."""
    try:
        d = _manager.appeal(dispute_id, request.appellant, request.extra_bond_wei, request.extra_fee_wei)
        return {"dispute_id": d.dispute_id, "appeal_round": d.appeal_round, "phase": d.phase.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{dispute_id}/dismiss")
async def dismiss_dispute(dispute_id: str, dismisser: str = "owner"):
    """Dismiss a dispute."""
    try:
        d = _manager.dismiss_dispute(dispute_id, dismisser)
        return {"dispute_id": d.dispute_id, "phase": d.phase.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{dispute_id}")
async def get_dispute(dispute_id: str):
    """Get dispute details and status."""
    d = _manager.get_dispute(dispute_id)
    if d is None:
        raise HTTPException(status_code=404, detail="Dispute not found.")
    return {
        "dispute_id": d.dispute_id, "claimant": d.claimant, "respondent": d.respondent,
        "phase": d.phase.value, "outcome": d.outcome.value,
        "claimant_bond_wei": d.claimant_bond_wei, "respondent_bond_wei": d.respondent_bond_wei,
        "juror_count": d.juror_count, "appeal_round": d.appeal_round,
        "contract_frozen": d.contract_frozen,
    }


@router.get("/")
async def list_disputes(phase: Optional[str] = None):
    """List all disputes, optionally filtered by phase."""
    p = DisputePhase(phase) if phase else None
    disputes = _manager.list_disputes(phase=p)
    return {
        "disputes": [{"dispute_id": d.dispute_id, "phase": d.phase.value, "outcome": d.outcome.value} for d in disputes],
        "total": len(disputes),
    }


@router.post("/juror/register")
async def register_juror(request: JurorRegisterRequest):
    """Register as a juror by staking."""
    try:
        j = _juror_pool.register(request.address, request.amount_wei)
        return {"address": j.address, "staked_wei": j.staked_wei, "active": j.active}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/juror/pool-size")
async def juror_pool_size():
    """Get the size of the active juror pool."""
    return {"pool_size": _juror_pool.get_pool_size()}
