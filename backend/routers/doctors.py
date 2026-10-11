"""
routers/doctors.py — Doctor management endpoints for hospital admins.

POST   /doctors                        → register a new doctor
GET    /doctors                        → list doctors at the admin's facility
GET    /doctors/{doctor_id}            → get a doctor's profile
PUT    /doctors/{doctor_id}            → update doctor info
PATCH  /doctors/{doctor_id}/deactivate → deactivate a doctor (soft delete)
PATCH  /doctors/{doctor_id}/activate   → reactivate a doctor

hospital_admin: can only manage doctors within their own facility.
platform_admin: can manage doctors across all facilities.
"""

import logging
import os
import secrets
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr

from database.database import UserDB, FacilityDB, DatabaseConnection
from routers.auth import require_role, hash_password
from utils.email_service import (
    send_credentials_email,
    send_doctor_assignment_confirmation_email,
    send_facility_action_confirmation_email,
)

try:
    DatabaseConnection.initialize_pool()
except Exception:
    pass

router = APIRouter(prefix="/doctors", tags=["doctors"])
logger = logging.getLogger(__name__)

DOCTOR_CONFIRMATION_TTL_HOURS = int(os.getenv("DOCTOR_ASSIGN_CONFIRMATION_TTL_HOURS", "24"))
DOCTOR_ACTION_CONFIRMATION_TTL_HOURS = int(os.getenv("DOCTOR_ACTION_CONFIRMATION_TTL_HOURS", "24"))
PUBLIC_API_BASE_URL = os.getenv("PUBLIC_API_BASE_URL", "http://localhost:8000").rstrip("/")


class PendingDoctorRegistrationStore:
    """In-memory pending requests for email confirmation before doctor creation."""

    def __init__(self):
        self._items: dict[str, dict] = {}
        self._lock = Lock()

    def create(self, payload: dict, ttl_hours: int) -> tuple[str, datetime]:
        token = secrets.token_urlsafe(36)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=ttl_hours)
        with self._lock:
            self._items[token] = {"payload": payload, "expires_at": expires_at}
        return token, expires_at

    def pop_valid(self, token: str) -> Optional[dict]:
        now = datetime.now(timezone.utc)
        with self._lock:
            record = self._items.pop(token, None)
            if not record:
                return None
            if record["expires_at"] < now:
                return None
            return record["payload"]

    def discard(self, token: str):
        with self._lock:
            self._items.pop(token, None)


pending_doctor_registrations = PendingDoctorRegistrationStore()


class PendingDoctorActionStore:
    """In-memory pending doctor updates/deactivation/reactivation for confirmation."""

    def __init__(self):
        self._items: dict[str, dict] = {}
        self._lock = Lock()

    def create(self, payload: dict, ttl_hours: int) -> tuple[str, datetime]:
        token = secrets.token_urlsafe(36)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=ttl_hours)
        with self._lock:
            self._items[token] = {"payload": payload, "expires_at": expires_at}
        return token, expires_at

    def pop_valid(self, token: str) -> Optional[dict]:
        now = datetime.now(timezone.utc)
        with self._lock:
            record = self._items.pop(token, None)
            if not record:
                return None
            if record["expires_at"] < now:
                return None
            return record["payload"]

    def discard(self, token: str):
        with self._lock:
            self._items.pop(token, None)


pending_doctor_actions = PendingDoctorActionStore()


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class DoctorRegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    specialty: Optional[str] = None   # e.g. "generalist", "dentist", "pediatrician"
    facility_id: Optional[int] = None  # hospital_admin uses their own; platform_admin must supply


class DoctorUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    specialty: Optional[str] = None


class DoctorResponse(BaseModel):
    user_id: int
    email: str
    full_name: str
    specialty: Optional[str]
    facility_id: Optional[int]
    is_active: bool
    created_at: Optional[datetime] = None


class DoctorRegistrationPendingResponse(BaseModel):
    status: str
    message: str
    facility_id: int
    confirmation_sent_to: list[EmailStr]
    expires_at: datetime


class DoctorActionPendingResponse(BaseModel):
    status: str
    message: str
    action: str
    doctor_id: int
    facility_id: int
    confirmation_sent_to: list[EmailStr]
    expires_at: datetime


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _assert_facility_access(current_user: dict, target_facility_id: Optional[int]):
    """Raise 403 if a hospital_admin tries to access a doctor outside their facility."""
    if current_user['role'] == 'hospital_admin':
        if target_facility_id != current_user['facility_id']:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")


def _get_doctor_or_404(doctor_id: int) -> dict:
    user = UserDB.get_user_by_id(doctor_id)
    if not user or user['role'] != 'doctor':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Doctor not found")
    return dict(user)


def _send_doctor_credentials_email(email: str, full_name: str, password: str):
    sent, error = send_credentials_email(
        recipient_email=email,
        recipient_name=full_name,
        username=email,
        temporary_password=password,
        role="doctor",
    )
    if not sent:
        logger.warning(
            "Doctor created but credential email failed for %s: %s",
            email,
            error,
        )


def _facility_confirmation_recipients(facility_id: int) -> list[str]:
    facility = FacilityDB.get_facility(facility_id)
    if not facility:
        return []

    recipients = set()
    primary_email = (facility.get("primary_email") or "").strip()
    if primary_email:
        recipients.add(primary_email.lower())

    for user in UserDB.get_users_by_facility(facility_id):
        if user.get("role") != "hospital_admin":
            continue
        admin_email = (user.get("email") or "").strip()
        if admin_email:
            recipients.add(admin_email.lower())

    return sorted(recipients)


def _queue_platform_admin_doctor_action(
    *,
    action: str,
    doctor_id: int,
    facility_id: int,
    current_user: dict,
    details: dict[str, str],
    payload: dict,
) -> JSONResponse:
    facility = FacilityDB.get_facility(facility_id)
    if not facility:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Facility {facility_id} not found",
        )

    recipients = _facility_confirmation_recipients(facility_id)
    if not recipients:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No facility confirmation recipients found (primary_email or hospital_admin email is required)",
        )

    requested_by = (
        current_user.get("full_name")
        or current_user.get("email")
        or "Platform Admin"
    )
    pending_payload = {
        "action": action,
        "doctor_id": doctor_id,
        "facility_id": facility_id,
        "requested_by": requested_by,
        **payload,
    }
    token, expires_at = pending_doctor_actions.create(
        payload=pending_payload,
        ttl_hours=DOCTOR_ACTION_CONFIRMATION_TTL_HOURS,
    )

    confirmation_url = f"{PUBLIC_API_BASE_URL}/doctors/confirm-action/{token}"
    sent, error = send_facility_action_confirmation_email(
        recipients=recipients,
        facility_name=facility.get("name", "Facility"),
        action_title=f"Doctor {action.title()}",
        action_summary=f"Doctor {action}",
        requested_by_name=requested_by,
        confirmation_url=confirmation_url,
        expires_at_iso=expires_at.isoformat(),
        details=details,
    )

    if sent:
        message = f"Confirmation emails sent. Doctor {action} will run after hospital confirmation."
    else:
        logger.warning(
            "Doctor %s queued but confirmation email failed for facility %s: %s",
            action,
            facility_id,
            error,
        )
        message = (
            f"Doctor {action} request is queued and still requires hospital confirmation. "
            "Email service is currently unavailable, so admins should wait for confirmation processing."
        )

    return JSONResponse(
        status_code=status.HTTP_202_ACCEPTED,
        content={
            "status": "pending_confirmation",
            "message": message,
            "action": action,
            "doctor_id": doctor_id,
            "facility_id": facility_id,
            "confirmation_sent_to": recipients,
            "expires_at": expires_at.isoformat(),
        },
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post(
    "",
    response_model=DoctorResponse,
    status_code=status.HTTP_201_CREATED,
)
def register_doctor(
    request: DoctorRegisterRequest,
    current_user: dict = Depends(require_role("hospital_admin", "platform_admin"))
):
    """Register a new doctor. hospital_admin registers doctors for their own facility."""
    if current_user['role'] == 'hospital_admin':
        facility_id = current_user['facility_id']
        if facility_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your admin account is not linked to a facility"
            )
        if request.facility_id is not None and request.facility_id != facility_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only register doctors for your own facility"
            )
    else:
        # platform_admin must provide target facility.
        if request.facility_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="facility_id is required"
            )
        facility_id = request.facility_id
        facility = FacilityDB.get_facility(facility_id)
        if not facility:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Facility {facility_id} not found"
            )

    if UserDB.get_user_by_email(request.email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    user = UserDB.create_user(
        email=request.email,
        password_hash=hash_password(request.password),
        full_name=request.full_name,
        role="doctor",
        facility_id=facility_id,
        specialty=request.specialty,
    )
    _send_doctor_credentials_email(
        email=request.email,
        full_name=request.full_name,
        password=request.password,
    )
    return DoctorResponse(**user)


@router.get("", response_model=list[DoctorResponse])
def list_doctors(
    current_user: dict = Depends(require_role("hospital_admin", "platform_admin"))
):
    """List doctors. hospital_admin sees only their facility's doctors."""
    if current_user['role'] == 'hospital_admin':
        facility_id = current_user['facility_id']
        if facility_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your admin account is not linked to a facility"
            )
        doctors = UserDB.get_doctors_by_facility(facility_id)
    else:
        doctors = UserDB.get_all_doctors()
    return [DoctorResponse(**d) for d in doctors]


@router.get("/confirm-registration", response_model=DoctorResponse)
def confirm_doctor_registration(token: str):
    """Confirm a platform-admin doctor assignment and create the doctor account."""
    payload = pending_doctor_registrations.pop_valid(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired confirmation token",
        )

    facility = FacilityDB.get_facility(payload["facility_id"])
    if not facility:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Facility {payload['facility_id']} not found",
        )

    if UserDB.get_user_by_email(payload["email"]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Doctor email already registered",
        )

    user = UserDB.create_user(
        email=payload["email"],
        password_hash=hash_password(payload["password"]),
        full_name=payload["full_name"],
        role="doctor",
        facility_id=payload["facility_id"],
        specialty=payload.get("specialty"),
    )
    _send_doctor_credentials_email(
        email=payload["email"],
        full_name=payload["full_name"],
        password=payload["password"],
    )
    return DoctorResponse(**user)


@router.get("/{doctor_id}", response_model=DoctorResponse)
def get_doctor(
    doctor_id: int,
    current_user: dict = Depends(require_role("hospital_admin", "platform_admin"))
):
    """Get a single doctor's profile."""
    user = _get_doctor_or_404(doctor_id)
    _assert_facility_access(current_user, user.get('facility_id'))
    return DoctorResponse(**user)


@router.put(
    "/{doctor_id}",
    response_model=DoctorResponse,
)
def update_doctor(
    doctor_id: int,
    request: DoctorUpdateRequest,
    current_user: dict = Depends(require_role("hospital_admin", "platform_admin"))
):
    """Update a doctor's full_name, email, or specialty."""
    user = _get_doctor_or_404(doctor_id)
    _assert_facility_access(current_user, user.get('facility_id'))

    updates = {k: v for k, v in request.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")

    if 'email' in updates:
        existing = UserDB.get_user_by_email(updates['email'])
        if existing and existing['user_id'] != doctor_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already in use by another account"
            )

    UserDB.update_user(doctor_id, **updates)
    return DoctorResponse(**UserDB.get_user_by_id(doctor_id))


@router.patch(
    "/{doctor_id}/deactivate",
    response_model=DoctorResponse,
)
def deactivate_doctor(
    doctor_id: int,
    current_user: dict = Depends(require_role("hospital_admin", "platform_admin"))
):
    """Deactivate a doctor (soft delete — they cannot log in but data is preserved)."""
    user = _get_doctor_or_404(doctor_id)
    _assert_facility_access(current_user, user.get('facility_id'))

    if not user['is_active']:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Doctor is already inactive")

    UserDB.update_user(doctor_id, is_active=False)
    return DoctorResponse(**UserDB.get_user_by_id(doctor_id))


@router.patch(
    "/{doctor_id}/activate",
    response_model=DoctorResponse,
)
def activate_doctor(
    doctor_id: int,
    current_user: dict = Depends(require_role("hospital_admin", "platform_admin"))
):
    """Reactivate a previously deactivated doctor."""
    user = _get_doctor_or_404(doctor_id)
    _assert_facility_access(current_user, user.get('facility_id'))

    if user['is_active']:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Doctor is already active")

    UserDB.update_user(doctor_id, is_active=True)
    return DoctorResponse(**UserDB.get_user_by_id(doctor_id))


@router.get("/confirm-action/{token}", response_model=DoctorResponse)
def confirm_doctor_action(token: str):
    payload = pending_doctor_actions.pop_valid(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired confirmation token",
        )

    doctor_id = payload["doctor_id"]
    action = payload["action"]
    user = _get_doctor_or_404(doctor_id)

    if action == "update":
        updates = payload.get("updates") or {}
        if not updates:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No fields to update",
            )
        if "email" in updates:
            existing = UserDB.get_user_by_email(updates["email"])
            if existing and existing["user_id"] != doctor_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email already in use by another account",
                )
        UserDB.update_user(doctor_id, **updates)

    elif action == "deactivate":
        if not user["is_active"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Doctor is already inactive",
            )
        UserDB.update_user(doctor_id, is_active=False)

    elif action == "activate":
        if user["is_active"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Doctor is already active",
            )
        UserDB.update_user(doctor_id, is_active=True)

    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported doctor action",
        )

    return DoctorResponse(**UserDB.get_user_by_id(doctor_id))
