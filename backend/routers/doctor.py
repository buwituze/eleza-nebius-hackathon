"""
routers/doctor.py — Clinician dashboard endpoints.

These are the endpoints the doctor's dashboard calls.
They expose completed session data for review and queue management.

GET  /doctor/queue              → current queue state across all departments
GET  /doctor/briefs/{id}        → fetch the doctor brief for a completed session
GET  /doctor/sessions           → list all sessions and their stages
POST /doctor/queue/reset        → reset queue counters (start of day)
"""

from fastapi import APIRouter, HTTPException
from session import get_session, all_session_ids, SessionStage
from routing import get_queue_lengths, reset_queues

router = APIRouter(prefix="/doctor", tags=["doctor"])


@router.get("/queue")
def get_queue():
    """
    Return current queue lengths across all departments.
    Used by the dashboard to display waiting numbers.
    """
    return {"queues": get_queue_lengths()}


@router.post("/queue/reset")
def reset_queue():
    """Reset all queue counters. Call at the start of each day."""
    reset_queues()
    return {"message": "All queues reset."}


@router.get("/sessions")
def list_sessions():
    """
    List all active sessions with their current stage and key details.
    Useful for the doctor dashboard overview panel.
    """
    sessions = []
    for sid in all_session_ids():
        s = get_session(sid)
        if not s:
            continue
        sessions.append({
            "session_id":      s.id,
            "stage":           s.stage.value,
            "language":        s.language,
            "chief_complaint": s.extraction.get("chief_complaint", "") if s.extraction else "",
            "priority":        s.score.get("priority", "") if s.score else "",
            "turns":           len(s.turns),
        })

    # Sort so HIGH priority and COMPLETE sessions appear first
    priority_order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2, "": 3}
    sessions.sort(key=lambda x: priority_order.get(x["priority"], 3))
    return {"sessions": sessions, "total": len(sessions)}


@router.get("/briefs/{session_id}")
def get_brief(session_id: str):
    """
    Fetch the full doctor brief for a completed session.
    Returns 404 if not found, 409 if session is not yet complete.
    """
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.COMPLETE:
        raise HTTPException(
            status_code=409,
            detail=f"Session is not complete yet. Current stage: {session.stage.value}",
        )
    return session.doctor_brief


@router.get("/briefs/{session_id}/extraction")
def get_extraction(session_id: str):
    """Return just the structured symptom extraction (Model B output) for a session."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    return {"session_id": session_id, "extraction": session.extraction}


@router.get("/briefs/{session_id}/score")
def get_score(session_id: str):
    """Return just the risk score (Model D output) for a session."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if not session.score:
        raise HTTPException(status_code=409, detail="Score not yet available.")
    return {"session_id": session_id, "score": session.score}
