# Backend - Pre-Consultation Agent

Voice-based pre-consultation and triage system backend with PostgreSQL database. This system acts as a data collection point for hospital-owned equipment, supporting Kinyarwanda and English voice interactions.

## Purpose

This backend powers a supervised consultation support tool that:

- Collects structured patient data through voice interaction
- Manages consultation sessions and patient queues
- Generates summaries for healthcare workers
- Routes patients to appropriate departments
- Stores conversation history and extracted symptoms

## Quick Setup

### 1. Database

```bash
createdb pre_consultation_db
psql -U postgres -d pre_consultation_db -f schema.sql
```

### 2. Configuration

Create `.env`:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=pre_consultation_db
DB_USER=postgres
DB_PASSWORD=your_password

SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your_smtp_username
SMTP_PASSWORD=your_smtp_password
SMTP_USE_TLS=true
SMTP_USE_SSL=false
SMTP_FROM_EMAIL=operations@example.com
SMTP_FROM_NAME=Hospital Operations
PUBLIC_API_BASE_URL=http://localhost:8000
DOCTOR_ASSIGN_CONFIRMATION_TTL_HOURS=24
```

Email behavior:

- After `/auth/register`, the newly created user receives an email with username and temporary password.
- After hospital admins add a doctor via `/doctors`, the doctor receives the same credentials email.
- When platform admins add a doctor via `/doctors`, the doctor is not created immediately. A confirmation email is sent to the facility primary email and hospital admin email(s); creation only happens after confirmation.

### 3. Dependencies

```bash
pip install -r requirements.txt
```

### 4. Test Database

```bash
cd ../testing
python test_database.py
```

### 5. Run API

```bash
python main.py
```

## Python Usage

```python
from database import DatabaseConnection, PatientDB, SessionDB

DatabaseConnection.initialize_pool()

# Create a new patient record
patient = PatientDB.create_patient("Marie Uwimana", "+250788123456", "kinyarwanda")

# Start a consultation session
session = SessionDB.create_session(patient['patient_id'])

# Update with risk assessment and suggestions
SessionDB.update_prediction_info(session['session_id'], "Urgent - Chest Pain", 0.85)

# Close the session when consultation is complete
SessionDB.close_session(session['session_id'])
```

## Database Tables

- `patient` - Patient records and contact information
- `healthcare_worker` - Medical staff credentials
- `session` - Consultation sessions with status and outcomes
- `conversation_message` - Complete message history for each session
- `symptom` - Extracted symptoms and medical observations
- `prediction` - Risk assessments and triage recommendations
- `prescription` - Treatment recommendations and prescriptions

## Views

- `v_session_overview` - Complete session details
- `v_sessions_awaiting_review` - Sessions needing review
- `v_worker_activity` - Worker statistics

## Functions

- `close_session(session_id)` - Close session
- `get_patient_history(patient_id)` - Get patient history

## Backup

```bash
pg_dump -U postgres pre_consultation_db > backup.sql
psql -U postgres pre_consultation_db < backup.sql
```

## System Description

### Models Used

- **Whisper Models (Speech-to-Text):**
  - **Kinyarwanda Whisper (akera/whisper-large-v3-kin-200h-v2):** Fine-tuned for Kinyarwanda, used for highly accurate transcription of patient audio in Kinyarwanda.
  - **English Whisper (openai/whisper-large-v3):** Used for English speech-to-text and for language detection. Also acts as a fallback for other languages and supports transcription in English.
  - Both models are loaded at API startup and selected automatically based on detected or hinted language.

- **Gemini (Google GenAI):**
  - **Model B:** Extracts clinical information (chief complaint, severity, red flags, clarity, and full patient details) from transcribed text.
  - **Model C:** Selects the next clinical question to ask, ensuring coverage and adapting to the conversation.
  - **Model D:** Assigns risk and priority scores for triage, based on extracted symptoms and rules.
  - **Model E:** Generates patient-facing guidance messages in the appropriate language and urgency.
  - **Model F:** Produces structured doctor summaries from session data.

- **Custom Rule-Based Models:**
  - **model_c_rules.py:** Contains symptom-specific question trees to reduce API costs and improve consistency, especially for common complaints (e.g., mouth problems, headache).

### Key Endpoints

- **/auth/**
  - `POST /auth/login`: Authenticate user, return JWT token.
  - `POST /auth/register`: Register new user (admin only), triggers credentials email.
  - `GET /auth/me`: Get current user info from token.

- **/kiosk/**
  - `POST /kiosk/start`: Start a new session, get session ID and greeting.
  - `POST /kiosk/{id}/audio`: Submit initial audio complaint, get first question.
  - `POST /kiosk/{id}/answer`: Submit audio answer, get next question or finish.
  - `POST /kiosk/{id}/finish`: Trigger scoring, get patient message and routing.
  - `GET /kiosk/{id}/status`: Poll current session stage.

- **/dialogue/**
  - `GET /sessions/{id}/question`: Get the next question for a session.
  - `POST /sessions/{id}/answer`: Submit a text answer.
  - `POST /sessions/{id}/answer-audio`: Submit an audio answer.

- **/doctor/**
  - `GET /doctor/queue`: Get current queue state.
  - `GET /doctor/briefs/{id}`: Fetch doctor brief for a completed session.
  - `GET /doctor/sessions`: List all sessions and their stages.

- **/patients/**
  - `GET /patients/{patient_id}`: Get patient details.
  - `GET /patients/{patient_id}/sessions`: Get patient session history.

### Email Service

- **SMTP and EmailJS Support:** The system can send emails via SMTP or EmailJS, configurable via environment variables.
- **Usage:** Sends credentials to new users and doctors, and handles confirmation flows for doctor registration.
- **Tools:** Uses Python’s `smtplib` for SMTP and HTTP requests for EmailJS.
