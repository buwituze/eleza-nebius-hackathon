"""
routers/sessions.py — Session lifecycle endpoints.

POST /sessions        → start a new patient session
DELETE /sessions/{id} → end and clean up a session
GET  /sessions/{id}   → inspect current session state (useful for debugging)
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from session import create_session, get_session, delete_session
from utils.session_logger import log_session
from datetime import datetime

router = APIRouter(prefix="/sessions", tags=["sessions"])


class StartSessionRequest(BaseModel):
    language:    Optional[str] = None   # Patient's screen selection, or None if skipped.
                                        # Passed as a hint to Model A — detection always runs.
    patient_age: Optional[int] = None
    location:    str           = ""     # e.g. "Emergency, Desk 3"


class StartSessionResponse(BaseModel):
    session_id: str
    stage:      str


@router.post("", response_model=StartSessionResponse)
def start_session(body: StartSessionRequest):
    """Create a new patient session and return its ID."""
    # Normalize language to lowercase for consistency
    normalized_language = body.language.lower() if body.language else "unknown"
    
    session = create_session(
        language    = normalized_language,
        patient_age = body.patient_age,
        location    = body.location,
    )
    return StartSessionResponse(session_id=session.id, stage=session.stage.value)


@router.get("/{session_id}")
def get_session_state(session_id: str):
    """Return the current state of a session (for debugging / frontend polling)."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    return {
        "session_id":      session.id,
        "stage":           session.stage.value,
        "language":        session.language,
        "patient_age":     session.patient_age,
        "location":        session.location,
        "transcript":      session.transcript,
        "extraction":      session.extraction,
        "turns":           [{"question": t.question, "answer": t.answer} for t in session.turns],
        "score":           session.score,
        "patient_message": session.patient_message,
        "doctor_brief":    session.doctor_brief,
    }


@router.delete("/{session_id}")
def end_session(session_id: str):
    """Delete a session and free its memory."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    
    # Log session data before deletion (if conversation happened)
    if session.routing_mode and session.api_calls_count > 0:
        try:
            log_session({
                "session_id": session.id,
                "patient_id": 0,  # No patient login in this system
                "conversation_mode": session.routing_mode,
                "chief_complaint": session.chief_complaint,
                "severity_estimate": session.severity_estimate,
                "red_flags_detected": session.red_flags_detected,
                "transcription_quality": session.transcription_quality,
                "api_calls_count": session.api_calls_count,
                "cost_estimate": session.cost_estimate,
                "routing_reasoning": session.routing_reasoning,
                "timestamp": datetime.now().isoformat(),
                "patient_age": session.patient_age,
                "patient_gender": session.patient_gender,
            })
            print(f"✅ Session {session_id} logged successfully")
        except Exception as e:
            print(f"⚠️ Failed to log session {session_id}: {e}")
    
    delete_session(session_id)
    return {"deleted": session_id}