"""
routers/transcription.py — Audio intake endpoint.

POST /sessions/{id}/audio
  → Runs Model A (speech-to-text)
  → Runs Model B (clinical extraction)
  → Returns transcription and extraction only (no questions)
  → Call GET /sessions/{id}/question next to start dialogue
AUDIO FORMAT REQUIREMENT:
  Only WAV format is supported. See backend/AUDIO_FORMAT.md for details.
  Frontend apps should record audio in WAV format (16kHz mono recommended)."""

import os
import asyncio
from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from typing import Optional

from session import get_session, SessionStage
from models import model_a, model_b
from routing.conversation_router import route_conversation

router = APIRouter(prefix="/sessions", tags=["transcription"])


@router.post("/{session_id}/audio")
async def receive_audio(
    session_id: str,
    audio:      UploadFile       = File(...),
    language:   Optional[str]    = Form(None),  # Patient's screen selection — hint only
):
    """
    Accept a patient audio file, transcribe it, and extract clinical information.
    Does not return questions — use GET /sessions/{id}/question for that.

    language (form field): passed as a hint to Model A. Detection always runs
    regardless — the selected language is never used to skip detection.

    Transitions session: AWAITING_AUDIO → AWAITING_AUDIO (stays until dialogue begins)
    
    Returns 503 if models are still loading or failed to load.
    """
    # Check if models are ready
    models_status = model_a.get_models_status()
    if not models_status.get("ready", False):
        print(f"\n⚠️ Models not ready. Status: {models_status.get('status', 'unknown')}")
        raise HTTPException(
            status_code=503,
            detail=f"AI models still loading ({models_status.get('status')}). "
                   f"Check /startup/status and retry in a few seconds."
        )
    
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.AWAITING_AUDIO:
        raise HTTPException(
            status_code=409,
            detail=f"Session is in stage '{session.stage.value}', not awaiting audio.",
        )

    audio_bytes = await audio.read()
    print(f"\n📥 Audio received: {len(audio_bytes)} bytes ({len(audio_bytes)/(1024*1024):.2f}MB)")

    # Resolve hint: prefer form field, fall back to session language if already known
    # Normalize language to lowercase for consistency
    hint = language.lower() if language else (session.language if session.language != "unknown" else None)
    print(f"Language hint: {hint}")

    # Model A — transcribe (detection always runs; hint is tiebreaker only)
    print("🔄 Starting transcription...")
    try:
        a_result = await asyncio.to_thread(model_a.transcribe, audio_bytes, language_hint=hint)
        print(f"✅ Transcription complete!")
    except KeyboardInterrupt:
        raise
    except Exception as e:
        print(f"❌ Transcription failed: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Transcription failed: {type(e).__name__}: {e}")

    session.transcript      = a_result["full_text"]
    session.transcript_conf = a_result["mean_confidence"]
    session.language        = a_result["dominant_language"]  # always update from detection
    session.transcription_quality = a_result.get("quality", "unknown")  # high/medium/low
    session.api_calls_count += 1  # Model A API call

    # Model B — light extraction for routing (NEW SYSTEM)
    print("🔄 Starting light extraction for routing...")
    try:
        session.light_extraction = await asyncio.to_thread(model_b.extract_light, session.transcript)
        session.api_calls_count += 1  # Model B light extraction API call
        print(f"✅ Light extraction complete!")
        
        # Extract key fields
        session.chief_complaint = session.light_extraction.get("chief_complaint", "unknown")
        session.severity_estimate = session.light_extraction.get("severity_estimate", 0)
        session.red_flags_detected = session.light_extraction.get("red_flags_present", False)
        
    except Exception as e:
        print(f"❌ Light extraction failed: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Light extraction failed: {type(e).__name__}: {e}")
    
    # Conversation Router — decide which path to take (NEW SYSTEM)
    print("🔄 Routing conversation...")
    try:
        routing_result = route_conversation(
            light_extraction=session.light_extraction,
            transcription_quality=session.transcription_quality,
            language=session.language
        )
        session.routing_mode = routing_result["mode"]
        session.routing_reasoning = routing_result["reasoning"]
        print(f"✅ Routing: {session.routing_mode} - {session.routing_reasoning}")
        
    except Exception as e:
        print(f"❌ Routing failed: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        # Fallback to AI-powered if routing fails
        session.routing_mode = "ai_powered"
        session.routing_reasoning = f"Routing error, defaulting to AI: {str(e)}"

    # Estimate cost based on API calls so far
    session.cost_estimate = session.api_calls_count * 0.0004  # Rough estimate
    
    return {
        "session_id":             session.id,
        "stage":                  session.stage.value,
        "transcript":             session.transcript,
        "transcript_language":    session.language,
        "transcript_confidence":  session.transcript_conf,
        "transcription_quality":  session.transcription_quality,
        "language_source":        a_result.get("language_source"),
        "light_extraction":       session.light_extraction,
        "routing_mode":           session.routing_mode,
        "routing_reasoning":      session.routing_reasoning,
        "chief_complaint":        session.chief_complaint,
        "severity_estimate":      session.severity_estimate,
        "red_flags_detected":     session.red_flags_detected,
        "api_calls":              session.api_calls_count,
        "cost_estimate_usd":      session.cost_estimate,
    }