"""
routers/patients.py — Patient management and viewing endpoints.

GET    /patients                       → list all patients
GET    /patients/{patient_id}          → get patient details
GET    /patients/{patient_id}/sessions → get patient session history
GET    /patients/{patient_id}/session/{session_id} → get detailed session info
"""

from typing import Optional
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends, Query
from pydantic import BaseModel

from database.database import (
    PatientDB, SessionDB, ExtendedSessionDB, ConversationDB,
    SymptomDB, PredictionDB, AudioDB, DatabaseConnection
)
from routers.auth import get_current_user, require_role

# Initialize database connection pool
try:
    DatabaseConnection.initialize_pool()
except:
    pass

router = APIRouter(prefix="/patients", tags=["patients"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class PatientListItem(BaseModel):
    patient_id: int
    full_name: str
    residency: Optional[str]
    age: Optional[int] = None
    priority: Optional[str]
    session_id: Optional[int]
    start_time: Optional[datetime]
    queue_number: Optional[int]
    queue_status: Optional[str]


class PatientDetail(BaseModel):
    patient_id: int
    full_name: str
    phone_number: str
    preferred_language: str
    location: Optional[str]
    created_at: Optional[datetime]


class SessionSummary(BaseModel):
    session_id: int
    start_time: Optional[datetime]
    predicted_condition: Optional[str]
    risk_level: Optional[str]
    prescribed: bool


class SessionDetail(BaseModel):
    session_id: int
    patient_id: int
    start_time: Optional[datetime]
    end_time: Optional[datetime]
    status: str
    detected_language: Optional[str]
    full_transcript: Optional[str]
    transcript_confidence: Optional[float]
    extraction_data: Optional[dict]
    score_data: Optional[dict]
    patient_message: Optional[str]
    doctor_brief: Optional[dict]
    conversation: list
    symptoms: list
    prediction: Optional[dict]
    audio_recordings: list


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=list[PatientListItem])
def list_patients(
    search: Optional[str] = Query(None, description="Search by name or phone"),
    current_user: dict = Depends(require_role("doctor", "hospital_admin", "platform_admin"))
):
    """List all patients. Searchable by name or phone."""
    patients = ExtendedSessionDB.get_all_patients()
    
    if search:
        search_lower = search.lower()
        patients = [
            p for p in patients
            if search_lower in p.get('full_name', '').lower() or
               search_lower in p.get('phone_number', '')
        ]
    
    return [PatientListItem(**p) for p in patients]


@router.get("/{patient_id}", response_model=PatientDetail)
def get_patient(
    patient_id: int,
    current_user: dict = Depends(require_role("doctor", "hospital_admin", "platform_admin"))
):
    """Get patient basic information"""
    patient = PatientDB.get_patient_by_id(patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    return PatientDetail(**patient)


@router.get("/{patient_id}/sessions", response_model=list[SessionSummary])
def get_patient_sessions(
    patient_id: int,
    current_user: dict = Depends(require_role("doctor", "hospital_admin", "platform_admin"))
):
    """Get patient's session history"""
    patient = PatientDB.get_patient_by_id(patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    sessions = ExtendedSessionDB.get_patient_sessions(patient_id)
    return [SessionSummary(**s) for s in sessions]


@router.get("/{patient_id}/session/{session_id}", response_model=SessionDetail)
def get_session_details(
    patient_id: int,
    session_id: int,
    current_user: dict = Depends(require_role("doctor", "hospital_admin", "platform_admin"))
):
    """
    Get detailed session information including:
    - Full transcript
    - Structured extraction data
    - Risk score
    - Doctor's brief
    - Conversation turns
    - Symptoms
    - Prediction
    - Audio recordings (file paths)
    """
    # Get session
    session = SessionDB.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    if session['patient_id'] != patient_id:
        raise HTTPException(status_code=400, detail="Session does not belong to this patient")
    
    # Get related data
    conversation = ConversationDB.get_conversation(session_id)
    symptoms = SymptomDB.get_session_symptoms(session_id)
    prediction = PredictionDB.get_session_prediction(session_id)
    audio_recordings = AudioDB.get_session_audio(session_id)
    
    return SessionDetail(
        session_id=session['session_id'],
        patient_id=session['patient_id'],
        start_time=session['start_time'],
        end_time=session.get('end_time'),
        status=session['status'],
        detected_language=session.get('detected_language'),
        full_transcript=session.get('full_transcript'),
        transcript_confidence=session.get('transcript_confidence'),
        extraction_data=session.get('extraction_data'),
        score_data=session.get('score_data'),
        patient_message=session.get('patient_message'),
        doctor_brief=session.get('doctor_brief'),
        conversation=[dict(c) for c in conversation],
        symptoms=[dict(s) for s in symptoms],
        prediction=dict(prediction) if prediction else None,
        audio_recordings=[dict(a) for a in audio_recordings]
    )
