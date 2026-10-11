"""
routers/kiosk.py — Patient kiosk interface endpoints.

POST /kiosk/start              → start session, get session_id + greeting
POST /kiosk/{id}/audio         → submit initial audio complaint, get first question
POST /kiosk/{id}/answer        → submit audio answer, get next question or "done"
POST /kiosk/{id}/finish        → trigger scoring, get patient message + routing
GET  /kiosk/{id}/status        → poll current stage

Language handling:
    The frontend sends the patient's selected language (or None if they skipped).
    Model A always detects language from audio regardless — the selected language
    is passed as a hint and only used as a tiebreaker, never as an override.
    This means a patient who selected English but speaks Kinyarwanda will still
    be correctly transcribed in Kinyarwanda.
AUDIO FORMAT REQUIREMENT:
only WAV format is supported. See backend/AUDIO_FORMAT.md for details.
    Frontend apps should record audio in WAV format (16kHz mono recommended).
    
Data persistence:
    Sessions live in memory during conversation for speed.
    Audio files and all data are persisted to database only when session completes.
"""

import os
import re
import asyncio
import uuid
from pathlib import Path
from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Body
from pydantic import BaseModel
from typing import Optional

from session import get_session, create_session, SessionStage, ConversationTurn
from routing import assign_routing, suggest_unclear_issue_routing
from models import model_a, model_b, model_c, model_d, model_e, model_f
from models.model_c_rules import PATIENT_INFO_QUESTIONS
from database.database import (
    PatientDB, SessionDB, ConversationDB, SymptomDB, PredictionDB,
    AudioDB, QueueDB, ExtendedSessionDB, DatabaseConnection, FacilityDB
)

# Initialize database connection pool
try:
    DatabaseConnection.initialize_pool()
except:
    pass  # May already be initialized

# Audio storage directory
AUDIO_DIR = Path(os.getenv("AUDIO_STORAGE_DIR", "data/audio"))
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

MAX_TURNS = int(os.getenv("MAX_TURNS", 8))

router = APIRouter(prefix="/kiosk", tags=["kiosk"])


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------

class StartRequest(BaseModel):
    language:    Optional[str] = None    # Patient's selection, or None if skipped
    patient_age: Optional[int] = None
    patient_location: Optional[str] = None
    facility_id: int = 1                  # Default facility


class StartResponse(BaseModel):
    session_id: str
    greeting:   str


class QuestionResponse(BaseModel):
    session_id:        str
    question:          str
    coverage_complete: bool
    patient_name:      str = ""
    patient_phone:     str = ""


class FinishRequest(BaseModel):
    patient_name:      str = ""
    patient_phone:     str = ""
    patient_location:  str = ""
class FinishResponse(BaseModel):
    session_id:      str
    patient_message: str
    department:      str
    queue:           str
    queue_number:    int
    location_hint:   str
    urgency_label:   str


class StatusResponse(BaseModel):
    session_id: str
    stage:      str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _greeting(language: Optional[str]) -> str:
    if language == "kinyarwanda":
        return (
            "Murakaza neza. Ndi sisitemu ifasha muganga wawe gutegura ikiganiro cyanyu. "
            "Ndabaza ibibazo bike kugirango amakuru yanyu ategurwe mbere yuko muganga abakira. "
            "Twatangira?"
        )
    if language == "english":
        return (
            "Welcome. I am a pre-consultation assistant, not a doctor. "
            "I will ask you a few questions so your doctor can review your case before meeting you. "
            "Ready to begin?"
        )
    # No selection — offer both
    return "Welcome / Murakaza neza. Please speak to begin. / Vuga kugirango utangire."


def _save_audio_file(session_id: str, audio_bytes: bytes, sequence: int, speaker: str) -> str:
    """Save audio file to disk and return file path"""
    session_dir = AUDIO_DIR / session_id
    session_dir.mkdir(exist_ok=True)
    
    filename = f"{sequence:03d}_{speaker}.wav"
    file_path = session_dir / filename
    
    with open(file_path, 'wb') as f:
        f.write(audio_bytes)
    
    return str(file_path)


def _normalize_text(value: str) -> str:
    return " ".join((value or "").split()).strip()


# ---------------------------------------------------------------------------
# Patient info normalization helpers
# ---------------------------------------------------------------------------

_NAME_INTRO_PHRASES = [
    # Kinyarwanda
    "njye nitwa ", "amazina yanjye ni ", "nitwa ", "nzwa ", "ndiho ",
    "nze nitwa ", "twita ",
    # English
    "my name is ", "i'm called ", "i am called ", "they call me ",
    "call me ", "my name's ", "i am ", "i'm ",
    # French (occasionally mixed in)
    "je m'appelle ", "mon nom est ",
]

_ENGLISH_ONES = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
}
_ENGLISH_TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
}
_KINYARWANDA_NUMBERS = {
    "cumi na icyenda": 19, "cumi na umunani": 18, "cumi na karindwi": 17,
    "cumi na gatandatu": 16, "cumi na gatanu": 15, "cumi na kane": 14,
    "cumi na gatatu": 13, "cumi na kabiri": 12, "cumi na rimwe": 11,
    "mirongo icyenda": 90, "mirongo inani": 80, "mirongo irindwi": 70,
    "mirongo itandatu": 60, "mirongo itanu": 50, "mirongo ine": 40,
    "mirongo itatu": 30, "mirongo ibiri": 20, "makumyabiri": 20,
    "icyenda": 9, "umunani": 8, "karindwi": 7, "gatandatu": 6,
    "gatanu": 5, "kane": 4, "gatatu": 3, "kabiri": 2, "rimwe": 1,
    "icumi": 10, "cumi": 10, "ijana": 100,
}


def _clean_name(raw: str) -> str:
    """Strip Kinyarwanda/English intro phrases from name answers."""
    lower = raw.strip().lower()
    # Sort by length descending so longer phrases match before shorter prefixes
    for phrase in sorted(_NAME_INTRO_PHRASES, key=len, reverse=True):
        if lower.startswith(phrase):
            result = raw.strip()[len(phrase):].strip().strip(".,;")
            if result:
                return result
    return raw.strip()


def _words_to_age(text: str) -> Optional[int]:
    """Convert spoken age (words or digits) to an integer."""
    lower = text.strip().lower()

    # 1. Plain integer string
    try:
        val = int(lower)
        if 0 < val < 130:
            return val
    except ValueError:
        pass

    # 2. Digit(s) embedded in text, e.g. "I am 25 years old"
    digits = re.findall(r'\b(\d+)\b', lower)
    if digits:
        val = int(digits[0])
        if 0 < val < 130:
            return val

    # 3. Kinyarwanda: try longest phrase match first, then check "na <ones>"
    for phrase in sorted(_KINYARWANDA_NUMBERS, key=len, reverse=True):
        if phrase in lower:
            base = _KINYARWANDA_NUMBERS[phrase]
            rest_match = re.search(re.escape(phrase) + r'\s+na\s+(\w+)', lower)
            if rest_match:
                addend = _KINYARWANDA_NUMBERS.get(rest_match.group(1), 0)
                val = base + addend
            else:
                val = base
            if 0 < val < 130:
                return val

    # 4. English word numbers: "twenty-five", "thirty two", etc.
    for tens_word, tens_val in _ENGLISH_TENS.items():
        if tens_word in lower:
            rest = lower[lower.index(tens_word) + len(tens_word):].strip().lstrip('-').strip()
            for ones_word, ones_val in _ENGLISH_ONES.items():
                if rest.startswith(ones_word):
                    return tens_val + ones_val
            return tens_val
    for ones_word, ones_val in _ENGLISH_ONES.items():
        if re.search(r'\b' + ones_word + r'\b', lower):
            return ones_val

    return None


def _normalize_extraction_patient_info(extraction: dict) -> dict:
    """
    Post-process model_b extraction to ensure name/age/location are consistently
    formatted regardless of whether the LLM applied normalization or not.
    """
    if extraction.get("patient_name"):
        extraction["patient_name"] = _clean_name(extraction["patient_name"])

    if extraction.get("patient_age"):
        age_int = _words_to_age(str(extraction["patient_age"]))
        if age_int is not None:
            extraction["patient_age"] = str(age_int)

    return extraction


def _resolve_patient_info_target(question: str) -> Optional[str]:
    normalized_question = _normalize_text(question).lower()
    for language_questions in PATIENT_INFO_QUESTIONS.values():
        for q in language_questions:
            if _normalize_text(q.get("question", "")).lower() == normalized_question:
                return q.get("targets")
    return None


def _capture_patient_info_from_answer(session, question: str, answer: str) -> None:
    target = _resolve_patient_info_target(question)
    if not target:
        return

    clean_answer = _normalize_text(answer)
    if not clean_answer:
        return

    if target == "patient_name":
        normalized_name = _clean_name(clean_answer)
        session.patient_name = normalized_name
        session.extraction["patient_name"] = normalized_name
    elif target == "patient_age":
        age_int = _words_to_age(clean_answer)
        if age_int is not None:
            session.patient_age = age_int
            session.extraction["patient_age"] = str(age_int)
        else:
            session.extraction["patient_age"] = clean_answer
    elif target == "patient_gender":
        session.patient_gender = clean_answer
        session.extraction["patient_gender"] = clean_answer
    elif target == "patient_phone":
        session.patient_phone = clean_answer
        session.extraction["patient_phone"] = clean_answer
    elif target == "patient_location":
        session.patient_location = clean_answer
        session.extraction["patient_location"] = clean_answer


def _build_full_transcript(session) -> str:
    lines = []

    initial = _normalize_text(session.transcript)
    if initial:
        lines.append(f"Patient: {initial}")

    for turn in session.turns:
        q = _normalize_text(turn.question)
        a = _normalize_text(turn.answer)
        if q:
            lines.append(f"Assistant: {q}")
        if a:
            lines.append(f"Patient: {a}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/start", response_model=StartResponse)
def kiosk_start(body: StartRequest):
    """
    Start a new patient session.
    language is the patient's screen selection — optional, used as a hint only.
    Creates patient record and session record in database.
    
    Returns:
        StartResponse with session_id and greeting
        
    Raises:
        503 if database is not ready
        500 if database operation fails
    """
    print("\n" + "="*80)
    print("🚀 NEW SESSION STARTED")
    print(f"Language selected: {body.language}")
    print(f"Patient Age: {body.patient_age}")
    resolved_facility_id = body.facility_id
    
    # Normalize language to lowercase for consistency
    normalized_language = body.language.lower() if body.language else "unknown"
    
    try:
        resolved_facility_id = FacilityDB.resolve_facility_id(body.facility_id)
        print(f"Facility ID: {body.facility_id} -> using {resolved_facility_id}")

        # Create or get patient in database
        patient = PatientDB.create_new_patient(
            preferred_language=normalized_language if normalized_language != "unknown" else "kinyarwanda",
            location=body.patient_location
        )
        print(f"Patient DB ID: {patient['patient_id']}")
        
        # Create session in database
        db_session = SessionDB.create_session(patient['patient_id'])
        print(f"Session DB ID: {db_session['session_id']}")
        
    except Exception as e:
        error_msg = f"Database operation failed: {type(e).__name__}: {str(e)}"
        print(f"❌ {error_msg}")
        import traceback
        traceback.print_exc()
        
        # Check if it's a connection error
        if "connection" in str(e).lower() or "pool" in str(e).lower():
            raise HTTPException(
                status_code=503,
                detail="Database not available. Check server startup at /startup/status"
            )
        else:
            raise HTTPException(status_code=500, detail=error_msg)
    
    # Create in-memory session (for fast conversation)
    session = create_session(
        language    = normalized_language,
        patient_age = body.patient_age,
    )
    # Store DB IDs in memory session for later
    session.db_session_id = db_session['session_id']
    session.db_patient_id = patient['patient_id']
    session.facility_id = resolved_facility_id
    session.patient_location = (body.patient_location or "").strip()
    
    greeting = _greeting(normalized_language)
    
    print(f"In-Memory Session ID: {session.id}")
    print(f"💬 Greeting: '{greeting}'")
    print("="*80 + "\n")
    
    return StartResponse(
        session_id = session.id,
        greeting   = greeting,
    )


@router.post("/{session_id}/audio", response_model=QuestionResponse)
async def kiosk_audio(
    session_id: str,
    audio: UploadFile = File(...),
    language: Optional[str] = Form(None),
):
    """
    Receive patient's initial audio complaint, transcribe it, extract clinical
    info, and return the first follow-up question.

    language (form field): the patient's screen selection, passed as a hint to
    Model A. Detection always runs regardless of this value.
    
    Audio is saved to disk but not yet persisted to database (happens on finish).
    """
    print("\n" + "="*80)
    print("🎤 INITIAL AUDIO RECEIVED")
    print(f"Session ID: {session_id}")
    
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.AWAITING_AUDIO:
        raise HTTPException(status_code=409, detail="Audio already submitted for this session.")

    audio_bytes = await audio.read()
    print(f"Audio size: {len(audio_bytes)} bytes")
    
    # Save audio file to disk
    audio_path = _save_audio_file(session_id, audio_bytes, 0, "patient")
    session.audio_files = [(0, "patient", audio_path, len(audio_bytes))]
    print(f"Audio saved to: {audio_path}")

    # Use session language as hint if not passed directly in the form
    # Normalize language to lowercase for consistency
    hint = language.lower() if language else (session.language if session.language != "unknown" else None)
    print(f"Language hint: {hint}")

    print("\n🔄 Running Model A (Speech-to-Text)...")
    try:
        a_result = await asyncio.to_thread(model_a.transcribe, audio_bytes, language_hint=hint)
        print(f"✅ Transcription successful!")
        print(f"📝 PATIENT SAID: '{a_result['full_text']}'")
        print(f"   Confidence: {a_result['mean_confidence']:.2%}")
        print(f"   Language detected: {a_result['dominant_language']}")
    except KeyboardInterrupt:
        print("❌ Interrupted by user")
        raise
    except Exception as e:
        print(f"❌ Transcription error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Transcription error: {type(e).__name__}: {e}")

    session.transcript      = a_result["full_text"]
    session.transcript_conf = a_result["mean_confidence"]
    session.language        = a_result["dominant_language"]  # always update from detection result

    print("\n🔄 Running Model B (Clinical Extraction)...")
    try:
        session.extraction = await asyncio.to_thread(model_b.extract, session.transcript)
        _normalize_extraction_patient_info(session.extraction)
        print(f"✅ Extraction successful!")
        print(f"   Extracted: {session.extraction}")

        if session.extraction.get("patient_name"):
            session.patient_name = session.extraction["patient_name"]
            print(f"   📝 Patient name extracted: {session.patient_name}")
        if session.extraction.get("patient_age"):
            age_int = _words_to_age(str(session.extraction["patient_age"]))
            if age_int is not None:
                session.patient_age = age_int
                session.extraction["patient_age"] = str(age_int)
            print(f"   📝 Patient age extracted: {session.patient_age}")
        if session.extraction.get("patient_gender"):
            session.patient_gender = session.extraction["patient_gender"]
            print(f"   📝 Patient gender extracted: {session.patient_gender}")
        if session.extraction.get("patient_phone"):
            session.patient_phone = session.extraction["patient_phone"]
            print(f"   📝 Patient phone extracted: {session.patient_phone}")
        if session.extraction.get("patient_location"):
            session.patient_location = session.extraction["patient_location"]
            print(f"   📝 Patient location extracted: {session.patient_location}")
    except Exception as e:
        print(f"❌ Extraction error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Extraction error: {type(e).__name__}: {e}")

    print("\n🔄 Running Model C (Question Generation)...")
    question = model_c.select_next_question(
        extraction      = session.extraction,
        questions_asked = session.questions_asked,
        patient_answers = session.patient_answers,
    )
    session.stage = SessionStage.QUESTIONING
    print(f"✅ Question generated!")
    print(f"💬 ASSISTANT ASKS: '{question}'")
    print("="*80 + "\n")

    return QuestionResponse(
        session_id        = session.id,
        question          = question,
        coverage_complete = False,
        patient_name      = session.patient_name,
        patient_phone     = session.patient_phone,
    )


@router.post("/{session_id}/answer", response_model=QuestionResponse)
async def kiosk_answer(
    session_id: str,
    question: str = Form(...),
    audio: UploadFile = File(...),
):
    """
    Submit a patient's audio answer. Transcribes it using the session's
    detected language, then returns the next question or signals done.

    When coverage_complete is True, call POST /kiosk/{id}/finish next.
    
    Audio saved to disk but not persisted to database yet.
    """
    print("\n" + "="*80)
    print("🎤 ANSWER AUDIO RECEIVED")
    print(f"Session ID: {session_id}")
    print(f"Previous question: '{question}'")
    
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.QUESTIONING:
        raise HTTPException(status_code=409, detail="Session is not in the questioning stage.")

    audio_bytes = await audio.read()
    print(f"Audio size: {len(audio_bytes)} bytes")
    
    # Save audio file to disk
    if not hasattr(session, 'audio_files'):
        session.audio_files = []
    sequence = len(session.audio_files)
    audio_path = _save_audio_file(session_id, audio_bytes, sequence, "patient")
    session.audio_files.append((sequence, "patient", audio_path, len(audio_bytes)))
    print(f"Audio saved to: {audio_path}")

    # For answers, use the already-detected session language as the hint
    print(f"\n🔄 Running Model A (Transcribing answer in {session.language})...")
    try:
        a_result = await asyncio.to_thread(model_a.transcribe, audio_bytes, language_hint=session.language)
        answer   = a_result["full_text"]
        print(f"✅ Transcription successful!")
        print(f"📝 PATIENT ANSWERED: '{answer}'")
        print(f"   Confidence: {a_result['mean_confidence']:.2%}")
    except Exception as e:
        print(f"❌ Answer transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Answer transcription failed: {e}")

    session.turns.append(ConversationTurn(question=question, answer=answer))
    _capture_patient_info_from_answer(session, question, answer)
    print(f"Turn #{len(session.turns)} recorded")

    print("\n🔄 Running Model B (Updating extraction)...")
    try:
        conversation_history = [
            {"question": t.question, "answer": t.answer}
            for t in session.turns
        ]
        target_language = session.language if session.language in {"kinyarwanda", "english"} else "kinyarwanda"
        session.extraction = await asyncio.to_thread(
            model_b.extract_full,
            session.transcript,
            conversation_history=conversation_history,
            target_language=target_language,
        )
        _normalize_extraction_patient_info(session.extraction)
        print(f"✅ Extraction updated: {session.extraction}")

        if session.extraction.get("patient_name"):
            session.patient_name = session.extraction["patient_name"]
            print(f"   📝 Patient name extracted: {session.patient_name}")
        if session.extraction.get("patient_age"):
            age_int = _words_to_age(str(session.extraction["patient_age"]))
            if age_int is not None:
                session.patient_age = age_int
                session.extraction["patient_age"] = str(age_int)
            print(f"   📝 Patient age extracted: {session.patient_age}")
        if session.extraction.get("patient_gender"):
            session.patient_gender = session.extraction["patient_gender"]
            print(f"   📝 Patient gender extracted: {session.patient_gender}")
        if session.extraction.get("patient_phone"):
            session.patient_phone = session.extraction["patient_phone"]
            print(f"   📝 Patient phone extracted: {session.patient_phone}")
        if session.extraction.get("patient_location"):
            session.patient_location = session.extraction["patient_location"]
            print(f"   📝 Patient location extracted: {session.patient_location}")

        # Preserve previously extracted patient info if Model B dropped it on re-extraction
        if not session.extraction.get("patient_name") and session.patient_name:
            session.extraction["patient_name"] = session.patient_name
        if not session.extraction.get("patient_age") and session.patient_age:
            session.extraction["patient_age"] = str(session.patient_age)
        if not session.extraction.get("patient_gender") and session.patient_gender:
            session.extraction["patient_gender"] = session.patient_gender
        if not session.extraction.get("patient_phone") and session.patient_phone:
            session.extraction["patient_phone"] = session.patient_phone
        if not session.extraction.get("patient_location") and session.patient_location:
            session.extraction["patient_location"] = session.patient_location
    except Exception as e:
        print(f"⚠️ Extraction update failed (continuing): {e}")

    print("\n🔄 Running Model C (Checking coverage)...")
    if model_c.is_coverage_complete(session.extraction, len(session.turns), MAX_TURNS):
        session.stage = SessionStage.SCORING
        print(f"✅ Coverage complete! ({len(session.turns)} turns completed)")
        print("="*80 + "\n")
        return QuestionResponse(
            session_id=session.id,
            question="",
            coverage_complete=True,
            patient_name=session.patient_name,
            patient_phone=session.patient_phone,
        )

    print(f"📊 Coverage not yet complete ({len(session.turns)}/{MAX_TURNS} turns)")
    next_q = model_c.select_next_question(
        extraction      = session.extraction,
        questions_asked = session.questions_asked,
        patient_answers = session.patient_answers,
    )
    print(f"✅ Next question generated!")
    print(f"💬 ASSISTANT ASKS: '{next_q}'")
    print("="*80 + "\n")
    return QuestionResponse(
        session_id=session.id,
        question=next_q,
        coverage_complete=False,
        patient_name=session.patient_name,
        patient_phone=session.patient_phone,
    )


@router.post("/{session_id}/finish", response_model=FinishResponse)
async def kiosk_finish(
    session_id: str,
    body: Optional[FinishRequest] = Body(default=None),
):
    """
    Finalise the session. Runs Models D, E, F and returns
    the patient message and routing decision.
    
    Persists all session data to database:
    - Audio file references
    - Conversation messages
    - Extracted symptoms
    - Risk prediction
    - Complete session data
    - Creates queue entry
    """
    print("\n" + "="*80)
    print("🏁 FINISHING SESSION")
    print(f"Session ID: {session_id}")
    
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.SCORING:
        raise HTTPException(status_code=409, detail="Session is not ready to finish.")
    body = body or FinishRequest()
    full_transcript = _build_full_transcript(session)

    print("\n🔄 Running Model D (Risk Scoring)...")
    session.score = await asyncio.to_thread(model_d.score, session.extraction, age=session.patient_age)
    print(f"✅ Score: {session.score}")

    routing_override_department = None
    suspected_issue = str(session.score.get("suspected_issue", "")).strip().lower()
    if session.score.get("priority") != "HIGH" and suspected_issue == "unclear or unclassifiable complaint":
        print("\n🔄 Running unclear-issue routing fallback...")
        fallback = await asyncio.to_thread(
            suggest_unclear_issue_routing,
            extraction=session.extraction,
            questions_asked=session.questions_asked,
            patient_answers=session.patient_answers,
            language=session.language,
        )
        if fallback:
            routing_override_department = fallback.get("department")
            session.score["suspected_issue"] = fallback.get("suspected_issue", session.score["suspected_issue"])
            session.score["routing_fallback"] = fallback
            print(f"✅ Fallback selected: issue={session.score['suspected_issue']}, department={routing_override_department}")
        else:
            print("ℹ️ Fallback unavailable; using default routing")

    print("\n🔄 Assigning routing...")
    routing = assign_routing(
        priority        = session.score["priority"],
        suspected_issue = session.score["suspected_issue"],
        department_override=routing_override_department,
    )
    print(f"✅ Routing: {routing.department}, Queue: {routing.queue}")

    print("\n🔄 Running Model E (Patient Message)...")
    session.patient_message = await asyncio.to_thread(
        model_e.generate_message,
        extraction     = session.extraction,
        score          = session.score,
        language       = session.language,
        location       = routing.location_hint,
        low_confidence = session.score.get("confidence", 1.0) < 0.4,
    )
    print(f"✅ Patient message generated")

    print("\n🔄 Running Model F (Doctor Brief)...")
    session.doctor_brief = await asyncio.to_thread(
        model_f.generate_brief,
        session_id      = session.id,
        extraction      = session.extraction,
        score           = session.score,
        questions_asked = session.questions_asked,
        patient_answers = session.patient_answers,
        transcript      = full_transcript,
        language        = session.language,
        patient_age     = session.patient_age,
    )
    print(f"✅ Doctor brief generated")
    
    session.location = routing.location_hint
    session.stage    = SessionStage.COMPLETE

    # ========================================================================
    # PERSIST TO DATABASE
    # ========================================================================
    print("\n💾 PERSISTING TO DATABASE...")

    # Keep a safe default so finish can still respond if DB persistence fails.
    queue_entry = {"queue_number": routing.queue_number}

    try:
        # 0. Update patient info (use placeholders if empty — DB requires name length >= 2, valid phone)
        full_name = (body.patient_name or session.patient_name or "").strip()
        phone_number = (body.patient_phone or session.patient_phone or session.extraction.get("patient_phone") or "").strip()
        location_value = (body.patient_location or session.patient_location or session.extraction.get("patient_location") or "").strip() or None
        if len(full_name) < 2:
            full_name = "Unknown"
        phone_number = "".join(c for c in phone_number if c in "0123456789+-() ").strip()
        if not phone_number:
            phone_number = "0"
        session.patient_phone = phone_number
        if location_value:
            session.patient_location = location_value
        PatientDB.update_patient(
            patient_id=session.db_patient_id,
            full_name=full_name,
            phone_number=phone_number,
            location=location_value,
        )
        print(f"✅ Updated patient info")

        # 1. Save audio file references
        if hasattr(session, 'audio_files'):
            for seq, speaker, path, size in session.audio_files:
                AudioDB.save_audio_reference(
                    session_id=session.db_session_id,
                    sequence_number=seq,
                    speaker_type=speaker,
                    file_path=path,
                    file_size_bytes=size
                )
            print(f"✅ Saved {len(session.audio_files)} audio references")

        # 2. Save conversation messages
        seq_num = 1
        ConversationDB.add_message(
            session_id=session.db_session_id,
            sender_type='patient',
            message_text=session.transcript,
            sequence_number=seq_num
        )
        seq_num += 1
        for turn in session.turns:
            ConversationDB.add_message(
                session_id=session.db_session_id,
                sender_type='ml_system',
                message_text=turn.question,
                sequence_number=seq_num
            )
            seq_num += 1
            ConversationDB.add_message(
                session_id=session.db_session_id,
                sender_type='patient',
                message_text=turn.answer,
                sequence_number=seq_num
            )
            seq_num += 1
        print(f"✅ Saved {seq_num - 1} conversation messages")

        # 3. Save symptoms (each symptom in its own try so one bad entry can't abort the rest)
        symptoms_list = session.extraction.get('associated_symptoms') or []
        saved_symptoms = 0
        for symptom in symptoms_list:
            try:
                if isinstance(symptom, dict):
                    SymptomDB.add_symptom(
                        session_id=session.db_session_id,
                        symptom_name=symptom.get('name', 'unknown'),
                        duration=symptom.get('duration'),
                        additional_info=symptom.get('description')
                    )
                else:
                    SymptomDB.add_symptom(
                        session_id=session.db_session_id,
                        symptom_name=str(symptom)
                    )
                saved_symptoms += 1
            except Exception as sym_err:
                print(f"⚠️ Could not save symptom '{symptom}': {sym_err}")
        if saved_symptoms:
            print(f"✅ Saved {saved_symptoms} symptoms")

        # 4. Save prediction/risk score
        db_risk_level = str(session.score.get('priority', 'medium')).strip().lower()
        if db_risk_level not in {'low', 'medium', 'high'}:
            db_risk_level = 'medium'
        PredictionDB.create_prediction(
            session_id=session.db_session_id,
            predicted_condition=session.score.get('suspected_issue', 'Unknown'),
            risk_level=db_risk_level,
            confidence_score=min(float(session.score.get('confidence', 0.5)), 1.0),
            model_version='1.0'
        )
        print(f"✅ Saved prediction")

        # 5. Create queue entry in the routed destination queue.
        queue_entry = QueueDB.create_queue_entry(
            session_id=session.db_session_id,
            patient_id=session.db_patient_id,
            facility_id=session.facility_id,
            queue_name=routing.queue,
            department=routing.department,
            location_hint=routing.location_hint,
        )
        print(f"✅ Created queue entry #{queue_entry['queue_number']}")

        # 5a. Notify patient by SMS now that their queue number is confirmed.
        try:
            from utils.sms_service import send_queue_assignment_sms
            sms_ok, sms_err = send_queue_assignment_sms(
                patient_name=full_name,
                phone_number=phone_number,
                queue_number=queue_entry["queue_number"],
                department=routing.department,
                location_hint=routing.location_hint,
                language=session.language or "english",
            )
            print(f"✅ SMS sent to {phone_number}" if sms_ok else f"⚠️ SMS not sent: {sms_err}")
        except Exception as _sms_exc:
            print(f"⚠️ SMS notification failed: {_sms_exc}")

        # 6. Attach routing destination and queue details to doctor-facing info.
        session.doctor_brief["routing_assignment"] = {
            "department": routing.department,
            "queue": routing.queue,
            "queue_number": queue_entry.get("queue_number", routing.queue_number),
            "location_hint": routing.location_hint,
            "urgency_label": routing.urgency_label,
        }

    except Exception as e:
        print(f"❌ Database persistence error (steps 0-6): {e}")
        import traceback
        traceback.print_exc()

    # 7. Always save complete session data — kept in its own block so a failure
    #    in steps 0-6 never prevents extraction_data / doctor_brief from being stored.
    try:
        _red_flags = session.extraction.get('red_flags_present')
        if _red_flags is None:
            _red_flags = session.score.get('red_flags_detected')
        _severity = session.extraction.get('severity_estimate') or session.score.get('severity_estimate')
        try:
            _severity = int(_severity) if _severity is not None else None
        except (TypeError, ValueError):
            _severity = None
        ExtendedSessionDB.save_complete_session(
            session_id=session.db_session_id,
            extraction_data=session.extraction,
            score_data=session.score,
            patient_message=session.patient_message,
            doctor_brief=session.doctor_brief,
            full_transcript=full_transcript,
            transcript_confidence=session.transcript_conf,
            detected_language=session.language,
            patient_age=session.patient_age,
            patient_gender=session.patient_gender or None,
            red_flags_detected=bool(_red_flags) if _red_flags is not None else False,
            chief_complaint=session.extraction.get('chief_complaint') or None,
            severity_estimate=_severity,
        )
        print(f"✅ Saved complete session data")
        print("💾 DATABASE PERSISTENCE COMPLETE")
    except Exception as e:
        print(f"❌ Failed to save complete session data: {e}")
        import traceback
        traceback.print_exc()
    
    print("="*80 + "\n")

    return FinishResponse(
        session_id      = session.id,
        patient_message = session.patient_message,
        department      = routing.department,
        queue           = routing.queue,
        queue_number    = queue_entry.get('queue_number', 0),
        location_hint   = routing.location_hint,
        urgency_label   = routing.urgency_label,
    )


@router.get("/{session_id}/status", response_model=StatusResponse)
def kiosk_status(session_id: str):
    """Poll the current stage of a session."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    return StatusResponse(session_id=session.id, stage=session.stage.value)
