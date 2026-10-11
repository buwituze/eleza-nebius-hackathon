import logging
import os
from typing import Optional, Tuple

logger = logging.getLogger(__name__)


def _twilio_settings() -> dict:
    return {
        "account_sid": os.getenv("TWILIO_ACCOUNT_SID", "").strip(),
        "auth_token":  os.getenv("TWILIO_AUTH_TOKEN", "").strip(),
        "from_number": os.getenv("TWILIO_FROM_NUMBER", "").strip(),
    }


def _normalize_phone(phone_number: str, default_country_code: str = "250") -> str:
    """Normalize a phone number to E.164 format.

    Handles common local formats:
      079XXXXXXX  → +25079XXXXXXX  (Rwanda local, leading 0)
      79XXXXXXX   → +25079XXXXXXX  (Rwanda local, no leading 0)
      +25079...   → unchanged      (already E.164)
    """
    number = phone_number.strip().replace(" ", "").replace("-", "")
    if number.startswith("+"):
        return number  # already E.164
    if number.startswith("00"):
        return "+" + number[2:]
    if number.startswith("0"):
        return f"+{default_country_code}{number[1:]}"
    # bare number without country code — prepend it
    return f"+{default_country_code}{number}"


def send_sms(phone_number: str, message: str) -> Tuple[bool, Optional[str]]:
    """Send an SMS via Twilio. Returns (success, error_message)."""
    if not phone_number or phone_number.strip() in {"", "0"}:
        return False, "No valid phone number provided"

    phone_number = _normalize_phone(phone_number)

    settings = _twilio_settings()
    missing = [k for k, v in settings.items() if not v]
    if missing:
        return False, f"Twilio not configured (missing: {', '.join(missing)})"

    try:
        from twilio.rest import Client
        client = Client(settings["account_sid"], settings["auth_token"])
        client.messages.create(
            body=message,
            from_=settings["from_number"],
            to=phone_number,
        )
        return True, None
    except Exception as exc:
        logger.exception("Failed to send SMS via Twilio")
        return False, str(exc)


def _first_name(full_name: str) -> str:
    if not full_name or full_name.strip() in {"", "Unknown"}:
        return ""
    return full_name.strip().split()[0]


def send_queue_assignment_sms(
    patient_name: str,
    phone_number: str,
    queue_number: int,
    department: str,
    location_hint: str,
    language: str = "english",
) -> Tuple[bool, Optional[str]]:
    """SMS sent to patient after session ends — tells them where to wait and their queue number."""
    name = _first_name(patient_name)

    if language == "kinyarwanda":
        greeting = f"Muraho {name}," if name else "Muraho,"
        msg = (
            f"{greeting} ikiganiro cya mbere cyarangiye. "
            f"Murajya Kuri {department} — {location_hint}. "
            f"Inomero yawe ni #{queue_number}. "
            f"— Eleza"
        )
    else:
        greeting = f"Hello {name}," if name else "Hello,"
        msg = (
            f"{greeting} your pre-consultation is complete. "
            f"Please go to {department} — {location_hint}. "
            f"Your queue number is #{queue_number}. "
            f"— Eleza"
        )

    return send_sms(phone_number, msg)


def send_exam_assignment_sms(
    patient_name: str,
    phone_number: str,
    queue_number: int,
    required_exams: list,
    room_name: Optional[str],
    location_hint: Optional[str],
    language: str = "english",
) -> Tuple[bool, Optional[str]]:
    """SMS sent to patient after a doctor assigns them exams — tells them what and where."""
    name = _first_name(patient_name)
    exam_str = ", ".join(required_exams) if required_exams else "examination"
    location = room_name or location_hint or "the assigned room"

    if language == "kinyarwanda":
        greeting = f"Muraho {name}," if name else "Muraho,"
        msg = (
            f"{greeting} wasabwe gukora: {exam_str}. "
            f"Murajya kuri {location}. "
            f"Inomero yawe ni #{queue_number}. "
            f"— Eleza"
        )
    else:
        greeting = f"Hello {name}," if name else "Hello,"
        msg = (
            f"{greeting} you have been assigned: {exam_str}. "
            f"Please go to {location}. "
            f"Your queue number is #{queue_number}. "
            f"— Eleza"
        )

    return send_sms(phone_number, msg)
