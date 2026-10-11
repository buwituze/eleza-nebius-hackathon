CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE language_preference AS ENUM ('kinyarwanda', 'english');
CREATE TYPE worker_role AS ENUM ('doctor', 'nurse', 'clinician');
CREATE TYPE session_status AS ENUM ('active', 'awaiting_review', 'completed');
CREATE TYPE sender_type AS ENUM ('patient', 'ml_system');
CREATE TYPE severity_level AS ENUM ('mild', 'moderate', 'severe');
CREATE TYPE risk_level AS ENUM ('low', 'medium', 'high');

CREATE TABLE patient (
    patient_id SERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    preferred_language language_preference DEFAULT 'kinyarwanda',
    location VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT patient_phone_check CHECK (phone_number ~ '^[0-9+\-\(\) ]+$'),
    CONSTRAINT patient_name_length CHECK (LENGTH(TRIM(full_name)) >= 2)
);

CREATE INDEX idx_patient_phone ON patient(phone_number);
CREATE INDEX idx_patient_name ON patient(full_name);
CREATE INDEX idx_patient_created_at ON patient(created_at DESC);
CREATE UNIQUE INDEX idx_patient_phone_name ON patient(phone_number, full_name);

CREATE TABLE healthcare_worker (
    worker_id SERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    role worker_role NOT NULL,
    specialization VARCHAR(255),
    facility VARCHAR(255),
    contact_info VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT worker_name_length CHECK (LENGTH(TRIM(full_name)) >= 2)
);

CREATE INDEX idx_worker_role ON healthcare_worker(role);
CREATE INDEX idx_worker_facility ON healthcare_worker(facility);
CREATE INDEX idx_worker_active ON healthcare_worker(is_active) WHERE is_active = TRUE;

CREATE TABLE session (
    session_id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE,
    status session_status DEFAULT 'active' NOT NULL,
    prediction_label VARCHAR(255),
    prediction_confidence NUMERIC(5,4),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_session_patient FOREIGN KEY (patient_id) 
        REFERENCES patient(patient_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT session_time_check CHECK (end_time IS NULL OR end_time >= start_time),
    CONSTRAINT session_confidence_range CHECK (prediction_confidence IS NULL OR 
        (prediction_confidence >= 0 AND prediction_confidence <= 1))
);

CREATE INDEX idx_session_patient ON session(patient_id);
CREATE INDEX idx_session_status ON session(status);
CREATE INDEX idx_session_start_time ON session(start_time DESC);
CREATE INDEX idx_session_patient_status ON session(patient_id, status);

CREATE TABLE conversation_message (
    message_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL,
    sender_type sender_type NOT NULL,
    message_text TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    sequence_number INTEGER NOT NULL,
    metadata JSONB,
    CONSTRAINT fk_message_session FOREIGN KEY (session_id) 
        REFERENCES session(session_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT message_text_not_empty CHECK (LENGTH(TRIM(message_text)) > 0),
    CONSTRAINT message_sequence_positive CHECK (sequence_number > 0)
);

CREATE INDEX idx_message_session ON conversation_message(session_id);
CREATE INDEX idx_message_timestamp ON conversation_message(timestamp);
CREATE INDEX idx_message_session_sequence ON conversation_message(session_id, sequence_number);
CREATE UNIQUE INDEX idx_message_session_sequence_unique ON conversation_message(session_id, sequence_number);

CREATE TABLE symptom (
    symptom_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL,
    symptom_name VARCHAR(255) NOT NULL,
    severity severity_level,
    duration VARCHAR(100),
    additional_info TEXT,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_symptom_session FOREIGN KEY (session_id) 
        REFERENCES session(session_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT symptom_name_not_empty CHECK (LENGTH(TRIM(symptom_name)) > 0)
);

CREATE INDEX idx_symptom_session ON symptom(session_id);
CREATE INDEX idx_symptom_name ON symptom(symptom_name);
CREATE INDEX idx_symptom_severity ON symptom(severity);

CREATE TABLE prediction (
    prediction_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL,
    predicted_condition VARCHAR(255) NOT NULL,
    risk_level risk_level NOT NULL,
    confidence_score NUMERIC(5,4) NOT NULL,
    model_version VARCHAR(50),
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reviewed_by INTEGER,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    CONSTRAINT fk_prediction_session FOREIGN KEY (session_id) 
        REFERENCES session(session_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_prediction_reviewer FOREIGN KEY (reviewed_by) 
        REFERENCES healthcare_worker(worker_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT prediction_confidence_range CHECK (confidence_score >= 0 AND confidence_score <= 1),
    CONSTRAINT prediction_review_time_check CHECK (reviewed_at IS NULL OR reviewed_at >= generated_at)
);

CREATE INDEX idx_prediction_session ON prediction(session_id);
CREATE INDEX idx_prediction_condition ON prediction(predicted_condition);
CREATE INDEX idx_prediction_risk ON prediction(risk_level);
CREATE INDEX idx_prediction_reviewer ON prediction(reviewed_by);
CREATE UNIQUE INDEX idx_prediction_session_unique ON prediction(session_id);

CREATE TABLE prescription (
    prescription_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL,
    worker_id INTEGER NOT NULL,
    medication_name VARCHAR(255) NOT NULL,
    dosage VARCHAR(255) NOT NULL,
    instructions TEXT NOT NULL,
    duration VARCHAR(100),
    prescribed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    dispensed BOOLEAN DEFAULT FALSE,
    dispensed_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    CONSTRAINT fk_prescription_session FOREIGN KEY (session_id) 
        REFERENCES session(session_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_prescription_worker FOREIGN KEY (worker_id) 
        REFERENCES healthcare_worker(worker_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT prescription_medication_not_empty CHECK (LENGTH(TRIM(medication_name)) > 0),
    CONSTRAINT prescription_dosage_not_empty CHECK (LENGTH(TRIM(dosage)) > 0),
    CONSTRAINT prescription_instructions_not_empty CHECK (LENGTH(TRIM(instructions)) > 0)
);

CREATE INDEX idx_prescription_session ON prescription(session_id);
CREATE INDEX idx_prescription_worker ON prescription(worker_id);
CREATE INDEX idx_prescription_medication ON prescription(medication_name);
CREATE INDEX idx_prescription_prescribed_at ON prescription(prescribed_at DESC);
CREATE INDEX idx_prescription_dispensed ON prescription(dispensed) WHERE dispensed = FALSE;

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_patient_updated_at BEFORE UPDATE ON patient
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_healthcare_worker_updated_at BEFORE UPDATE ON healthcare_worker
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_session_updated_at BEFORE UPDATE ON session
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE VIEW v_session_overview AS
SELECT 
    s.session_id, s.start_time, s.end_time, s.status,
    p.patient_id, p.full_name AS patient_name, p.phone_number, p.preferred_language,
    pred.predicted_condition, pred.risk_level, pred.confidence_score,
    pr.prescription_id, pr.medication_name,
    hw.full_name AS prescriber_name, hw.role AS prescriber_role
FROM session s
JOIN patient p ON s.patient_id = p.patient_id
LEFT JOIN prediction pred ON s.session_id = pred.session_id
LEFT JOIN prescription pr ON s.session_id = pr.session_id
LEFT JOIN healthcare_worker hw ON pr.worker_id = hw.worker_id;

CREATE VIEW v_sessions_awaiting_review AS
SELECT 
    s.session_id, s.start_time,
    p.full_name AS patient_name, p.phone_number,
    pred.predicted_condition, pred.risk_level, pred.confidence_score,
    COUNT(DISTINCT sym.symptom_id) AS symptom_count,
    COUNT(DISTINCT cm.message_id) AS message_count
FROM session s
JOIN patient p ON s.patient_id = p.patient_id
LEFT JOIN prediction pred ON s.session_id = pred.session_id
LEFT JOIN symptom sym ON s.session_id = sym.session_id
LEFT JOIN conversation_message cm ON s.session_id = cm.session_id
WHERE s.status = 'awaiting_review'
GROUP BY s.session_id, s.start_time, p.full_name, p.phone_number, 
         pred.predicted_condition, pred.risk_level, pred.confidence_score
ORDER BY s.start_time ASC;

CREATE VIEW v_worker_activity AS
SELECT 
    hw.worker_id, hw.full_name, hw.role, hw.facility,
    COUNT(DISTINCT pr.prescription_id) AS total_prescriptions,
    COUNT(DISTINCT pred.prediction_id) AS total_reviews,
    MAX(pr.prescribed_at) AS last_prescription_date,
    MAX(pred.reviewed_at) AS last_review_date
FROM healthcare_worker hw
LEFT JOIN prescription pr ON hw.worker_id = pr.worker_id
LEFT JOIN prediction pred ON hw.worker_id = pred.reviewed_by
WHERE hw.is_active = TRUE
GROUP BY hw.worker_id, hw.full_name, hw.role, hw.facility;

CREATE OR REPLACE FUNCTION close_session(p_session_id INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE session 
    SET status = 'completed', end_time = CURRENT_TIMESTAMP
    WHERE session_id = p_session_id AND status != 'completed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_patient_history(p_patient_id INTEGER)
RETURNS TABLE (
    session_id INTEGER,
    start_time TIMESTAMP WITH TIME ZONE,
    predicted_condition VARCHAR(255),
    risk_level risk_level,
    prescribed BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.session_id, s.start_time,
        pred.predicted_condition, pred.risk_level,
        (pr.prescription_id IS NOT NULL) AS prescribed
    FROM session s
    LEFT JOIN prediction pred ON s.session_id = pred.session_id
    LEFT JOIN prescription pr ON s.session_id = pr.session_id
    WHERE s.patient_id = p_patient_id
    ORDER BY s.start_time DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- EXTENDED SCHEMA: Authentication, Facilities, Rooms, Queue Management
-- ============================================================================

CREATE TYPE user_role AS ENUM ('platform_admin', 'hospital_admin', 'doctor');
CREATE TYPE room_status AS ENUM ('active', 'inactive', 'maintenance');
CREATE TYPE queue_status AS ENUM ('waiting', 'in_progress', 'completed', 'cancelled');

-- Users table for authentication
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT user_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT user_name_length CHECK (LENGTH(TRIM(full_name)) >= 2)
);

CREATE INDEX idx_user_email ON users(email);
CREATE INDEX idx_user_role ON users(role);
CREATE INDEX idx_user_active ON users(is_active) WHERE is_active = TRUE;

-- Facilities table
CREATE TABLE facility (
    facility_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    primary_email VARCHAR(255) NOT NULL,
    primary_phone VARCHAR(20) NOT NULL,
    location VARCHAR(500) NOT NULL,
    admin_user_id INTEGER,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_facility_admin FOREIGN KEY (admin_user_id)
        REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT facility_name_length CHECK (LENGTH(TRIM(name)) >= 2),
    CONSTRAINT facility_email_format CHECK (primary_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

CREATE INDEX idx_facility_name ON facility(name);
CREATE INDEX idx_facility_admin ON facility(admin_user_id);
CREATE INDEX idx_facility_active ON facility(is_active) WHERE is_active = TRUE;

-- Link users to facilities
ALTER TABLE users ADD COLUMN facility_id INTEGER;
ALTER TABLE users ADD CONSTRAINT fk_user_facility 
    FOREIGN KEY (facility_id) REFERENCES facility(facility_id) ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX idx_user_facility ON users(facility_id);

-- Update healthcare_worker to link to users and facilities  
ALTER TABLE healthcare_worker ADD COLUMN user_id INTEGER UNIQUE;
ALTER TABLE healthcare_worker ADD COLUMN facility_id INTEGER;
ALTER TABLE healthcare_worker ADD CONSTRAINT fk_worker_user
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE healthcare_worker ADD CONSTRAINT fk_worker_facility
    FOREIGN KEY (facility_id) REFERENCES facility(facility_id) ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX idx_worker_user ON healthcare_worker(user_id);
CREATE INDEX idx_worker_facility_link ON healthcare_worker(facility_id);

-- Rooms table
CREATE TABLE room (
    room_id SERIAL PRIMARY KEY,
    facility_id INTEGER NOT NULL,
    room_name VARCHAR(100) NOT NULL,
    room_type VARCHAR(100) NOT NULL,
    status room_status DEFAULT 'active' NOT NULL,
    floor_number INTEGER,
    capacity INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_room_facility FOREIGN KEY (facility_id)
        REFERENCES facility(facility_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT room_name_length CHECK (LENGTH(TRIM(room_name)) >= 1),
    CONSTRAINT room_capacity_positive CHECK (capacity > 0)
);

CREATE INDEX idx_room_facility ON room(facility_id);
CREATE INDEX idx_room_status ON room(status);
CREATE UNIQUE INDEX idx_room_facility_name ON room(facility_id, room_name);

-- Examination queue table
CREATE TABLE examination_queue (
    queue_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL UNIQUE,
    patient_id INTEGER NOT NULL,
    facility_id INTEGER NOT NULL,
    queue_name VARCHAR(100),
    department VARCHAR(100),
    location_hint VARCHAR(255),
    assigned_doctor_id INTEGER,
    assigned_room_id INTEGER,
    queue_number INTEGER NOT NULL,
    queue_status queue_status DEFAULT 'waiting' NOT NULL,
    required_exams TEXT[],
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_queue_session FOREIGN KEY (session_id)
        REFERENCES session(session_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_queue_patient FOREIGN KEY (patient_id)
        REFERENCES patient(patient_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_queue_facility FOREIGN KEY (facility_id)
        REFERENCES facility(facility_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_queue_doctor FOREIGN KEY (assigned_doctor_id)
        REFERENCES healthcare_worker(worker_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_queue_room FOREIGN KEY (assigned_room_id)
        REFERENCES room(room_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT queue_number_positive CHECK (queue_number > 0)
);

CREATE INDEX idx_queue_session ON examination_queue(session_id);
CREATE INDEX idx_queue_patient ON examination_queue(patient_id);
CREATE INDEX idx_queue_facility ON examination_queue(facility_id);
CREATE INDEX idx_queue_doctor ON examination_queue(assigned_doctor_id);
CREATE INDEX idx_queue_room ON examination_queue(assigned_room_id);
CREATE INDEX idx_queue_status ON examination_queue(queue_status);
CREATE INDEX idx_queue_created ON examination_queue(created_at DESC);

-- Audio storage references (file paths, not binary data)
CREATE TABLE audio_recording (
    audio_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL,
    sequence_number INTEGER NOT NULL,
    speaker_type sender_type NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size_bytes INTEGER,
    duration_seconds NUMERIC(10,2),
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_audio_session FOREIGN KEY (session_id)
        REFERENCES session(session_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT audio_sequence_positive CHECK (sequence_number >= 0),
    CONSTRAINT audio_file_size_positive CHECK (file_size_bytes IS NULL OR file_size_bytes > 0)
);

CREATE INDEX idx_audio_session ON audio_recording(session_id);
CREATE INDEX idx_audio_session_sequence ON audio_recording(session_id, sequence_number);

-- Session data storage for structured extraction and scores
ALTER TABLE session ADD COLUMN extraction_data JSONB;
ALTER TABLE session ADD COLUMN score_data JSONB;
ALTER TABLE session ADD COLUMN patient_message TEXT;
ALTER TABLE session ADD COLUMN doctor_brief JSONB;
ALTER TABLE session ADD COLUMN full_transcript TEXT;
ALTER TABLE session ADD COLUMN transcript_confidence NUMERIC(5,4);
ALTER TABLE session ADD COLUMN detected_language VARCHAR(50);

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_facility_updated_at BEFORE UPDATE ON facility
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_room_updated_at BEFORE UPDATE ON room
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_queue_updated_at BEFORE UPDATE ON examination_queue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Views for doctor dashboard
CREATE VIEW v_patient_list AS
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

CREATE VIEW v_facility_stats AS
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
GROUP BY f.facility_id, f.name, f.primary_email, f.primary_phone, f.location, f.admin_user_id, f.is_active, u.full_name;
