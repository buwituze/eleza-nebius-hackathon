"""
routers/facilities.py — Facility management endpoints.

GET    /facilities             → list all facilities
POST   /facilities             → create new facility (platform admin)
GET    /facilities/{id}        → get facility details
PUT    /facilities/{id}        → update facility (platform admin)
DELETE /facilities/{id}        → delete facility (platform admin, with permission)
"""

from typing import Optional
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, EmailStr

from database.database import FacilityDB, DatabaseConnection
from routers.auth import get_current_user, require_role

# Initialize database connection pool
try:
    DatabaseConnection.initialize_pool()
except:
    pass

router = APIRouter(prefix="/facilities", tags=["facilities"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class FacilityCreate(BaseModel):
    name: str
    primary_email: EmailStr
    primary_phone: str
    location: str


class FacilityUpdate(BaseModel):
    name: Optional[str] = None
    primary_email: Optional[EmailStr] = None
    primary_phone: Optional[str] = None
    location: Optional[str] = None
    admin_user_id: Optional[int] = None
    is_active: Optional[bool] = None


class FacilityResponse(BaseModel):
    facility_id: int
    name: str
    primary_email: str
    primary_phone: str
    location: str
    admin_user_id: Optional[int]
    admin_name: Optional[str]
    total_doctors: int
    total_rooms: int
    active_rooms: int
    is_active: bool
    created_at: Optional[datetime] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=list[FacilityResponse])
def list_facilities(current_user: dict = Depends(get_current_user)):
    """List all facilities. Available to all authenticated users."""
    facilities = FacilityDB.get_all_facilities()
    normalized: list[FacilityResponse] = []
    for facility in facilities:
        row = dict(facility)
        row.setdefault("admin_user_id", None)
        row.setdefault("admin_name", None)
        row.setdefault("total_doctors", 0)
        row.setdefault("total_rooms", 0)
        row.setdefault("active_rooms", 0)
        row.setdefault("is_active", True)
        normalized.append(FacilityResponse(**row))
    return normalized


@router.post("", response_model=dict)
def create_facility(
    facility: FacilityCreate,
    current_user: dict = Depends(require_role("platform_admin"))
):
    """Create a new facility. Platform admin only."""
    new_facility = FacilityDB.create_facility(
        name=facility.name,
        primary_email=facility.primary_email,
        primary_phone=facility.primary_phone,
        location=facility.location
    )
    return new_facility


@router.get("/{facility_id}", response_model=dict)
def get_facility(
    facility_id: int,
    current_user: dict = Depends(get_current_user)
):
    """Get facility details by ID"""
    facility = FacilityDB.get_facility(facility_id)
    if not facility:
        raise HTTPException(status_code=404, detail="Facility not found")
    return facility


@router.put("/{facility_id}", response_model=dict)
def update_facility(
    facility_id: int,
    updates: FacilityUpdate,
    current_user: dict = Depends(require_role("platform_admin"))
):
    """Update facility. Platform admin only."""
    facility = FacilityDB.get_facility(facility_id)
    if not facility:
        raise HTTPException(status_code=404, detail="Facility not found")
    
    update_data = {k: v for k, v in updates.dict().items() if v is not None}
    if update_data:
        FacilityDB.update_facility(facility_id, **update_data)
    
    return FacilityDB.get_facility(facility_id)


@router.delete("/{facility_id}")
def delete_facility(
    facility_id: int,
    current_user: dict = Depends(require_role("platform_admin"))
):
    """Delete facility. Platform admin only. Requires confirmation."""
    facility = FacilityDB.get_facility(facility_id)
    if not facility:
        raise HTTPException(status_code=404, detail="Facility not found")
    
    FacilityDB.delete_facility(facility_id)
    return {"message": "Facility deleted successfully"}
