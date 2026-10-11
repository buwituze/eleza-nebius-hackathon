"""
routers/queue.py — Examination queue management endpoints.

GET    /queue                         → get queue for facility
GET    /queue/{queue_id}              → get queue entry details
POST   /queue/{queue_id}/assign       → assign patient to doctor/room
PUT    /queue/{queue_id}/status       → update queue status
GET    /queue/doctor/me               → get queue for current doctor
"""

from typing import Optional, List
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends, Query
from pydantic import BaseModel

from database.database import QueueDB, DatabaseConnection, RoomDB
from routers.auth import get_current_user, require_role

# Initialize database connection pool
try:
    DatabaseConnection.initialize_pool()
except:
    pass

router = APIRouter(prefix="/queue", tags=["queue"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class AssignQueueRequest(BaseModel):
    doctor_id: int
    room_id: Optional[int] = None
    required_exams: Optional[List[str]] = None
    notes: Optional[str] = None


class AssignSessionRoomRequest(BaseModel):
    room_id: int
    required_exams: Optional[List[str]] = None
    notes: Optional[str] = None


class UpdateStatusRequest(BaseModel):
    status: str  # waiting, in_progress, completed, cancelled


class QueueEntryResponse(BaseModel):
    queue_id: int
    queue_number: int
    queue_status: str
    queue_name: Optional[str] = None
    department: Optional[str] = None
    location_hint: Optional[str] = None
    patient_name: str
    phone_number: Optional[str]
    risk_level: Optional[str]
    predicted_condition: Optional[str]
    doctor_name: Optional[str]
    room_name: Optional[str]
    facility_name: str
    created_at: datetime
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    required_exams: Optional[List[str]] = None


class RoomQueueEntryResponse(QueueEntryResponse):
    position: int
    assigned_room_id: Optional[int] = None
    assigned_doctor_id: Optional[int] = None


MOCK_REQUIRED_EXAM_SETS = [
    [
        "Complete Blood Count (CBC)",
        "Basic Metabolic Panel (BMP)",
        "Vital Signs Recheck",
    ],
    [
        "C-Reactive Protein (CRP)",
        "Urinalysis",
        "Point-of-Care Glucose",
    ],
    [
        "Chest X-Ray",
        "Pulse Oximetry Trend",
        "ECG",
    ],
    [
        "Liver Function Panel",
        "Electrolytes Panel",
        "Physical Examination Follow-up",
    ],
]


def _get_worker_id_for_user(user_id: int) -> int:
    with DatabaseConnection.get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT worker_id FROM healthcare_worker WHERE user_id = %s",
                (user_id,),
            )
            result = cur.fetchone()
            if not result:
                raise HTTPException(
                    status_code=404,
                    detail="Worker profile not found for this user",
                )
            return result['worker_id']


def _default_mock_exams(
    queue_id: int,
    queue_name: Optional[str] = None,
    department: Optional[str] = None,
) -> List[str]:
    seed_text = f"{queue_name or ''}|{department or ''}|{queue_id}"
    seed = sum(ord(ch) for ch in seed_text)
    exam_set = MOCK_REQUIRED_EXAM_SETS[seed % len(MOCK_REQUIRED_EXAM_SETS)]
    return list(exam_set)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/room/{room_id}", response_model=list[RoomQueueEntryResponse])
def get_room_queue(
    room_id: int,
    current_user: dict = Depends(require_role("doctor", "hospital_admin", "platform_admin")),
):
    """
    Get active patients in a specific room, ordered by queue number.
    Each entry includes a live `position` field (decreases as earlier patients complete).
    """
    entries = QueueDB.get_room_queue(room_id)
    return [RoomQueueEntryResponse(**entry) for entry in entries]


@router.post("/{queue_id}/complete")
def complete_examination(
    queue_id: int,
    current_user: dict = Depends(require_role("doctor", "hospital_admin")),
):
    """
    Mark an examination as completed (exam taken).
    Doctors may only complete examinations assigned to them.
    """
    entry = QueueDB.get_queue_entry(queue_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Queue entry not found")

    if entry['queue_status'] == 'completed':
        raise HTTPException(status_code=400, detail="Examination is already completed")

    if current_user['role'] == 'doctor':
        worker_id = _get_worker_id_for_user(current_user['user_id'])
        # v_queue_overview doesn't expose assigned_doctor_id — fetch raw row
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT assigned_doctor_id FROM examination_queue WHERE queue_id = %s",
                    (queue_id,),
                )
                row = cur.fetchone()
        if not row or row['assigned_doctor_id'] != worker_id:
            raise HTTPException(
                status_code=403,
                detail="You can only complete examinations assigned to you",
            )

    QueueDB.update_queue_status(queue_id, 'completed')
    return {"message": "Examination marked as completed", "queue_id": queue_id}


@router.get("", response_model=list[QueueEntryResponse])
def get_facility_queue(
    status: Optional[str] = Query(None, description="Filter by status"),
    session_id: Optional[int] = Query(None, description="Filter by session ID"),
    current_user: dict = Depends(require_role("doctor", "hospital_admin", "platform_admin"))
):
    """
    Get queue for the current user's facility.
    Platform admin must specify facility_id as query param.
    """
    if session_id is not None:
        entry = QueueDB.get_queue_entry_by_session(session_id)
        if not entry:
            return []
        return [QueueEntryResponse(**entry)]

    facility_id = current_user.get('facility_id')
    if not facility_id:
        raise HTTPException(status_code=400, detail="User not assigned to a facility")

    queue = QueueDB.get_facility_queue(facility_id, status)
    return [QueueEntryResponse(**entry) for entry in queue]


@router.get("/{queue_id}", response_model=QueueEntryResponse)
def get_queue_entry(
    queue_id: int,
    current_user: dict = Depends(get_current_user)
):
    """Get queue entry details"""
    entry = QueueDB.get_queue_entry(queue_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Queue entry not found")
    
    return QueueEntryResponse(**entry)


@router.post("/{queue_id}/assign")
def assign_queue_entry(
    queue_id: int,
    request: AssignQueueRequest,
    current_user: dict = Depends(require_role("doctor", "hospital_admin"))
):
    """
    Assign a patient to a doctor and room with required exams.
    Doctors can assign to themselves, hospital admins can assign to any doctor.
    """
    entry = QueueDB.get_queue_entry(queue_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Queue entry not found")
    
    # Doctors can only assign to themselves
    if current_user['role'] == 'doctor':
        # Find worker_id from user
        from database.database import HealthcareWorkerDB
        worker = HealthcareWorkerDB.get_worker(request.doctor_id)
        if not worker or worker.get('user_id') != current_user['user_id']:
            raise HTTPException(status_code=403, detail="Doctors can only assign patients to themselves")
    
    QueueDB.assign_to_doctor(
        queue_id=queue_id,
        doctor_id=request.doctor_id,
        room_id=request.room_id,
        exams=request.required_exams,
        notes=request.notes
    )

    updated_entry = QueueDB.get_queue_entry(queue_id)

    if request.required_exams and entry.get("phone_number"):
        try:
            from utils.sms_service import send_exam_assignment_sms
            from database.database import PatientDB
            patient = PatientDB.get_patient_by_phone(entry["phone_number"])
            language = (patient or {}).get("preferred_language", "english")
            send_exam_assignment_sms(
                patient_name=entry.get("patient_name", ""),
                phone_number=entry["phone_number"],
                queue_number=entry.get("queue_number", 0),
                required_exams=request.required_exams,
                room_name=(updated_entry or {}).get("room_name"),
                location_hint=entry.get("location_hint"),
                language=language,
            )
        except Exception as _sms_exc:
            print(f"⚠️ SMS notification failed: {_sms_exc}")

    return {"message": "Patient assigned successfully", "queue_entry": updated_entry}


@router.post("/session/{session_id}/assign-room")
def assign_room_for_session(
    session_id: int,
    request: AssignSessionRoomRequest,
    current_user: dict = Depends(require_role("doctor")),
):
    """
    Assign a room to the queue entry tied to the session.
    If exams are not provided, attach mock required exams automatically.
    """
    queue_row = QueueDB.get_queue_by_session(session_id)
    if not queue_row:
        raise HTTPException(status_code=404, detail="Queue entry not found for session")

    room = RoomDB.get_room(request.room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    if room['status'] != 'active':
        raise HTTPException(status_code=400, detail="Only active rooms can be assigned")

    if room['facility_id'] != queue_row['facility_id']:
        raise HTTPException(
            status_code=403,
            detail="Selected room does not belong to the queue facility",
        )

    doctor_id = _get_worker_id_for_user(current_user['user_id'])

    exams = request.required_exams or _default_mock_exams(
        queue_id=queue_row['queue_id'],
        queue_name=queue_row.get('queue_name'),
        department=queue_row.get('department'),
    )

    QueueDB.assign_to_doctor(
        queue_id=queue_row['queue_id'],
        doctor_id=doctor_id,
        room_id=request.room_id,
        exams=exams,
        notes=request.notes,
    )

    updated = QueueDB.get_queue_entry(queue_row['queue_id'])

    if updated and updated.get("phone_number"):
        try:
            from utils.sms_service import send_exam_assignment_sms
            from database.database import PatientDB
            patient = PatientDB.get_patient_by_phone(updated["phone_number"])
            language = (patient or {}).get("preferred_language", "english")
            send_exam_assignment_sms(
                patient_name=updated.get("patient_name", ""),
                phone_number=updated["phone_number"],
                queue_number=updated.get("queue_number", 0),
                required_exams=exams,
                room_name=updated.get("room_name"),
                location_hint=updated.get("location_hint"),
                language=language,
            )
        except Exception as _sms_exc:
            print(f"⚠️ SMS notification failed: {_sms_exc}")

    return {
        "message": "Room assigned successfully",
        "queue_entry": updated,
        "required_exams": exams,
    }


@router.put("/{queue_id}/status")
def update_queue_status(
    queue_id: int,
    request: UpdateStatusRequest,
    current_user: dict = Depends(require_role("doctor", "hospital_admin"))
):
    """Update queue entry status"""
    entry = QueueDB.get_queue_entry(queue_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Queue entry not found")
    
    valid_statuses = ['waiting', 'in_progress', 'completed', 'cancelled']
    if request.status not in valid_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status. Must be one of: {', '.join(valid_statuses)}"
        )
    
    QueueDB.update_queue_status(queue_id, request.status)
    return {"message": "Queue status updated", "queue_entry": QueueDB.get_queue_entry(queue_id)}


@router.get("/doctor/me", response_model=list[QueueEntryResponse])
def get_my_queue(current_user: dict = Depends(require_role("doctor"))):
    """Get queue for the current doctor"""
    worker_id = _get_worker_id_for_user(current_user['user_id'])
    
    queue = QueueDB.get_doctor_queue(worker_id)
    return [QueueEntryResponse(**entry) for entry in queue]
