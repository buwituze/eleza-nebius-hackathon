"""
models/model_b.py — Clinical information extraction wrapper.
"""

import os, json, re
from typing import Optional
import google.generativeai as genai

genai.configure(api_key=os.getenv("GEMINI_API_KEY"))

EMPTY_SCHEMA = {
    "chief_complaint":         "",
    "duration":                "",
    "severity":                "",
    "body_part":               "",
    "associated_symptoms":     [],
    "red_flags_present":       None,
    "additional_observations": "",
}

RED_FLAG_TERMS = [
    "can't breathe", "cannot breathe", "chest pain", "chest tightness",
    "unconscious", "fainted", "collapsed", "severe bleeding", "coughing blood",
    "seizure", "convulsion", "sudden vision loss", "paralysis", "can't move",
    "guhumeka", "amaraso", "imitsi", "kunanirwa",
]

_SYSTEM = """You are a clinical information extraction assistant.
Extract observable facts from the patient transcript and populate the JSON schema.
Rules:
- Output valid JSON only. No markdown, no extra text.
- Leave fields empty if information is missing. Never guess.
- No diagnosis, no medical advice, no new fields.
- red_flags_present: true if breathing difficulty, chest pain, loss of consciousness,
  heavy bleeding, seizure, or sudden paralysis is mentioned. Otherwise false or null.
- The transcript may be in English, Kinyarwanda, or both."""


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


def _validate(raw: dict) -> dict:
    d = {k: raw.get(k, v) for k, v in EMPTY_SCHEMA.items()}

    for key in ["chief_complaint", "duration", "severity", "body_part", "additional_observations"]:
        if not isinstance(d[key], str):
            d[key] = str(d[key]) if d[key] else ""

    if not isinstance(d["associated_symptoms"], list):
        d["associated_symptoms"] = [d["associated_symptoms"]] if d["associated_symptoms"] else []

    if d["red_flags_present"] not in (True, False, None):
        d["red_flags_present"] = None

    all_text = " ".join([
        d["chief_complaint"], d["additional_observations"],
        " ".join(d["associated_symptoms"]),
    ]).lower()
    if any(term in all_text for term in RED_FLAG_TERMS):
        d["red_flags_present"] = True

    return d


def extract(transcript: str) -> dict:
    """
    Extract structured clinical fields from a transcript string.
    Returns the extraction dict (matching EMPTY_SCHEMA keys).
    Raises RuntimeError on failure.
    """
    if len(transcript.strip()) < 10:
        return dict(EMPTY_SCHEMA)

    # Simplified prompt to avoid token exhaustion
    full_prompt = f"""Extract clinical information from this patient statement and return as JSON.

Required JSON format:
{{
  "chief_complaint": "main symptom in patient's words",
  "duration": "how long",
  "severity": "mild/moderate/severe",
  "body_part": "affected area",
  "associated_symptoms": ["other symptoms"],
  "red_flags_present": true/false/null,
  "additional_observations": "other notes"
}}

Patient says: {transcript.strip()}

Return only the JSON, no other text."""

    model = genai.GenerativeModel('models/gemini-flash-latest')
    
    # Debug: check prompt length
    print(f"DEBUG - Prompt length: {len(full_prompt)} chars")
    
    response = model.generate_content(
        full_prompt,
        generation_config={
            'temperature': 0.0,
            'max_output_tokens': 2048,
            'top_p': 0.95,
            'top_k': 40
        }
    )
    
    # Debug output
    print(f"DEBUG - Response length: {len(response.text) if response.text else 0}")
    print(f"DEBUG - Finish reason: {response.candidates[0].finish_reason if response.candidates else 'N/A'}")
    print(f"DEBUG - Full response text:\n{response.text}\n---END---")
    
    if not response.text or len(response.text) < 50:
        raise RuntimeError(f"Empty/short response. Finish reason: {response.candidates[0].finish_reason if response.candidates else 'N/A'}")
    
    return _validate(_parse(response.text))

# Alias for backward compatibility
extract_info = extract
