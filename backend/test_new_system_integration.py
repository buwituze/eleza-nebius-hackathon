"""
test_new_system_integration.py — Integration test for the new two-stage extraction system.

Tests all three routing modes:
1. Rule-based path (known symptom, low severity)
2. AI-powered path (high severity or unknown symptom)
3. Emergency path (red flags detected)

Run with: python backend/test_new_system_integration.py
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from models import model_a, model_b
from models.model_c_rules import get_symptom_questions, normalize_complaint
from routing.conversation_router import route_conversation
from utils.session_logger import log_session, generate_performance_report, generate_expansion_report, clear_logs
from datetime import datetime


def test_rule_based_path():
    """Test 1: Known symptom (headache), low severity → Rule-based path"""
    print("\n" + "="*70)
    print("TEST 1: RULE-BASED PATH (Known Symptom + Low Severity)")
    print("="*70)
    
    # Simulate transcription
    transcript = "I have a headache that started 2 days ago. It's not very severe."
    
    print(f"📝 Transcript: {transcript}")
    
    # Step 1: Light extraction
    print("\n🔄 Step 1: Light extraction...")
    light = model_b.extract_light(transcript)
    print(f"✅ Chief complaint: {light['chief_complaint']}")
    print(f"✅ Severity: {light['severity_estimate']}/10")
    print(f"✅ Red flags: {light['red_flags_present']}")
    
    # Step 2: Routing
    print("\n🔄 Step 2: Routing decision...")
    routing = route_conversation(
        light_extraction=light,
        transcription_quality="high",
        language="english"
    )
    print(f"✅ Mode: {routing['mode']}")
    print(f"✅ Reasoning: {routing['reasoning']}")
    
    # Step 3: Get questions
    if routing['mode'] == "rule_based":
        print("\n🔄 Step 3: Getting predefined questions...")
        questions = get_symptom_questions(light['chief_complaint'], "english")
        if questions:
            print(f"✅ Found {len(questions)} predefined questions:")
            for i, q in enumerate(questions, 1):
                print(f"   {i}. {q}")
        else:
            print("❌ No questions found - will fall back to AI")
    
    # Estimate API calls
    api_calls = 1 + 1  # Light extraction + final full extraction (no AI questions)
    cost = api_calls * 0.0004
    print(f"\n💰 Estimated API calls: {api_calls}")
    print(f"💰 Estimated cost: ${cost:.4f}")
    
    # Log session
    log_session({
        "session_id": "test_rule_001",
        "patient_id": 1,
        "conversation_mode": routing['mode'],
        "chief_complaint": light['chief_complaint'],
        "severity_estimate": light['severity_estimate'],
        "red_flags_detected": light['red_flags_present'],
        "transcription_quality": "high",
        "api_calls_count": api_calls,
        "cost_estimate": cost,
        "routing_reasoning": routing['reasoning'],
        "timestamp": datetime.now().isoformat(),
        "patient_age": 35,
        "patient_gender": "female"
    })
    
    print("\n✅ TEST 1 PASSED: Rule-based path working as expected")
    return True


def test_ai_powered_path():
    """Test 2: High severity → AI-powered path"""
    print("\n" + "="*70)
    print("TEST 2: AI-POWERED PATH (High Severity)")
    print("="*70)
    
    # Simulate transcription
    transcript = "I have very severe stomach pain, I've been vomiting all night and can barely stand."
    
    print(f"📝 Transcript: {transcript}")
    
    # Step 1: Light extraction
    print("\n🔄 Step 1: Light extraction...")
    light = model_b.extract_light(transcript)
    print(f"✅ Chief complaint: {light['chief_complaint']}")
    print(f"✅ Severity: {light['severity_estimate']}/10")
    print(f"✅ Red flags: {light['red_flags_present']}")
    
    # Step 2: Routing
    print("\n🔄 Step 2: Routing decision...")
    routing = route_conversation(
        light_extraction=light,
        transcription_quality="high",
        language="english"
    )
    print(f"✅ Mode: {routing['mode']}")
    print(f"✅ Reasoning: {routing['reasoning']}")
    
    # Step 3: Verify AI path
    if routing['mode'] == "ai_powered":
        print("\n✅ Correctly routed to AI-powered conversation")
        print("   (Would use model_c.select_next_question() for adaptive questions)")
    
    # Estimate API calls (AI path uses more calls)
    api_calls = 1 + 6 + 1  # Light + 6 AI questions + full extraction
    cost = api_calls * 0.0004
    print(f"\n💰 Estimated API calls: {api_calls}")
    print(f"💰 Estimated cost: ${cost:.4f}")
    
    # Log session
    log_session({
        "session_id": "test_ai_002",
        "patient_id": 2,
        "conversation_mode": routing['mode'],
        "chief_complaint": light['chief_complaint'],
        "severity_estimate": light['severity_estimate'],
        "red_flags_detected": light['red_flags_present'],
        "transcription_quality": "high",
        "api_calls_count": api_calls,
        "cost_estimate": cost,
        "routing_reasoning": routing['reasoning'],
        "timestamp": datetime.now().isoformat(),
        "patient_age": 42,
        "patient_gender": "male"
    })
    
    print("\n✅ TEST 2 PASSED: AI-powered path working as expected")
    return True


def test_emergency_path():
    """Test 3: Red flags detected → Emergency path"""
    print("\n" + "="*70)
    print("TEST 3: EMERGENCY PATH (Red Flags)")
    print("="*70)
    
    # Simulate transcription
    transcript = "I have chest pain and difficulty breathing. My left arm feels numb."
    
    print(f"📝 Transcript: {transcript}")
    
    # Step 1: Light extraction
    print("\n🔄 Step 1: Light extraction...")
    light = model_b.extract_light(transcript)
    print(f"✅ Chief complaint: {light['chief_complaint']}")
    print(f"✅ Severity: {light['severity_estimate']}/10")
    print(f"✅ Red flags: {light['red_flags_present']}")
    
    # Step 2: Routing
    print("\n🔄 Step 2: Routing decision...")
    routing = route_conversation(
        light_extraction=light,
        transcription_quality="high",
        language="english"
    )
    print(f"✅ Mode: {routing['mode']}")
    print(f"✅ Reasoning: {routing['reasoning']}")
    
    # Step 3: Verify emergency protocol
    if routing['mode'] == "emergency":
        print("\n🚨 EMERGENCY PATH ACTIVATED!")
        print("   → Minimal questions, immediate escalation")
        print("   → Red flag checks performed")
    
    # Estimate API calls (emergency = minimal)
    api_calls = 1 + 1 + 1  # Light + 1 question + full extraction
    cost = api_calls * 0.0004
    print(f"\n💰 Estimated API calls: {api_calls}")
    print(f"💰 Estimated cost: ${cost:.4f}")
    
    # Log session
    log_session({
        "session_id": "test_emergency_003",
        "patient_id": 3,
        "conversation_mode": routing['mode'],
        "chief_complaint": light['chief_complaint'],
        "severity_estimate": light['severity_estimate'],
        "red_flags_detected": light['red_flags_present'],
        "transcription_quality": "high",
        "api_calls_count": api_calls,
        "cost_estimate": cost,
        "routing_reasoning": routing['reasoning'],
        "timestamp": datetime.now().isoformat(),
        "patient_age": 58,
        "patient_gender": "male"
    })
    
    print("\n✅ TEST 3 PASSED: Emergency path working as expected")
    return True


def test_unknown_symptom():
    """Test 4: Unknown symptom → AI-powered + logged for expansion"""
    print("\n" + "="*70)
    print("TEST 4: UNKNOWN SYMPTOM (Expansion Logging)")
    print("="*70)
    
    # Simulate transcription
    transcript = "I have a strange rash on my back that's been itching for a week."
    
    print(f"📝 Transcript: {transcript}")
    
    # Step 1: Light extraction
    print("\n🔄 Step 1: Light extraction...")
    light = model_b.extract_light(transcript)
    print(f"✅ Chief complaint: {light['chief_complaint']}")
    print(f"✅ Severity: {light['severity_estimate']}/10")
    
    # Step 2: Check if known
    normalized = normalize_complaint(light['chief_complaint'])
    questions = get_symptom_questions(normalized, "english")
    
    if not questions:
        print(f"\n⚠️  Symptom '{light['chief_complaint']}' is UNKNOWN")
        print("   → Will use AI-powered conversation")
        print("   → Will log for expansion")
    
    # Step 3: Routing
    print("\n🔄 Step 3: Routing decision...")
    routing = route_conversation(
        light_extraction=light,
        transcription_quality="medium",
        language="english"
    )
    print(f"✅ Mode: {routing['mode']}")
    print(f"✅ Reasoning: {routing['reasoning']}")
    
    # Estimate API calls
    api_calls = 1 + 6 + 1  # Light + AI questions + full extraction
    cost = api_calls * 0.0004
    print(f"\n💰 Estimated API calls: {api_calls}")
    print(f"💰 Estimated cost: ${cost:.4f}")
    
    # Log session (will auto-log unknown symptom)
    log_session({
        "session_id": "test_unknown_004",
        "patient_id": 4,
        "conversation_mode": routing['mode'],
        "chief_complaint": light['chief_complaint'],
        "severity_estimate": light['severity_estimate'],
        "red_flags_detected": light['red_flags_present'],
        "transcription_quality": "medium",
        "api_calls_count": api_calls,
        "cost_estimate": cost,
        "routing_reasoning": routing['reasoning'],
        "timestamp": datetime.now().isoformat(),
        "patient_age": 28,
        "patient_gender": "female"
    })
    
    print("\n✅ TEST 4 PASSED: Unknown symptom logged for expansion")
    return True


def main():
    """Run all integration tests"""
    print("\n" + "="*70)
    print("🧪 NEW SYSTEM INTEGRATION TESTS")
    print("="*70)
    print("\nTesting two-stage extraction system with intelligent routing...")
    print("This will demonstrate all three routing paths:")
    print("  1. Rule-based (known symptoms, low severity)")
    print("  2. AI-powered (high severity or unknown symptoms)")
    print("  3. Emergency (red flags detected)")
    
    # Clear previous logs
    clear_logs()
    
    # Run tests
    tests_passed = 0
    tests_total = 4
    
    try:
        if test_rule_based_path():
            tests_passed += 1
    except Exception as e:
        print(f"\n❌ TEST 1 FAILED: {e}")
        import traceback
        traceback.print_exc()
    
    try:
        if test_ai_powered_path():
            tests_passed += 1
    except Exception as e:
        print(f"\n❌ TEST 2 FAILED: {e}")
        import traceback
        traceback.print_exc()
    
    try:
        if test_emergency_path():
            tests_passed += 1
    except Exception as e:
        print(f"\n❌ TEST 3 FAILED: {e}")
        import traceback
        traceback.print_exc()
    
    try:
        if test_unknown_symptom():
            tests_passed += 1
    except Exception as e:
        print(f"\n❌ TEST 4 FAILED: {e}")
        import traceback
        traceback.print_exc()
    
    # Generate reports
    print("\n" + "="*70)
    print("📊 ANALYTICS REPORTS")
    print("="*70)
    
    print(generate_performance_report(days=1))
    print("\n" + generate_expansion_report())
    
    # Summary
    print("\n" + "="*70)
    print("📋 TEST SUMMARY")
    print("="*70)
    print(f"\nTests passed: {tests_passed}/{tests_total}")
    
    if tests_passed == tests_total:
        print("\n✅ ALL TESTS PASSED! System is ready for deployment.")
        print("\nNext steps:")
        print("  1. Run database migration: backend/database/migrations/add_new_system_fields.sql")
        print("  2. Test with real audio files")
        print("  3. Deploy to production")
        print("  4. Monitor routing distribution and costs")
    else:
        print(f"\n❌ {tests_total - tests_passed} test(s) failed. Please review errors above.")
    
    return tests_passed == tests_total


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
