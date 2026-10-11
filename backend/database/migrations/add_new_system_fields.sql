-- ============================================================================
-- MIGRATION: Add New System Fields to Session Table
-- Date: March 8, 2026
-- Purpose: Support new two-stage extraction and intelligent routing system
-- ============================================================================

-- Add new ENUM type for conversation modes
CREATE TYPE conversation_mode_type AS ENUM ('emergency', 'rule_based', 'ai_powered');

-- Add new columns to session table
ALTER TABLE session
    ADD COLUMN conversation_mode conversation_mode_type,
    ADD COLUMN api_calls_count INTEGER DEFAULT 0,
    ADD COLUMN cost_estimate NUMERIC(10,6) DEFAULT 0.0,
    ADD COLUMN transcription_quality VARCHAR(20),
    ADD COLUMN patient_age INTEGER,
    ADD COLUMN patient_gender VARCHAR(20),
    ADD COLUMN chief_complaint VARCHAR(255),
    ADD COLUMN routing_reasoning TEXT,
    ADD COLUMN severity_estimate INTEGER,
    ADD COLUMN red_flags_detected BOOLEAN DEFAULT FALSE;

-- Add check constraints
ALTER TABLE session
    ADD CONSTRAINT session_api_calls_positive CHECK (api_calls_count >= 0),
    ADD CONSTRAINT session_cost_positive CHECK (cost_estimate >= 0),
    ADD CONSTRAINT session_age_valid CHECK (patient_age IS NULL OR (patient_age >= 0 AND patient_age <= 150)),
    ADD CONSTRAINT session_severity_valid CHECK (severity_estimate IS NULL OR (severity_estimate >= 1 AND severity_estimate <= 10));

-- Add indexes for common queries
CREATE INDEX idx_session_conversation_mode ON session(conversation_mode);
CREATE INDEX idx_session_chief_complaint ON session(chief_complaint);
CREATE INDEX idx_session_red_flags ON session(red_flags_detected) WHERE red_flags_detected = TRUE;
CREATE INDEX idx_session_severity ON session(severity_estimate DESC);

-- Add comments for documentation
COMMENT ON COLUMN session.conversation_mode IS 'Routing decision: emergency, rule_based, or ai_powered';
COMMENT ON COLUMN session.api_calls_count IS 'Total API calls made during this session';
COMMENT ON COLUMN session.cost_estimate IS 'Estimated cost in USD for API calls';
COMMENT ON COLUMN session.transcription_quality IS 'Whisper transcription quality: high, medium, low';
COMMENT ON COLUMN session.patient_age IS 'Patient age for better context in risk scoring';
COMMENT ON COLUMN session.patient_gender IS 'Patient gender for better clinical context';
COMMENT ON COLUMN session.chief_complaint IS 'Normalized main symptom/complaint';
COMMENT ON COLUMN session.routing_reasoning IS 'Explanation of why this routing mode was chosen';
COMMENT ON COLUMN session.severity_estimate IS 'Initial severity estimate (1-10 scale)';
COMMENT ON COLUMN session.red_flags_detected IS 'Whether red flags were detected';

-- ============================================================================
-- ROLLBACK INSTRUCTIONS (if needed):
-- ============================================================================
-- ALTER TABLE session
--     DROP COLUMN conversation_mode,
--     DROP COLUMN api_calls_count,
--     DROP COLUMN cost_estimate,
--     DROP COLUMN transcription_quality,
--     DROP COLUMN patient_age,
--     DROP COLUMN patient_gender,
--     DROP COLUMN chief_complaint,
--     DROP COLUMN routing_reasoning,
--     DROP COLUMN severity_estimate,
--     DROP COLUMN red_flags_detected;
-- DROP TYPE conversation_mode_type;
