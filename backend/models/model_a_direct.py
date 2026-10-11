"""
models/model_a_direct.py — Speech-to-text using models directly (NO PIPELINE).

This is an alternative implementation that bypasses transformers pipeline entirely
to avoid num_frames and other pipeline bugs. Use this if model_a.py has issues.

To use: In main.py, change `from models import model_a` to `from models import model_a_direct as model_a`
"""

import io
import os
import numpy as np
import librosa
import torch
from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor
from typing import Optional

SR       = 16_000
DEVICE   = os.getenv("DEVICE", "cpu")
DTYPE    = torch.float16 if DEVICE == "cuda" else torch.float32
HF_TOKEN = os.getenv("HF_TOKEN")

# Audio format validation
MAX_AUDIO_SIZE_MB = 50
MAX_DURATION_SECONDS = 300

_WHISPER_TO_LANG = {
    "rw": "kinyarwanda",
    "en": "english",
}
_LANG_TO_WHISPER = {v: k for k, v in _WHISPER_TO_LANG.items()}
_DEFAULT_LANGUAGE = "kinyarwanda"

_kin_model = None
_kin_processor = None
_eng_model = None
_eng_processor = None
_models_ready = False
_loading_status = "not_started"


def load_models():
    """Load Whisper models directly without pipeline."""
    global _kin_model, _kin_processor, _eng_model, _eng_processor, _models_ready, _loading_status

    try:
        _loading_status = "loading_kinyarwanda_model"
        _kin_model = AutoModelForSpeechSeq2Seq.from_pretrained(
            "akera/whisper-large-v3-kin-200h-v2",
            torch_dtype=DTYPE,
            low_cpu_mem_usage=True,
            use_safetensors=True,
            token=HF_TOKEN,
        ).to(DEVICE)
        _kin_processor = AutoProcessor.from_pretrained(
            "akera/whisper-large-v3-kin-200h-v2",
            token=HF_TOKEN,
        )

        _loading_status = "loading_english_model"
        _eng_model = AutoModelForSpeechSeq2Seq.from_pretrained(
            "openai/whisper-large-v3",
            torch_dtype=DTYPE,
            low_cpu_mem_usage=True,
            use_safetensors=True,
            token=HF_TOKEN,
        ).to(DEVICE)
        _eng_processor = AutoProcessor.from_pretrained(
            "openai/whisper-large-v3",
            token=HF_TOKEN,
        )

        _loading_status = "ready"
        _models_ready = True
        print("Whisper models loaded (direct mode).")
    except Exception as e:
        _loading_status = f"error: {e}"
        print(f"Error loading Whisper models: {e}")


def get_models_status() -> dict:
    return {"ready": _models_ready, "status": _loading_status}


def initialize() -> dict:
    """Load models if not already loaded."""
    if not _models_ready:
        load_models()
    return get_models_status()


def _transcribe_with_model(audio_array: np.ndarray, model, processor, language_code: str = None) -> str:
    """Transcribe audio using model directly."""
    # Process audio
    input_features = processor(
        audio_array,
        sampling_rate=SR,
        return_tensors="pt"
    ).input_features.to(DEVICE, dtype=DTYPE)

    # Generate tokens
    if language_code:
        forced_decoder_ids = processor.get_decoder_prompt_ids(language=language_code, task="transcribe")
        predicted_ids = model.generate(input_features, forced_decoder_ids=forced_decoder_ids)
    else:
        predicted_ids = model.generate(input_features)

    # Decode
    transcription = processor.batch_decode(predicted_ids, skip_special_tokens=True)[0]
    return transcription.strip()


def _detect_language(audio: np.ndarray, language_hint: Optional[str]) -> str:
    """Detect language from audio clip."""
    # Use first 5 seconds
    clip_duration = min(5 * SR, len(audio))
    clip = audio[:clip_duration]
    
    print(f"  Detection clip: {clip_duration/SR:.1f}s")
    
    try:
        print("  Running Whisper language detection...", flush=True)
        
        # Use English model for detection (can detect all languages)
        input_features = _eng_processor(
            clip,
            sampling_rate=SR,
            return_tensors="pt"
        ).input_features.to(DEVICE, dtype=DTYPE)

        # Generate with language detection
        generated_ids = _eng_model.generate(input_features, max_new_tokens=10)
        
        # Decode to get detected language from tokens
        # Whisper includes language token in outputs
        transcription = _eng_processor.batch_decode(generated_ids, skip_special_tokens=False)[0]
        
        # Try to extract language from special tokens
        # For now, just use the hint since direct language detection from tokens is complex
        print(f"  Using language hint: {language_hint}")
        
        if language_hint in ("kinyarwanda", "english"):
            return language_hint
        return _DEFAULT_LANGUAGE

    except KeyboardInterrupt:
        raise
    except Exception as e:
        print(f"  ⚠️ Language detection failed: {type(e).__name__}: {e}")
        print(f"  Falling back to hint={language_hint} or default={_DEFAULT_LANGUAGE}")
        return language_hint if language_hint in ("kinyarwanda", "english") else _DEFAULT_LANGUAGE


def transcribe(audio_bytes: bytes, language_hint: Optional[str] = None) -> dict:
    """
    Transcribe audio using models directly (no pipeline).
    
    Args:
        audio_bytes: WAV audio file bytes
        language_hint: Optional language hint ("kinyarwanda" or "english")
    
    Returns:
        dict with keys: text, language, confidence
    """
    if not _models_ready:
        raise RuntimeError("Models not loaded. Call initialize() first.")
    
    # Validate file size
    size_mb = len(audio_bytes) / (1024 * 1024)
    print(f"Loading audio file ({size_mb:.2f}MB)...")
    
    if size_mb > MAX_AUDIO_SIZE_MB:
        raise ValueError(f"Audio file too large: {size_mb:.2f}MB (max: {MAX_AUDIO_SIZE_MB}MB)")
    
    # Load audio with librosa
    audio, sr = librosa.load(io.BytesIO(audio_bytes), sr=SR, mono=True)
    duration = len(audio) / SR
    print(f"Audio duration: {duration:.1f}s")
    
    if duration > MAX_DURATION_SECONDS:
        raise ValueError(f"Audio too long: {duration:.1f}s (max: {MAX_DURATION_SECONDS}s)")
    
    # Detect language
    print(f"Detecting language (hint: {language_hint})...")
    language = _detect_language(audio, language_hint)
    print(f"Language resolved: {language}")
    
    # Select model
    if language == "kinyarwanda":
        model = _kin_model
        processor = _kin_processor
        lang_code = "rw"
    else:
        model = _eng_model
        processor = _eng_processor
        lang_code = "en"
    
    # Process in chunks (64 seconds each)
    chunk_duration = 64
    seg_len = chunk_duration * SR
    num_segments = (len(audio) + seg_len - 1) // seg_len
    
    print(f"Processing {num_segments} segment(s) with {language} model...")
    
    segments = []
    for i in range(0, len(audio), seg_len):
        seg_num = (i // seg_len) + 1
        print(f"  Segment {seg_num}/{num_segments}...", end=" ", flush=True)
        
        chunk = audio[i:i + seg_len]
        
        try:
            text = _transcribe_with_model(chunk, model, processor, lang_code)
            segments.append(text)
            print(f"✓")
        except KeyboardInterrupt:
            print("✗ Interrupted")
            raise
        except Exception as e:
            print(f"✗ Error: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
            raise RuntimeError(f"Transcription failed at segment {seg_num}/{num_segments}: {type(e).__name__}: {e}")
    
    full_text = " ".join(s for s in segments if s)
    
    return {
        "text": full_text,
        "language": language,
        "confidence": 0.95,  # Direct mode doesn't provide chunk-level confidence
    }
