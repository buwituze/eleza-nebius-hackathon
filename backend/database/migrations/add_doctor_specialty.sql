-- ============================================================================
-- MIGRATION: Add specialty column to users table
-- Date: March 15, 2026
-- Purpose: Allow doctors to have a specialty (e.g. generalist, dentist, pediatrician)
-- ============================================================================

ALTER TABLE users ADD COLUMN specialty VARCHAR(100);

CREATE INDEX idx_user_specialty ON users(specialty) WHERE specialty IS NOT NULL;

COMMENT ON COLUMN users.specialty IS 'Doctor specialty: generalist, dentist, pediatrician, etc.';

-- ============================================================================
-- ROLLBACK:
--   ALTER TABLE users DROP COLUMN specialty;
--   DROP INDEX IF EXISTS idx_user_specialty;
-- ============================================================================
