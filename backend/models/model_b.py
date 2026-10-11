"""
models/model_b.py — Clinical information extraction wrapper.

NEW SYSTEM (March 2026):
- Light extraction: Quick routing info (chief_complaint, severity, red_flags, clarity)
- Full extraction: Comprehensive extraction with conversation context
- Language cleanup: Normalize mixed Kinyarwanda/English/French to pure language
"""

import os, json, re
from typing import Optional, List, Dict
from google import genai
from .gemini_utils import generate_with_fallback

# Lazy-initialized Gemini client — avoids crashing at import time if key is missing
_client = None

def _get_client():
    global _client
    if _client is None:
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise RuntimeError("GEMINI_API_KEY environment variable is not set.")
        _client = genai.Client(api_key=api_key)
    return _client

# ============================================================================
# SCHEMAS
# ============================================================================

LIGHT_SCHEMA = {
    "chief_complaint": "",        # Main symptom (normalized, single word/phrase)
    "severity_estimate": 0,       # 1-10 scale
    "red_flags_present": None,    # True/False/None
    "clarity": ""                 # "clear" | "unclear" | "ambiguous"
}

FULL_SCHEMA = {
    "patient_name":            "",    # Extracted from conversation
    "patient_age":             "",    # Extracted from conversation
    "patient_gender":          "",    # Extracted from conversation
    "patient_phone":           "",    # Extracted from conversation
    "patient_location":        "",    # Extracted from conversation
    "chief_complaint":         "",
    "duration":                "",
    "severity":                "",
    "body_part":               "",
    "associated_symptoms":     [],
    "progression":             "",  # "worsening" | "improving" | "stable"
    "triggers":                "",
    "red_flags_present":       None,
    "additional_observations": "",
}

# ============================================================================
# RED FLAG DETECTION
# ============================================================================

RED_FLAG_TERMS = {
    "breathing": ["can't breathe", "cannot breathe", "difficulty breathing", 
                  "guhumeka nabi", "ntashobora guhumeka"],
    "chest": ["chest pain", "chest tightness", "crushing pain", 
             "ububabare bw'igituza", "igituza"],
    "consciousness": ["unconscious", "fainted", "collapsed", "lost consciousness",
                     "yaracitse ubwenge", "yarapfuye"],
    "bleeding": ["severe bleeding", "coughing blood", "vomiting blood",
                "amaraso menshi", "kuruka amaraso"],
    "neurological": ["seizure", "convulsion", "sudden vision loss", "paralysis", 
                    "can't move", "ntashobora kwimuka", "imitsi"],
    "pain": ["worst pain ever", "unbearable", "10/10", "birabura cyane"],
}

def _detect_red_flags(text: str) -> bool:
    """Check for red flag keywords in text."""
    text_lower = text.lower()
    for category, terms in RED_FLAG_TERMS.items():
        if any(term in text_lower for term in terms):
            return True
    return False

# ============================================================================
# LANGUAGE CLEANUP HELPERS
# ============================================================================

_LANGUAGE_CLEANUP_PROMPT = """You are a medical translation assistant.

The patient spoke in casual Kinyarwanda mixed with English/French words (common in Rwanda).
Your task: Clean and standardize the language.

Rules:
1. If mostly Kinyarwanda → Output PURE Kinyarwanda only
2. If mostly English → Output pure English only
3. Preserve meaning exactly
4. Keep medical terms clear
5. One sentence output

Example:
Input: "Ndumva headache cyane depuis ejo"
Output (Kinyarwanda): "Ndumva umutwe ubuza cyane kuva ejo"
Output (English): "I have a severe headache since yesterday"

Choose the DOMINANT language and output only that."""

def _cleanup_mixed_language(text: str, target_language: str = "kinyarwanda") -> str:
    """
    Clean up mixed language text to pure Kinyarwanda or English.
    Uses Gemini to normalize casual mixed speech.
    """
    if len(text.strip()) < 10:
        return text
    
    prompt = f"""{_LANGUAGE_CLEANUP_PROMPT}

Input text: "{text}"

Target language: {target_language}

Output (pure {target_language} only):"""
    
    try:
        response = generate_with_fallback(
            _get_client(),
            contents=prompt,
            config={
                'temperature': 0.0,
                'max_output_tokens': 200,
                'thinking_config': {'thinking_budget': 0},
            }
        )
        return response.text.strip()
    except Exception as e:
        print(f"Warning: Language cleanup failed: {e}. Using original text.")
        return text

# ============================================================================
# LIGHT EXTRACTION (Quick Routing)
# ============================================================================

_LIGHT_SYSTEM = """You are a triage routing assistant for a hospital pre-consultation system.

Extract ONLY the essential routing information from the patient's statement.

Your task:
1. Identify the MAIN symptom/complaint (one word/phrase - normalize variations)
2. Estimate severity on 1-10 scale (mild=1-3, moderate=4-6, severe=7-10)
3. Detect red flags (life-threatening symptoms)
4. Assess clarity of the transcription

Complaint normalization examples:
- "umutwe ubuza", "headache", "head pain" → "headache"
- "inda irarwaye", "stomach pain", "belly ache" → "stomach_pain"
- "amenyo abuze", "tooth pain" → "mouth_problems"

Clarity assessment:
- "clear": Statement is coherent and understandable
- "unclear": Transcription seems garbled or incomplete
- "ambiguous": Could mean multiple things

Red flags (ALWAYS true if present):
- Difficulty breathing, chest pain
- Loss of consciousness, seizures
- Severe bleeding
- Sudden paralysis or vision loss
- "Worst pain ever" descriptions

Output ONLY valid JSON matching this schema:
{
  "chief_complaint": "normalized_symptom",
  "severity_estimate": 5,
  "red_flags_present": false,
  "clarity": "clear"
}"""

def extract_light(transcript: str) -> dict:
    """
    Quick extraction for routing decisions only.
    
    Args:
        transcript: Patient's initial statement (possibly mixed language)
    
    Returns:
        {
            "chief_complaint": str,      # Normalized symptom name
            "severity_estimate": int,     # 1-10 scale
            "red_flags_present": bool,    # Safety check
            "clarity": str                # "clear" | "unclear" | "ambiguous"
        }
    
    Uses ~300 tokens, fast response time.
    """
    if len(transcript.strip()) < 10:
        return dict(LIGHT_SCHEMA)
    
    # Quick red flag check (keyword-based, before API call)
    has_red_flag = _detect_red_flags(transcript)
    
    prompt = f"""{_LIGHT_SYSTEM}

Patient statement:
"{transcript.strip()}"

Extract routing information as JSON:"""
    
    try:
        response = generate_with_fallback(
            _get_client(),
            contents=prompt,
            config={
                'temperature': 0.0,
                'max_output_tokens': 150,
                'response_mime_type': 'application/json',
                'thinking_config': {'thinking_budget': 0},
            }
        )
        
        result = _parse_json(response.text)
        
        # Validate schema
        extraction = {
            "chief_complaint": str(result.get("chief_complaint", "")).lower().strip(),
            "severity_estimate": int(result.get("severity_estimate", 5)),
            "red_flags_present": result.get("red_flags_present", has_red_flag),
            "clarity": result.get("clarity", "clear")
        }
        
        # Override with keyword detection if found
        if has_red_flag:
            extraction["red_flags_present"] = True
        
        # Ensure severity is in 1-10 range
        extraction["severity_estimate"] = max(1, min(10, extraction["severity_estimate"]))
        
        return extraction
        
    except Exception as e:
        print(f"Error in light extraction: {e}")
        # Fallback to basic detection
        return {
            "chief_complaint": "unknown",
            "severity_estimate": 5,
            "red_flags_present": has_red_flag,
            "clarity": "unclear"
        }

# ============================================================================
# FULL EXTRACTION (Comprehensive)
# ============================================================================

_FULL_SYSTEM = """You are a clinical information extraction assistant.

Extract comprehensive clinical information from the patient's complete conversation.

Rules:
- Extract ONLY observable facts, never diagnose
- Leave fields empty if information is missing
- Be specific about duration ("started yesterday" not just "recent")
- Severity: Use exact numbers if given, or "mild"/"moderate"/"severe"
- Associated symptoms: List separately, be specific
- If patient phone number or home location is explicitly stated, capture them in patient_phone and patient_location

CRITICAL — patient info normalization:
- patient_name: Extract ONLY the person's actual name. Strip ALL intro phrases and do NOT include them.
  Kinyarwanda intros to strip: "Nitwa", "Njye nitwa", "Amazina yanjye ni", "Nzwa", "Ndiho"
  English intros to strip: "My name is", "I am", "I'm", "I'm called", "They call me", "Call me"
  Example: "Nitwa Benitha Uwituze" → "Benitha Uwituze"
  Example: "My name is John Doe" → "John Doe"
- patient_age: ALWAYS output as a plain integer (number), NEVER as words.
  Example: "ndafite imyaka makumyabiri na gatanu" → 25
  Example: "I am twenty five years old" → 25
  Example: "nfite imyaka mirongo itatu" → 30
- patient_location: Normalize to "Neighborhood, City" format when recognizable.
  Example: "ntuye kanombe muri kigali" → "Kanombe, Kigali"
  Example: "I live in Gikondo in Kigali" → "Gikondo, Kigali"
  Example: "Remera, Kigali" → "Remera, Kigali" (already good)

Red flags (mark true if ANY present):
- Difficulty breathing, chest pain, pressure
- Loss of consciousness, fainting
- Severe bleeding, coughing/vomiting blood
- Seizures, sudden vision loss
- Sudden severe pain ("worst ever")
- Inability to move limbs

Output ONLY valid JSON matching the schema."""

def extract_full(transcript: str, conversation_history: Optional[List[Dict]] = None,
                 target_language: str = "kinyarwanda") -> dict:
    """
    Comprehensive extraction with full conversation context.
    
    Args:
        transcript: Initial patient statement
        conversation_history: List of {"question": str, "answer": str}
        target_language: "kinyarwanda" or "english" for cleanup
    
    Returns:
        Full clinical extraction dict matching FULL_SCHEMA
    
    Uses ~800 tokens, detailed response.
    """
    if len(transcript.strip()) < 10:
        return dict(FULL_SCHEMA)
    
    # Clean/normalize mixed language if needed
    cleaned_transcript = _cleanup_mixed_language(transcript, target_language)
    
    # Build conversation context
    conversation_text = f"Initial statement: {cleaned_transcript}\n\n"
    
    if conversation_history:
        conversation_text += "Follow-up conversation:\n"
        for i, turn in enumerate(conversation_history, 1):
            q = turn.get("question", "")
            a = turn.get("answer", "")
            # Clean answers too
            cleaned_answer = _cleanup_mixed_language(a, target_language) if a else ""
            conversation_text += f"Q{i}: {q}\nA{i}: {cleaned_answer}\n"
    
    schema_json = json.dumps(FULL_SCHEMA, indent=2)
    
    prompt = f"""{_FULL_SYSTEM}

Schema:
{schema_json}

Patient conversation:
{conversation_text}

Extract all clinical information as JSON:"""
    
    try:
        response = generate_with_fallback(
            _get_client(),
            contents=prompt,
            config={
                'temperature': 0.0,
                'max_output_tokens': 400,
                'response_mime_type': 'application/json',
                'thinking_config': {'thinking_budget': 0},
            }
        )
        
        result = _parse_json(response.text)
        extraction = _validate_full(result)
        
        # Double-check red flags with keyword detection
        all_text = " ".join([
            transcript,
            extraction.get("chief_complaint", ""),
            extraction.get("additional_observations", ""),
            " ".join(extraction.get("associated_symptoms", [])),
            *[turn.get("answer", "") for turn in (conversation_history or [])]
        ])
        
        if _detect_red_flags(all_text):
            extraction["red_flags_present"] = True
        
        return extraction
        
    except Exception as e:
        print(f"Error in full extraction: {e}")
        raise RuntimeError(f"Failed to extract clinical information: {e}")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _parse_json(raw: str) -> dict:
    """Parse JSON from Gemini response, handling markdown formatting."""
    cleaned = raw.strip()
    # Remove markdown code blocks if present
    cleaned = re.sub(r"```(?:json)?\s*", "", cleaned).rstrip("`")
    
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Fallback: extract JSON from text
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if not match:
            raise ValueError(f"No valid JSON in response. Got: {raw[:300]}")
        return json.loads(match.group(0))

def _validate_full(raw: dict) -> dict:
    """Validate and normalize full extraction result."""
    d = {k: raw.get(k, v) for k, v in FULL_SCHEMA.items()}
    
    # Ensure string fields are strings
    for key in ["patient_name", "patient_age", "patient_gender", "patient_phone", "patient_location",
                "chief_complaint", "duration", "severity", "body_part", 
                "progression", "triggers", "additional_observations"]:
        if not isinstance(d[key], str):
            d[key] = str(d[key]) if d[key] else ""
    
    # Ensure list field is list
    if not isinstance(d["associated_symptoms"], list):
        d["associated_symptoms"] = [d["associated_symptoms"]] if d["associated_symptoms"] else []
    
    # Ensure boolean field is boolean or None
    if d["red_flags_present"] not in (True, False, None):
        d["red_flags_present"] = None
    
    return d

# ============================================================================
# BACKWARD COMPATIBILITY
# ============================================================================

def extract(transcript: str) -> dict:
    """
    Legacy function for backward compatibility.
    Calls extract_full() with no conversation history.
    
    Returns dict matching FULL_SCHEMA.
    """
    return extract_full(transcript, conversation_history=None)

# Alias for notebook compatibility
extract_info = extract
