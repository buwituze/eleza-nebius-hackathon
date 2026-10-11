-- ============================================================================
-- MIGRATION: Fix v_facility_stats missing admin_user_id and is_active columns
-- Date: March 17, 2026
-- Purpose: FacilityResponse pydantic model requires admin_user_id and is_active
--          but the view omitted them, causing a 500 on GET /facilities.
-- ============================================================================

CREATE OR REPLACE VIEW v_facility_stats AS
SELECT 
    f.facility_id, f.name, f.primary_email, f.primary_phone, f.location,
    f.admin_user_id,
    f.is_active,
    u.full_name AS admin_name,
    COUNT(DISTINCT hw.worker_id) AS total_doctors,
    COUNT(DISTINCT r.room_id) AS total_rooms,
    COUNT(DISTINCT CASE WHEN r.status = 'active' THEN r.room_id END) AS active_rooms
FROM facility f
LEFT JOIN users u ON f.admin_user_id = u.user_id
LEFT JOIN healthcare_worker hw ON hw.facility_id = f.facility_id AND hw.is_active = TRUE
LEFT JOIN room r ON r.facility_id = f.facility_id
WHERE f.is_active = TRUE
GROUP BY f.facility_id, f.name, f.primary_email, f.primary_phone, f.location,
         f.admin_user_id, f.is_active, u.full_name;
