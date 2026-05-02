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

  # ------------------------------------------
  # Layer 3: PhysX sim functional check
  # ------------------------------------------
  # Tests sim CREATION (not training) because IsaacGym Preview 4's GPU PhysX path
  # depends on host NVIDIA driver compatibility. CPU PhysX is the ground-truth
  # functional smoke; GPU PhysX is advisory (driver >=570 is known to SIGSEGV).
  echo ""
  echo "--- Layer 3: PhysX sim functional check ---"

  cat > /tmp/_create_sim_cpu.py <<'PYEOF'
import isaacgym
from isaacgym import gymapi
gym = gymapi.acquire_gym()
sp = gymapi.SimParams()
sp.up_axis = gymapi.UP_AXIS_Z
sp.gravity = gymapi.Vec3(0.0, 0.0, -9.81)
sp.physx.solver_type = 1
sp.physx.use_gpu = False
sp.use_gpu_pipeline = False
sim = gym.create_sim(0, -1, gymapi.SIM_PHYSX, sp)
gym.destroy_sim(sim)
print("ok")
PYEOF
  CPU_OK=$(python /tmp/_create_sim_cpu.py 2>/dev/null | tail -1 || echo "MISSING")
  if [ "${CPU_OK}" = "ok" ]; then
    ok "gym.create_sim (CPU PhysX) — sim functional"
  else
    fail "gym.create_sim (CPU PhysX) — got: ${CPU_OK}"
  fi

  cat > /tmp/_create_sim_gpu.py <<'PYEOF'
import isaacgym
from isaacgym import gymapi
gym = gymapi.acquire_gym()
sp = gymapi.SimParams()
sp.up_axis = gymapi.UP_AXIS_Z
sp.gravity = gymapi.Vec3(0.0, 0.0, -9.81)
sp.physx.solver_type = 1
sp.physx.use_gpu = True
sp.use_gpu_pipeline = True
sim = gym.create_sim(0, 0, gymapi.SIM_PHYSX, sp)
gym.destroy_sim(sim)
print("ok")
PYEOF
  # Run in subshell so SIGSEGV does not abort the smoke script.
  # Outer 2>/dev/null silences bash's own "Segmentation fault" job-control message.
  # `&& GPU_RC=0 || GPU_RC=$?` is required because `set -e` (line 4) would otherwise
  # abort the script on the subshell's non-zero exit (e.g. 139 from SIGSEGV).
  bash -c 'python /tmp/_create_sim_gpu.py 2>/dev/null' >/tmp/_gpu_smoke.out 2>/dev/null \
    && GPU_RC=0 || GPU_RC=$?
  GPU_LAST=$(tail -1 /tmp/_gpu_smoke.out 2>/dev/null || echo "")
  if [ "${GPU_RC}" -eq 0 ] && [ "${GPU_LAST}" = "ok" ]; then
    ok "gym.create_sim (GPU PhysX) — host driver compatible with IsaacGym Preview 4"
    echo "  [INFO] To run full training (works on this host):"
    echo "         cd /workspace/dexteroushands/bidexhands && \\"
    echo "         python train.py --task ShadowHandOver --algo ppo --num_envs 4096 --headless"
  else
    if [ "${GPU_RC}" -eq 139 ]; then
      GPU_DIAG="SIGSEGV (exit 139) — host driver/PhysX incompatibility"
    elif [ "${GPU_RC}" -ne 0 ]; then
      GPU_DIAG="non-zero exit ${GPU_RC}"
    else
      GPU_DIAG="completed without printing 'ok' (last line: '${GPU_LAST}')"
    fi
    echo "  [NOTE] GPU PhysX gym.create_sim failed: ${GPU_DIAG}"
    echo "         Host NVIDIA driver is likely incompatible with IsaacGym Preview 4"
    echo "         (validated against driver ~535; drivers >=570 known to SIGSEGV in PhysX)."
    echo "         Workarounds: (a) downgrade host driver to 535.x series;"
    echo "                      (b) migrate to IsaacLab + IsaacSim 4.x for current drivers;"
    echo "                      (c) use this container only for code-paths that do not"
    echo "                          create a PhysX sim (offline RL, dataset loading,"
    echo "                          algorithm unit tests)."
    echo "  [INFO] This is NOT counted as a smoke FAIL — CPU PhysX path is functional."
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
