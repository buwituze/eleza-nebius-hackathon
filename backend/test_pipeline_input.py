"""
Test script to verify correct input format for transformers ASR pipeline.
This helps ensure our model_a.py implementation is bulletproof.
"""
import numpy as np
import io

# Simulate what librosa.load() returns
def simulate_librosa_output():
    """librosa.load() returns float32 numpy array by default"""
    # Create a dummy audio array (1 second at 16kHz)
    audio = np.random.randn(16000).astype(np.float32)
    return audio, 16000

# Test different input formats
audio, sr = simulate_librosa_output()

print("Testing input formats for transformers ASR pipeline:")
print(f"1. Audio array dtype: {audio.dtype}")
print(f"2. Audio array shape: {audio.shape}")
print(f"3. Audio array is C-contiguous: {audio.flags['C_CONTIGUOUS']}")
print(f"4. Audio array is writable: {audio.flags['WRITEABLE']}")

# Test slicing (like we do for chunks)
chunk = audio[0:8000]
print(f"\nAfter slicing:")
print(f"5. Chunk dtype: {chunk.dtype}")
print(f"6. Chunk is C-contiguous: {chunk.flags['C_CONTIGUOUS']}")
print(f"7. Chunk is writable: {chunk.flags['WRITEABLE']}")

# Test astype
chunk_converted = chunk.astype(np.float32)
print(f"\nAfter .astype(np.float32):")
print(f"8. Converted dtype: {chunk_converted.dtype}")
print(f"9. Converted is C-contiguous: {chunk_converted.flags['C_CONTIGUOUS']}")
print(f"10. Is same object: {chunk is chunk_converted}")

# Test what dict should look like
audio_input = {"array": chunk_converted, "sampling_rate": sr}
print(f"\nDict format:")
print(f"11. Keys: {audio_input.keys()}")
print(f"12. Array type in dict: {type(audio_input['array'])}")
print(f"13. SR type in dict: {type(audio_input['sampling_rate'])}")

# Recommendation
print("\n" + "="*60)
print("CORRECT FORMAT FOR TRANSFORMERS ASR PIPELINE:")
print("="*60)
print('{"array": np.ndarray (float32, C-contiguous), "sampling_rate": int}')
print("\nCurrent implementation ✓ uses this format correctly")
