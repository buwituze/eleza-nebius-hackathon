"""
Test Whisper models directly without API to debug issues.

Usage:
    python test_whisper.py test_audio.wav
    python test_whisper.py test_audio.wav --language kinyarwanda
"""

import sys
import os
import time
import psutil
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent))

def print_system_info():
    """Print current system resource usage."""
    mem = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=1)
    print(f"\n📊 System Resources:")
    print(f"   RAM: {mem.percent}% ({mem.used/(1024**3):.1f}GB / {mem.total/(1024**3):.1f}GB)")
    print(f"   CPU: {cpu}%")


def test_model_loading():
    """Test if Whisper models can be loaded."""
    print("=" * 80)
    print("TEST 1: Model Loading")
    print("=" * 80)
    
    print("\n⏳ Loading Whisper models (this takes 1-2 minutes)...")
    print_system_info()
    
    start = time.time()
    
    try:
        from models import model_a
        model_a.load_models()
        
        elapsed = time.time() - start
        print(f"\n✅ Models loaded successfully in {elapsed:.1f}s")
        print_system_info()
        
        status = model_a.get_models_status()
        print(f"\nStatus: {status}")
        
        return True
        
    except Exception as e:
        print(f"\n❌ Model loading failed: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_transcription(audio_file: str, language_hint: str = None):
    """Test transcribing an audio file."""
    print("\n" + "=" * 80)
    print("TEST 2: Transcription")
    print("=" * 80)
    
    from models import model_a
    
    # Check if models are ready
    status = model_a.get_models_status()
    if not status["ready"]:
        print(f"❌ Models not ready: {status['status']}")
        print("Run test_model_loading() first or wait for models to load.")
        return False
    
    # Load audio file
    audio_path = Path(audio_file)
    if not audio_path.exists():
        print(f"❌ File not found: {audio_file}")
        return False
    
    print(f"\n📁 Loading audio: {audio_file}")
    file_size = audio_path.stat().st_size
    print(f"   Size: {file_size/(1024*1024):.2f}MB")
    
    audio_bytes = audio_path.read_bytes()
    
    print(f"   Language hint: {language_hint or 'None'}")
    print_system_info()
    
    # Transcribe
    print("\n⏳ Starting transcription...")
    start = time.time()
    
    try:
        result = model_a.transcribe(audio_bytes, language_hint=language_hint)
        
        elapsed = time.time() - start
        print(f"\n✅ Transcription completed in {elapsed:.1f}s")
        print_system_info()
        
        print("\n📝 RESULTS:")
        print(f"   Language: {result['dominant_language']}")
        print(f"   Source: {result['language_source']}")
        print(f"   Confidence: {result['mean_confidence']:.2%}")
        print(f"   Text length: {len(result['full_text'])} characters")
        print(f"\n   Transcription:")
        print(f"   {result['full_text'][:200]}{'...' if len(result['full_text']) > 200 else ''}")
        
        return True
        
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user (Ctrl+C)")
        return False
        
    except Exception as e:
        elapsed = time.time() - start
        print(f"\n❌ Transcription failed after {elapsed:.1f}s")
        print(f"   Error: {type(e).__name__}: {e}")
        print_system_info()
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run the tests."""
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nExample:")
        print("  python test_whisper.py test_audio.wav")
        print("  python test_whisper.py test_audio.wav --language kinyarwanda")
        return
    
    audio_file = sys.argv[1]
    language_hint = None
    
    if len(sys.argv) > 2 and sys.argv[2] == "--language":
        language_hint = sys.argv[3] if len(sys.argv) > 3 else None
    
    print("\n🧪 WHISPER MODEL TEST")
    print("=" * 80)
    print(f"Audio file: {audio_file}")
    print(f"Language hint: {language_hint or 'Auto-detect'}")
    print("=" * 80)
    
    # Test 1: Load models
    if not test_model_loading():
        print("\n⚠️ Cannot proceed - models failed to load")
        return
    
    # Test 2: Transcribe
    print("\n\n")
    success = test_transcription(audio_file, language_hint)
    
    # Summary
    print("\n" + "=" * 80)
    if success:
        print("✅ ALL TESTS PASSED")
    else:
        print("❌ TESTS FAILED")
    print("=" * 80)
    

if __name__ == "__main__":
    main()
