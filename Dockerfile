# Use AMD's official ROCm + PyTorch image as the base.
# This comes pre-loaded with PyTorch built for AMD, and all the C++ compilers (amdclang++) we need.
FROM rocm/pytorch:rocm6.1_ubuntu22.04_py3.10_pytorch_2.1.2

ARG INSTALL_TTS=1

# Keep Python quiet, prevent interactive prompts, and explicitly expose the Conda python executable to the system PATH
# --- THE MAGIC APU FIX: HSA_ENABLE_SDMA=0 prevents the 780M from hard-crashing the display manager during memory transfers! ---
# We also add PYTORCH_HIP_ALLOC_CONF to prevent memory fragmentation in the APU's shared RAM.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TTS_ENABLED=${INSTALL_TTS} \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/conda/envs/py_3.10/bin:${PATH}" \
    HSA_ENABLE_SDMA=0 \
    PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.8,max_split_size_mb:512

# Install runtime system dependencies (ffmpeg), build tools (cmake), and audio/video headers
# required to compile torchaudio directly from C++ source code.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    build-essential \
    cmake \
    curl \
    jq \
    pkg-config \
    libavformat-dev \
    libavcodec-dev \
    libavdevice-dev \
    libavutil-dev \
    libswscale-dev \
    libswresample-dev \
    libavfilter-dev \
    sox \
    libsox-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip, setuptools, and wheel globally, and add ninja to significantly speed up C++ compilation
RUN python -m pip install --no-cache-dir --upgrade pip "setuptools<70.0.0" wheel ninja

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
# - Pin setuptools to <70.0.0 to prevent it from deleting the pkg_resources module needed for C++ compiling
RUN python -m pip install --no-cache-dir pandas nltk "pyannote.audio==3.4.0" "faster-whisper==1.2.1" "transformers==4.36.2" ffmpeg-python "numpy<1.23" "setuptools<70.0.0"

# Install WhisperX WITHOUT dependencies (Crucial: so it doesn't overwrite our ROCm PyTorch with an NVIDIA one!)
RUN python -m pip install --no-cache-dir --no-deps "whisperx==3.7.4"

# Install your application's Python dependencies
COPY requirements.txt requirements-tts.txt ./
# Pin numpy and setuptools one last time during the requirements install to be absolutely bulletproof
RUN python -m pip install --no-cache-dir -r requirements.txt "numpy<1.23" "setuptools<70.0.0" \
    && if [ "$INSTALL_TTS" = "1" ]; then python -m pip install --no-cache-dir -r requirements-tts.txt "numpy<1.23" "setuptools<70.0.0"; fi

# FORCE REPLACE torchaudio by compiling it from GitHub source!
# PyPI doesn't host source distributions for torchaudio, so we clone it directly.
# Compiling directly from the v2.1.2 tag guarantees 100% C++ ABI compatibility with AMD's PyTorch.
RUN python -m pip uninstall -y torchaudio \
    && python -m pip install --no-cache-dir "setuptools<70.0.0" \
    && git clone --depth 1 --branch v2.1.2 https://github.com/pytorch/audio.git /tmp/torchaudio \
    && cd /tmp/torchaudio \
    && BUILD_SOX=1 python setup.py bdist_wheel \
    && python -m pip install --no-cache-dir --no-deps dist/*.whl \
    && cd / \
    && rm -rf /tmp/torchaudio

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