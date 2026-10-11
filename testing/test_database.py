import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))

from database import (  # type: ignore
    DatabaseConnection, PatientDB, SessionDB, ConversationDB,
    SymptomDB, PredictionDB, PrescriptionDB
)


def test_connection():
    print("🔌 Testing database connection...")
    try:
        DatabaseConnection.initialize_pool(min_conn=1, max_conn=2)
        with DatabaseConnection.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version();")
                version = cur.fetchone()
                print(f"✅ Connected: {version['version'][:50]}...")
        return True
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False


def test_tables_exist():
    print("\n📋 Checking tables...")
    required_tables = ['patient', 'healthcare_worker', 'session', 
                      'conversation_message', 'symptom', 'prediction', 'prescription']
    
    query = """SELECT table_name FROM information_schema.tables 
               WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"""
    
    try:
        tables = DatabaseConnection.execute_query(query)
        table_names = [t['table_name'] for t in tables]
        
        all_exist = True
        for table in required_tables:
            exists = table in table_names
            print(f"{'✅' if exists else '❌'} Table '{table}'")
            all_exist = all_exist and exists
        return all_exist
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_crud_operations():
    print("\n🔧 Testing CRUD operations...")
    
    try:
        patient = PatientDB.create_patient("Test Patient", "+250788999999", "kinyarwanda", "Kigali")
        print(f"  ✅ Patient created: {patient['patient_id']}")
        
        session = SessionDB.create_session(patient['patient_id'])
        print(f"  ✅ Session created: {session['session_id']}")
        
        message = ConversationDB.add_message(
            session['session_id'], 'ml_system', 'Hello, how can I help you?', 1
        )
        print(f"  ✅ Message added: {message['message_id']}")
        
        symptom = SymptomDB.add_symptom(session['session_id'], 'fever', 'moderate', '3 days')
        print(f"  ✅ Symptom added: {symptom['symptom_id']}")
        
        prediction = PredictionDB.create_prediction(
            session['session_id'], 'Suspected Typhoid', 'medium', 0.8523, 'v1.0.0'
        )
        print(f"  ✅ Prediction created: {prediction['prediction_id']}")
        
        SessionDB.update_session_status(session['session_id'], 'awaiting_review')
        print("  ✅ Session status updated")
        
        retrieved_patient = PatientDB.get_patient_by_id(patient['patient_id'])
        retrieved_session = SessionDB.get_session(session['session_id'])
        conversation = ConversationDB.get_conversation(session['session_id'])
        symptoms = SymptomDB.get_session_symptoms(session['session_id'])
        
        assert retrieved_patient and retrieved_session['status'] == 'awaiting_review'
        assert len(conversation) == 1 and len(symptoms) == 1
        print("  ✅ All read operations successful")
        
        DatabaseConnection.execute_update("DELETE FROM session WHERE session_id = %s", (session['session_id'],))
        DatabaseConnection.execute_update("DELETE FROM patient WHERE patient_id = %s", (patient['patient_id'],))
        print("  ✅ Test data cleaned")
        
        return True
    except Exception as e:
        print(f"  ❌ CRUD failed: {e}")
        return False


def test_functions():
    print("\n⚙️  Testing functions...")
    
    try:
        patient = PatientDB.create_patient("Function Test", "+250788888888", "english")
        session = SessionDB.create_session(patient['patient_id'])
        
        history = DatabaseConnection.execute_query("SELECT * FROM get_patient_history(%s)", (patient['patient_id'],))
        assert isinstance(history, list)
        print(f"  ✅ get_patient_history works ({len(history)} sessions)")
        
        SessionDB.close_session(session['session_id'])
        updated_session = SessionDB.get_session(session['session_id'])
        assert updated_session['status'] == 'completed' and updated_session['end_time']
        print("  ✅ close_session works")
        
        DatabaseConnection.execute_update("DELETE FROM session WHERE session_id = %s", (session['session_id'],))
        DatabaseConnection.execute_update("DELETE FROM patient WHERE patient_id = %s", (patient['patient_id'],))
        
        return True
    except Exception as e:
        print(f"  ❌ Functions failed: {e}")
        return False


def run_all_tests():
    print("=" * 60)
    print("🧪 DATABASE VERIFICATION TESTS")
    print("=" * 60)
    
    results = [
        ("Connection", test_connection()),
    ]
    
    if not results[0][1]:
        print("\n❌ Cannot proceed. Check .env and ensure PostgreSQL is running.")
        return False
    
    results.extend([
        ("Tables", test_tables_exist()),
        ("CRUD Operations", test_crud_operations()),
        ("Functions", test_functions()),
    ])
    
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    
    for test_name, result in results:
        print(f"{'✅ PASS' if result else '❌ FAIL'}: {test_name}")
    
    print(f"\nTotal: {passed}/{len(results)} tests passed")
    
    if passed == len(results):
        print("\n🎉 All tests passed! Database is ready.")
        return True
    else:
        print(f"\n⚠️  {len(results) - passed} test(s) failed.")
        return False


if __name__ == "__main__":
    try:
        success = run_all_tests()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⚠️  Tests interrupted")
        sys.exit(1)
    finally:
        DatabaseConnection.close_pool()
        print("\n👋 Connection pool closed")
