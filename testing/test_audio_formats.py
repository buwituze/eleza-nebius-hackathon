"""
Test script to verify audio format handling for Model A.
Tests MP4, WAV, MP3, and other formats.
"""

import sys
import os

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))

def test_audio_file(audio_path: str):
    """Test transcription with a specific audio file."""
    print(f"\n{'='*80}")
    print(f"Testing: {audio_path}")
    print(f"{'='*80}")
    
    if not os.path.exists(audio_path):
        print(f"❌ File not found: {audio_path}")
        return
    
    # Read audio file
    with open(audio_path, 'rb') as f:
        audio_bytes = f.read()
    
    print(f"✅ File size: {len(audio_bytes):,} bytes")
    
    # Import and load model
    from models import model_a
    
    print("🔄 Loading models...")
    model_a.load_models()
    
    status = model_a.get_models_status()
    if not status['ready']:
        print(f"❌ Models not ready: {status['status']}")
        return
    
    print("✅ Models loaded")
    
    # Test transcription
    print("\n🔄 Transcribing...")
    try:
        result = model_a.transcribe(audio_bytes, language_hint="kinyarwanda")
        print(f"\n✅ Transcription successful!")
        print(f"\n📝 Text: {result['full_text']}")
        print(f"🌍 Language: {result['dominant_language']}")
        print(f"📊 Confidence: {result['mean_confidence']:.2%}")
        print(f"🔍 Source: {result['language_source']}")
    except Exception as e:
        print(f"\n❌ Transcription failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_audio_formats.py <path_to_audio_file>")
        print("\nExample:")
        print("  python test_audio_formats.py ../Datasets/speech/my_audio.mp4")
        sys.exit(1)
    
    audio_path = sys.argv[1]
    test_audio_file(audio_path)
