# DexterousHands Docker Environment

GPU-ready Docker environment for training dexterous hand policies with IsaacGym.

## Quick Start (one command)

```bash
bash docker/setup.sh
```

`setup.sh` is idempotent and does everything needed:

1. Extracts IsaacGym from a community Docker image to `../isaacgym/` (if missing)
2. Builds the image
3. Starts the container and waits for the editable installs to finish
4. Runs the smoke test

Host prerequisites (Docker, GPU driver, NVIDIA Container Toolkit) are **not** checked by `setup.sh` — verify them yourself before running it (see the Prerequisites section below).

The sections below describe the manual steps (and are the fallback if `setup.sh` fails).

---

## Prerequisites (manual, required on host)

### 1. NVIDIA GPU driver + Container Toolkit

```bash
# Verify GPU is accessible
docker run --rm --gpus all nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu20.04 nvidia-smi
```

### 2. IsaacGym source

`setup.sh` auto-extracts IsaacGym from a community Docker image. To do it manually instead, download **IsaacGym Preview Release 4** from https://developer.nvidia.com/isaac-gym and lay the repos out as:

```
<parent>/
  DexterousHands/    <- this repo
  isaacgym/          <- extracted source
    python/
      setup.py
      isaacgym/
```

The compose files mount the **parent directory** as `/workspace`, so the container sees both repos at `/workspace/DexterousHands` and `/workspace/isaacgym`.

---

## Manual build (if not using setup.sh)

```bash
cd DexterousHands
docker compose -f docker/docker-compose.headless.yaml build
```

---

## Run

**Headless (training / CI):**
```bash
docker compose -f docker/docker-compose.headless.yaml up -d
docker exec -it dexterousnhands_container bash
```

**X11 (visualization on local display):**
```bash
xhost +local:docker
docker compose -f docker/docker-compose.x11.yaml up -d
docker exec -it dexterousnhands_container bash
```

---

## Smoke Test

The full smoke test script covers GPU, Python deps, bidexhands editable install, IsaacGym import, and a 1-iteration training run:

```bash
docker exec dexterousnhands_container bash /workspace/DexterousHands/docker/smoke_test.sh
```

Quick manual checks:

```bash
docker exec -it dexterousnhands_container nvidia-smi
docker exec -it dexterousnhands_container python -c \
  "import bidexhands; print(bidexhands.__file__)"
docker exec -it dexterousnhands_container python -c \
  "import isaacgym; print('isaacgym ok')"
```

---

## Training

```bash
docker exec -it dexterousnhands_container bash
# Inside container:
cd /workspace/DexterousHands/bidexhands
python train.py --task ShadowHandOver --algo ppo --num_envs 4096
```

---

## Stop

```bash
docker compose -f docker/docker-compose.headless.yaml down
```
