import os
import logging
import json
import uuid
from typing import Optional, Dict, List, Any, Tuple
from contextlib import contextmanager
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DatabaseConnection:
    _connection_pool: Optional[pool.ThreadedConnectionPool] = None
    
    @classmethod
    def initialize_pool(cls, min_conn: int = 1, max_conn: int = 10):
        if cls._connection_pool is not None:
            logger.warning("Connection pool already initialized")
            return
        
        try:
            cls._connection_pool = pool.ThreadedConnectionPool(
                min_conn, max_conn,
                host=os.getenv('DB_HOST', 'localhost'),
                port=os.getenv('DB_PORT', '5432'),
                database=os.getenv('DB_NAME', 'pre_consultation_db'),
                user=os.getenv('DB_USER', 'postgres'),
                password=os.getenv('DB_PASSWORD', ''),
                cursor_factory=RealDictCursor
            )
            logger.info("Database connection pool initialized")
        except Exception as e:
            logger.error(f"Failed to initialize connection pool: {e}")
            raise
    
    @classmethod
    def close_pool(cls):
        if cls._connection_pool:
            cls._connection_pool.closeall()
            cls._connection_pool = None
            logger.info("Database connection pool closed")
    
    @classmethod
    @contextmanager
    def get_connection(cls):
        if cls._connection_pool is None:
            cls.initialize_pool()
        
        conn = cls._connection_pool.getconn()
        try:
            yield conn
            conn.commit()
        except Exception as e:
            conn.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            cls._connection_pool.putconn(conn)
    
    @classmethod
    def execute_query(cls, query: str, params: Optional[Tuple] = None, fetch_one: bool = False):
        with cls.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                return cur.fetchone() if fetch_one else cur.fetchall()
    
    @classmethod
    def execute_update(cls, query: str, params: Optional[Tuple] = None) -> int:
        with cls.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                return cur.rowcount


class PatientDB:
    @staticmethod
    def create_patient(full_name: str, phone_number: str, 
                      preferred_language: str = 'kinyarwanda', 
                      location: Optional[str] = None) -> Dict:
        query = """
            INSERT INTO patient (full_name, phone_number, preferred_language, location)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (phone_number, full_name) 
            DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (full_name, phone_number, preferred_language, location))
                return dict(cur.fetchone())
    
    @staticmethod
    def create_new_patient(preferred_language: str = 'kinyarwanda', location: Optional[str] = None) -> Dict:
        """
        Create a placeholder patient at kiosk start. Each visit gets a unique patient row;
        name/phone are updated at finish when collected. Placeholders must satisfy:
        - patient_name_length: LENGTH(TRIM(full_name)) >= 2
        - patient_phone_check: phone ~ '^[0-9+\-\(\) ]+$'
        - idx_patient_phone_name: unique (phone_number, full_name) — use unique placeholder
        """
        unique_suffix = uuid.uuid4().hex[:12]
        full_name = f"Pending-{unique_suffix}"
        phone_number = "0"
        query = """
            INSERT INTO patient (full_name, phone_number, preferred_language, location)
            VALUES (%s, %s, %s, %s)
            RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (full_name, phone_number, preferred_language, location))
                return dict(cur.fetchone())

    @staticmethod
    def update_patient(patient_id: int, full_name: str, phone_number: str, location: Optional[str] = None) -> Optional[Dict]:
        query = """
            UPDATE patient
            SET full_name = %s, phone_number = %s, location = %s
            WHERE patient_id = %s
            RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (full_name, phone_number, location, patient_id))
                return dict(cur.fetchone())

    @staticmethod
    def get_patient_by_phone(phone_number: str) -> Optional[Dict]:
        query = "SELECT * FROM patient WHERE phone_number = %s ORDER BY created_at DESC LIMIT 1"
        return DatabaseConnection.execute_query(query, (phone_number,), fetch_one=True)
    
    @staticmethod
    def get_patient_by_id(patient_id: int) -> Optional[Dict]:
        query = "SELECT * FROM patient WHERE patient_id = %s"
        return DatabaseConnection.execute_query(query, (patient_id,), fetch_one=True)


class SessionDB:
    @staticmethod
    def create_session(patient_id: int) -> Dict:
        query = "INSERT INTO session (patient_id, status) VALUES (%s, 'active') RETURNING *"
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (patient_id,))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_session(session_id: int) -> Optional[Dict]:
        query = "SELECT * FROM session WHERE session_id = %s"
        return DatabaseConnection.execute_query(query, (session_id,), fetch_one=True)
    
    @staticmethod
    def update_session_status(session_id: int, status: str) -> int:
        query = "UPDATE session SET status = %s WHERE session_id = %s"
        return DatabaseConnection.execute_update(query, (status, session_id))
    
    @staticmethod
    def close_session(session_id: int) -> int:
        query = "SELECT close_session(%s)"
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (session_id,))
                return 1
    
    @staticmethod
    def update_prediction_info(session_id: int, prediction_label: str, confidence: float) -> int:
        query = "UPDATE session SET prediction_label = %s, prediction_confidence = %s WHERE session_id = %s"
        return DatabaseConnection.execute_update(query, (prediction_label, confidence, session_id))
    
    @staticmethod
    def get_sessions_awaiting_review() -> List[Dict]:
        return DatabaseConnection.execute_query("SELECT * FROM v_sessions_awaiting_review")


class ConversationDB:
    @staticmethod
    def add_message(session_id: int, sender_type: str, message_text: str, 
                    sequence_number: int, metadata: Optional[Dict] = None) -> Dict:
        query = """
            INSERT INTO conversation_message 
            (session_id, sender_type, message_text, sequence_number, metadata)
            VALUES (%s, %s, %s, %s, %s) RETURNING *
        """
        metadata_json = json.dumps(metadata) if metadata else None
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (session_id, sender_type, message_text, sequence_number, metadata_json))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_conversation(session_id: int) -> List[Dict]:
        query = "SELECT * FROM conversation_message WHERE session_id = %s ORDER BY sequence_number"
        return DatabaseConnection.execute_query(query, (session_id,))
    
    @staticmethod
    def get_last_sequence_number(session_id: int) -> int:
        query = "SELECT COALESCE(MAX(sequence_number), 0) as last_seq FROM conversation_message WHERE session_id = %s"
        result = DatabaseConnection.execute_query(query, (session_id,), fetch_one=True)
        return result['last_seq'] if result else 0


class SymptomDB:
    @staticmethod
    def add_symptom(session_id: int, symptom_name: str, severity: Optional[str] = None, 
                    duration: Optional[str] = None, additional_info: Optional[str] = None) -> Dict:
        query = """
            INSERT INTO symptom (session_id, symptom_name, severity, duration, additional_info)
            VALUES (%s, %s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (session_id, symptom_name, severity, duration, additional_info))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_session_symptoms(session_id: int) -> List[Dict]:
        query = "SELECT * FROM symptom WHERE session_id = %s ORDER BY recorded_at"
        return DatabaseConnection.execute_query(query, (session_id,))


class PredictionDB:
    @staticmethod
    def create_prediction(session_id: int, predicted_condition: str, risk_level: str, 
                         confidence_score: float, model_version: Optional[str] = None) -> Dict:
        query = """
            INSERT INTO prediction (session_id, predicted_condition, risk_level, confidence_score, model_version)
            VALUES (%s, %s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (session_id, predicted_condition, risk_level, confidence_score, model_version))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_session_prediction(session_id: int) -> Optional[Dict]:
        query = "SELECT * FROM prediction WHERE session_id = %s"
        return DatabaseConnection.execute_query(query, (session_id,), fetch_one=True)
    
    @staticmethod
    def mark_reviewed(prediction_id: int, worker_id: int, review_notes: Optional[str] = None) -> int:
        query = """
            UPDATE prediction SET reviewed_by = %s, reviewed_at = CURRENT_TIMESTAMP, 
            review_notes = %s WHERE prediction_id = %s
        """
        return DatabaseConnection.execute_update(query, (worker_id, review_notes, prediction_id))


class PrescriptionDB:
    @staticmethod
    def create_prescription(session_id: int, worker_id: int, medication_name: str, 
                          dosage: str, instructions: str, duration: Optional[str] = None,
                          notes: Optional[str] = None) -> Dict:
        query = """
            INSERT INTO prescription (session_id, worker_id, medication_name, dosage, instructions, duration, notes)
            VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (session_id, worker_id, medication_name, dosage, instructions, duration, notes))
                return dict(cur.fetchone())
    
    @staticmethod
    def mark_dispensed(prescription_id: int) -> int:
        query = "UPDATE prescription SET dispensed = TRUE, dispensed_at = CURRENT_TIMESTAMP WHERE prescription_id = %s"
        return DatabaseConnection.execute_update(query, (prescription_id,))
    
    @staticmethod
    def get_session_prescription(session_id: int) -> Optional[Dict]:
        query = "SELECT * FROM prescription WHERE session_id = %s"
        return DatabaseConnection.execute_query(query, (session_id,), fetch_one=True)


class HealthcareWorkerDB:
    @staticmethod
    def get_worker(worker_id: int) -> Optional[Dict]:
        query = "SELECT * FROM healthcare_worker WHERE worker_id = %s"
        return DatabaseConnection.execute_query(query, (worker_id,), fetch_one=True)
    
    @staticmethod
    def get_worker_activity(worker_id: int) -> Optional[Dict]:
        query = "SELECT * FROM v_worker_activity WHERE worker_id = %s"
        return DatabaseConnection.execute_query(query, (worker_id,), fetch_one=True)
    
    @staticmethod
    def get_workers_by_facility(facility_id: int) -> List[Dict]:
        query = "SELECT * FROM healthcare_worker WHERE facility_id = %s AND is_active = TRUE"
        return DatabaseConnection.execute_query(query, (facility_id,))
    
    @staticmethod
    def create_worker(full_name: str, role: str, facility_id: int, user_id: Optional[int] = None,
                     specialization: Optional[str] = None, contact_info: Optional[str] = None) -> Dict:
        query = """
            INSERT INTO healthcare_worker (full_name, role, facility_id, user_id, specialization, contact_info)
            VALUES (%s, %s, %s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (full_name, role, facility_id, user_id, specialization, contact_info))
                return dict(cur.fetchone())
    
    @staticmethod
    def update_worker(worker_id: int, **kwargs) -> int:
        allowed_fields = {'full_name', 'role', 'specialization', 'contact_info', 'is_active'}
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        if not updates:
            return 0
        
        set_clause = ", ".join([f"{k} = %s" for k in updates.keys()])
        query = f"UPDATE healthcare_worker SET {set_clause} WHERE worker_id = %s"
        return DatabaseConnection.execute_update(query, (*updates.values(), worker_id))
    
    @staticmethod
    def deactivate_worker(worker_id: int) -> int:
        query = "UPDATE healthcare_worker SET is_active = FALSE WHERE worker_id = %s"
        return DatabaseConnection.execute_update(query, (worker_id,))


class UserDB:
    _has_specialty_column_cache: Optional[bool] = None

    @classmethod
    def _has_specialty_column(cls) -> bool:
        if cls._has_specialty_column_cache is not None:
            return cls._has_specialty_column_cache

        query = """
            SELECT EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'users'
                  AND column_name = 'specialty'
            ) AS exists
        """
        row = DatabaseConnection.execute_query(query, fetch_one=True)
        cls._has_specialty_column_cache = bool(row and row.get('exists'))
        return cls._has_specialty_column_cache

    @classmethod
    def _user_select_fields(cls) -> str:
        if cls._has_specialty_column():
            return "user_id, email, full_name, role, specialty, facility_id, is_active, created_at"
        return "user_id, email, full_name, role, NULL::text AS specialty, facility_id, is_active, created_at"

    @staticmethod
    def create_user(email: str, password_hash: str, full_name: str, role: str,
                   facility_id: Optional[int] = None, specialty: Optional[str] = None) -> Dict:
        if UserDB._has_specialty_column():
            query = """
                INSERT INTO users (email, password_hash, full_name, role, facility_id, specialty)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING user_id, email, full_name, role, facility_id, specialty, is_active, created_at
            """
            params = (email, password_hash, full_name, role, facility_id, specialty)
        else:
            query = """
                INSERT INTO users (email, password_hash, full_name, role, facility_id)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING user_id, email, full_name, role, facility_id, NULL::text AS specialty, is_active, created_at
            """
            params = (email, password_hash, full_name, role, facility_id)

        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                return dict(cur.fetchone())
    
    @staticmethod
    def get_user_by_email(email: str) -> Optional[Dict]:
        query = "SELECT * FROM users WHERE email = %s"
        return DatabaseConnection.execute_query(query, (email,), fetch_one=True)
    
    @staticmethod
    def get_user_by_id(user_id: int) -> Optional[Dict]:
        query = "SELECT * FROM users WHERE user_id = %s"
        return DatabaseConnection.execute_query(query, (user_id,), fetch_one=True)
    
    @staticmethod
    def update_user(user_id: int, **kwargs) -> int:
        allowed_fields = {'email', 'password_hash', 'full_name', 'is_active', 'facility_id'}
        if UserDB._has_specialty_column():
            allowed_fields.add('specialty')
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        if not updates:
            return 0
        
        set_clause = ", ".join([f"{k} = %s" for k in updates.keys()])
        query = f"UPDATE users SET {set_clause} WHERE user_id = %s"
        return DatabaseConnection.execute_update(query, (*updates.values(), user_id))
    
    @staticmethod
    def get_users_by_facility(facility_id: int) -> List[Dict]:
        query = f"SELECT {UserDB._user_select_fields()} FROM users WHERE facility_id = %s"
        return DatabaseConnection.execute_query(query, (facility_id,))

    @staticmethod
    def get_doctors_by_facility(facility_id: int) -> List[Dict]:
        query = f"""
            SELECT {UserDB._user_select_fields()}
            FROM users WHERE facility_id = %s AND role = 'doctor' ORDER BY full_name
        """
        return DatabaseConnection.execute_query(query, (facility_id,))

    @staticmethod
    def get_all_doctors() -> List[Dict]:
        query = f"""
            SELECT {UserDB._user_select_fields()}
            FROM users WHERE role = 'doctor' ORDER BY facility_id, full_name
        """
        return DatabaseConnection.execute_query(query)

    @staticmethod
    def get_users_by_role(role: str) -> List[Dict]:
        query = f"""
            SELECT {UserDB._user_select_fields()}
            FROM users WHERE role = %s ORDER BY full_name
        """
        return DatabaseConnection.execute_query(query, (role,))

    @staticmethod
    def get_all_users() -> List[Dict]:
        query = f"""
            SELECT {UserDB._user_select_fields()}
            FROM users
            ORDER BY full_name
        """
        return DatabaseConnection.execute_query(query)


class FacilityDB:
    @staticmethod
    def create_facility(name: str, primary_email: str, primary_phone: str,
                       location: str) -> Dict:
        query = """
            INSERT INTO facility (name, primary_email, primary_phone, location)
            VALUES (%s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (name, primary_email, primary_phone, location))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_facility(facility_id: int) -> Optional[Dict]:
        query = "SELECT * FROM facility WHERE facility_id = %s"
        return DatabaseConnection.execute_query(query, (facility_id,), fetch_one=True)
    
    @staticmethod
    def get_all_facilities() -> List[Dict]:
        query = "SELECT * FROM v_facility_stats ORDER BY name"
        return DatabaseConnection.execute_query(query)

    @staticmethod
    def get_active_facility() -> Optional[Dict]:
        query = "SELECT * FROM facility WHERE is_active = TRUE ORDER BY facility_id LIMIT 1"
        return DatabaseConnection.execute_query(query, fetch_one=True)

    @staticmethod
    def resolve_facility_id(preferred_facility_id: Optional[int] = None) -> int:
        """
        Resolve to a valid facility id.
        Priority:
        1) preferred facility if it exists
        2) first active facility
        3) auto-create a default facility
        """
        if preferred_facility_id:
            facility = FacilityDB.get_facility(preferred_facility_id)
            if facility:
                return preferred_facility_id

        active = FacilityDB.get_active_facility()
        if active:
            return int(active['facility_id'])

        created = FacilityDB.create_facility(
            name="Default Facility",
            primary_email="facility@example.com",
            primary_phone="+250000000000",
            location="Main Campus"
        )
        return int(created['facility_id'])
    
    @staticmethod
    def update_facility(facility_id: int, **kwargs) -> int:
        allowed_fields = {'name', 'primary_email', 'primary_phone', 'location', 'admin_user_id', 'is_active'}
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        if not updates:
            return 0
        
        set_clause = ", ".join([f"{k} = %s" for k in updates.keys()])
        query = f"UPDATE facility SET {set_clause} WHERE facility_id = %s"
        return DatabaseConnection.execute_update(query, (*updates.values(), facility_id))
    
    @staticmethod
    def delete_facility(facility_id: int) -> int:
        query = "DELETE FROM facility WHERE facility_id = %s"
        return DatabaseConnection.execute_update(query, (facility_id,))


class RoomDB:
    @staticmethod
    def create_room(facility_id: int, room_name: str, room_type: str,
                   floor_number: Optional[int] = None, capacity: int = 1) -> Dict:
        query = """
            INSERT INTO room (facility_id, room_name, room_type, floor_number, capacity)
            VALUES (%s, %s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (facility_id, room_name, room_type, floor_number, capacity))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_room(room_id: int) -> Optional[Dict]:
        query = "SELECT * FROM room WHERE room_id = %s"
        return DatabaseConnection.execute_query(query, (room_id,), fetch_one=True)
    
    @staticmethod
    def get_rooms_by_facility(facility_id: int) -> List[Dict]:
        query = "SELECT * FROM room WHERE facility_id = %s ORDER BY room_name"
        return DatabaseConnection.execute_query(query, (facility_id,))
    
    @staticmethod
    def get_active_rooms(facility_id: int) -> List[Dict]:
        query = "SELECT * FROM room WHERE facility_id = %s AND status = 'active' ORDER BY room_name"
        return DatabaseConnection.execute_query(query, (facility_id,))
    
    @staticmethod
    def update_room(room_id: int, **kwargs) -> int:
        allowed_fields = {'room_name', 'room_type', 'status', 'floor_number', 'capacity'}
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        if not updates:
            return 0
        
        set_clause = ", ".join([f"{k} = %s" for k in updates.keys()])
        query = f"UPDATE room SET {set_clause} WHERE room_id = %s"
        return DatabaseConnection.execute_update(query, (*updates.values(), room_id))
    
    @staticmethod
    def delete_room(room_id: int) -> int:
        query = "DELETE FROM room WHERE room_id = %s"
        return DatabaseConnection.execute_update(query, (room_id,))


class QueueDB:
    @staticmethod
    def create_queue_entry(session_id: int, patient_id: int, facility_id: int,
                          queue_name: str = 'general', department: Optional[str] = None,
                          location_hint: Optional[str] = None,
                          required_exams: Optional[List[str]] = None) -> Dict:
        # Ensure facility exists to satisfy FK constraints.
        resolved_facility_id = FacilityDB.resolve_facility_id(facility_id)

        # Get next queue number for this facility and destination queue.
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                # Backward-compatible schema updates for existing deployments.
                cur.execute("ALTER TABLE examination_queue ADD COLUMN IF NOT EXISTS queue_name VARCHAR(100)")
                cur.execute("ALTER TABLE examination_queue ADD COLUMN IF NOT EXISTS department VARCHAR(100)")
                cur.execute("ALTER TABLE examination_queue ADD COLUMN IF NOT EXISTS location_hint VARCHAR(255)")

                cur.execute("""
                    SELECT COALESCE(MAX(queue_number), 0) + 1 AS queue_number
                    FROM examination_queue 
                    WHERE facility_id = %s
                      AND COALESCE(queue_name, 'general') = %s
                      AND DATE(created_at) = CURRENT_DATE
                """, (resolved_facility_id, queue_name))
                row = cur.fetchone()
                queue_number = row['queue_number']
                
                query = """
                    INSERT INTO examination_queue (
                        session_id, patient_id, facility_id, queue_name, department,
                        location_hint, queue_number, required_exams
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING *
                """
                cur.execute(
                    query,
                    (
                        session_id,
                        patient_id,
                        resolved_facility_id,
                        queue_name,
                        department,
                        location_hint,
                        queue_number,
                        required_exams,
                    ),
                )
                return dict(cur.fetchone())
    
    @staticmethod
    def get_queue_entry(queue_id: int) -> Optional[Dict]:
        query = "SELECT * FROM v_queue_overview WHERE queue_id = %s"
        return DatabaseConnection.execute_query(query, (queue_id,), fetch_one=True)
    
    @staticmethod
    def get_queue_by_session(session_id: int) -> Optional[Dict]:
        query = "SELECT * FROM examination_queue WHERE session_id = %s"
        return DatabaseConnection.execute_query(query, (session_id,), fetch_one=True)

    @staticmethod
    def get_queue_entry_by_session(session_id: int) -> Optional[Dict]:
        query = """
            SELECT * FROM v_queue_overview
            WHERE queue_id = (SELECT queue_id FROM examination_queue WHERE session_id = %s LIMIT 1)
        """
        return DatabaseConnection.execute_query(query, (session_id,), fetch_one=True)
    
    @staticmethod
    def get_facility_queue(facility_id: int, status: Optional[str] = None) -> List[Dict]:
        if status:
            query = "SELECT * FROM v_queue_overview WHERE facility_name = (SELECT name FROM facility WHERE facility_id = %s) AND queue_status = %s"
            return DatabaseConnection.execute_query(query, (facility_id, status))
        else:
            query = "SELECT * FROM v_queue_overview WHERE facility_name = (SELECT name FROM facility WHERE facility_id = %s)"
            return DatabaseConnection.execute_query(query, (facility_id,))
    
    @staticmethod
    def assign_to_doctor(queue_id: int, doctor_id: int, room_id: Optional[int] = None,
                        exams: Optional[List[str]] = None, notes: Optional[str] = None) -> int:
        updates = {'assigned_doctor_id': doctor_id}
        if room_id:
            updates['assigned_room_id'] = room_id
        if exams:
            updates['required_exams'] = exams
        if notes:
            updates['notes'] = notes
        
        set_clause = ", ".join([f"{k} = %s" for k in updates.keys()])
        query = f"UPDATE examination_queue SET {set_clause}, queue_status = 'in_progress', started_at = CURRENT_TIMESTAMP WHERE queue_id = %s"
        return DatabaseConnection.execute_update(query, (*updates.values(), queue_id))
    
    @staticmethod
    def update_queue_status(queue_id: int, status: str) -> int:
        extra = ", completed_at = CURRENT_TIMESTAMP" if status == 'completed' else ""
        query = f"UPDATE examination_queue SET queue_status = %s{extra} WHERE queue_id = %s"
        return DatabaseConnection.execute_update(query, (status, queue_id))
    
    @staticmethod
    def get_doctor_queue(doctor_id: int) -> List[Dict]:
        query = """
            SELECT * FROM v_queue_overview
            WHERE assigned_doctor_id = (SELECT worker_id FROM healthcare_worker WHERE worker_id = %s)
            ORDER BY queue_number
        """
        return DatabaseConnection.execute_query(query, (doctor_id,))

    @staticmethod
    def get_room_queue(room_id: int) -> List[Dict]:
        query = """
            SELECT
                q.queue_id, q.queue_number, q.queue_status,
                q.queue_name, q.department, q.location_hint,
                q.required_exams, q.assigned_room_id, q.assigned_doctor_id,
                p.full_name AS patient_name, p.phone_number,
                pred.risk_level, pred.predicted_condition,
                hw.full_name AS doctor_name,
                r.room_name,
                f.name AS facility_name,
                q.created_at, q.started_at, q.completed_at,
                ROW_NUMBER() OVER (ORDER BY q.queue_number) AS position
            FROM examination_queue q
            JOIN patient p ON q.patient_id = p.patient_id
            JOIN facility f ON q.facility_id = f.facility_id
            LEFT JOIN session s ON q.session_id = s.session_id
            LEFT JOIN prediction pred ON s.session_id = pred.session_id
            LEFT JOIN healthcare_worker hw ON q.assigned_doctor_id = hw.worker_id
            LEFT JOIN room r ON q.assigned_room_id = r.room_id
            WHERE q.assigned_room_id = %s
              AND q.queue_status NOT IN ('completed', 'cancelled')
            ORDER BY q.queue_number
        """
        return DatabaseConnection.execute_query(query, (room_id,))


class AudioDB:
    @staticmethod
    def save_audio_reference(session_id: int, sequence_number: int, speaker_type: str,
                            file_path: str, file_size_bytes: Optional[int] = None,
                            duration_seconds: Optional[float] = None) -> Dict:
        query = """
            INSERT INTO audio_recording (session_id, sequence_number, speaker_type, file_path, file_size_bytes, duration_seconds)
            VALUES (%s, %s, %s, %s, %s, %s) RETURNING *
        """
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (session_id, sequence_number, speaker_type, file_path, file_size_bytes, duration_seconds))
                return dict(cur.fetchone())
    
    @staticmethod
    def get_session_audio(session_id: int) -> List[Dict]:
        query = "SELECT * FROM audio_recording WHERE session_id = %s ORDER BY sequence_number"
        return DatabaseConnection.execute_query(query, (session_id,))


class ExtendedSessionDB:
    """Extended session operations with new JSONB fields"""
    
    @staticmethod
    def save_complete_session(session_id: int, extraction_data: Dict, score_data: Dict,
                             patient_message: str, doctor_brief: Dict, full_transcript: str,
                             transcript_confidence: float, detected_language: str,
                             patient_age: Optional[int] = None,
                             patient_gender: Optional[str] = None,
                             red_flags_detected: Optional[bool] = None,
                             chief_complaint: Optional[str] = None,
                             severity_estimate: Optional[int] = None) -> int:
        query = """
            UPDATE session SET
                extraction_data = %s,
                score_data = %s,
                patient_message = %s,
                doctor_brief = %s,
                full_transcript = %s,
                transcript_confidence = %s,
                detected_language = %s,
                patient_age = %s,
                patient_gender = %s,
                red_flags_detected = %s,
                chief_complaint = %s,
                severity_estimate = %s,
                status = 'completed',
                end_time = CURRENT_TIMESTAMP
            WHERE session_id = %s
        """
        return DatabaseConnection.execute_update(query, (
            json.dumps(extraction_data),
            json.dumps(score_data),
            patient_message,
            json.dumps(doctor_brief),
            full_transcript,
            transcript_confidence,
            detected_language,
            patient_age,
            patient_gender,
            red_flags_detected,
            chief_complaint,
            severity_estimate,
            session_id
        ))
    
    @staticmethod
    def get_patient_sessions(patient_id: int) -> List[Dict]:
        query = "SELECT * FROM v_patient_list WHERE patient_id = %s ORDER BY start_time DESC"
        return DatabaseConnection.execute_query(query, (patient_id,))
    
    @staticmethod
    def get_all_patients() -> List[Dict]:
        query = "SELECT DISTINCT ON (patient_id) * FROM v_patient_list ORDER BY patient_id, start_time DESC"
        return DatabaseConnection.execute_query(query)
