# Use AMD's official ROCm + PyTorch image as the base.
# This comes pre-loaded with PyTorch built for AMD, and all the C++ compilers (amdclang++) we need.
FROM rocm/pytorch:rocm6.1_ubuntu22.04_py3.10_pytorch_2.1.2

ARG INSTALL_TTS=1

# Keep Python quiet, prevent interactive prompts, and explicitly expose the Conda python executable to the system PATH
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TTS_ENABLED=${INSTALL_TTS} \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/conda/envs/py_3.10/bin:${PATH}"

# Install runtime system dependencies (ffmpeg) and build tools (cmake)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    build-essential \
    cmake \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip, setuptools, and wheel globally to ensure it understands modern wheel tags
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel

WORKDIR /build

# Clone the specific ROCm-patched fork of CTranslate2 mentioned in the WhisperX discussion
RUN git clone https://github.com/mega-ice/CTranslate2-rocm.git --recurse-submodules \
    && cd CTranslate2-rocm \
    && git checkout fix-rocm7.1-hip-namespace \
    && git submodule update --init --recursive \
    && mkdir build && cd build \
    # Compile CTranslate2 natively! Note the gfx1103 flag which specifically targets your 780M APU.
    # We also explicitly set the install prefix so we know exactly where the libraries go.
    && cmake .. -DWITH_MKL=OFF -DWITH_HIP=ON -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/amdclang++ -DCMAKE_HIP_ARCHITECTURES="gfx1103" -DBUILD_CLI=OFF -DCMAKE_INSTALL_PREFIX=/usr/local \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    # Build the Python bindings so WhisperX can actually talk to the C++ engine
    && cd ../python \
    # Pin numpy to <1.23 so we don't break the base image's numba/scipy packages
    && python -m pip install --no-cache-dir -r install_requirements.txt "numpy<1.23" \
    # Explicitly tell the Python builder where to find the C++ library we just installed
    && CTRANSLATE2_ROOT=/usr/local python setup.py bdist_wheel \
    && python -m pip install --no-cache-dir dist/*.whl --force-reinstall "numpy<1.23" \
    # Cleanup build folder to save space in the final Docker image
    && cd / && rm -rf /build

WORKDIR /app

# Ensure Linux can find the newly compiled CTranslate2 libraries
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64:/opt/rocm/lib:/opt/rocm/lib/llvm/lib:${LD_LIBRARY_PATH}"

# Install the specific versions of faster-whisper, pyannote, transformers, and ffmpeg-python
# - Pin numpy to <1.23 so they don't upgrade it and break the base image's numba package
# - Pin transformers to 4.36.2 to perfectly match the PyTorch 2.1.2 era (preventing >=2.4 requirement errors)
RUN python -m pip install --no-cache-dir pandas nltk "pyannote.audio==3.4.0" "faster-whisper==1.2.1" "transformers==4.36.2" ffmpeg-python "numpy<1.23"

# Install WhisperX WITHOUT dependencies (Crucial: so it doesn't overwrite our ROCm PyTorch with an NVIDIA one!)
RUN python -m pip install --no-cache-dir --no-deps "whisperx==3.7.4"

# Install your application's Python dependencies
COPY requirements.txt requirements-tts.txt ./
# Pin numpy one last time during the requirements install to be absolutely bulletproof
RUN python -m pip install --no-cache-dir -r requirements.txt "numpy<1.23" \
    && if [ "$INSTALL_TTS" = "1" ]; then python -m pip install --no-cache-dir -r requirements-tts.txt "numpy<1.23"; fi

# FORCE REPLACE torchaudio with the CPU version as the absolute final step.
# Because pip inevitably pulls the CUDA version of torchaudio during the dependency installations,
# we surgically remove it and drop in the CPU version with --no-deps to prevent it from ruining our AMD PyTorch!
RUN python -m pip uninstall -y torchaudio \
    && python -m pip install --no-cache-dir --no-deps torchaudio==2.1.2+cpu --extra-index-url https://download.pytorch.org/whl/cpu

# Copy application code
COPY . .

# Create data directories
RUN mkdir -p /data/db /data/podcasts /data/feeds /data/models/piper

# Expose port
EXPOSE 8000

# Healthcheck to verify application is ready
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=30 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application natively using the python module runner!
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]