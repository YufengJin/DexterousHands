# =========================================================
# DexterousHands Dockerfile (uv venv + GPU-ready)
# =========================================================
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV UV_LINK_MODE=copy
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python
ENV VIRTUAL_ENV=/opt/venv
ENV PATH=/opt/venv/bin:/root/.local/bin:$PATH

# ---------------------------------------------------------
# System dependencies (IsaacGym headless rendering + debug tools)
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    curl \
    bzip2 \
    ca-certificates \
    git \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    libx11-6 \
    libxext6 \
    libxrender1 \
    libsm6 \
    libegl1 \
    libosmesa6 \
    ffmpeg \
    lsof \
    psmisc \
    tmux \
    vim \
    x11-apps \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# Install uv (copy static binary from official image)
# ---------------------------------------------------------
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# ---------------------------------------------------------
# Create Python 3.8 venv managed by uv
# (IsaacGym supports Python 3.7/3.8; 3.8 recommended)
# ---------------------------------------------------------
RUN uv venv /opt/venv --python 3.8

# ---------------------------------------------------------
# Pre-install Python dependencies (leverages Docker layer cache)
# Only requirements.txt is copied; layer is reused unless deps change.
# Note: isaacgym is NOT listed here — it must be provided by the user
# and is installed editable at container start via entrypoint.sh.
# ---------------------------------------------------------
WORKDIR /workspace
COPY requirements.txt ./
# Pin numpy==1.23.0 explicitly: requirements.txt omits it, but setup.py requires it.
# Installing it here avoids a version downgrade at entrypoint time.
RUN uv pip install -r requirements.txt && uv pip install "numpy==1.23.0"

# ---------------------------------------------------------
# Entrypoint (bidexhands itself is installed editable at container start)
# ---------------------------------------------------------
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
