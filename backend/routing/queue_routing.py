"""
queue_routing.py — Queue and department routing logic.

A rule engine that maps priority + suspected issue → department + queue position.
No ML required. Rules are explicit, auditable, and easy to update.
"""

from dataclasses import dataclass
import json
import os
import re
from typing import Optional
from google import genai


_gemini_client = genai.Client(api_key=os.getenv("GEMINI_API_KEY")) if os.getenv("GEMINI_API_KEY") else None


@dataclass
class RoutingDecision:
    department:    str           # Where the patient should go
    queue:         str           # Which queue they join
    queue_number:  int           # Their position in that queue
    urgency_label: str           # Human-readable label for the patient
    location_hint: str           # Specific desk or waiting area


# ---------------------------------------------------------------------------
# Department rules
# Priority + suspected issue → department
# ---------------------------------------------------------------------------
_DEPARTMENT_RULES: dict[tuple, str] = {
    # HIGH priority always goes to Emergency regardless of issue
    ("HIGH",   "*"):                                    "Emergency",

    # MEDIUM by issue category
    ("MEDIUM", "cardiorespiratory-related complaint"):  "Emergency",
    ("MEDIUM", "neurological-related complaint"):       "General Medicine",
    ("MEDIUM", "gastrointestinal-related complaint"):   "General Medicine",
    ("MEDIUM", "musculoskeletal-related complaint"):    "Orthopaedics",
    ("MEDIUM", "dermatological-related complaint"):     "Dermatology",
    ("MEDIUM", "urological-related complaint"):         "Urology",
    ("MEDIUM", "ENT-related complaint"):                "ENT",
    ("MEDIUM", "general or systemic complaint"):        "General Medicine",
    ("MEDIUM", "mental health-related complaint"):      "Mental Health",
    ("MEDIUM", "obstetric or gynaecological complaint"):"Gynaecology",
    ("MEDIUM", "paediatric-related complaint"):         "Paediatrics",
    ("MEDIUM", "ophthalmology-related complaint"):      "Ophthalmology",
    ("MEDIUM", "unclear or unclassifiable complaint"):  "General Medicine",

    # LOW by issue category (same mapping, different waiting area)
    ("LOW",    "cardiorespiratory-related complaint"):  "General Medicine",
    ("LOW",    "neurological-related complaint"):       "General Medicine",
    ("LOW",    "gastrointestinal-related complaint"):   "General Medicine",
    ("LOW",    "musculoskeletal-related complaint"):    "General Medicine",
    ("LOW",    "dermatological-related complaint"):     "Dermatology",
    ("LOW",    "urological-related complaint"):         "General Medicine",
    ("LOW",    "ENT-related complaint"):                "ENT",
    ("LOW",    "general or systemic complaint"):        "General Medicine",
    ("LOW",    "mental health-related complaint"):      "Mental Health",
    ("LOW",    "obstetric or gynaecological complaint"):"Gynaecology",
    ("LOW",    "paediatric-related complaint"):         "Paediatrics",
    ("LOW",    "ophthalmology-related complaint"):      "Ophthalmology",
    ("LOW",    "unclear or unclassifiable complaint"):  "General Medicine",
}

# Department → queue name + waiting area description
_DEPARTMENT_CONFIG: dict[str, dict] = {
    "Emergency":      {"queue": "emergency",    "location": "Emergency Department — present to the desk immediately"},
    "General Medicine":{"queue": "general",     "location": "Waiting Area A — General Outpatient"},
    "Orthopaedics":   {"queue": "ortho",        "location": "Waiting Area B — Orthopaedics"},
    "Dermatology":    {"queue": "derm",         "location": "Waiting Area C — Dermatology"},
    "Urology":        {"queue": "urology",      "location": "Waiting Area D — Urology"},
    "ENT":            {"queue": "ent",           "location": "Waiting Area E — ENT"},
    "Mental Health":  {"queue": "mh",            "location": "Waiting Area F — Mental Health"},
    "Gynaecology":    {"queue": "gynae",         "location": "Waiting Area G — Gynaecology"},
    "Paediatrics":    {"queue": "paediatrics",   "location": "Waiting Area H — Paediatrics"},
    "Ophthalmology":  {"queue": "ophthalmology", "location": "Waiting Area I — Ophthalmology"},
}

_URGENCY_LABELS = {
    "HIGH":   "Urgent",
    "MEDIUM": "Standard",
    "LOW":    "Routine",
}

# In-memory queue counters — replace with DB-backed counters in production
_queue_counters: dict[str, int] = {config["queue"]: 0 for config in _DEPARTMENT_CONFIG.values()}


def _resolve_department(priority: str, suspected_issue: str) -> str:
    """Match priority + issue to a department using the rules table."""
    # Exact match first
    key = (priority, suspected_issue)
    if key in _DEPARTMENT_RULES:
        return _DEPARTMENT_RULES[key]
    # HIGH wildcard
    if priority == "HIGH":
        return _DEPARTMENT_RULES[("HIGH", "*")]
    # Default fallback
    return "General Medicine"


def _next_queue_number(queue_name: str) -> int:
    """Increment and return the next number for a given queue."""
    _queue_counters[queue_name] = _queue_counters.get(queue_name, 0) + 1
    return _queue_counters[queue_name]


def _sanitize_department(department: Optional[str]) -> str:
    if not department:
        return "General Medicine"
    return department if department in _DEPARTMENT_CONFIG else "General Medicine"


def _parse_json_payload(raw: str) -> dict:
    cleaned = raw.strip()
    cleaned = re.sub(r"```(?:json)?\s*", "", cleaned).rstrip("`")
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if not match:
            raise ValueError("No JSON payload found")
        return json.loads(match.group(0))


def suggest_unclear_issue_routing(
    extraction: dict,
    questions_asked: list[str],
    patient_answers: list[str],
    language: str,
) -> Optional[dict]:
    """
    For unclear issue labels, ask Gemini for a best-fit department and issue label.
    Returns None when suggestion is unavailable.
    """
    if _gemini_client is None:
        return None

    conversation = "\n".join(
        f"Q: {q}\nA: {a}" for q, a in zip(questions_asked, patient_answers)
    ) or "(no follow-up conversation)"
    allowed_departments = list(_DEPARTMENT_CONFIG.keys())
    departments_text = "\n".join(f"- {d}" for d in allowed_departments)

    prompt = f"""You are a clinical routing assistant.
The current triage issue label is unclear. Choose the best destination department and an improved issue label.

Rules:
- Use only these department values:
{departments_text}
- Keep issue label short and specific (example: ophthalmology-related complaint).
- Return strict JSON only.

Patient language: {language}
Structured extraction:
{json.dumps(extraction, ensure_ascii=False, indent=2)}

Conversation:
{conversation}

Output schema:
{{
  "department": "<department from list>",
  "suspected_issue": "<short issue label>",
  "confidence": 0.0,
  "reason": "<short reason>"
}}"""

    try:
        response = _gemini_client.models.generate_content(
            model="gemini-3.1-flash-lite-preview",
            contents=prompt,
            config={
                "temperature": 0.0,
                "max_output_tokens": 250,
                "response_mime_type": "application/json",
                "thinking_config": {"thinking_budget": 0},
            },
        )
        parsed = _parse_json_payload(response.text)
    except Exception:
        return None

    department = _sanitize_department(str(parsed.get("department", "")).strip())
    suspected_issue = str(parsed.get("suspected_issue", "")).strip() or "general or systemic complaint"
    try:
        confidence = max(0.0, min(1.0, float(parsed.get("confidence", 0.0))))
    except (TypeError, ValueError):
        confidence = 0.0

    return {
        "department": department,
        "suspected_issue": suspected_issue,
        "confidence": round(confidence, 2),
        "reason": str(parsed.get("reason", "")).strip(),
    }


def assign_routing(priority: str, suspected_issue: str, department_override: Optional[str] = None) -> RoutingDecision:
    """
    Assign a department, queue, and position to a patient.

    Args:
        priority:        "HIGH" | "MEDIUM" | "LOW"
        suspected_issue: Issue category string from Model D.

    Returns:
        RoutingDecision with all routing details.
    """
    department = _sanitize_department(department_override) if department_override else _resolve_department(priority, suspected_issue)
    config     = _DEPARTMENT_CONFIG.get(department, _DEPARTMENT_CONFIG["General Medicine"])
    queue_name = config["queue"]
    number     = _next_queue_number(queue_name)

    return RoutingDecision(
        department    = department,
        queue         = queue_name,
        queue_number  = number,
        urgency_label = _URGENCY_LABELS.get(priority, "Standard"),
        location_hint = config["location"],
    )


def get_queue_lengths() -> dict[str, int]:
    """Return current queue lengths for all departments."""
    return dict(_queue_counters)


def reset_queues() -> None:
    """Reset all queue counters (e.g. at start of day)."""
    for key in _queue_counters:
        _queue_counters[key] = 0
