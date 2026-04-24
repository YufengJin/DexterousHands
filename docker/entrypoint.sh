#!/usr/bin/env bash
set -e

# Remove stale sentinel from previous container runs so setup.sh's wait loop
# doesn't falsely think entrypoint has already finished when it re-runs.
rm -f /tmp/entrypoint_done

cd /workspace

# Determine DexterousHands project root (may be /workspace/DexterousHands when parent dir is mounted)
DEXHANDS_ROOT=""
if [ -f /workspace/DexterousHands/setup.py ]; then
  DEXHANDS_ROOT="/workspace/DexterousHands"
elif [ -f /workspace/setup.py ]; then
  DEXHANDS_ROOT="/workspace"
fi

if [ -n "${DEXHANDS_ROOT}" ]; then
  # Install IsaacGym (editable) if the user has placed it alongside DexterousHands.
  # Expected layout on the host:
  #   <parent>/
  #     DexterousHands/   <- this repo
  #     isaacgym/         <- downloaded from https://developer.nvidia.com/isaac-gym
  ISAACGYM_PYTHON="/workspace/isaacgym/python"
  if [ -f "${ISAACGYM_PYTHON}/setup.py" ]; then
    echo "Installing isaacgym from ${ISAACGYM_PYTHON} (editable)..."
    uv pip install -e "${ISAACGYM_PYTHON}"
  else
    echo "[WARN] IsaacGym not found at ${ISAACGYM_PYTHON}."
    echo "       Download from https://developer.nvidia.com/isaac-gym and place it at:"
    echo "       $(dirname ${DEXHANDS_ROOT})/isaacgym/"
    echo "       Then restart the container."
  fi

  echo "Installing bidexhands from ${DEXHANDS_ROOT} (editable)..."
  uv pip install -e "${DEXHANDS_ROOT}"
fi

# Write sentinel so smoke_test.sh knows the entrypoint finished
touch /tmp/entrypoint_done

if [ $# -eq 0 ]; then
  exec bash
else
  exec "$@"
fi
