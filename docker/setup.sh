#!/usr/bin/env bash
# One-shot IsaacGym setup for dexteroushands.
# Auto-rendered by env-generator when probe.json:quirks contains is_isaacgym.
# Idempotent: safe to re-run.
#
# Usage (from anywhere):
#   bash /path/to/dexteroushands/docker/setup.sh
#
# Does NOT verify host prerequisites (Docker / NVIDIA driver / Container
# Toolkit). Run docker/check_prereqs.sh separately if needed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PARENT_DIR="$(cd "${REPO_ROOT}/.." && pwd)"
ISAACGYM_DIR="${PARENT_DIR}/isaacgym"

COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.headless.yaml"
COMMUNITY_IMAGE="uvarc/isaacgym:1.0.preview4-cuda11"
CONTAINER_NAME="dexteroushands-headless"
SENTINEL="/tmp/entrypoint_done"
WAIT_TIMEOUT=600

if [ -t 1 ]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; N=''
fi
info() { printf "${G}[INFO]${N} %s\n" "$*"; }
warn() { printf "${Y}[WARN]${N} %s\n" "$*"; }
err()  { printf "${R}[FAIL]${N} %s\n" "$*" >&2; }
step() { printf "\n${B}==>${N} ${B}%s${N}\n" "$*"; }

# ------------------------------------------
# Step 1: Extract IsaacGym if missing
# ------------------------------------------
step "Step 1/4: Checking IsaacGym"

if [ -f "${ISAACGYM_DIR}/python/setup.py" ]; then
  info "IsaacGym already present at ${ISAACGYM_DIR}"
else
  warn "IsaacGym not found at ${ISAACGYM_DIR}"
  info "Pulling community image ${COMMUNITY_IMAGE} (~2GB, one-time)..."
  docker pull "${COMMUNITY_IMAGE}"

  info "Extracting /opt/isaacgym -> ${ISAACGYM_DIR}..."
  CID=$(docker create "${COMMUNITY_IMAGE}" dummy)
  trap "docker rm -f ${CID} >/dev/null 2>&1 || true" EXIT
  docker cp "${CID}:/opt/isaacgym" "${ISAACGYM_DIR}"
  docker rm "${CID}" >/dev/null
  trap - EXIT

  if [ -f "${ISAACGYM_DIR}/python/setup.py" ]; then
    info "IsaacGym extracted successfully"
  else
    err "Extraction finished but ${ISAACGYM_DIR}/python/setup.py is missing"
    exit 1
  fi
fi

# ------------------------------------------
# Step 2: Build image
# ------------------------------------------
step "Step 2/4: Building Docker image"
docker compose -f "${COMPOSE_FILE}" build

# ------------------------------------------
# Step 3: Start container, wait for entrypoint
# ------------------------------------------
step "Step 3/4: Starting container and waiting for entrypoint"
docker compose -f "${COMPOSE_FILE}" up -d

info "Waiting for entrypoint (editable installs can take ~1min on first run)..."
sleep 2
WAIT=2
while ! docker exec "${CONTAINER_NAME}" test -f "${SENTINEL}" 2>/dev/null; do
  sleep 3
  WAIT=$((WAIT + 3))
  if [ "${WAIT}" -ge "${WAIT_TIMEOUT}" ]; then
    err "Entrypoint did not finish within ${WAIT_TIMEOUT}s"
    err "Inspect: docker logs ${CONTAINER_NAME}"
    exit 1
  fi
done
info "Entrypoint done (${WAIT}s)"

# ------------------------------------------
# Step 4: Editable-install sanity check
# ------------------------------------------
step "Step 4/4: Editable-install check"
docker exec "${CONTAINER_NAME}" python -c "import DexterousHands; print(DexterousHands.__file__)" \
  || { err "Editable install check failed"; exit 1; }
info "Setup complete. Container ${CONTAINER_NAME} is running."

echo
echo "  Enter container:  docker exec -it ${CONTAINER_NAME} bash"
echo "  Stop container:   docker compose -f ${COMPOSE_FILE} down"
