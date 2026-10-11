"""
utils/session_logger.py — Session logging and analytics for the new system.

Purpose:
- Track conversation modes used
- Monitor API call counts and costs
- Log unknown symptoms for expansion
- Generate analytics for optimization
"""

import json
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from collections import Counter, defaultdict

# ============================================================================
# IN-MEMORY LOGGING (for development/testing)
# In production, replace with database queries
# ============================================================================

_SESSION_LOG = []
_UNKNOWN_SYMPTOMS_LOG = []

# ============================================================================
# SESSION LOGGING
# ============================================================================

def log_session(session_data: Dict):
    """
    Log a completed session for analytics.
    
    Args:
        session_data: {
            "session_id": str,
            "patient_id": int,
            "conversation_mode": str,
            "chief_complaint": str,
            "severity_estimate": int,
            "red_flags_detected": bool,
            "transcription_quality": str,
            "api_calls_count": int,
            "cost_estimate": float,
            "routing_reasoning": str,
            "timestamp": str (ISO format),
            "patient_age": int | None,
            "patient_gender": str | None
        }
    """
    _SESSION_LOG.append(session_data)
    
    # Log if unknown symptom
    if session_data.get("conversation_mode") == "ai_powered" and \
       "unknown" in session_data.get("routing_reasoning", "").lower():
        log_unknown_symptom(session_data["chief_complaint"], session_data["session_id"])
    
    print(f"[SESSION] Logged: {session_data['session_id']} - "
          f"{session_data['conversation_mode']} - "
          f"{session_data['chief_complaint']}")


def log_unknown_symptom(complaint: str, session_id: str = None):
    """
    Log an unknown symptom for future expansion.
    
    Args:
        complaint: The complaint that wasn't in question trees
        session_id: Optional session ID for tracking
    """
    _UNKNOWN_SYMPTOMS_LOG.append({
        "complaint": complaint.lower().strip(),
        "session_id": session_id,
        "timestamp": datetime.now().isoformat()
    })
    
    print(f"[EXPANSION] Unknown symptom: '{complaint}' (session: {session_id})")


# ============================================================================
# ANALYTICS & REPORTING
# ============================================================================

def get_session_statistics(days: int = 30) -> Dict:
    """
    Get session statistics for the specified time period.
    
    Args:
        days: Number of days to analyze (default: 30)
    
    Returns:
        Dict with comprehensive statistics
    """
    if not _SESSION_LOG:
        return {"error": "No sessions logged yet"}
    
    # Filter by date
    cutoff = datetime.now() - timedelta(days=days)
    recent_sessions = [
        s for s in _SESSION_LOG
        if datetime.fromisoformat(s["timestamp"]) >= cutoff
    ]
    
    if not recent_sessions:
        return {"error": f"No sessions in last {days} days"}
    
    # Calculate statistics
    modes = [s["conversation_mode"] for s in recent_sessions]
    mode_counts = Counter(modes)
    
    complaints = [s["chief_complaint"] for s in recent_sessions]
    complaint_counts = Counter(complaints)
    
    total_api_calls = sum(s["api_calls_count"] for s in recent_sessions)
    total_cost = sum(s["cost_estimate"] for s in recent_sessions)
    
    red_flag_count = sum(1 for s in recent_sessions if s.get("red_flags_detected", False))
    
    # Severity distribution
    severities = [s["severity_estimate"] for s in recent_sessions if s.get("severity_estimate")]
    avg_severity = sum(severities) / len(severities) if severities else 0
    
    return {
        "period_days": days,
        "total_sessions": len(recent_sessions),
        "mode_distribution": dict(mode_counts),
        "mode_percentages": {
            mode: (count / len(recent_sessions)) * 100
            for mode, count in mode_counts.items()
        },
        "top_complaints": complaint_counts.most_common(10),
        "total_api_calls": total_api_calls,
        "avg_api_calls_per_session": total_api_calls / len(recent_sessions),
        "total_cost_usd": total_cost,
        "avg_cost_per_session_usd": total_cost / len(recent_sessions),
        "red_flag_sessions": red_flag_count,
        "red_flag_percentage": (red_flag_count / len(recent_sessions)) * 100,
        "avg_severity": avg_severity,
        "quality_distribution": Counter(
            s["transcription_quality"] for s in recent_sessions
            if s.get("transcription_quality")
        )
    }


def get_unknown_symptoms_report(min_occurrences: int = 3) -> Dict:
    """
    Get report of unknown symptoms for expansion planning.
    
    Args:
        min_occurrences: Minimum number of times a symptom must appear
                        to be considered for expansion (default: 3)
    
    Returns:
        Dict with unknown symptom analysis
    """
    if not _UNKNOWN_SYMPTOMS_LOG:
        return {"message": "No unknown symptoms logged yet"}
    
    complaints = [entry["complaint"] for entry in _UNKNOWN_SYMPTOMS_LOG]
    counts = Counter(complaints)
    
    # Filter by minimum occurrences
    expansion_candidates = [
        (symptom, count) for symptom, count in counts.most_common()
        if count >= min_occurrences
    ]
    
    return {
        "total_unknown_encounters": len(_UNKNOWN_SYMPTOMS_LOG),
        "unique_symptoms": len(counts),
        "top_10_unknown": counts.most_common(10),
        "expansion_candidates": expansion_candidates,
        "recommendation": f"Consider adding question trees for: {', '.join(s for s, c in expansion_candidates[:3])}"
            if expansion_candidates else "No symptoms meet minimum occurrence threshold yet"
    }


def get_cost_analysis(days: int = 30) -> Dict:
    """
    Analyze API costs and potential savings.
    
    Args:
        days: Number of days to analyze
    
    Returns:
        Cost breakdown and comparison
    """
    if not _SESSION_LOG:
        return {"error": "No data available"}
    
    stats = get_session_statistics(days)
    
    # Calculate what cost would have been if all AI-powered
    total_sessions = stats["total_sessions"]
    all_ai_cost = total_sessions * 0.0052  # Assuming 13 API calls @ $0.0004 each
    actual_cost = stats["total_cost_usd"]
    savings = all_ai_cost - actual_cost
    savings_percentage = (savings / all_ai_cost) * 100 if all_ai_cost > 0 else 0
    
    # Cost by mode
    mode_costs = defaultdict(float)
    mode_sessions = defaultdict(int)
    
    cutoff = datetime.now() - timedelta(days=days)
    for session in _SESSION_LOG:
        if datetime.fromisoformat(session["timestamp"]) >= cutoff:
            mode = session["conversation_mode"]
            mode_costs[mode] += session["cost_estimate"]
            mode_sessions[mode] += 1
    
    avg_cost_by_mode = {
        mode: mode_costs[mode] / mode_sessions[mode]
        for mode in mode_costs
        if mode_sessions[mode] > 0
    }
    
    return {
        "period_days": days,
        "total_sessions": total_sessions,
        "actual_total_cost_usd": actual_cost,
        "all_ai_cost_would_be_usd": all_ai_cost,
        "savings_usd": savings,
        "savings_percentage": savings_percentage,
        "avg_cost_per_session": {
            "actual": stats["avg_cost_per_session_usd"],
            "if_all_ai": 0.0052
        },
        "cost_by_mode": dict(mode_costs),
        "avg_cost_by_mode": avg_cost_by_mode,
        "projection_monthly": {
            "actual": actual_cost * (30 / days),
            "all_ai": all_ai_cost * (30 / days),
            "monthly_savings": savings * (30 / days)
        }
    }


def generate_expansion_report() -> str:
    """
    Generate human-readable expansion planning report.
    
    Returns:
        Formatted report string
    """
    unknown_report = get_unknown_symptoms_report()
    
    if "message" in unknown_report:
        return "📊 No data yet for expansion planning."
    
    report = f"""
╔══════════════════════════════════════════════════════════════════╗
║               SYMPTOM COVERAGE EXPANSION REPORT                   ║
╠══════════════════════════════════════════════════════════════════╣
║ Total unknown symptom encounters: {unknown_report['total_unknown_encounters']:31d} ║
║ Unique unknown symptoms: {unknown_report['unique_symptoms']:41d} ║
╠══════════════════════════════════════════════════════════════════╣
║ TOP 10 UNKNOWN SYMPTOMS:                                         ║
"""
    
    for i, (symptom, count) in enumerate(unknown_report['top_10_unknown'], 1):
        report += f"║ {i:2d}. {symptom[:45]:45s} ({count:3d} times) ║\n"
    
    report += "╠══════════════════════════════════════════════════════════════════╣\n"
    report += f"║ EXPANSION CANDIDATES (≥3 occurrences):                          ║\n"
    
    if unknown_report['expansion_candidates']:
        for symptom, count in unknown_report['expansion_candidates'][:5]:
            report += f"║   • {symptom[:50]:50s} ({count:2d}x) ║\n"
    else:
        report += "║   None yet - need more data                                     ║\n"
    
    report += "╠══════════════════════════════════════════════════════════════════╣\n"
    report += f"║ RECOMMENDATION:                                                  ║\n"
    report += f"║ {unknown_report['recommendation'][:64]:64s} ║\n"
    report += "╚══════════════════════════════════════════════════════════════════╝"
    
    return report


def generate_performance_report(days: int = 7) -> str:
    """
    Generate human-readable performance report.
    
    Args:
        days: Number of days to analyze
    
    Returns:
        Formatted report string
    """
    stats = get_session_statistics(days)
    cost_analysis = get_cost_analysis(days)
    
    if "error" in stats:
        return f"📊 No data available for last {days} days."
    
    report = f"""
╔══════════════════════════════════════════════════════════════════╗
║                  SYSTEM PERFORMANCE REPORT                        ║
║                  Last {days:2d} days                                       ║
╠══════════════════════════════════════════════════════════════════╣
║ SESSIONS:                                                         ║
║   Total: {stats['total_sessions']:58d} ║
║   Red Flags: {stats['red_flag_sessions']:52d} ({stats['red_flag_percentage']:.1f}%) ║
║   Average Severity: {stats['avg_severity']:46.1f}/10 ║
╠══════════════════════════════════════════════════════════════════╣
║ ROUTING MODES:                                                    ║
║   Emergency: {stats['mode_distribution'].get('emergency', 0):52d} ({stats['mode_percentages'].get('emergency', 0):5.1f}%) ║
║   Rule-Based: {stats['mode_distribution'].get('rule_based', 0):51d} ({stats['mode_percentages'].get('rule_based', 0):5.1f}%) ║
║   AI-Powered: {stats['mode_distribution'].get('ai_powered', 0):51d} ({stats['mode_percentages'].get('ai_powered', 0):5.1f}%) ║
╠══════════════════════════════════════════════════════════════════╣
║ API USAGE:                                                        ║
║   Total API Calls: {stats['total_api_calls']:47d} ║
║   Avg per Session: {stats['avg_api_calls_per_session']:47.1f} ║
╠══════════════════════════════════════════════════════════════════╣
║ COSTS:                                                            ║
║   Total Cost: ${stats['total_cost_usd']:52.4f} ║
║   Avg Cost/Session: ${stats['avg_cost_per_session_usd']:44.4f} ║
║   If All AI: ${cost_analysis['all_ai_cost_would_be_usd']:53.4f} ║
║   SAVINGS: ${cost_analysis['savings_usd']:55.4f} ({cost_analysis['savings_percentage']:.1f}%) ║
╠══════════════════════════════════════════════════════════════════╣
║ MONTHLY PROJECTION:                                               ║
║   Current Rate: ${cost_analysis['projection_monthly']['actual']:47.2f}/month ║
║   All-AI Rate: ${cost_analysis['projection_monthly']['all_ai']:48.2f}/month ║
║   Savings: ${cost_analysis['projection_monthly']['monthly_savings']:53.2f}/month ║
╚══════════════════════════════════════════════════════════════════╝
"""
    
    return report


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def clear_logs():
    """Clear all in-memory logs (for testing)."""
    global _SESSION_LOG, _UNKNOWN_SYMPTOMS_LOG
    _SESSION_LOG = []
    _UNKNOWN_SYMPTOMS_LOG = []
    print("[SESSION] Logs cleared")


def export_logs(filepath: str):
    """
    Export logs to JSON file.
    
    Args:
        filepath: Path to save JSON file
    """
    data = {
        "sessions": _SESSION_LOG,
        "unknown_symptoms": _UNKNOWN_SYMPTOMS_LOG,
        "exported_at": datetime.now().isoformat()
    }
    
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print(f"[SESSION] Logs exported to {filepath}")


if __name__ == "__main__":
    # Test the logger
    print("=" * 70)
    print("SESSION LOGGER - Testing")
    print("=" * 70)
    
    # Simulate some sessions
    test_sessions = [
        {
            "session_id": "test_001",
            "patient_id": 1,
            "conversation_mode": "rule_based",
            "chief_complaint": "headache",
            "severity_estimate": 4,
            "red_flags_detected": False,
            "transcription_quality": "high",
            "api_calls_count": 7,
            "cost_estimate": 0.0028,
            "routing_reasoning": "Known symptom, low severity",
            "timestamp": datetime.now().isoformat(),
            "patient_age": 35,
            "patient_gender": "female"
        },
        {
            "session_id": "test_002",
            "patient_id": 2,
            "conversation_mode": "ai_powered",
            "chief_complaint": "stomach_pain",
            "severity_estimate": 8,
            "red_flags_detected": False,
            "transcription_quality": "high",
            "api_calls_count": 10,
            "cost_estimate": 0.0040,
            "routing_reasoning": "High severity (8/10)",
            "timestamp": datetime.now().isoformat(),
            "patient_age": 42,
            "patient_gender": "male"
        },
        {
            "session_id": "test_003",
            "patient_id": 3,
            "conversation_mode": "emergency",
            "chief_complaint": "chest_pain",
            "severity_estimate": 9,
            "red_flags_detected": True,
            "transcription_quality": "high",
            "api_calls_count": 6,
            "cost_estimate": 0.0024,
            "routing_reasoning": "Red flag detected",
            "timestamp": datetime.now().isoformat(),
            "patient_age": 58,
            "patient_gender": "male"
        },
        {
            "session_id": "test_004",
            "patient_id": 4,
            "conversation_mode": "ai_powered",
            "chief_complaint": "weird_rash",
            "severity_estimate": 5,
            "red_flags_detected": False,
            "transcription_quality": "medium",
            "api_calls_count": 10,
            "cost_estimate": 0.0040,
            "routing_reasoning": "Unknown symptom 'weird_rash' - using AI conversation",
            "timestamp": datetime.now().isoformat(),
            "patient_age": 28,
            "patient_gender": "female"
        }
    ]
    
    for session in test_sessions:
        log_session(session)
    
    print("\n" + generate_performance_report(7))
    print("\n" + generate_expansion_report())
