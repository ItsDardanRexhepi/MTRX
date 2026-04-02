"""Router for health diagnostics."""

from fastapi import APIRouter

from runtime.doctor.diagnostics import run_doctor

router = APIRouter()


@router.get("/check")
async def doctor_check():
    """Run full system health diagnostics."""
    report = run_doctor()
    return {
        "healthy": report["healthy"],
        "checks": report["checks"],
        "summary": report["summary"],
    }

@router.get("/check/text")
async def doctor_text():
    """Run diagnostics and return plain-text report."""
    report = run_doctor()
    return {"report": report["display"]}
