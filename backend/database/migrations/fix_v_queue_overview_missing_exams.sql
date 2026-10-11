-- ============================================================================
-- MIGRATION: Fix v_queue_overview missing required_exams and notes columns
-- Date: April 1, 2026
-- Purpose: v_queue_overview omitted q.required_exams and q.notes, so GET
--          /queue?session_id=X always returned null for required_exams and
--          the frontend displayed "No exams found" even after a doctor
--          successfully assigned exams.
-- ============================================================================

DROP VIEW IF EXISTS v_queue_overview;

CREATE VIEW v_queue_overview AS
SELECT
    q.queue_id, q.queue_number, q.queue_status,
    q.queue_name, q.department, q.location_hint,
    q.required_exams, q.notes,
    p.full_name AS patient_name, p.phone_number,
    pred.risk_level, pred.predicted_condition,
    hw.full_name AS doctor_name,
    r.room_name,
    f.name AS facility_name,
    q.created_at, q.started_at, q.completed_at
FROM examination_queue q
JOIN patient p ON q.patient_id = p.patient_id
JOIN facility f ON q.facility_id = f.facility_id
LEFT JOIN session s ON q.session_id = s.session_id
LEFT JOIN prediction pred ON s.session_id = pred.session_id
LEFT JOIN healthcare_worker hw ON q.assigned_doctor_id = hw.worker_id
LEFT JOIN room r ON q.assigned_room_id = r.room_id
ORDER BY q.queue_number;
