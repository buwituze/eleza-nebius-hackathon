"""
models/model_d.py — Risk and priority scoring wrapper.
"""

import os, json, re
from typing import Optional
from google import genai
from .gemini_utils import generate_with_fallback

_client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

PRIORITY_LEVELS = ["HIGH", "MEDIUM", "LOW"]

ISSUE_CATEGORIES = [
    "cardiorespiratory-related complaint",
    "neurological-related complaint",
    "gastrointestinal-related complaint",
    "musculoskeletal-related complaint",
    "dermatological-related complaint",
    "urological-related complaint",
    "ENT-related complaint",
    "general or systemic complaint",
    "mental health-related complaint",
    "obstetric or gynaecological complaint",
    "paediatric-related complaint",
    "unclear or unclassifiable complaint",
]

_TRIAGE_RULES = """
HIGH: red flag present, OR severity severe/extreme/8-10, OR acute rapid onset, OR infant/elderly with moderate+ symptoms.
MEDIUM: moderate severity (4-7/10), symptom hours to days, mild associated symptoms, no red flags.
LOW: mild severity (1-3/10), stable for days to weeks, no associated symptoms, no red flags.
Confidence: 0.8-1.0 if severity + duration + red flag status all known. 0.5-0.79 if one missing. Below 0.5 if most missing.
Risk factors: observable facts only. Max 4. Short phrases.
"""

_SYSTEM = """You are a clinical triage scoring assistant. Output a risk score for clinician review only.
Rules:
- No diagnosis, no treatment advice, no patient-facing language.
- Output valid JSON only matching the schema. No extra text.
- suspected_issue must be exactly one value from the provided category list."""


def _parse(raw: str) -> dict:
    # Since we use response_mime_type='application/json', response is already JSON
    cleaned = raw.strip()
    # Remove markdown code blocks if present
    cleaned = re.sub(r"```(?:json)?\s*", "", cleaned).rstrip("`")
    
    try:
        # Try direct JSON parse first
        d = json.loads(cleaned)
    except json.JSONDecodeError:
        # Fallback: try to extract JSON from text
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if not match:
            raise ValueError(f"No valid JSON in response. Got: {raw[:500]}")
        d = json.loads(match.group(0))

    priority = str(d.get("priority", "MEDIUM")).upper()
    if priority not in PRIORITY_LEVELS:
        priority = "MEDIUM"

    suspected = d.get("suspected_issue", "")
    if suspected not in ISSUE_CATEGORIES:
        suspected = "unclear or unclassifiable complaint"

    factors = d.get("risk_factors", [])
    if not isinstance(factors, list):
        factors = [str(factors)] if factors else []

    try:
        conf = round(max(0.0, min(1.0, float(d.get("confidence", 0.5)))), 2)
    except (TypeError, ValueError):
        conf = 0.5

    return {"priority": priority, "suspected_issue": suspected,
            "risk_factors": factors[:4], "confidence": conf}


def score(extraction: dict, age: Optional[int] = None) -> dict:
    """
    Score urgency from a Model B extraction dict.
    Returns {"priority", "suspected_issue", "risk_factors", "confidence"}.
    """
    symptom  = extraction.get("chief_complaint", "")
    severity = extraction.get("severity", "").lower()
    red_flag = extraction.get("red_flags_present")

    # Safety override — skip API call for confirmed severe red flags
    if red_flag and severity in ("severe", "extreme", "unbearable", "very severe"):
        issue = ("cardiorespiratory-related complaint"
                 if any(w in symptom.lower() for w in ["chest", "breath", "heart"])
                 else "general or systemic complaint")
        return {
            "priority":        "HIGH",
            "suspected_issue": issue,
            "risk_factors":    ([symptom] + extraction.get("associated_symptoms", []))[:4],
            "confidence":      0.95,
        }

    data = {
        "symptom":             symptom or "unknown",
        "severity":            extraction.get("severity") or "unknown",
        "duration":            extraction.get("duration") or "unknown",
        "body_part":           extraction.get("body_part") or "unknown",
        "associated_symptoms": extraction.get("associated_symptoms", []),
        "red_flags_present":   red_flag,
        "age":                 age,
    }
    schema     = {"priority": "HIGH|MEDIUM|LOW", "suspected_issue": "<one from list>",
                  "risk_factors": ["<fact>"], "confidence": 0.0}
    categories = "\n".join(f"- {c}" for c in ISSUE_CATEGORIES)

    prompt = f"""Patient data:\n{json.dumps(data, indent=2)}

Allowed categories:\n{categories}

Triage rules:\n{_TRIAGE_RULES}

Schema:\n{json.dumps(schema, indent=2)}

Return the populated JSON only."""

    full_prompt = f"""{_SYSTEM}

Understood. JSON risk score only.

{prompt}"""
    
    try:
        response = generate_with_fallback(
            _client,
            contents=full_prompt,
            config={
                'temperature': 0.0,
                'max_output_tokens': 300,
                'response_mime_type': 'application/json',
                'thinking_config': {'thinking_budget': 0},
            }
        )
        return _parse(response.text)
    except Exception:
        return {"priority": "MEDIUM", "suspected_issue": "unclear or unclassifiable complaint",
                "risk_factors": [], "confidence": 0.0}

# Wrapper for notebook compatibility
def score_risk(extraction: dict, questions_asked: list[str], patient_answers: list[str], patient_age: int = None) -> dict:
    """Wrapper function for notebook compatibility."""
    return score(extraction, age=patient_age)
