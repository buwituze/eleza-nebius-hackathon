FROM python:3.12-slim-bookworm

WORKDIR /app

# System dependencies for audio processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only PyTorch first — avoids pulling the default CUDA build (~750 MB saved)
# The remaining packages in requirements.txt will see torch already installed and skip it.
RUN pip install --no-cache-dir \
    "torch>=2.3.0,<3.0.0" \
    --index-url https://download.pytorch.org/whl/cpu

# Install remaining Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check \
    --upgrade-strategy only-if-needed \
    -r requirements.txt

# Copy application code
COPY . /app

# Whisper models are NOT baked into the image.
# They are downloaded at first startup to the persistent disk mounted at /data/models,
# and reused on every subsequent deploy (see start.sh).
ENV HF_HOME=/data/models
ENV DEVICE=cpu
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

COPY start.sh /start.sh
RUN chmod +x /start.sh

# Long start-period to cover first-boot model download (~10–30 min over the network).
# Subsequent boots load from the persistent disk cache and are much faster.
HEALTHCHECK --interval=30s --timeout=10s --start-period=3600s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health').read()" || exit 1

CMD ["/start.sh"]
