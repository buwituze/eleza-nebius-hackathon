"""
Simple CLI Client for Testing Conversational API
Run this to chat with the API
"""

import requests
import json

# API Configuration
API_BASE_URL = "http://localhost:8000"

def print_separator():
    print("\n" + "="*70 + "\n")

def start_demo():
    """Start the conversational demo"""
    print("""
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║         🏥 TYPHOID DIAGNOSTIC CONVERSATIONAL API DEMO           ║
║                                                                  ║
║         Type your answers to the questions                       ║
║         The AI will guide you through the consultation           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
    """)
    
    # Start conversation
    print("🔄 Starting new consultation...\n")
    
    try:
        response = requests.post(f"{API_BASE_URL}/conversation/start")
        response.raise_for_status()
        data = response.json()
    except requests.exceptions.ConnectionError:
        print("❌ Error: Cannot connect to API server")
        print("Make sure the API is running: python conversational_api.py")
        return
    except Exception as e:
        print(f"❌ Error: {e}")
        return
    
    session_id = data['session_id']
    print(f"✅ Session started: {session_id}\n")
    
    print_separator()
    print("🤖 Agent:", data['message'])
    print()
    
    # Show first question
    next_question = data['next_question']
    print(f"🤖 Agent: {next_question['question']}")
    
    if next_question.get('options'):
        print(f"   Options: {', '.join(next_question['options'])}")
    
    print(f"   Progress: {next_question['progress']}")
    print_separator()
    
    # Conversation loop
    while True:
        # Get user input
        user_input = input("👤 You: ").strip()
        
        if not user_input:
            print("Please enter a response.")
            continue
        
        if user_input.lower() in ['quit', 'exit', 'bye']:
            print("\n👋 Ending consultation...")
            break
        
        # Send message to API
        try:
            response = requests.post(
                f"{API_BASE_URL}/conversation/message",
                json={
                    "session_id": session_id,
                    "message": user_input
                }
            )
            response.raise_for_status()
            data = response.json()
        except Exception as e:
            print(f"❌ Error: {e}")
            break
        
        print_separator()
        
        # Display agent response
        print(f"🤖 Agent: {data['agent_message']}")
        
        # Check if consultation is complete
        if data['is_complete']:
            print_separator()
            print("✅ Consultation Complete!")
            
            if data.get('diagnosis'):
                diagnosis = data['diagnosis']
                print("\n📊 DIAGNOSIS SUMMARY:")
                print(f"   Prediction: {diagnosis['prediction']}")
                print(f"   Confidence: {diagnosis['confidence']:.1f}%")
                print(f"   Severity Risk: {diagnosis['severity_risk_percentage']:.1f}%")
            
            print_separator()
            
            # Ask if user wants to see full conversation
            see_history = input("\nWould you like to see the full conversation history? (yes/no): ").strip().lower()
            
            if see_history == 'yes':
                print_separator()
                print("📜 CONVERSATION HISTORY:")
                print_separator()
                
                for msg in data['conversation_history']:
                    role_emoji = "🤖" if msg['role'] == 'agent' else "👤"
                    print(f"{role_emoji} {msg['role'].upper()}: {msg['content']}\n")
            
            break
        
        # Show next question if available
        if data.get('next_question'):
            next_q = data['next_question']
            
            if next_q.get('options'):
                print(f"   Options: {', '.join(next_q['options'])}")
            
            print(f"   Progress: {next_q['progress']}")
        
        print_separator()
    
    print("\n👋 Thank you for using the Typhoid Diagnostic System!")


def test_api_health():
    """Test if API is running"""
    try:
        response = requests.get(f"{API_BASE_URL}/")
        if response.status_code == 200:
            print("✅ API is running and healthy")
            print(f"   {response.json()}")
            return True
        else:
            print(f"⚠️  API responded with status code: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to API")
        print(f"   Make sure the API is running on {API_BASE_URL}")
        print("   Run: python conversational_api.py")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


if __name__ == "__main__":
    print("Testing API connection...")
    print_separator()
    
    if test_api_health():
        print_separator()
        start_demo()
    else:
        print("\nPlease start the API server first:")
        print("  python conversational_api.py")