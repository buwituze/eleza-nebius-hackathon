# Hugging Face Spaces Dockerfile
# HF Spaces requires the Dockerfile at the repo root and the app on port 7860.
# For Render deployment, see backend/Dockerfile instead.

FROM python:3.12-slim-bookworm

WORKDIR /app

# System dependencies for audio processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only PyTorch first (avoids the default CUDA build, saves ~500 MB)
RUN pip install --no-cache-dir \
    "torch>=2.3.0,<3.0.0" \
    --index-url https://download.pytorch.org/whl/cpu

# Install remaining Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check \
    --upgrade-strategy only-if-needed \
    -r requirements.txt

# Copy backend source
COPY backend/ /app/

# HF Spaces requires port 7860.
# start.sh reads $PORT so setting it here is all that's needed.
ENV PORT=7860
# HF Spaces persistent storage mounts at /data — models cache there across restarts.
# Enable persistent storage in your Space settings (Storage tab) to avoid
# re-downloading models (~6 GB) on every cold start.
ENV HF_HOME=/data/models
ENV DEVICE=cpu
ENV PYTHONUNBUFFERED=1

EXPOSE 7860

# Reuse the same startup script as the Render deployment.
# It pre-downloads Whisper models to $HF_HOME, then starts gunicorn.
COPY backend/start.sh /start.sh
RUN chmod +x /start.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=3600s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:7860/health').read()" || exit 1

CMD ["/start.sh"]
