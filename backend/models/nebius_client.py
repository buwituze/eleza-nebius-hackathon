"""
models/nebius_client.py — Shared NVIDIA Nemotron client via Nebius Token Factory.

Nebius Token Factory exposes an OpenAI-compatible API, so the official `openai`
SDK is used with a custom base_url.

Stage → model mapping:
  Model B (data extraction)        → Nemotron-3.5 Lightning
  Model C (adaptive question loop) → Nemotron-3.5 Lightning
  Model D (triage & risk scoring)  → Nemotron-3 Ultra 550B
  Model E (patient guidance)       → Nemotron-3 Super 120B
  Model F (doctor brief)           → Nemotron-3 Ultra 550B
"""

import os
import re
from typing import Optional

from openai import OpenAI, BadRequestError

# EU endpoint by default. Keys issued for us-central1 must use
# https://api.tokenfactory.us-central1.nebius.com/v1/ instead.
_DEFAULT_BASE_URL = "https://api.tokenfactory.nebius.com/v1/"

MODEL_LIGHTNING = os.getenv("NEMOTRON_LIGHTNING_MODEL", "nvidia/Nemotron-3_5-Lightning")
MODEL_SUPER     = os.getenv("NEMOTRON_SUPER_MODEL",     "nvidia/nemotron-3-super-120b-a12b")
MODEL_ULTRA     = os.getenv("NEMOTRON_ULTRA_MODEL",     "nvidia/Nemotron-3-Ultra-550b-a55b")

MODEL_B = MODEL_LIGHTNING
MODEL_C = MODEL_LIGHTNING
MODEL_D = MODEL_ULTRA
MODEL_E = MODEL_SUPER
MODEL_F = MODEL_ULTRA

# Nemotron 3 models reason before answering by default. The pipeline relies on
# short, direct outputs (like Gemini's thinking_budget=0), so reasoning is off
# unless NEMOTRON_ENABLE_THINKING=true.
_ENABLE_THINKING = os.getenv("NEMOTRON_ENABLE_THINKING", "false").lower() == "true"

_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL)

# Lazy-initialized client — avoids crashing at import time if key is missing
_client = None


def is_configured() -> bool:
    return bool(os.getenv("NEBIUS_API_KEY"))


def _get_client() -> OpenAI:
    global _client
    if _client is None:
        api_key = os.getenv("NEBIUS_API_KEY")
        if not api_key:
            raise RuntimeError("NEBIUS_API_KEY environment variable is not set.")
        _client = OpenAI(
            base_url=os.getenv("NEBIUS_BASE_URL", _DEFAULT_BASE_URL),
            api_key=api_key,
            timeout=float(os.getenv("NEBIUS_TIMEOUT_SECONDS", "60")),
            max_retries=2,
        )
    return _client


def _create(model: str, messages: list, temperature: float, max_tokens: int, json_mode: bool):
    kwargs = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    optional = {}
    if json_mode:
        optional["response_format"] = {"type": "json_object"}
    if not _ENABLE_THINKING:
        optional["extra_body"] = {"chat_template_kwargs": {"enable_thinking": False}}

    try:
        return _get_client().chat.completions.create(**kwargs, **optional)
    except BadRequestError:
        if not optional:
            raise
        # Some deployments reject response_format / chat_template_kwargs —
        # retry without them; callers already parse JSON out of plain text.
        return _get_client().chat.completions.create(**kwargs)


def generate(model: str, prompt: str, *, temperature: float = 0.0, max_tokens: int = 300,
             json_mode: bool = False, system: Optional[str] = None) -> str:
    """
    Run one chat completion and return the response text.
    Falls back to Nemotron Lightning if the requested model fails.
    Raises the last exception if every attempt fails.
    """
    messages = ([{"role": "system", "content": system}] if system else []) + [
        {"role": "user", "content": prompt}
    ]

    models = [model] if model == MODEL_LIGHTNING else [model, MODEL_LIGHTNING]
    last_error = None
    for m in models:
        try:
            response = _create(m, messages, temperature, max_tokens, json_mode)
            text = _THINK_BLOCK.sub("", response.choices[0].message.content or "").strip()
            if not text:
                raise ValueError("empty response content")
            return text
        except Exception as e:
            print(f"Warning: Nemotron model '{m}' failed ({type(e).__name__}: {e}). Trying next...")
            last_error = e
    raise last_error
