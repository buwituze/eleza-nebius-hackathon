"""
routers/dialogue.py — Model C question-answer loop endpoints.

GET  /sessions/{id}/question
  → Runs Model C to get next question based on current extraction
  → Transitions session to QUESTIONING stage

POST /sessions/{id}/answer
  → Records patient's answer (text)
  → Re-runs Model B to update extraction with new info
  → Returns next question OR signals that coverage is complete

POST /sessions/{id}/answer-audio
  → Accepts audio answer from patient
  → Runs Model A to transcribe (using session language as hint)
  → Records answer and updates extraction
  → Returns next question OR signals that coverage is complete

Note: /answer and /answer-audio are internal/debug routes.
      The kiosk frontend uses POST /kiosk/{id}/answer which handles
      audio answers directly in one call.
"""

import os
import asyncio
from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from pydantic import BaseModel

from session import get_session, SessionStage, ConversationTurn
from models import model_a, model_b, model_c
from models.model_c_rules import get_symptom_questions, get_patient_info_questions

MAX_TURNS = int(os.getenv("MAX_TURNS", 10))  # Increased for rule-based questions

router = APIRouter(prefix="/sessions", tags=["dialogue"])


class AnswerRequest(BaseModel):
    question: str   # The question that was asked (for the log)
    answer:   str   # The patient's answer (pre-transcribed text)


@router.get("/{session_id}/question")
def get_next_question(session_id: str):
    """
    Get the next question based on current extraction.

    Can be called:
    - After initial audio transcription to start dialogue
    - After each answer to continue dialogue

    Transitions session: AWAITING_AUDIO → QUESTIONING (first call)
                         QUESTIONING    → QUESTIONING (subsequent calls)
    """
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage not in (SessionStage.AWAITING_AUDIO, SessionStage.QUESTIONING):
        raise HTTPException(
            status_code=409,
            detail=f"Cannot get question in stage '{session.stage.value}'. Must be AWAITING_AUDIO or QUESTIONING.",
        )
    if not session.light_extraction:
        raise HTTPException(
            status_code=409,
            detail="No extraction available yet. Submit audio first via POST /sessions/{id}/audio.",
        )

    # Determine question source based on routing mode
    if session.routing_mode == "emergency":
        # Emergency: minimal questions, move to scoring quickly
        if len(session.turns) >= 1:  # Asked patient info, now move on
            # Do full extraction before scoring
            print("🔄 Emergency mode: performing full extraction...")
            conversation_history = session.transcript + " " + " ".join(session.patient_answers)
            try:
                session.extraction = model_b.extract_full(
                    transcript=session.transcript,
                    conversation_history=conversation_history,
                    target_language=session.language
                )
                session.api_calls_count += 1
            except Exception as e:
                print(f"❌ Full extraction failed: {e}")
                session.extraction = session.light_extraction  # Fallback
            
            session.stage = SessionStage.SCORING
            return {
                "session_id":        session.id,
                "stage":             session.stage.value,
                "coverage_complete": True,
                "next_question":     None,
                "extraction":        session.extraction,
            }
        else:
            # Ask one emergency-related question
            next_question = "Can you describe your main concern right now?" if session.language == "english" else "Ni iki gikomeye ubu?"
    
    elif session.routing_mode == "rule_based":
        # Rule-based: use predefined questions
        questions = get_symptom_questions(session.chief_complaint, session.language)
        
        if questions and len(session.turns) < len(questions):
            # Get next question from the tree
            q_dict = questions[len(session.turns)]
            next_question = q_dict.get("question") if isinstance(q_dict, dict) else q_dict
        elif len(session.turns) >= 3:  # Asked all rule-based questions
            # Do full extraction before moving to scoring
            print("🔄 Rule-based mode: performing full extraction...")
            conversation_history = session.transcript + " " + " ".join(session.patient_answers)
            try:
                session.extraction = model_b.extract_full(
                    transcript=session.transcript,
                    conversation_history=conversation_history,
                    target_language=session.language
                )
                session.api_calls_count += 1
            except Exception as e:
                print(f"❌ Full extraction failed: {e}")
                session.extraction = session.light_extraction  # Fallback
            
            session.stage = SessionStage.SCORING
            return {
                "session_id":        session.id,
                "stage":             session.stage.value,
                "coverage_complete": True,
                "next_question":     None,
                "extraction":        session.extraction,
            }
        else:
            # Fallback to AI if something went wrong
            next_question = model_c.select_next_question(
                extraction=session.light_extraction,
                questions_asked=session.questions_asked,
                patient_answers=session.patient_answers,
            )
            session.api_calls_count += 1
    
    else:  # ai_powered
        # AI-powered: use old Model C with adaptive questions
        if model_c.is_coverage_complete(session.light_extraction, len(session.turns), MAX_TURNS):
            # Do full extraction before scoring
            print("🔄 AI mode: performing full extraction...")
            conversation_history = session.transcript + " " + " ".join(session.patient_answers)
            try:
                session.extraction = model_b.extract_full(
                    transcript=session.transcript,
                    conversation_history=conversation_history,
                    target_language=session.language
                )
                session.api_calls_count += 1
            except Exception as e:
                print(f"❌ Full extraction failed: {e}")
                session.extraction = session.light_extraction  # Fallback
            
            session.stage = SessionStage.SCORING
            return {
                "session_id":        session.id,
                "stage":             session.stage.value,
                "coverage_complete": True,
                "next_question":     None,
                "extraction":        session.extraction,
            }
        
        next_question = model_c.select_next_question(
            extraction=session.light_extraction,
            questions_asked=session.questions_asked,
            patient_answers=session.patient_answers,
        )
        session.api_calls_count += 1
    
    session.stage = SessionStage.QUESTIONING
    session.cost_estimate = session.api_calls_count * 0.0004

    return {
        "session_id":        session.id,
        "stage":             session.stage.value,
        "coverage_complete": False,
        "next_question":     next_question,
        "routing_mode":      session.routing_mode,
        "api_calls":         session.api_calls_count,
        "cost_estimate_usd": session.cost_estimate,
    }


@router.post("/{session_id}/answer")
async def submit_answer(session_id: str, body: AnswerRequest):
    """
    Record a pre-transcribed patient answer and return the next question.
    For audio answers use POST /sessions/{id}/answer-audio instead.

    Transitions session: QUESTIONING → QUESTIONING (loop) or → SCORING (when done)
    """
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.QUESTIONING:
        raise HTTPException(
            status_code=409,
            detail=f"Session is in stage '{session.stage.value}', not questioning.",
        )

    # Check if this is a patient info answer
    answer_lower = body.answer.lower()
    # Note: age might already be set from initial session creation
    
    session.turns.append(ConversationTurn(question=body.question, answer=body.answer))
    
    # Don't update extraction on every turn to save API calls - we'll do full extraction at end
    # Just continue with light extraction for now

    # Check based on routing mode
    if session.routing_mode == "emergency" and len(session.turns) >= 1:
        is_complete = True
    elif session.routing_mode == "rule_based" and len(session.turns) >= 3:
        is_complete = True
    elif session.routing_mode == "ai_powered" and model_c.is_coverage_complete(session.light_extraction, len(session.turns), MAX_TURNS):
        is_complete = True
    else:
        is_complete = False
    
    if is_complete:
        session.stage = SessionStage.SCORING
        return {
            "session_id":        session.id,
            "stage":             session.stage.value,
            "coverage_complete": True,
            "next_question":     None,
            "extraction":        session.extraction,
        }

    next_question = model_c.select_next_question(
        extraction      = session.extraction,
        questions_asked = session.questions_asked,
        patient_answers = session.patient_answers,
    )

    return {
        "session_id":        session.id,
        "stage":             session.stage.value,
        "coverage_complete": False,
        "next_question":     next_question,
        "extraction":        session.extraction,
    }


@router.post("/{session_id}/answer-audio")
async def submit_answer_audio(
    session_id: str,
    question:   str        = Form(...),
    audio:      UploadFile = File(...),
):
    """
    Accept a patient's audio answer, transcribe it, update extraction,
    and return the next question.

    Uses the session's already-detected language as a hint to Model A.
    Detection still runs on every call — the hint is only a tiebreaker.

    Transitions session: QUESTIONING → QUESTIONING (loop) or → SCORING (when done)
    """
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.stage != SessionStage.QUESTIONING:
        raise HTTPException(
            status_code=409,
            detail=f"Session is in stage '{session.stage.value}', not questioning.",
        )

    audio_bytes = await audio.read()

    # Use the session's detected language as hint — detection still runs
    hint = session.language if session.language != "unknown" else None

    try:
        a_result    = await asyncio.to_thread(model_a.transcribe, audio_bytes, language_hint=hint)
        answer_text = a_result["full_text"]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Answer transcription failed: {e}")

    # Check if this is a patient info answer
    answer_lower = answer_text.lower()
    if not session.patient_name and ("name" in question.lower() or "izina" in question.lower()):
        session.patient_name = answer_text
    elif not session.patient_gender and ("gender" in question.lower() or "igitsina" in question.lower()):
        session.patient_gender = answer_text
    
    session.turns.append(ConversationTurn(question=question, answer=answer_text))
    
    # Check completion based on routing mode
    if session.routing_mode == "emergency" and len(session.turns) >= 1:
        is_complete = True
    elif session.routing_mode == "rule_based" and len(session.turns) >= 3:
        is_complete = True
    elif session.routing_mode == "ai_powered" and model_c.is_coverage_complete(session.light_extraction, len(session.turns), MAX_TURNS):
        is_complete = True
    else:
        is_complete = False
    
    if is_complete:
        session.stage = SessionStage.SCORING
        return {
            "session_id":         session.id,
            "stage":              session.stage.value,
            "coverage_complete":  True,
            "next_question":      None,
            "extraction":         session.extraction,
            "transcribed_answer": answer_text,
        }

    if session.routing_mode == "rule_based":
        next_question = model_c.select_next_question(
            extraction=session.extraction,
            questions_asked=session.questions_asked,
            patient_answers=session.patient_answers,
        )
        session.api_calls_count += 1
    else:  # ai_powered or emergency
        next_question = model_c.select_next_question(
            extraction=session.light_extraction,
            questions_asked=session.questions_asked,
            patient_answers=session.patient_answers,
        )
        session.api_calls_count += 1

    session.cost_estimate = session.api_calls_count * 0.0004
    return {
        "session_id":         session.id,
        "stage":              session.stage.value,
        "coverage_complete":  False,
        "next_question":      next_question,
        "routing_mode":       session.routing_mode,
        "transcribed_answer": answer_text,
        "api_calls":          session.api_calls_count,
        "cost_estimate_usd":  session.cost_estimate,
    }