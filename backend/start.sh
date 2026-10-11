#!/bin/bash
# start.sh — container entrypoint for Render deployment
#
# On first boot: downloads Whisper models to the persistent disk (~10–30 min).
# On every subsequent boot: models are already on disk, skips download (~0 s).
# The app then loads them from disk in 1–5 min and handles requests normally.

set -e

MODEL_CACHE_DIR="${HF_HOME:-/data/models}/hub"
mkdir -p "$MODEL_CACHE_DIR"

echo "=== Pre-Consultation Backend ==="
echo "HF_HOME : ${HF_HOME:-/data/models}"
echo "DEVICE  : ${DEVICE:-cpu}"
echo "PORT    : ${PORT:-8000}"
echo ""

# Pre-download Whisper models to the persistent disk if not already cached.
# This runs Python inline to reuse the already-installed huggingface_hub library.
python - <<'PY'
import os, sys
from pathlib import Path
from huggingface_hub import snapshot_download

hf_home   = os.environ.get("HF_HOME", "/data/models")
hub_dir   = Path(hf_home) / "hub"
hf_token  = os.environ.get("HF_TOKEN")   # required if models are gated

MODELS = [
    "akera/whisper-large-v3-kin-200h-v2",
    "openai/whisper-large-v3",
]

for repo_id in MODELS:
    slug      = repo_id.replace("/", "--")
    model_dir = hub_dir / f"models--{slug}"

    if model_dir.exists() and any(model_dir.iterdir()):
        print(f"  [cached]      {repo_id}")
    else:
        print(f"  [downloading] {repo_id}  — this may take several minutes on first boot ...")
        snapshot_download(
            repo_id=repo_id,
            cache_dir=str(hub_dir),
            token=hf_token or None,
        )
        print(f"  [done]        {repo_id}")

print("")
print("Model cache ready — starting application ...")
PY

# Start the app.
# - 1 worker: both Whisper large-v3 models together need ~6 GB RAM in float32.
#   Use a Render instance with at least 8 GB RAM (Pro Plus plan).
#   If you switch to float16 (half-precision on supported CPUs), ~3 GB RAM
#   total is sufficient and a Pro plan (4 GB) may work.
# - $PORT: Render injects this automatically; falls back to 8000 locally.
exec gunicorn \
    -k uvicorn.workers.UvicornWorker \
    main:app \
    --bind "0.0.0.0:${PORT:-8000}" \
    --workers 1 \
    --timeout 300 \
    --graceful-timeout 30 \
    --keep-alive 5
