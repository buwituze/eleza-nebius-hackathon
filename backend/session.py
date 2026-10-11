"""
session.py — In-memory session store and shared data types.

Each patient visit is a Session. It is created when the patient arrives
and mutated as the pipeline progresses. Session IDs are the keys.
"""

import uuid
from dataclasses import dataclass, field
from typing import Optional
from enum import Enum


class SessionStage(str, Enum):
    """Tracks where in the pipeline a session currently is."""
    AWAITING_AUDIO = "awaiting_audio"   # Patient has arrived, nothing recorded yet
    EXTRACTING     = "extracting"       # Model A + B running
    QUESTIONING    = "questioning"      # Model C loop active
    SCORING        = "scoring"          # Models D, E, F running
    COMPLETE       = "complete"         # All done, brief ready for doctor


@dataclass
class ConversationTurn:
    question: str
    answer:   str


@dataclass
class Session:
    id:              str
    stage:           SessionStage           = SessionStage.AWAITING_AUDIO
    language:        str                    = "unknown"   # Set after Model A detects from audio
    patient_age:     Optional[int]          = None
    location:        str                    = ""

    # Model A output
    transcript:      str                    = ""
    transcript_conf: float                  = 0.0
    transcription_quality: str              = ""          # high/medium/low from Model A

    # Model B light extraction (for routing)
    light_extraction: dict                  = field(default_factory=dict)
    
    # Model B output (plain dict to avoid circular imports)
    extraction:      dict                   = field(default_factory=dict)
    
    # New system fields
    routing_mode:    str                    = ""          # emergency/rule_based/ai_powered
    routing_reasoning: str                  = ""          # Why this route was chosen
    chief_complaint: str                    = ""          # From light extraction
    severity_estimate: int                  = 0           # 1-10 scale
    red_flags_detected: bool                = False
    patient_name:    str                    = ""          # Asked during conversation
    patient_phone:   str                    = ""          # Asked during conversation
    patient_gender:  str                    = ""          # Asked during conversation
    patient_location: str                   = ""          # Asked during conversation
    api_calls_count: int                    = 0           # Track API usage
    cost_estimate:   float                  = 0.0         # Estimated cost in USD

    # Model C conversation log
    turns:           list[ConversationTurn] = field(default_factory=list)

    # Model D output
    score:           dict                   = field(default_factory=dict)

    # Model E output
    patient_message: str                    = ""

    # Model F output
    doctor_brief:    dict                   = field(default_factory=dict)

    @property
    def questions_asked(self) -> list[str]:
        return [t.question for t in self.turns]

    @property
    def patient_answers(self) -> list[str]:
        return [t.answer for t in self.turns]


# ---------------------------------------------------------------------------
# Simple in-memory store — swap for Redis or a DB in production
# ---------------------------------------------------------------------------
_store: dict[str, Session] = {}


def create_session(language: str = "unknown", patient_age: Optional[int] = None,
                   location: str = "") -> Session:
    session = Session(
        id          = str(uuid.uuid4()),
        language    = language,
        patient_age = patient_age,
        location    = location,
    )
    _store[session.id] = session
    return session


def get_session(session_id: str) -> Optional[Session]:
    return _store.get(session_id)


def delete_session(session_id: str) -> None:
    _store.pop(session_id, None)


def all_session_ids() -> list[str]:
    return list(_store.keys())