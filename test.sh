#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# test.sh - End-to-end test harness for the WAS-Ansible k3s bootstrapping repo
# -----------------------------------------------------------------------------
# This script spins up a throw-away Ubuntu container (acting as a lightweight
# VM) and runs the repo's edge bootstrap just like cloud-init would.  Nothing
# is installed on the host machine – everything happens inside the container.
#
# Usage:
#   ./test.sh                         # run with default dummy values
#   K3S_URL="https://10.0.0.10:6443" \
#   K3S_TOKEN="K108.abc..."          \
#   NODE_LABELS="env=edge,tenant=42" \
#   AGENT_EXTRA_ARGS="--node-ip 10.0.0.11" \
#   ./test.sh
#
# Required binaries on host:
#   - docker (>=20.10)
#
# The container is removed automatically when the test finishes.
# -----------------------------------------------------------------------------
set -euo pipefail

# --- Configuration -----------------------------------------------------------
IMAGE=${IMAGE:-ubuntu:22.04}
K3S_URL=${K3S_URL:-"https://127.0.0.1:6443"}
K3S_TOKEN=${K3S_TOKEN:-"K108.dummy-token-string"}
NODE_LABELS=${NODE_LABELS:-"env=edge,tenant=test"}
AGENT_EXTRA_ARGS=${AGENT_EXTRA_ARGS:-""}

# A unique container name so several runs can happen in parallel if needed.
CONTAINER_NAME="was-ansible-test-$(date +%s%N)"

# The path to this repo on the host will be mounted read-only inside the
# container at /workspace so we always test the local checkout.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helper functions --------------------------------------------------------
cleanup() {
  # Ensure the container is removed even if the script is interrupted.
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
    echo "[+] Cleaning up container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" &>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# --- Launch the ephemeral test container ------------------------------------
echo "[+] Starting test container '${CONTAINER_NAME}' using image '${IMAGE}'..."
docker run \
  --name "${CONTAINER_NAME}" \
  --privileged \
  --detach \
  --volume "${REPO_ROOT}:/workspace:ro" \
  --workdir /workspace \
  --env K3S_URL="${K3S_URL}" \
  --env K3S_TOKEN="${K3S_TOKEN}" \
  --env NODE_LABELS="${NODE_LABELS}" \
  --env AGENT_EXTRA_ARGS="${AGENT_EXTRA_ARGS}" \
  "${IMAGE}" \
  tail -f /dev/null >/dev/null

# --- Run the edge bootstrap script ------------------------------------------
echo "[+] Running edge bootstrap script..."
echo "    K3S_URL: ${K3S_URL}"
echo "    NODE_LABELS: ${NODE_LABELS}"
echo "    AGENT_EXTRA_ARGS: ${AGENT_EXTRA_ARGS}"
echo ""

if docker exec "${CONTAINER_NAME}" bash /workspace/ansible/edge_user_data.sh; then
  echo ""
  echo "✅ Bootstrap script completed successfully!"
else
  echo ""
  echo "❌ Bootstrap script failed!"
  echo ""
  echo "--- Container logs (last 20 lines) ---"
  docker logs "${CONTAINER_NAME}" 2>&1 | tail -20
  exit 1
fi 