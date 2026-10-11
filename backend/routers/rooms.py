"""Room management endpoints."""

import logging
import os
import secrets
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, Query, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from database.database import RoomDB, FacilityDB, DatabaseConnection, UserDB
from routers.auth import get_current_user, require_role
from utils.email_service import send_facility_action_confirmation_email

# Initialize database connection pool
try:
    DatabaseConnection.initialize_pool()
except:
    pass

router = APIRouter(prefix="/rooms", tags=["rooms"])
logger = logging.getLogger(__name__)

ROOM_ACTION_CONFIRMATION_TTL_HOURS = int(
    os.getenv("ROOM_ACTION_CONFIRMATION_TTL_HOURS", "24")
)
PUBLIC_API_BASE_URL = os.getenv("PUBLIC_API_BASE_URL", "http://localhost:8000").rstrip(
    "/"
)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class RoomCreate(BaseModel):
    facility_id: int
    room_name: str
    room_type: str
    floor_number: Optional[int] = None
    capacity: int = 1


class RoomUpdate(BaseModel):
    room_name: Optional[str] = None
    room_type: Optional[str] = None
    status: Optional[str] = None  # active, inactive, maintenance
    floor_number: Optional[int] = None
    capacity: Optional[int] = None


class RoomStatusUpdate(BaseModel):
    status: str  # active, inactive, maintenance


class RoomResponse(BaseModel):
    room_id: int
    facility_id: int
    room_name: str
    room_type: str
    status: str
    floor_number: Optional[int]
    capacity: int
    created_at: Optional[datetime] = None


class RoomActionPendingResponse(BaseModel):
    status: str
    message: str
    action: str
    room_id: Optional[int] = None
    facility_id: int
    confirmation_sent_to: list[str]
    expires_at: datetime


class PendingRoomActionStore:
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


pending_room_actions = PendingRoomActionStore()


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


def _queue_platform_admin_room_action(
    *,
    action: str,
    facility_id: int,
    current_user: dict,
    details: dict[str, str],
    payload: dict,
    room_id: Optional[int] = None,
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
        "facility_id": facility_id,
        "room_id": room_id,
        "requested_by": requested_by,
        **payload,
    }
    token, expires_at = pending_room_actions.create(
        payload=pending_payload,
        ttl_hours=ROOM_ACTION_CONFIRMATION_TTL_HOURS,
    )

    confirmation_url = f"{PUBLIC_API_BASE_URL}/rooms/confirm-action/{token}"
    sent, error = send_facility_action_confirmation_email(
        recipients=recipients,
        facility_name=facility.get("name", "Facility"),
        action_title=f"Room {action.title()}",
        action_summary=f"Room {action}",
        requested_by_name=requested_by,
        confirmation_url=confirmation_url,
        expires_at_iso=expires_at.isoformat(),
        details=details,
    )

    if sent:
        message = f"Confirmation emails sent. Room {action} will run after hospital confirmation."
    else:
        logger.warning(
            "Room %s queued but confirmation email failed for facility %s: %s",
            action,
            facility_id,
            error,
        )
        message = (
            f"Room {action} request is queued and still requires hospital confirmation. "
            "Email service is currently unavailable, so admins should wait for confirmation processing."
        )

    return JSONResponse(
        status_code=status.HTTP_202_ACCEPTED,
        content={
            "status": "pending_confirmation",
            "message": message,
            "action": action,
            "room_id": room_id,
            "facility_id": facility_id,
            "confirmation_sent_to": recipients,
            "expires_at": expires_at.isoformat(),
        },
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=list[RoomResponse])
def list_rooms(
    facility_id: Optional[int] = Query(None, description="Filter by facility ID"),
    status: Optional[str] = Query(None, description="Filter by status"),
    current_user: dict = Depends(get_current_user)
):
    """
    List rooms. Filters by facility_id if provided.
    Hospital admins and doctors see their facility's rooms.
    Platform admins see all or filtered rooms.
    """
    # If user is not platform admin, restrict to their facility
    if current_user['role'] != 'platform_admin':
        if not current_user['facility_id']:
            raise HTTPException(status_code=403, detail="User not assigned to a facility")
        facility_id = current_user['facility_id']
    
    if not facility_id:
        raise HTTPException(status_code=400, detail="facility_id is required")
    
    if status == 'active':
        rooms = RoomDB.get_active_rooms(facility_id)
    else:
        rooms = RoomDB.get_rooms_by_facility(facility_id)
        if status:
            rooms = [r for r in rooms if r['status'] == status]
    
    return [RoomResponse(**r) for r in rooms]


@router.post(
    "",
    response_model=RoomResponse,
)
def create_room(
    room: RoomCreate,
    current_user: dict = Depends(require_role("platform_admin", "hospital_admin"))
):
    """Create a new room. Platform admin or hospital admin only."""
    # Verify facility exists
    facility = FacilityDB.get_facility(room.facility_id)
    if not facility:
        raise HTTPException(status_code=404, detail="Facility not found")

    # Hospital admin can only create rooms in their facility
    if current_user['role'] == 'hospital_admin' and current_user['facility_id'] != room.facility_id:
        raise HTTPException(status_code=403, detail="Can only create rooms in your facility")
    
    new_room = RoomDB.create_room(
        facility_id=room.facility_id,
        room_name=room.room_name,
        room_type=room.room_type,
        floor_number=room.floor_number,
        capacity=room.capacity
    )
    return RoomResponse(**new_room)


@router.get("/{room_id}", response_model=RoomResponse)
def get_room(
    room_id: int,
    current_user: dict = Depends(get_current_user)
):
    """Get room details by ID"""
    room = RoomDB.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Check access permissions
    if current_user['role'] != 'platform_admin':
        if current_user['facility_id'] != room['facility_id']:
            raise HTTPException(status_code=403, detail="Access denied")
    
    return RoomResponse(**room)


@router.put(
    "/{room_id}",
    response_model=RoomResponse,
)
def update_room(
    room_id: int,
    updates: RoomUpdate,
    current_user: dict = Depends(require_role("platform_admin", "hospital_admin"))
):
    """Update room details"""
    room = RoomDB.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Hospital admin can only update rooms in their facility
    if current_user['role'] == 'hospital_admin':
        if current_user['facility_id'] != room['facility_id']:
            raise HTTPException(status_code=403, detail="Can only update rooms in your facility")
    
    update_data = {k: v for k, v in updates.dict().items() if v is not None}
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")

    RoomDB.update_room(room_id, **update_data)
    
    return RoomResponse(**RoomDB.get_room(room_id))


@router.put("/{room_id}/status", response_model=RoomResponse)
def update_room_status(
    room_id: int,
    status_update: RoomStatusUpdate,
    current_user: dict = Depends(require_role("hospital_admin"))
):
    """Update room status. Hospital admin only."""
    room = RoomDB.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    if current_user['facility_id'] != room['facility_id']:
        raise HTTPException(status_code=403, detail="Can only update rooms in your facility")
    
    valid_statuses = ['active', 'inactive', 'maintenance']
    if status_update.status not in valid_statuses:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {', '.join(valid_statuses)}")
    
    RoomDB.update_room(room_id, status=status_update.status)
    return RoomResponse(**RoomDB.get_room(room_id))


@router.delete("/{room_id}")
def delete_room(
    room_id: int,
    current_user: dict = Depends(require_role("platform_admin", "hospital_admin"))
):
    """Delete a room"""
    room = RoomDB.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Hospital admin can only delete rooms in their facility
    if current_user['role'] == 'hospital_admin' and current_user['facility_id'] != room['facility_id']:
        raise HTTPException(status_code=403, detail="Can only delete rooms in your facility")

    RoomDB.delete_room(room_id)
    return {"message": "Room deleted successfully"}


@router.get("/confirm-action/{token}", response_model=dict)
def confirm_room_action(token: str):
    payload = pending_room_actions.pop_valid(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired confirmation token",
        )

    action = payload['action']
    if action == 'create':
        room_data = payload.get('room_data') or {}
        facility = FacilityDB.get_facility(room_data.get('facility_id'))
        if not facility:
            raise HTTPException(status_code=404, detail="Facility not found")
        room = RoomDB.create_room(**room_data)
        return RoomResponse(**room).model_dump()

    room_id = payload.get('room_id')
    if room_id is None:
        raise HTTPException(status_code=400, detail='room_id is required')

    room = RoomDB.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail='Room not found')

    if action == 'update':
        updates = payload.get('updates') or {}
        if not updates:
            raise HTTPException(status_code=400, detail='No fields to update')
        RoomDB.update_room(room_id, **updates)
        return RoomResponse(**RoomDB.get_room(room_id)).model_dump()

    if action == 'delete':
        RoomDB.delete_room(room_id)
        return {
            'status': 'deleted',
            'room_id': room_id,
            'message': 'Room deleted successfully',
        }

    raise HTTPException(status_code=400, detail='Unsupported room action')
