#!/usr/bin/env bash
# Run inside the container:
#   docker exec dexterousnhands_container bash /workspace/DexterousHands/docker/smoke_test.sh
set -e

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=========================================="
echo " DexterousHands Docker Smoke Test"
echo "=========================================="

# ------------------------------------------
# Wait for entrypoint to finish (race guard)
# entrypoint.sh writes /tmp/entrypoint_done when complete
# ------------------------------------------
echo "[INFO] Waiting for entrypoint to finish..."
WAIT=0
until [ -f /tmp/entrypoint_done ] || [ "${WAIT}" -ge 300 ]; do
  sleep 2
  WAIT=$((WAIT+2))
done
if [ ! -f /tmp/entrypoint_done ]; then
  echo "[FAIL] Entrypoint did not finish within 300s"
  exit 1
fi
echo "[INFO] Entrypoint done."

# ------------------------------------------
# Layer 1: Environment (no IsaacGym needed)
# ------------------------------------------
echo ""
echo "--- Layer 1: Environment ---"

# GPU visible
if nvidia-smi > /dev/null 2>&1; then
  GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
  ok "GPU visible: ${GPU}"
else
  fail "nvidia-smi failed"
fi

# Python version is 3.8
PY_VER=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if [ "${PY_VER}" = "3.8" ]; then
  ok "Python version: ${PY_VER}"
else
  fail "Python version is ${PY_VER}, expected 3.8"
fi

# venv is active and comes from /opt/venv
PY_PATH=$(which python)
if echo "${PY_PATH}" | grep -q "/opt/venv"; then
  ok "venv active: ${PY_PATH}"
else
  fail "venv not active, python is at ${PY_PATH}"
fi

# torch installed and CUDA-enabled (version may differ from requirements.txt after isaacgym install)
TORCH_VER=$(python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "MISSING")
if [ "${TORCH_VER}" != "MISSING" ]; then
  ok "torch installed: ${TORCH_VER}"
else
  fail "torch not installed"
fi

# torch CUDA available
CUDA_OK=$(python -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "False")
if [ "${CUDA_OK}" = "True" ]; then
  ok "torch.cuda.is_available() = True"
else
  fail "torch.cuda.is_available() = False (driver/runtime mismatch?)"
fi

# numpy version
NUMPY_VER=$(python -c "import numpy; print(numpy.__version__)" 2>/dev/null || echo "MISSING")
if echo "${NUMPY_VER}" | grep -q "1.23"; then
  ok "numpy: ${NUMPY_VER}"
else
  fail "numpy version is '${NUMPY_VER}', expected 1.23.x"
fi

# bidexhands installed as editable from /workspace
# Use find_spec without importing (avoids triggering isaacgym early)
BIDEX_PATH=$(python -c "
import importlib.util
spec = importlib.util.find_spec('bidexhands')
print(spec.origin if spec else 'NOT_FOUND')
" 2>/dev/null || echo "NOT_FOUND")

if echo "${BIDEX_PATH}" | grep -q "^/workspace/"; then
  ok "bidexhands editable install: ${BIDEX_PATH}"
else
  fail "bidexhands not found or not editable (got: ${BIDEX_PATH})"
fi

# ------------------------------------------
# Layer 2: Full simulation (requires IsaacGym)
# ------------------------------------------
echo ""
echo "--- Layer 2: Full Simulation (requires IsaacGym) ---"

# isaacgym prints diagnostic lines to stdout on import; use tail -1 to get only our sentinel
ISAACGYM_OK=$(python -c "import isaacgym; print('ok')" 2>/dev/null | tail -1 || echo "MISSING")
if [ "${ISAACGYM_OK}" = "ok" ]; then
  ok "import isaacgym"

  # Same tail-1 trick for bidexhands (which triggers isaacgym internals on import)
  BIDEX_FULL=$(python -c "import isaacgym; import bidexhands; print('ok')" 2>/dev/null | tail -1 || echo "FAILED")
  if [ "${BIDEX_FULL}" = "ok" ]; then
    ok "import bidexhands (full)"
  else
    fail "import bidexhands failed (run manually to see traceback)"
  fi

  # 1-iteration headless training smoke test
  # train.py uses os.getcwd() to find cfg/, so must be run from the bidexhands/ dir
  BIDEXHANDS_DIR=""
  for root in /workspace/DexterousHands /workspace; do
    if [ -f "${root}/bidexhands/train.py" ]; then
      BIDEXHANDS_DIR="${root}/bidexhands"
      break
    fi
  done

  if [ -n "${BIDEXHANDS_DIR}" ]; then
    echo "[INFO] Running 1-iteration headless training from ${BIDEXHANDS_DIR}..."
    # IsaacGym commonly segfaults at gym shutdown (known upstream issue).
    # Success is determined by whether the training loop actually ran, not the exit code.
    (cd "${BIDEXHANDS_DIR}" && python train.py \
        --task ShadowHandOver \
        --algo ppo \
        --num_envs 16 \
        --headless \
        --max_iterations 1) \
        > /tmp/train_smoke.log 2>&1 || true
    if grep -q "Learning iteration 0/1" /tmp/train_smoke.log; then
      ok "1-iteration training (ShadowHandOver, headless)"
      # Warn about known shutdown segfault so it's not a surprise
      if grep -q "Segmentation fault" /tmp/train_smoke.log; then
        echo "  [NOTE] Segfault at gym shutdown is a known IsaacGym upstream issue (not a real failure)"
      fi
    else
      fail "1-iteration training failed — see /tmp/train_smoke.log"
      tail -20 /tmp/train_smoke.log
    fi
  else
    fail "bidexhands/train.py not found"
  fi
else
  echo "[SKIP] IsaacGym not installed — Layer 2 skipped."
  echo "       Download from: https://developer.nvidia.com/isaac-gym"
  echo "       Place at: $(dirname /workspace/DexterousHands)/isaacgym/"
  echo "       Then restart the container (entrypoint will auto-install it)."
fi

# ------------------------------------------
# Summary
# ------------------------------------------
echo ""
echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

[ "${FAIL}" -eq 0 ]
