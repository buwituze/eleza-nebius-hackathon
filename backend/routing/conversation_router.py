"""
routing/conversation_router.py — Central routing logic for conversation flow.

NEW SYSTEM (March 2026):
Intelligent routing based on severity, transcription quality, and symptom type.

Routes:
1. EMERGENCY: Red flags detected → Skip to triage
2. RULE_BASED: Known symptom, low severity, good quality → Predefined questions
3. AI_POWERED: High severity, unclear data, or unknown symptom → Gemini conversation
"""

from typing import Dict, List, Optional
from models import model_c_rules

# ============================================================================
# ROUTING DECISION THRESHOLDS
# ============================================================================

# Severity threshold (1-10 scale)
HIGH_SEVERITY_THRESHOLD = 5  # 5+ → Use AI conversation

# Transcription quality thresholds
QUALITY_LEVELS = {
    "high": 3,     # Trust completely → can use rules
    "medium": 2,   # Some uncertainty → careful with rules
    "low": 1       # Don't trust → use AI
}

# ============================================================================
# ROUTING MODES
# ============================================================================

class ConversationMode:
    """Conversation flow modes."""
    EMERGENCY = "emergency"           # Red flag → immediate triage
    RULE_BASED = "rule_based"         # Predefined questions
    AI_POWERED = "ai_powered"         # Gemini-generated questions
    

# ============================================================================
# MAIN ROUTING FUNCTION
# ============================================================================

def route_conversation(
    light_extraction: Dict,
    transcription_quality: str,
    language: str = "kinyarwanda"
) -> Dict:
    """
    Decide conversation strategy based on patient state and data quality.
    
    Args:
        light_extraction: Result from model_b.extract_light()
            {
                "chief_complaint": str,
                "severity_estimate": int (1-10),
                "red_flags_present": bool,
                "clarity": str ("clear"|"unclear"|"ambiguous")
            }
        
        transcription_quality: From model_a.transcribe()
            "high" | "medium" | "low"
        
        language: "kinyarwanda" or "english"
    
    Returns:
        {
            "mode": str,                    # "emergency" | "rule_based" | "ai_powered"
            "patient_info_questions": [...],  # Always ask these first
            "symptom_questions": [...] | None,  # Predefined or None (use AI)
            "max_turns": int,                # Maximum conversation turns
            "reasoning": str,                 # Why this mode was chosen
            "red_flag_checks": [...],         # Symptom-specific red flags to watch for
        }
    """
    chief_complaint = light_extraction.get("chief_complaint", "unknown")
    severity = light_extraction.get("severity_estimate", 5)
    red_flags = light_extraction.get("red_flags_present", False)
    clarity = light_extraction.get("clarity", "clear")
    
    # Always get patient info questions (asked first)
    patient_info_questions = model_c_rules.get_patient_info_questions(language)
    
    # Get red flag checks for this symptom
    red_flag_checks = model_c_rules.get_red_flag_checks(chief_complaint)
    
    # ========================================================================
    # ROUTE 1: EMERGENCY (Red Flags)
    # ========================================================================
    if red_flags:
        return {
            "mode": ConversationMode.EMERGENCY,
            "patient_info_questions": patient_info_questions,
            "symptom_questions": None,  # Skip questions, go straight to triage
            "max_turns": 0,  # No conversation, immediate triage
            "reasoning": "Red flag detected - immediate triage required",
            "red_flag_checks": red_flag_checks
        }
    
    # ========================================================================
    # ROUTE 2: Check if we have question tree for this symptom
    # ========================================================================
    has_tree = model_c_rules.has_question_tree(chief_complaint)
    
    if not has_tree:
        # Unknown symptom → Always use AI
        return {
            "mode": ConversationMode.AI_POWERED,
            "patient_info_questions": patient_info_questions,
            "symptom_questions": None,  # AI will generate
            "max_turns": 5,
            "reasoning": f"Unknown symptom '{chief_complaint}' - using AI conversation",
            "red_flag_checks": []
        }
    
    # ========================================================================
    # ROUTE 3: Decide between RULE_BASED and AI_POWERED
    # ========================================================================
    
    # Factors that favor AI:
    use_ai_reasons = []
    
    # 1. High severity
    if severity >= HIGH_SEVERITY_THRESHOLD:
        use_ai_reasons.append(f"high severity ({severity}/10)")
    
    # 2. Poor transcription quality
    if transcription_quality == "low":
        use_ai_reasons.append("low transcription quality")
    
    # 3. Unclear/ambiguous transcription
    if clarity in ["unclear", "ambiguous"]:
        use_ai_reasons.append(f"transcription clarity: {clarity}")
    
    # 4. Medium quality + medium severity (borderline, play safe)
    if transcription_quality == "medium" and severity == HIGH_SEVERITY_THRESHOLD:
        use_ai_reasons.append("borderline case (medium quality + threshold severity)")
    
    # ========================================================================
    # Final decision
    # ========================================================================
    if use_ai_reasons:
        # Use AI-powered conversation (safer for complex/unclear cases)
        return {
            "mode": ConversationMode.AI_POWERED,
            "patient_info_questions": patient_info_questions,
            "symptom_questions": None,  # Model C will generate
            "max_turns": 5,
            "reasoning": "Using AI: " + "; ".join(use_ai_reasons),
            "red_flag_checks": red_flag_checks
        }
    else:
        # Use rule-based questions (fast and cheap)
        symptom_questions = model_c_rules.get_symptom_questions(chief_complaint, language)
        
        return {
            "mode": ConversationMode.RULE_BASED,
            "patient_info_questions": patient_info_questions,
            "symptom_questions": symptom_questions,
            "max_turns": len(patient_info_questions) + len(symptom_questions) if symptom_questions else 3,
            "reasoning": f"Known symptom '{chief_complaint}', low severity ({severity}/10), good quality",
            "red_flag_checks": red_flag_checks
        }


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def should_use_ai(
    chief_complaint: str,
    severity: int,
    clarity: str,
    transcription_quality: str
) -> bool:
    """
    Quick check: Should this case use AI-powered conversation?
    
    Args:
        chief_complaint: Normalized chief complaint
        severity: 1-10 scale
        clarity: "clear" | "unclear" | "ambiguous"
        transcription_quality: "high" | "medium" | "low"
    
    Returns:
        True if AI conversation recommended, False if rule-based is safe
    """
    # Unknown symptom → AI
    if not model_c_rules.has_question_tree(chief_complaint):
        return True
    
    # High severity → AI
    if severity >= HIGH_SEVERITY_THRESHOLD:
        return True
    
    # Poor quality → AI
    if transcription_quality == "low" or clarity in ["unclear", "ambiguous"]:
        return True
    
    # Otherwise, rule-based is fine
    return False


def get_conversation_strategy(routing_result: Dict) -> Dict:
    """
    Get detailed execution strategy from routing decision.
    
    Args:
        routing_result: Output from route_conversation()
    
    Returns:
        {
            "total_questions": int,
            "question_sources": {...},
            "expected_api_calls": int,
            "estimated_cost": float,
            "conversation_flow": [...]
        }
    """
    mode = routing_result["mode"]
    patient_info_q = routing_result.get("patient_info_questions", [])
    symptom_q = routing_result.get("symptom_questions", [])
    
    # Calculate expected API calls
    if mode == ConversationMode.EMERGENCY:
        # Emergency: light extract (1) + triage (4) = 5
        api_calls = 5
    elif mode == ConversationMode.RULE_BASED:
        # Rule: light extract (1) + full extract (1) + triage (4) = 6
        api_calls = 6
    else:  # AI_POWERED
        # AI: light extract (1) + AI questions (4) + full extract (1) + triage (4) = 10
        api_calls = 10
    
    # Estimate cost (Gemini Flash: ~$0.0004 per call average)
    estimated_cost = api_calls * 0.0004
    
    # Build conversation flow
    flow = []
    if patient_info_q:
        flow.append({"step": "patient_info", "questions": len(patient_info_q), "source": "predefined"})
    
    if mode == ConversationMode.RULE_BASED and symptom_q:
        flow.append({"step": "symptom_questions", "questions": len(symptom_q), "source": "predefined"})
    elif mode == ConversationMode.AI_POWERED:
        flow.append({"step": "symptom_questions", "questions": "4-5", "source": "AI-generated"})
    
    if mode != ConversationMode.EMERGENCY:
        flow.append({"step": "extraction", "source": "Model B full"})
    
    flow.append({"step": "triage", "source": "Models D/E/F"})
    
    return {
        "total_questions": len(patient_info_q) + (len(symptom_q) if symptom_q else 4),
        "question_sources": {
            "patient_info": "predefined",
            "symptoms": "predefined" if mode == ConversationMode.RULE_BASED else "AI"
        },
        "expected_api_calls": api_calls,
        "estimated_cost_usd": estimated_cost,
        "conversation_flow": flow
    }


def format_routing_report(routing_result: Dict) -> str:
    """
    Format routing decision as human-readable report.
    
    Args:
        routing_result: Output from route_conversation()
    
    Returns:
        Formatted string report
    """
    mode = routing_result["mode"]
    reasoning = routing_result["reasoning"]
    max_turns = routing_result["max_turns"]
    
    strategy = get_conversation_strategy(routing_result)
    
    report = f"""
╔══════════════════════════════════════════════════════════════════╗
║                    CONVERSATION ROUTING DECISION                  ║
╠══════════════════════════════════════════════════════════════════╣
║ Mode: {mode.upper():58s} ║
║ Reasoning: {reasoning[:56]:56s} ║
║ Max Turns: {max_turns:55d} ║
╠══════════════════════════════════════════════════════════════════╣
║ Patient Info Questions: {len(routing_result['patient_info_questions']):44d} ║
║ Symptom Questions: {'Predefined' if routing_result['symptom_questions'] else 'AI-Generated':49s} ║
║ Expected API Calls: {strategy['expected_api_calls']:48d} ║
║ Estimated Cost: ${strategy['estimated_cost_usd']:.4f:48s} ║
╚══════════════════════════════════════════════════════════════════╝
"""
    return report


# ============================================================================
# MONITORING & ANALYTICS
# ============================================================================

_ROUTING_DECISIONS = []

def log_routing_decision(routing_result: Dict, session_id: str = None):
    """
    Log routing decision for analytics.
    
    Args:
        routing_result: Output from route_conversation()
        session_id: Optional session identifier
    """
    from datetime import datetime
    
    entry = {
        "session_id": session_id,
        "timestamp": datetime.now().isoformat(),
        "mode": routing_result["mode"],
        "reasoning": routing_result["reasoning"],
        **get_conversation_strategy(routing_result)
    }
    
    _ROUTING_DECISIONS.append(entry)
    
    # In production, write to database
    print(f"[ROUTING] {routing_result['mode'].upper()}: {routing_result['reasoning']}")


def get_routing_statistics() -> Dict:
    """
    Get statistics about routing decisions.
    
    Returns:
        Dict with routing analytics
    """
    from collections import Counter
    
    if not _ROUTING_DECISIONS:
        return {"total_sessions": 0, "no_data": True}
    
    modes = [d["mode"] for d in _ROUTING_DECISIONS]
    mode_counts = Counter(modes)
    
    total_api_calls = sum(d["expected_api_calls"] for d in _ROUTING_DECISIONS)
    total_cost = sum(d["estimated_cost_usd"] for d in _ROUTING_DECISIONS)
    
    return {
        "total_sessions": len(_ROUTING_DECISIONS),
        "mode_distribution": dict(mode_counts),
        "total_api_calls": total_api_calls,
        "total_cost_usd": total_cost,
        "avg_api_calls_per_session": total_api_calls / len(_ROUTING_DECISIONS),
        "avg_cost_per_session": total_cost / len(_ROUTING_DECISIONS)
    }


if __name__ == "__main__":
    # Test the routing logic
    print("=" * 70)
    print("CONVERSATION ROUTER - Testing")
    print("=" * 70)
    
    # Test case 1: Low severity headache, good quality
    print("\n🧪 Test 1: Low severity headache, high quality transcription")
    result1 = route_conversation(
        light_extraction={
            "chief_complaint": "headache",
            "severity_estimate": 4,
            "red_flags_present": False,
            "clarity": "clear"
        },
        transcription_quality="high",
        language="kinyarwanda"
    )
    print(format_routing_report(result1))
    
    # Test case 2: High severity stomach pain
    print("\n🧪 Test 2: High severity stomach pain")
    result2 = route_conversation(
        light_extraction={
            "chief_complaint": "stomach_pain",
            "severity_estimate": 8,
            "red_flags_present": False,
            "clarity": "clear"
        },
        transcription_quality="high",
        language="english"
    )
    print(format_routing_report(result2))
    
    # Test case 3: Red flag case
    print("\n🧪 Test 3: Emergency - Red flag detected")
    result3 = route_conversation(
        light_extraction={
            "chief_complaint": "chest_pain",
            "severity_estimate": 9,
            "red_flags_present": True,
            "clarity": "clear"
        },
        transcription_quality="high",
        language="kinyarwanda"
    )
    print(format_routing_report(result3))
    
    # Test case 4: Unknown symptom
    print("\n🧪 Test 4: Unknown symptom")
    result4 = route_conversation(
        light_extraction={
            "chief_complaint": "weird_rash",
            "severity_estimate": 5,
            "red_flags_present": False,
            "clarity": "unclear"
        },
        transcription_quality="medium",
        language="english"
    )
    print(format_routing_report(result4))
    
    # Show statistics
    for result in [result1, result2, result3, result4]:
        log_routing_decision(result)
    
    print("\n📊 Routing Statistics:")
    stats = get_routing_statistics()
    print(f"   Total sessions: {stats['total_sessions']}")
    print(f"   Mode distribution: {stats['mode_distribution']}")
    print(f"   Avg API calls: {stats['avg_api_calls_per_session']:.1f}")
    print(f"   Avg cost: ${stats['avg_cost_per_session']:.4f}")
