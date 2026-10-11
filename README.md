---
title: Eleza Pre-Consultation Backend
emoji: 🏥
colorFrom: green
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
---

# Pre-Consultation Agent

For component specific details, see:

- [Backend README](backend/README.md)
- [Frontend README](frontend/README.md)

## Overview

Eleza is a faster way to talk to our doctors. This project is a pre-consultation agent — a hospital-owned, voice-based system that helps collect patient information before a doctor consultation.

It supports Kinyarwanda and English, asks follow-up questions to clarify symptoms, and provides structured outputs for clinical review.

This is a supervised support tool, not a diagnosis system.

## Project Description

The project combines:

- A **FastAPI backend** for voice processing, session flow, triage logic, and clinician-facing endpoints.
- A **Flutter frontend** for kiosk/patient interaction and doctor review workflows.
- Testing scripts and notebooks to validate model behavior and system integration.

Expected value:

- Reduce time spent in first-level intake.
- Improve symptom capture quality before consultation.
- Help doctors quickly review patient summaries and suggested next actions.

## System Architecture

### How It Works (End-to-End Flow)

```
Patient speaks into kiosk
        │
        ▼
┌──────────────────┐
│  Model A: STT    │  Whisper (Kinyarwanda or English)
│  Speech-to-Text  │  Transcribes audio to text
└────────┬─────────┘
         ▼
┌──────────────────┐
│  Model B: NLU    │  Gemini — extracts chief complaint,
│  Understanding   │  symptoms, severity, red flags
└────────┬─────────┘
         ▼
┌──────────────────┐
│  Model C: Policy │  Gemini + rule-based trees — picks next
│  Next Question   │  clinical question, ensures coverage
└────────┬─────────┘
         │  (loop until enough info or max turns)
         ▼
┌──────────────────┐
│  Model D: Triage │  Gemini — risk scoring, priority level,
│  Risk Scoring    │  department routing
└────────┬─────────┘
         ▼
┌──────────────────┐
│  Model E: Patient│  Gemini — generates patient-facing
│  Guidance        │  guidance in their language
└────────┬─────────┘
         ▼
┌──────────────────┐
│  Model F: Doctor │  Gemini — structured summary for
│  Summary         │  the reviewing clinician
└────────┬─────────┘
         ▼
  Doctor reviews brief
  in the dashboard
```

### ML Models & APIs

| Model   | Technology                                                                                                                                                                                          | Purpose                               |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| Model A | [akera/whisper-large-v3-kin-200h-v2](https://huggingface.co/akera/whisper-large-v3-kin-200h-v2) (Kinyarwanda) + [openai/whisper-large-v3](https://huggingface.co/openai/whisper-large-v3) (English) | Speech-to-text transcription          |
| Model B | Google Gemini                                                                                                                                                                                       | Extract clinical info from transcript |
| Model C | Google Gemini + rule-based question trees (`model_c_rules.py`)                                                                                                                                      | Choose next follow-up question        |
| Model D | Google Gemini                                                                                                                                                                                       | Risk scoring and triage               |
| Model E | Google Gemini                                                                                                                                                                                       | Patient guidance message generation   |
| Model F | Google Gemini                                                                                                                                                                                       | Doctor summary generation             |
| TTS     | ElevenLabs API (frontend)                                                                                                                                                                           | Text-to-speech for patient responses  |

### Core User Flows

**Kiosk (Patient) Flow:**

1. `POST /kiosk/start` — start session, get greeting
2. `POST /kiosk/{id}/audio` — submit initial voice complaint, get first question
3. `POST /kiosk/{id}/answer` — submit audio answer, get next question (repeats until enough info or max turns)
4. `POST /kiosk/{id}/finish` — trigger scoring, get patient guidance message and routing

**Doctor Flow:**

1. Login via `POST /auth/login`
2. View queue via `GET /doctor/queue`
3. Review patient briefs via `GET /doctor/briefs/{session_id}`

### Tech Stack

| Layer       | Technology                                                  |
| ----------- | ----------------------------------------------------------- |
| Backend API | Python 3.10+, FastAPI, Gunicorn + Uvicorn                   |
| Database    | PostgreSQL (psycopg2 connection pool)                       |
| ML Models   | HuggingFace Transformers (Whisper), Google Gemini API       |
| Frontend    | Flutter (Dart), cross-platform (Web, Android, iOS, Windows) |
| TTS         | ElevenLabs API                                              |
| Auth        | JWT tokens (bcrypt password hashing)                        |

## Demo And Deployment Links

- Demo video: [Link to demo video](https://drive.google.com/drive/folders/1eRBl3uKAhTo8PucomjlGDkXwoBHeUNrZ?usp=sharing)
- Deployed frontend: [Link to flutter APK file](https://drive.google.com/drive/folders/1_HDb-CJvF1riBDUhP5I5dgTGcu4zviLh?usp=sharing)
- Deployed backend/API: [Link to backend ](https://boisterously-implicatory-anderson.ngrok-free.dev/docs)
- Deployed database: [Link to Render database](https://dashboard.render.com/d/dpg-d6ol7qkr85hc739hdvog-a)

### Deployment Overview

| Component       | Platform                        | Notes                                                                                                                                                     |
| --------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backend API     | **HuggingFace Spaces** (Docker) | Port 7860. Config in root `Dockerfile`. First boot downloads ~6 GB of Whisper models.                                                                     |
| Backend tunnel  | **ngrok**                       | The current deployed URL is an ngrok tunnel. This URL can change — if it does, update it in `frontend/lib/services/api_service.dart` (hardcoded for web). |
| Database        | **Render PostgreSQL**           | Managed database. Connection details set via environment variables on HuggingFace Spaces.                                                                 |
| Frontend builds | **Codemagic CI/CD**             | Builds APK, web, and iOS artifacts. Config in `codemagic.yaml`.                                                                                           |
| Frontend APK    | **Google Drive**                | Downloadable APK for Android testing.                                                                                                                     |

## Quick Setup (Backend + Frontend)

### Prerequisites

- Python 3.10+
- Flutter SDK (stable, Dart 3.7.2+)
- PostgreSQL (for full backend database features)
- ~6 GB disk space for Whisper model downloads
- ~6 GB RAM to run both Whisper models simultaneously

> **First-run warning:** On first startup, the backend downloads two Whisper models (~3 GB each). This can take 5–15 minutes depending on your connection. Subsequent starts use the cached models.

### 1) Create And Activate Virtual Environment (Backend)

From the project root:

Windows PowerShell:

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

macOS/Linux:

```bash
python3 -m venv venv
source venv/bin/activate
```

Deactivate when done:

```bash
deactivate
```

### 2) Backend Setup

```bash
cd backend
pip install -r requirements.txt
```

Create a `.env` in `backend/` (copy from `backend/.env.example`):

```bash
cp .env.example .env
```

Then fill in the **required** values (see [Environment Variables](#environment-variables) below).

Database setup (if using PostgreSQL locally):

```bash
createdb pre_consultation_db
psql -U postgres -d pre_consultation_db -f database/schema.sql
```

Apply all migrations (run in order):

```bash
psql -U postgres -d pre_consultation_db -f database/migrations/add_new_system_fields.sql
psql -U postgres -d pre_consultation_db -f database/migrations/add_doctor_specialty.sql
psql -U postgres -d pre_consultation_db -f database/migrations/fix_v_facility_stats_missing_columns.sql
psql -U postgres -d pre_consultation_db -f database/migrations/add_age_to_patient_list_view.sql
psql -U postgres -d pre_consultation_db -f database/migrations/fix_v_queue_overview_missing_exams.sql
```

Create the first platform admin user:

```bash
python init_db.py
```

This is an interactive script that prompts for email, name, and password. You need this account to log in and create other users.

Run API:

```bash
uvicorn main:app --reload --port 8000
```

Useful endpoints after start:

- API docs (Swagger UI): `http://localhost:8000/docs`
- Startup status: `http://localhost:8000/startup/status`
- Health check: `http://localhost:8000/health`

### 3) Frontend Setup

In a separate terminal:

```bash
cd frontend
flutter pub get
```

Create a `.env` file in `frontend/`:

```env
API_BASE_URL=http://localhost:8000
ELEVENLABS_API_KEY=your_elevenlabs_api_key_here
```

- `API_BASE_URL` — the backend URL. Use `http://localhost:8000` for local dev, or the deployed ngrok/Render URL.
- `ELEVENLABS_API_KEY` — required for text-to-speech. Get one at [elevenlabs.io](https://elevenlabs.io). If omitted, TTS won't work but the rest of the app will.

> **Note:** When running on **web** (`flutter run -d chrome`), the base URL is hardcoded in `lib/services/api_service.dart`. Update it there if needed. The `.env` file is used for mobile/desktop builds.

Run frontend (choose one):

```bash
flutter run -d chrome
flutter run -d windows
flutter run -d android
```

You can also run on:

- iOS simulator/device (macOS only)
- Android emulator
- Physical Android/iOS device

## Testing Guide

Use any of the following depending on what you want to validate.

### Backend Testing Alternatives

1. Swagger UI (manual endpoint testing)

- Start backend and open `http://localhost:8000/docs`.
- Test endpoints interactively with request/response visibility.

2. Integration script

```bash
python backend/test_new_system_integration.py
```

3. Database verification script

```bash
python testing/test_database.py
```

4. Whisper/model loading and transcription check

```bash
python backend/test_whisper.py <path_to_audio.wav>
```

5. Audio format compatibility test

```bash
python testing/test_audio_formats.py <path_to_audio_file>
```

6. Conversation CLI script (legacy/manual flow simulation)

```bash
python testing/testconversation.py
```

Note: this script targets conversation endpoints that may differ from the current router contract. Use Swagger UI first if you want the most reliable manual API validation path.

7. Notebook-based testing

- `backend/kaggle-test.ipynb`
- `backend/colab-test.ipynb`
- Model notebooks in `notebooks/` for focused experimentation per model.

### Frontend Testing Alternatives

1. Run on web:

```bash
cd frontend
flutter run -d chrome
```

2. Run on Windows desktop:

```bash
cd frontend
flutter run -d windows
```

3. Run on emulator/device:

```bash
cd frontend
flutter run -d android
```

## Environment Variables

All backend env vars go in `backend/.env`. Copy `backend/.env.example` as a starting point.

### Required Variables

| Variable         | Description                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GOOGLE_API_KEY` | Google Gemini API key. Powers Models B–F (NLU, dialogue, triage, guidance, summaries). Get one at [aistudio.google.com](https://aistudio.google.com/apikey). |
| `HF_TOKEN`       | HuggingFace access token. Required to download Whisper models. Get one at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).          |
| `JWT_SECRET_KEY` | Secret key for signing JWT auth tokens. Use a long random string in production.                                                                              |
| `DB_HOST`        | PostgreSQL host (default: `localhost`).                                                                                                                      |
| `DB_PORT`        | PostgreSQL port (default: `5432`).                                                                                                                           |
| `DB_NAME`        | Database name (default: `pre_consultation_db`).                                                                                                              |
| `DB_USER`        | Database user (default: `postgres`).                                                                                                                         |
| `DB_PASSWORD`    | Database password.                                                                                                                                           |

### Optional Variables

| Variable                          | Default                       | Description                                                                                  |
| --------------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------- |
| `USE_DB`                          | `true`                        | Set to `false` to run without a database (limited functionality).                            |
| `DEVICE`                          | `cpu`                         | PyTorch device for Whisper (`cpu` or `cuda`).                                                |
| `MAX_TURNS`                       | `6`                           | Maximum follow-up questions per session.                                                     |
| `AUDIO_STORAGE_DIR`               | `data/audio`                  | Directory for saved audio recordings.                                                        |
| `LOG_LEVEL`                       | `INFO`                        | Python logging level.                                                                        |
| `SKIP_LANG_DETECTION_WHEN_HINTED` | `false`                       | Skip Whisper language detection when language is already known.                              |
| `EMAIL_PROVIDER`                  | `emailjs`                     | Email backend: `smtp` or `emailjs`. See [Email Variables](#email-variables-smtp-or-emailjs). |
| `PUBLIC_API_BASE_URL`             | `http://localhost:8000`       | Base URL included in emails.                                                                 |
| `APP_LOGIN_URL`                   | `http://localhost:3000/login` | Login URL included in credential emails.                                                     |

### SMS Variables (Twilio)

SMS notifications are used to send patients their queue assignment and exam instructions after triage.

| Variable             | Description                                                                          |
| -------------------- | ------------------------------------------------------------------------------------ |
| `TWILIO_ACCOUNT_SID` | Twilio account SID. Get one at [twilio.com/console](https://www.twilio.com/console). |
| `TWILIO_AUTH_TOKEN`  | Twilio auth token.                                                                   |
| `TWILIO_FROM_NUMBER` | Twilio-provisioned sender phone number (e.g., `+1234567890`).                        |

SMS messages are sent in English or Kinyarwanda depending on the patient's language. Phone numbers are auto-normalized to E.164 format (Rwanda `+250` prefix).

### Email Variables (SMTP or EmailJS)

Email is used to send login credentials to new users/doctors and confirmation requests for doctor assignments.

Set the provider with `EMAIL_PROVIDER` (`smtp` or `emailjs`).

**SMTP config:**

| Variable          | Default                          | Description             |
| ----------------- | -------------------------------- | ----------------------- |
| `SMTP_HOST`       | _(required)_                     | SMTP server hostname    |
| `SMTP_PORT`       | `587`                            | SMTP port               |
| `SMTP_USERNAME`   | _(optional)_                     | SMTP login username     |
| `SMTP_PASSWORD`   | _(optional)_                     | SMTP login password     |
| `SMTP_USE_TLS`    | `true`                           | Use STARTTLS            |
| `SMTP_USE_SSL`    | `false`                          | Use SMTP_SSL (port 465) |
| `SMTP_FROM_EMAIL` | _(required)_                     | Sender email address    |
| `SMTP_FROM_NAME`  | `Eleza: Pre-Consultation System` | Sender display name     |

**EmailJS config:**

| Variable              | Description                                 |
| --------------------- | ------------------------------------------- |
| `EMAILJS_API_URL`     | API endpoint (defaults to EmailJS v1.0 URL) |
| `EMAILJS_SERVICE_ID`  | EmailJS service ID                          |
| `EMAILJS_TEMPLATE_ID` | EmailJS template ID                         |
| `EMAILJS_PUBLIC_KEY`  | EmailJS public key                          |
| `EMAILJS_PRIVATE_KEY` | EmailJS private/access key                  |

### Frontend Variables

Frontend env vars go in `frontend/.env`:

| Variable             | Description                                                          |
| -------------------- | -------------------------------------------------------------------- |
| `API_BASE_URL`       | Backend API URL (e.g., `http://localhost:8000` or the deployed URL). |
| `ELEVENLABS_API_KEY` | ElevenLabs API key for text-to-speech functionality.                 |

## Database

### Schema

The database is PostgreSQL with the following core tables:

| Table                  | Purpose                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| `users`                | Auth users (roles: `platform_admin`, `hospital_admin`, `doctor`)         |
| `facility`             | Hospital/clinic records                                                  |
| `patient`              | Patient demographics (name, phone, language)                             |
| `session`              | Pre-consultation sessions with status, extracted data, and doctor briefs |
| `conversation_message` | Full message history per session                                         |
| `symptom`              | Extracted symptoms per session                                           |
| `prediction`           | Risk assessments and triage results                                      |
| `prescription`         | Treatment recommendations                                                |
| `healthcare_worker`    | Doctors/nurses linked to users and facilities                            |
| `room`                 | Rooms per facility                                                       |
| `examination_queue`    | Queue entries linking sessions to facilities, doctors, and rooms         |
| `audio_recording`      | References to saved audio files                                          |

### Migrations

Migrations are in `backend/database/migrations/` and must be applied in order after the base schema. See the [Backend Setup](#2-backend-setup) section for commands.

### Backup & Restore

```bash
pg_dump -U postgres pre_consultation_db > backup.sql
psql -U postgres pre_consultation_db < backup.sql
```

## Project Structure

```
pre-consultation-agent/
├── README.md                  # This file
├── Dockerfile                 # HuggingFace Spaces deployment
├── codemagic.yaml             # CI/CD for Flutter builds
│
├── backend/
│   ├── main.py                # FastAPI app entry point
│   ├── init_db.py             # Create first admin user (interactive)
│   ├── requirements.txt       # Python dependencies
│   ├── start.sh               # Container startup (model download + gunicorn)
│   ├── .env.example           # Environment variable template
│   ├── database/
│   │   ├── database.py        # PostgreSQL connection pool & DB classes
│   │   ├── schema.sql         # Full database schema
│   │   └── migrations/        # SQL migration files (apply in order)
│   ├── models/
│   │   ├── model_a.py         # Whisper speech-to-text
│   │   ├── model_b.py         # Gemini clinical extraction
│   │   ├── model_c.py         # Gemini next-question selection
│   │   ├── model_c_rules.py   # Rule-based question trees
│   │   ├── model_d.py         # Gemini risk scoring
│   │   ├── model_e.py         # Gemini patient guidance
│   │   ├── model_f.py         # Gemini doctor summary
│   │   └── gemini_utils.py    # Shared Gemini API utilities
│   ├── routers/               # FastAPI route handlers
│   │   ├── kiosk.py           # Patient kiosk endpoints
│   │   ├── dialogue.py        # Conversation endpoints
│   │   ├── doctor.py          # Doctor dashboard endpoints
│   │   ├── auth.py            # Authentication (login, register)
│   │   ├── patients.py        # Patient record endpoints
│   │   ├── facilities.py      # Facility management
│   │   ├── rooms.py           # Room management
│   │   ├── queue.py           # Queue management
│   │   └── ...                # Other routers
│   ├── routing/               # Session routing logic
│   └── utils/                 # Email (SMTP/EmailJS), SMS (Twilio), session logger
│
├── frontend/
│   ├── lib/
│   │   ├── main.dart          # App entry point
│   │   ├── screens/           # UI screens (kiosk/, doctor/, admin/)
│   │   ├── services/          # API, audio, TTS services
│   │   ├── models/            # Dart data models
│   │   └── components/        # Reusable UI components
│   ├── assets/translations/   # i18n (en.json, rw.json)
│   └── pubspec.yaml           # Flutter dependencies
│
├── notebooks/                 # Jupyter notebooks per model (experimentation)
├── testing/                   # Standalone test scripts
└── Datasets/                  # Training data
```

4. Run widget tests:

```bash
cd frontend
flutter test
```

5. Static checks:

```bash
cd frontend
flutter analyze
```

## Testing Reference

| File                                     | Type                | What It Tests                                                                                                                    | Key Metrics / Aspects                                                                                                                                                                        | How To Run                                                            |
| ---------------------------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `backend/test_unit_basic.py`             | Unit (pytest)       | Auth helpers: `hash_password`, `verify_password`, `create_access_token`, `decode_token`                                          | bcrypt format, password verify correctness, JWT roundtrip, token expiry handling                                                                                                             | `cd backend && python -m pytest test_unit_basic.py -v`                |
| `backend/test_new_system_integration.py` | Integration         | Two-stage extraction pipeline across 3 routing modes (rule-based, AI-powered, emergency)                                         | Routing mode correctness, API call count, cost estimates, predefined question retrieval                                                                                                      | `python backend/test_new_system_integration.py`                       |
| `testing/test_database.py`               | Integration         | DB connectivity, schema verification, full CRUD lifecycle (patient → session → message → symptom → prediction), stored functions | Connection success, 7 required tables present, CRUD ops, `get_patient_history()`, `close_session()`                                                                                          | `python testing/test_database.py`                                     |
| `backend/test_whisper.py`                | Smoke test          | Whisper model loading and transcription against a real audio file, system resource monitoring                                    | Model load time, transcription output, detected language, confidence, RAM/CPU usage                                                                                                          | `python backend/test_whisper.py <audio.wav> [--language kinyarwanda]` |
| `testing/test_audio_formats.py`          | Smoke test          | Audio transcription for arbitrary formats (MP4, WAV, MP3) via Model A                                                            | File size, model readiness, transcription text, detected language, confidence                                                                                                                | `python testing/test_audio_formats.py <audio_file>`                   |
| `backend/test_pipeline_input.py`         | Validation          | Numpy array format expected by HuggingFace ASR pipeline                                                                          | `dtype==float32`, C-contiguity, writability, dict key structure                                                                                                                              | `python backend/test_pipeline_input.py`                               |
| `backend/evaluate_system.py`             | Evaluation          | End-to-end system accuracy using Gemini-as-judge on completed DB sessions                                                        | Question relevance (1-5), information gain per turn, coverage rate (9 clinical fields), turn efficiency, routing accuracy. Composite = relevance×35% + gain×25% + coverage×25% + routing×15% | `cd backend && python evaluate_system.py [--limit N] [--json]`        |
| `testing/testconversation.py`            | End-to-end (manual) | Interactive CLI client testing the full conversation API loop                                                                    | API connectivity, session creation, question→answer flow, diagnosis output (prediction, confidence, severity)                                                                                | Start server, then `python testing/testconversation.py`               |

> **Note:** `testconversation.py` targets legacy endpoints (`/conversation/start`, `/conversation/message`) that may differ from the current kiosk contract. Use Swagger UI for the most reliable manual API validation.

## Results Summary

Current achieved results:

- A patient can speak to the system and receive tailored follow-up questions for clarification.
- The system provides next-step guidance without issuing a medical diagnosis.
- The system forwards structured patient information and symptoms for doctor review.
- Doctors can review patient cases and assign examinations or next actions.

Current gap against intended objective:

- A planned breathing-pattern emergency escalation feature (detect respiratory distress from speech/audio and escalate immediately) is not yet implemented.

## Analysis

Detailed analysis of the results and how they achieved or missed the objectives in the project proposal with the supervisor.

The project achieved key functional objectives for supervised pre-consultation intake: multilingual patient interaction (Kinyarwanda and English), iterative clarification, safe non-diagnostic guidance, and doctor-facing case summaries. These outcomes align with the objective of reducing intake friction while preserving clinician decision authority.

Afterdiscussin, the system direct the patient to a particular area as necessary or escalates to emergency if necessary. Finally, The doctor can also view each patient's case and assign them necessary examinations or other next steps.

However, one high-impact objective remains incomplete: automatic breathing/emergency detection directly from patient speech. Because this feature was not completed, emergency detection is currently dependent on existing symptom and red-flag logic rather than dedicated respiratory signal analysis. This leaves an important safety enhancement for future implementation.

## Discussion

A detailed discussion on the importance of the milestones and the impact of the results with the supervisor.

Key milestone impact:

- Voice capture and transcription enabled practical patient interaction in supported languages.
- Clarification question flow improved symptom detail quality before clinician review.
- Structured handoff to doctors reduced information loss between intake and consultation.
- Doctor-side review and action assignment supports real clinical workflow continuity.

Together, these milestones show that the system can function as a meaningful pre-consultation layer in hospital settings, especially where intake bottlenecks are common.

## Recommendations

Next steps:

- Implement respiratory distress detection from speech/audio to support immediate emergency escalation.
- Add stronger validation in real hospital pilot environments with clinician feedback loops.
- Expand multilingual robustness and accents handling.
- Add more preset symptoms so the system has a fallback and doesn't always call the models.
- Strengthen deployment hardening (security, privacy controls, auditability, and observability).

Community application guidance:

- Use the tool as supervised pre-consultation support, never as standalone diagnosis.
- Keep clinicians in the decision loop for all medical decisions.
- Pair technical rollout with user training for hospital staff and patient facilitators.

## Testing Images

Frontend (Flutter Web):

![alt text](<Screenshot 2026-03-13 222814.png>)

Backend:

Kaggle:

![alt text](<Screenshot 2026-03-13 235241.png>)

Swagger UI:

![alt text](image.png)
