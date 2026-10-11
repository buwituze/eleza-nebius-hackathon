"""
routers/triage.py — Final scoring and output generation endpoint.

POST /sessions/{id}/complete
  → Runs Model D (risk scoring)
  → Runs Model E (patient message)
  → Runs Model F (doctor brief)
  → Returns both outputs
"""

import asyncio
from fastapi import APIRouter, HTTPException

from session import get_session, SessionStage
from models import model_d, model_e, model_f

router = APIRouter(prefix="/sessions", tags=["triage"])


@router.post("/{session_id}/complete")
async def complete_session(session_id: str):
    """
    Finalise a session. Runs Models D, E, and F in sequence and returns:
    - patient_message: what to say/display to the patient
    - doctor_brief: the full clinician summary

    Transitions session: SCORING → COMPLETE
    """
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.SCORING:
        raise HTTPException(status_code=409, detail=f"Session is in stage '{session.stage.value}', not ready for scoring.")

    # Model D — risk score
    session.score = await asyncio.to_thread(
        model_d.score,
        extraction = session.extraction,
        age        = session.patient_age,
    )

    # Model E — patient message
    session.patient_message = await asyncio.to_thread(
        model_e.generate_message,
        extraction     = session.extraction,
        score          = session.score,
        language       = session.language,
        location       = session.location,
        low_confidence = session.score.get("confidence", 1.0) < 0.4,
    )

    # Model F — doctor brief
    session.doctor_brief = await asyncio.to_thread(
        model_f.generate_brief,
        session_id      = session.id,
        extraction      = session.extraction,
        score           = session.score,
        questions_asked = session.questions_asked,
        patient_answers = session.patient_answers,
        transcript      = session.transcript,
        language        = session.language,
        patient_age     = session.patient_age,
    )

    session.stage = SessionStage.COMPLETE

    return {
        "session_id":      session.id,
        "stage":           session.stage.value,
        "score":           session.score,
        "patient_message": session.patient_message,
        "doctor_brief":    session.doctor_brief,
    }
