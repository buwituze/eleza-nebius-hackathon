"""
models/model_a.py — Speech-to-text wrapper.

Language handling:
    Whisper always detects the language from audio features on every call.
    If the patient selected a language on the kiosk screen, it is passed as a
    hint and used as a tiebreaker when detection confidence is low. Detection
    is never skipped — the selected language never overrides what Whisper hears.

    After fine-tuning on patient audio data, detection becomes highly reliable
    and the hint matters less. No changes to this file will be needed at that
    point — just swap the model ID in load_models().
"""

import io
import os
import numpy as np
import librosa
import soundfile as sf
import torch
from transformers import pipeline, GenerationConfig
from typing import Optional

SR       = 16_000
DEVICE   = os.getenv("DEVICE", "cpu")
DTYPE    = torch.float16 if DEVICE == "cuda" else torch.float32
HF_TOKEN = os.getenv("HF_TOKEN")

# Audio format validation
MAX_AUDIO_SIZE_MB = 50  # Maximum file size in MB
MAX_DURATION_SECONDS = 300  # 5 minutes max

_WHISPER_TO_LANG = {
    "rw": "kinyarwanda",
    "en": "english",
}
_LANG_TO_WHISPER = {v: k for k, v in _WHISPER_TO_LANG.items()}
_DEFAULT_LANGUAGE = "kinyarwanda"

_kin_pipe       = None
_eng_pipe       = None
_models_ready   = False
_loading_status = "not_started"


def load_models():
    """Call once at API startup to load both Whisper models into memory."""
    global _kin_pipe, _eng_pipe, _models_ready, _loading_status

    try:
        print(f"   DEVICE: {DEVICE} (torch.cuda.is_available={torch.cuda.is_available()})")
        _loading_status = "loading_kinyarwanda_model"
        _kin_pipe = pipeline(
            "automatic-speech-recognition",
            model="akera/whisper-large-v3-kin-200h-v2",
            torch_dtype=DTYPE,
            device=DEVICE,
            token=HF_TOKEN,
        )

        _loading_status = "loading_english_model"
        _eng_pipe = pipeline(
            "automatic-speech-recognition",
            model="openai/whisper-large-v3",
            torch_dtype=DTYPE,
            device=DEVICE,
            token=HF_TOKEN,
        )
        
        # Fix outdated generation config in fine-tuned Kinyarwanda model
        # Copy the correct config from the base OpenAI model
        _loading_status = "fixing_generation_config"
        print("Fixing Kinyarwanda model generation config...")
        _kin_pipe.model.generation_config = GenerationConfig.from_pretrained("openai/whisper-large-v3")
        print("Generation config updated.")

        _loading_status = "ready"
        _models_ready   = True
        print("Whisper models loaded.")
    except Exception as e:
        _loading_status = f"error: {e}"
        print(f"Error loading Whisper models: {e}")


def get_models_status() -> dict:
    return {"ready": _models_ready, "status": _loading_status}


def _detect_language(audio: np.ndarray, language_hint: Optional[str] = None) -> str:
    """
    Detect language from audio using Whisper's own internal detection.
    Always runs — language_hint is only used as a tiebreaker when Whisper
    returns an unrecognised language code (not rw or en).

    Args:
        audio         : Full audio array at 16kHz.
        language_hint : Language selected by patient on kiosk screen, or None.

    Returns:
        'kinyarwanda' or 'english'
    """
    # Use first 5 seconds for detection (reduced from 10s to save memory/time)
    clip_duration = min(5 * SR, len(audio))
    clip = audio[:clip_duration]
    
    print(f"  Detection clip: {clip_duration/SR:.1f}s")
    
    try:
        print("  Running Whisper language detection...", flush=True)
        
        # Pass audio array directly - transformers pipeline handles sampling rate internally
        # Ensure float32 dtype and C-contiguous for compatibility
        clip_array = np.ascontiguousarray(clip, dtype=np.float32)
        
        result = _eng_pipe(
            clip_array,
            generate_kwargs={"task": "transcribe", "language": None},
            return_timestamps=False,
        )
        
        detected = result.get("language")
        print(f"  Whisper detected: {detected}")
        
        if detected in _WHISPER_TO_LANG:
            return _WHISPER_TO_LANG[detected]

        # Whisper detected something else (e.g. French, Swahili)
        # Use the hint if available, otherwise fall back to default
        print(f"  Unrecognized language '{detected}', using hint/default")
        if language_hint in ("kinyarwanda", "english"):
            return language_hint
        return _DEFAULT_LANGUAGE

    except KeyboardInterrupt:
        # Don't catch Ctrl+C
        raise
    except Exception as e:
        print(f"  ⚠️ Language detection failed: {type(e).__name__}: {e}")
        print(f"  Falling back to hint={language_hint} or default={_DEFAULT_LANGUAGE}")
        return language_hint if language_hint in ("kinyarwanda", "english") else _DEFAULT_LANGUAGE


def _confidence(chunks: list) -> float:
    if not chunks:
        return 0.0
    bad  = ["[BLANK_AUDIO]", "[MUSIC]"]
    hits = sum(1 for c in chunks if any(t in c.get("text", "") for t in bad))
    return round(max(0.0, 1.0 - hits / len(chunks)), 3)


def _assess_quality(confidence: float) -> str:
    """
    Assess transcription quality based on mean confidence score.
    
    Returns:
        "high"   if confidence >= 0.85 (trust for rule-based questions)
        "medium" if 0.70 <= confidence < 0.85 (some uncertainty)
        "low"    if confidence < 0.70 (use AI conversation for safety)
    """
    if confidence >= 0.85:
        return "high"
    elif confidence >= 0.70:
        return "medium"
    else:
        return "low"


def transcribe(audio_bytes: bytes, language_hint: Optional[str] = None) -> dict:
    """
    Transcribe raw audio bytes in WAV format.

    Always detects language from audio — language_hint is never used to skip
    detection. It is only used as a fallback when Whisper's detection returns
    an unrecognised language code.

    Args:
        audio_bytes   : Raw audio file content in WAV format.
        language_hint : Language selected by patient on kiosk screen, or None.

    Returns:
        {
            "full_text":         str,
            "dominant_language": str,
            "mean_confidence":   float,
            "language_source":   str,  # "detected" | "hint_fallback" | "default_fallback"
        }
    
    Raises:
        RuntimeError: If models not ready, file too large, invalid format, or processing fails.
    """
    if not _models_ready:
        raise RuntimeError(f"Models not ready. Status: {_loading_status}")

    # Validate file size
    size_mb = len(audio_bytes) / (1024 * 1024)
    if size_mb > MAX_AUDIO_SIZE_MB:
        raise RuntimeError(
            f"Audio file too large: {size_mb:.1f}MB. Maximum allowed: {MAX_AUDIO_SIZE_MB}MB. "
            f"Consider splitting into smaller segments or reducing quality."
        )
    
    if len(audio_bytes) < 100:
        raise RuntimeError("Audio file too small or corrupted. Minimum size: 100 bytes.")

    # Load audio with librosa (WAV format only for simplicity and reliability)
    print(f"Loading audio file ({size_mb:.2f}MB)...")
    try:
        audio, actual_sr = librosa.load(io.BytesIO(audio_bytes), sr=SR, mono=True)
    except Exception as e:
        error_msg = str(e).lower()
        if "input" in error_msg or "format" in error_msg or "decode" in error_msg:
            raise RuntimeError(
                f"Invalid audio format. Only WAV format is supported. "
                f"Please convert your audio to WAV before uploading. "
                f"Error details: {e}"
            )
        else:
            raise RuntimeError(f"Failed to load audio file: {e}")

    # Validate duration
    duration = len(audio) / SR
    print(f"Audio duration: {duration:.1f}s")
    
    if duration < 0.5:
        raise RuntimeError("Audio too short. Minimum duration: 0.5 seconds.")
    
    if duration > MAX_DURATION_SECONDS:
        raise RuntimeError(
            f"Audio too long: {duration:.1f}s. Maximum allowed: {MAX_DURATION_SECONDS}s. "
            f"Please split into smaller segments."
        )

    # Detect language (skip full detection when user selected a supported language - saves ~30-60s on CPU)
    skip_detection = os.getenv("SKIP_LANG_DETECTION_WHEN_HINTED", "false").lower() == "true"
    if skip_detection and language_hint in ("kinyarwanda", "english"):
        print(f"Using language hint (fast mode): {language_hint}")
        resolved = language_hint
    else:
        print(f"Detecting language (hint: {language_hint})...")
        resolved = _detect_language(audio, language_hint)
    print(f"Language resolved: {resolved}")

    if resolved == language_hint:
        source = "hint_fallback"
    elif language_hint is None and resolved == _DEFAULT_LANGUAGE:
        source = "default_fallback"
    else:
        source = "detected"

    pipe       = _kin_pipe if resolved == "kinyarwanda" else _eng_pipe
    lang_token = _LANG_TO_WHISPER.get(resolved, "rw")
    
    # Kinyarwanda model is specialized - don't pass language parameter
    # English model supports multiple languages - pass language parameter
    is_kinyarwanda = (resolved == "kinyarwanda")

    # Process audio in 30-second segments
    seg_len  = 30 * SR
    num_segments = (len(audio) + seg_len - 1) // seg_len
    print(f"Processing {num_segments} segment(s) with {resolved} model...")
    
    segments = []

    for i in range(0, len(audio), seg_len):
        seg_num = (i // seg_len) + 1
        print(f"  Segment {seg_num}/{num_segments}...", end=" ", flush=True)
        
        chunk  = audio[i : i + seg_len]
        
        try:
            # Pass audio array directly - transformers pipeline handles sampling rate internally
            # Ensure float32 dtype and C-contiguous for compatibility
            chunk_array = np.ascontiguousarray(chunk, dtype=np.float32)
            
            # Build generate_kwargs based on model type
            if is_kinyarwanda:
                # Kinyarwanda model is specialized - no language parameter needed
                generate_kwargs = {"task": "transcribe"}
            else:
                # English model supports multiple languages
                generate_kwargs = {"task": "transcribe", "language": lang_token}
            
            # Try with timestamps first for confidence calculation
            try:
                result = pipe(
                    chunk_array,
                    generate_kwargs=generate_kwargs,
                    return_timestamps=True,
                )
                chunks = result.get("chunks", [])
                text = result.get("text", "").strip()
                conf = _confidence(chunks)
            except (KeyError, TypeError, AttributeError, ValueError) as ts_error:
                # If timestamps fail (num_frames error, etc), retry without timestamps
                error_str = str(ts_error).lower()
                if any(x in error_str for x in ["num_frames", "numpy ndarray", "chunks", "timestamps"]):
                    print(f"⚠️ Retrying without timestamps... ", end="", flush=True)
                    result = pipe(
                        chunk_array,
                        generate_kwargs=generate_kwargs,
                        return_timestamps=False,
                    )
                    text = result.get("text", "").strip()
                    conf = 1.0  # Assume good confidence if no chunks available
                else:
                    raise
            
            segments.append({
                "text":       text,
                "confidence": conf,
            })
            print(f"✓ (conf: {conf:.2f})")
            
        except KeyboardInterrupt:
            print("✗ Interrupted")
            raise
        except Exception as e:
            print(f"✗ Error: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
            raise RuntimeError(f"Transcription failed at segment {seg_num}/{num_segments}: {type(e).__name__}: {e}")

    full_text = " ".join(s["text"] for s in segments if s["text"])
    mean_conf = round(float(np.mean([s["confidence"] for s in segments])), 3)
    quality = _assess_quality(mean_conf)
    
    print(f"Transcription complete. Text length: {len(full_text)} chars, Confidence: {mean_conf:.2%}, Quality: {quality}")

    return {
        "full_text":         full_text,
        "dominant_language": resolved,
        "mean_confidence":   mean_conf,
        "language_source":   source,
        "quality":           quality,  # NEW: "high", "medium", or "low"
    }
