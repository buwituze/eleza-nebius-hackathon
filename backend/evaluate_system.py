"""
evaluate_system.py — Standalone system accuracy evaluator.

Connects directly to the database, pulls completed sessions and their
conversation turns, then scores the system on:

  1. Question Relevance   (Gemini-as-judge, 1-5 per turn)
  2. Information Gain     (did each turn surface new clinical info?)
  3. Coverage Rate        (% of key clinical fields filled)
  4. Turn Efficiency      (how many turns to reach coverage)
  5. Routing Accuracy     (was the routing decision appropriate?)

Usage:
    cd backend
    python evaluate_system.py            # evaluate all completed sessions
    python evaluate_system.py --limit 5  # evaluate last 5 sessions
"""

import os, sys, json, re, argparse
from datetime import datetime
from dotenv import load_dotenv

# Load env from backend/.env
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

import psycopg2
from psycopg2.extras import RealDictCursor
from google import genai
from models.gemini_utils import generate_with_fallback

# ============================================================================
# DB CONNECTION
# ============================================================================

def _connect():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        database=os.getenv("DB_NAME", "pre_consultation_db"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", ""),
        cursor_factory=RealDictCursor,
    )


# ============================================================================
# GEMINI CLIENT
# ============================================================================

_client = None

def _get_client():
    global _client
    if _client is None:
        _client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    return _client


# ============================================================================
# DATA LOADING
# ============================================================================

def load_sessions(conn, limit=None):
    """Load completed sessions that have conversation messages."""
    query = """
        SELECT s.session_id, s.patient_id, s.status,
               s.conversation_mode, s.chief_complaint,
               s.severity_estimate, s.red_flags_detected,
               s.transcription_quality, s.routing_reasoning,
               s.api_calls_count, s.cost_estimate,
               s.patient_age, s.patient_gender,
               s.start_time, s.end_time,
               s.prediction_label, s.prediction_confidence
        FROM session s
        WHERE s.status IN ('completed', 'awaiting_review')
          AND EXISTS (
              SELECT 1 FROM conversation_message cm
              WHERE cm.session_id = s.session_id
          )
        ORDER BY s.start_time DESC
    """
    if limit:
        query += f" LIMIT {int(limit)}"

    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchall()


def load_conversation(conn, session_id):
    """Load conversation turns for a session, paired as Q/A."""
    query = """
        SELECT message_id, sender_type, message_text, sequence_number, metadata
        FROM conversation_message
        WHERE session_id = %s
        ORDER BY sequence_number ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, (session_id,))
        messages = cur.fetchall()

    # Pair ml_system (question) with patient (answer)
    turns = []
    i = 0
    while i < len(messages):
        msg = messages[i]
        if msg["sender_type"] == "ml_system":
            question = msg["message_text"]
            answer = ""
            if i + 1 < len(messages) and messages[i + 1]["sender_type"] == "patient":
                answer = messages[i + 1]["message_text"]
                i += 2
            else:
                i += 1
            turns.append({"question": question, "answer": answer})
        elif msg["sender_type"] == "patient" and not turns:
            # First message is patient's initial complaint (transcript)
            turns.append({"question": "(initial complaint)", "answer": msg["message_text"]})
            i += 1
        else:
            i += 1

    return turns


def load_symptoms(conn, session_id):
    """Load extracted symptoms for a session."""
    query = """
        SELECT symptom_name, severity, duration, additional_info
        FROM symptom
        WHERE session_id = %s
    """
    with conn.cursor() as cur:
        cur.execute(query, (session_id,))
        return cur.fetchall()


def load_prediction(conn, session_id):
    """Load prediction for a session."""
    query = """
        SELECT predicted_condition, risk_level, confidence_score
        FROM prediction
        WHERE session_id = %s
    """
    with conn.cursor() as cur:
        cur.execute(query, (session_id,))
        return cur.fetchone()


# ============================================================================
# METRIC 1: QUESTION RELEVANCE (Gemini-as-judge)
# ============================================================================

def evaluate_relevance(chief_complaint, turns):
    """Rate each question's relevance to the patient's complaint (1-5)."""
    if not turns or not chief_complaint:
        return [{"turn": i+1, "score": 3, "reason": "no data"} for i in range(len(turns))]

    turns_text = "\n".join(
        f"Turn {i+1}:\n  Q: {t['question']}\n  A: {t['answer']}"
        for i, t in enumerate(turns)
    )

    prompt = f"""You are evaluating a medical pre-consultation chatbot.
The patient's chief complaint is: "{chief_complaint}"

Here is the conversation:
{turns_text}

For EACH turn, rate how relevant the question is to the patient's medical situation.
Score 1-5:
  1 = Completely irrelevant (random or off-topic)
  2 = Loosely related but not useful
  3 = Somewhat relevant, generic but acceptable (e.g. asking patient info)
  4 = Relevant and purposeful
  5 = Highly relevant, directly addresses a clinical gap

Respond ONLY with valid JSON — an array of objects, one per turn:
[{{"turn": 1, "score": 4, "reason": "Asks about duration which is clinically important"}}, ...]

No markdown, no explanation outside the JSON."""

    try:
        response = generate_with_fallback(
            _get_client(),
            contents=prompt,
            config={"temperature": 0.1, "max_output_tokens": 1000,
                     "thinking_config": {"thinking_budget": 0}},
        )
        text = response.text.strip()
        text = re.sub(r'^```(?:json)?\s*', '', text)
        text = re.sub(r'\s*```$', '', text)
        return json.loads(text)
    except Exception as e:
        print(f"  [!] Relevance eval failed: {e}")
        return [{"turn": i+1, "score": 3, "reason": "evaluation failed"} for i in range(len(turns))]


# ============================================================================
# METRIC 2: INFORMATION GAIN (Gemini checks per-turn field coverage)
# ============================================================================

KEY_FIELDS = [
    "chief_complaint", "severity", "duration", "associated_symptoms",
    "progression", "body_part", "patient_name", "patient_age", "patient_gender",
]

def evaluate_information_gain(chief_complaint, turns):
    """Determine which clinical fields each turn helped fill."""
    if not turns:
        return []

    turns_text = ""
    for i, t in enumerate(turns):
        turns_text += f"\nTurn {i+1}:\n  Q: {t['question']}\n  A: {t['answer']}"

    prompt = f"""You are evaluating a medical pre-consultation conversation.
Chief complaint: "{chief_complaint or 'unknown'}"

Conversation:{turns_text}

Clinical fields to track: {json.dumps(KEY_FIELDS)}

For each turn (1 to {len(turns)}), list which NEW fields were first revealed in that turn's answer.
A field counts as "gained" only the first time it appears.

Respond ONLY with valid JSON:
[{{"turn": 1, "new_fields": ["chief_complaint", "body_part"]}}, ...]

No markdown, no explanation outside the JSON."""

    try:
        response = generate_with_fallback(
            _get_client(),
            contents=prompt,
            config={"temperature": 0.1, "max_output_tokens": 800,
                     "thinking_config": {"thinking_budget": 0}},
        )
        text = response.text.strip()
        text = re.sub(r'^```(?:json)?\s*', '', text)
        text = re.sub(r'\s*```$', '', text)
        return json.loads(text)
    except Exception as e:
        print(f"  [!] Info gain eval failed: {e}")
        return [{"turn": i+1, "new_fields": []} for i in range(len(turns))]


# ============================================================================
# METRIC 3: COVERAGE RATE
# ============================================================================

def compute_coverage(session, symptoms, prediction):
    """What % of key data points does the system have for this session."""
    filled = 0
    total = len(KEY_FIELDS)

    checks = {
        "chief_complaint": bool(session.get("chief_complaint")),
        "severity": bool(session.get("severity_estimate")),
        "duration": any(s.get("duration") for s in symptoms) if symptoms else False,
        "associated_symptoms": len(symptoms) > 1 if symptoms else False,
        "progression": False,  # Not stored in DB directly
        "body_part": False,    # Not stored in DB directly
        "patient_name": bool(session.get("patient_id")),  # patient exists
        "patient_age": bool(session.get("patient_age")),
        "patient_gender": bool(session.get("patient_gender")),
    }

    filled = sum(1 for v in checks.values() if v)
    return {
        "covered": [k for k, v in checks.items() if v],
        "missing": [k for k, v in checks.items() if not v],
        "rate": filled / total if total else 0,
    }


# ============================================================================
# METRIC 4: ROUTING ACCURACY
# ============================================================================

def evaluate_routing(session):
    """Check if the routing decision made sense."""
    mode = session.get("conversation_mode")
    severity = session.get("severity_estimate") or 0
    red_flags = session.get("red_flags_detected", False)
    quality = session.get("transcription_quality", "")

    if not mode:
        return {"appropriate": None, "reason": "no routing mode recorded"}

    if mode == "emergency":
        if red_flags:
            return {"appropriate": True, "reason": "Correct: red flags → emergency"}
        return {"appropriate": False, "reason": "Emergency but no red flags"}

    if mode == "rule_based":
        issues = []
        if red_flags:
            issues.append("red flags present")
        if severity and severity >= 5:
            issues.append(f"severity {severity}/10")
        if quality == "low":
            issues.append("low transcription quality")
        if issues:
            return {"appropriate": False, "reason": f"Rule-based but: {', '.join(issues)}"}
        return {"appropriate": True, "reason": "Correct: known symptom, low severity, good quality"}

    if mode == "ai_powered":
        if red_flags:
            return {"appropriate": False, "reason": "AI-powered but red flags (should be emergency)"}
        return {"appropriate": True, "reason": "Correct: AI for complex/unknown case"}

    return {"appropriate": None, "reason": f"Unknown mode: {mode}"}


# ============================================================================
# EVALUATE ONE SESSION
# ============================================================================

def evaluate_session(conn, session):
    sid = session["session_id"]
    complaint = session.get("chief_complaint") or "unknown"

    turns = load_conversation(conn, sid)
    symptoms = load_symptoms(conn, sid)
    prediction = load_prediction(conn, sid)

    # Skip sessions with no real conversation
    if len(turns) < 2:
        return {
            "session_id": sid,
            "skipped": True,
            "reason": f"Only {len(turns)} turn(s) — not enough to evaluate",
        }

    print(f"  Evaluating session {sid} ({complaint}, {len(turns)} turns)...")

    # 1. Relevance
    relevance = evaluate_relevance(complaint, turns)
    scores = [r.get("score", 3) for r in relevance]
    avg_relevance = sum(scores) / len(scores) if scores else 0

    # 2. Information gain
    gain = evaluate_information_gain(complaint, turns)
    turns_with_gain = sum(1 for g in gain if g.get("new_fields"))
    gain_rate = turns_with_gain / len(turns) if turns else 0

    # 3. Coverage
    coverage = compute_coverage(session, symptoms, prediction)

    # 4. Routing
    routing = evaluate_routing(session)

    # 5. Composite score (0-100)
    relevance_pct = (avg_relevance / 5.0) * 100
    gain_pct = gain_rate * 100
    coverage_pct = coverage["rate"] * 100
    routing_pct = 100 if routing["appropriate"] else (50 if routing["appropriate"] is None else 0)

    system_score = (
        relevance_pct * 0.35
        + gain_pct * 0.25
        + coverage_pct * 0.25
        + routing_pct * 0.15
    )

    return {
        "session_id": sid,
        "chief_complaint": complaint,
        "conversation_mode": session.get("conversation_mode"),
        "total_turns": len(turns),
        "avg_relevance": round(avg_relevance, 2),
        "information_gain_rate": round(gain_rate, 2),
        "coverage_rate": round(coverage["rate"], 2),
        "fields_covered": coverage["covered"],
        "fields_missing": coverage["missing"],
        "routing_appropriate": routing["appropriate"],
        "routing_reason": routing["reason"],
        "system_score": round(system_score, 1),
        "turn_details": [
            {
                "turn": i + 1,
                "question": turns[i]["question"][:80],
                "answer": turns[i]["answer"][:80],
                "relevance": relevance[i].get("score", "?") if i < len(relevance) else "?",
                "relevance_reason": relevance[i].get("reason", "") if i < len(relevance) else "",
                "new_fields": gain[i].get("new_fields", []) if i < len(gain) else [],
            }
            for i in range(len(turns))
        ],
    }


# ============================================================================
# PRINT REPORT
# ============================================================================

def print_report(results):
    valid = [r for r in results if not r.get("skipped")]
    skipped = [r for r in results if r.get("skipped")]

    print("\n" + "=" * 70)
    print("           SYSTEM ACCURACY EVALUATION REPORT")
    print("=" * 70)

    if not valid:
        print("\n  No sessions with enough data to evaluate.")
        if skipped:
            print(f"  ({len(skipped)} sessions skipped — too few turns)")
        return

    # Aggregate
    avg_score = sum(r["system_score"] for r in valid) / len(valid)
    avg_rel = sum(r["avg_relevance"] for r in valid) / len(valid)
    avg_gain = sum(r["information_gain_rate"] for r in valid) / len(valid)
    avg_cov = sum(r["coverage_rate"] for r in valid) / len(valid)
    routing_ok = sum(1 for r in valid if r["routing_appropriate"] is True)
    routing_total = sum(1 for r in valid if r["routing_appropriate"] is not None)
    avg_turns = sum(r["total_turns"] for r in valid) / len(valid)

    print(f"""
  Sessions evaluated:  {len(valid)}
  Sessions skipped:    {len(skipped)}

  +-------------------------------------------------+
  |  AGGREGATE METRICS                              |
  +-------------------------------------------------+
  |  System Score:          {avg_score:>5.1f} / 100             |
  |  Question Relevance:    {avg_rel:>4.2f} / 5.00             |
  |  Information Gain:      {avg_gain*100:>5.1f}%                    |
  |  Clinical Coverage:     {avg_cov*100:>5.1f}%                    |
  |  Routing Accuracy:      {routing_ok}/{routing_total} ({routing_ok/routing_total*100 if routing_total else 0:.0f}%)                  |
  |  Avg Turns / Session:   {avg_turns:>5.1f}                    |
  +-------------------------------------------------+
  |  WEIGHTS: Relevance 35% | Gain 25%              |
  |           Coverage 25%  | Routing 15%            |
  +-------------------------------------------------+
""")

    # Per-session
    for r in valid:
        mode = r["conversation_mode"] or "?"
        route_mark = "OK" if r["routing_appropriate"] else ("?" if r["routing_appropriate"] is None else "MISS")
        print(f"  --- Session {r['session_id']} ---")
        print(f"      Complaint: {r['chief_complaint']}  |  Mode: {mode}  |  Routing: {route_mark}")
        print(f"      Score: {r['system_score']}/100  |  Relevance: {r['avg_relevance']}/5  |  Gain: {r['information_gain_rate']*100:.0f}%  |  Coverage: {r['coverage_rate']*100:.0f}%")
        print(f"      Covered: {', '.join(r['fields_covered']) or 'none'}")
        print(f"      Missing: {', '.join(r['fields_missing']) or 'none'}")

        for td in r["turn_details"]:
            gain_mark = " +" + ",".join(td["new_fields"]) if td["new_fields"] else ""
            print(f"        T{td['turn']:d} [{td['relevance']}/5] Q: {td['question'][:55]}{gain_mark}")

        print()

    if skipped:
        print(f"  Skipped {len(skipped)} session(s) with < 2 turns.")


# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="Evaluate system accuracy from DB")
    parser.add_argument("--limit", type=int, default=None,
                        help="Max sessions to evaluate (default: all)")
    parser.add_argument("--json", action="store_true",
                        help="Output raw JSON instead of formatted report")
    args = parser.parse_args()

    print("Connecting to database...")
    conn = _connect()

    try:
        sessions = load_sessions(conn, limit=args.limit)
        print(f"Found {len(sessions)} completed session(s) with conversations.\n")

        if not sessions:
            print("No completed sessions to evaluate.")
            return

        results = []
        for session in sessions:
            result = evaluate_session(conn, session)
            results.append(result)

        if args.json:
            print(json.dumps(results, indent=2, default=str))
        else:
            print_report(results)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
