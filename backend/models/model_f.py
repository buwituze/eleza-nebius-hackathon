"""
models/model_f.py — Doctor summary generator wrapper.
"""

import os, json, re, datetime
from typing import Optional
from google import genai
from .gemini_utils import generate_with_fallback

_client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

_SYSTEM = """You are a clinical documentation assistant. Write a patient brief for a doctor.
Rules:
- Report only what the patient said and what the system recorded.
- No clinical interpretation, diagnosis, or advice.
- Clinical language. Past tense. Concise.
- Output valid JSON only matching the schema. No extra text."""


def _parse(raw: str) -> dict:
    # Since we use response_mime_type='application/json', response is already JSON
    cleaned = raw.strip()
    # Remove markdown code blocks if present
    cleaned = re.sub(r"```(?:json)?\s*", "", cleaned).rstrip("`")
    
    try:
        # Try direct JSON parse first
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Fallback: try to extract JSON from text
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if not match:
            raise ValueError(f"No valid JSON in response. Got: {raw[:500]}")
        return json.loads(match.group(0))


def generate_brief(session_id: str, extraction: dict, score: dict,
                   questions_asked: list[str], patient_answers: list[str],
                   transcript: str = "", language: str = "english",
                   patient_age: Optional[int] = None) -> dict:
    """
    Generate a structured doctor brief from a completed session.

    Returns a dict with all brief fields ready to send to the clinician dashboard.
    """
    assoc   = ", ".join(extraction.get("associated_symptoms", [])) or "none"
    rf      = "YES" if extraction.get("red_flags_present") else "No" if extraction.get("red_flags_present") is False else "Unknown"
    convo   = "\n".join(f"  Q: {q}\n  A: {a}" for q, a in zip(questions_asked, patient_answers)) or "  (none)"

    schema = {
        "narrative_summary": "<2-4 sentence factual summary of what the patient reported>",
        "key_findings":      ["<key fact>"],
        "red_flag_note":     "<one sentence if red flag, else empty string>",
    }

    prompt = f"""Session: {session_id} | Language: {language} | Age: {patient_age or 'unknown'}

Model B — Structured symptoms:
  Chief complaint : {extraction.get('chief_complaint') or 'not recorded'}
  Body part       : {extraction.get('body_part') or 'not recorded'}
  Duration        : {extraction.get('duration') or 'not recorded'}
  Severity        : {extraction.get('severity') or 'not recorded'}
  Other symptoms  : {assoc}
  Red flag        : {rf}
  Observations    : {extraction.get('additional_observations') or 'none'}

Model C — Conversation:
{convo}

Model D — Risk score:
  Priority        : {score.get('priority', 'unknown')}
  Suspected issue : {score.get('suspected_issue') or 'not determined'}
  Risk factors    : {', '.join(score.get('risk_factors', [])) or 'none'}
  Confidence      : {score.get('confidence', 0.0):.2f}

Schema:
{json.dumps(schema, indent=2)}

Return the populated JSON only."""

    full_prompt = f"""{_SYSTEM}

Understood. JSON brief only, no diagnosis.

{prompt}"""

    try:
        response = generate_with_fallback(
            _client,
            contents=full_prompt,
            config={
                'temperature': 0.1,
                'max_output_tokens': 600,
                'response_mime_type': 'application/json',
                'thinking_config': {'thinking_budget': 0},
            }
        )
        gemini_out = _parse(response.text)
    except Exception:
        gemini_out = {
            "narrative_summary": f"Patient reported {extraction.get('chief_complaint') or 'unspecified complaint'}. Duration: {extraction.get('duration') or 'unknown'}. Severity: {extraction.get('severity') or 'unknown'}.",
            "key_findings":      score.get("risk_factors") or [extraction.get("chief_complaint", "")],
            "red_flag_note":     "Red flag confirmed by system." if extraction.get("red_flags_present") else "",
        }

    return {
        "session_id":          session_id,
        "timestamp":           datetime.datetime.now().isoformat(),
        # Extraction fields the frontend reads from doctor_brief
        "chief_complaint":     extraction.get("chief_complaint", ""),
        "body_part":           extraction.get("body_part"),
        "duration":            extraction.get("duration"),
        "severity":            extraction.get("severity"),
        "associated_symptoms": extraction.get("associated_symptoms") or [],
        # Score fields the frontend reads from doctor_brief
        "priority":            score.get("priority", "UNKNOWN"),
        "suspected_issue":     score.get("suspected_issue", "not determined"),
        "confidence_score":    score.get("confidence", 0.0),
        "risk_factors":        score.get("risk_factors") or [],
        # Gemini-generated fields
        "narrative_summary":   gemini_out.get("narrative_summary", ""),
        "key_findings":        gemini_out.get("key_findings", []),
        "red_flag_note":       gemini_out.get("red_flag_note", ""),
        "conversation_log":    [{"question": q, "answer": a} for q, a in zip(questions_asked, patient_answers)],
        "raw_transcript":      transcript,
        "language":            language,
        "patient_age":         patient_age,
    }
