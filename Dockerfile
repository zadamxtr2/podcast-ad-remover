FROM python:3.11-slim

ARG INSTALL_TTS=1

# Keep Python quiet and avoid writing .pyc files into the container layer.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TTS_ENABLED=${INSTALL_TTS} \
    TORCH_CUDA_ARCH_LIST="" \
    CUDA_VISIBLE_DEVICES=""

# Install runtime system dependencies. FFmpeg is required for audio processing.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt requirements-tts.txt constraints-cpu.txt ./
# Install CPU-only PyTorch and all requirements using constraints to prevent CUDA dependencies
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple -c constraints-cpu.txt torch torchvision torchaudio
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple -c constraints-cpu.txt -r requirements.txt \
    && if [ "$INSTALL_TTS" = "1" ]; then pip install --no-cache-dir -r requirements-tts.txt; fi

# Copy application code
COPY . .

# Create data directories
RUN mkdir -p /data/db /data/podcasts /data/feeds /data/models/piper

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
