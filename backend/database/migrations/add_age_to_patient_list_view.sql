-- ============================================================================
-- MIGRATION: Expose patient_age in v_patient_list view
-- Date: March 18, 2026
-- Purpose: Surface the session-level patient_age so the doctor's All Patients
--          table can show an Age column without extra per-row API calls.
-- ============================================================================

CREATE OR REPLACE VIEW v_patient_list AS
SELECT
    p.patient_id,
    p.full_name,
    p.location AS residency,
    s.session_id,
    s.start_time,
    s.patient_age AS age,
    pred.risk_level AS priority,
    q.queue_number,
    q.queue_status,
    q.assigned_doctor_id,
    q.assigned_room_id
FROM patient p
LEFT JOIN session s ON p.patient_id = s.patient_id
LEFT JOIN prediction pred ON s.session_id = pred.session_id
LEFT JOIN examination_queue q ON s.session_id = q.session_id
ORDER BY s.start_time DESC;
