"""
models/gemini_utils.py — Shared Gemini call helper with model fallback.
"""

_MODEL_STACK = [
    "models/gemini-3.1-flash-lite-preview",  # primary
    "models/gemini-2.5-flash-lite",          # secondary backup
    "models/gemini-2.5-flash",               # final backup model
]

# Models that support thinking_config
_THINKING_MODELS = {"models/gemini-3.1-flash-lite-preview"}


def generate_with_fallback(client, contents, config: dict):
    """
    Try each model in _MODEL_STACK in order.
    Falls through to the next model on any exception.
    Strips thinking_config for models that don't support it.
    Raises the last exception if all models fail.
    """
    last_error = None
    for model in _MODEL_STACK:
        call_config = dict(config)
        if model not in _THINKING_MODELS:
            call_config.pop("thinking_config", None)
        try:
            return client.models.generate_content(
                model=model,
                contents=contents,
                config=call_config,
            )
        except Exception as e:
            print(f"Warning: Gemini model '{model}' failed ({type(e).__name__}: {e}). Trying next...")
            last_error = e
    raise last_error
