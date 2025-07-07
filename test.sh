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

# -----------------------------------------------------------------------------
# Multi-node test harness – control-plane + worker(s)
# -----------------------------------------------------------------------------

# Configurable parameters (override with env vars)
IMAGE=${IMAGE:-jrei/systemd-ubuntu:22.04}
K3S_TOKEN=${K3S_TOKEN:-"K108.dummy-token-string"}
NODE_LABELS=${NODE_LABELS:-"env=edge,tenant=test"}
AGENT_EXTRA_ARGS=${AGENT_EXTRA_ARGS:-""}
NETWORK_NAME=${NETWORK_NAME:-was-ansible-net}

# Derived variables
SCRIPT_START="$(date +%s%N)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_CONTAINER="was-ansible-server-${SCRIPT_START}"
WORKER_CONTAINER="was-ansible-worker-${SCRIPT_START}"

# Helper –  best-effort cleanup ------------------------------------------------
cleanup() {
  set +e
  echo "[+] Cleaning up containers & network ..."
  docker rm -f "${SERVER_CONTAINER}" "${WORKER_CONTAINER}" >/dev/null 2>&1 || true
  # Remove network only if we created it and it's now empty
  if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    if [ "$(docker network inspect -f '{{ len .Containers }}' "${NETWORK_NAME}")" = "0" ]; then
      docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# 1. Docker network (shared layer-2 for the containers)
# ----------------------------------------------------------------------------
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "[+] Creating Docker network '${NETWORK_NAME}'..."
  docker network create "${NETWORK_NAME}" >/dev/null
fi

# ----------------------------------------------------------------------------
# 2. Launch K3s server (control-plane) container
# ----------------------------------------------------------------------------
echo "[+] Starting K3s server container '${SERVER_CONTAINER}'..."
docker run \
  --name "${SERVER_CONTAINER}" \
  --privileged \
  --cgroupns host \
  --security-opt seccomp=unconfined \
  --detach \
  --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --network "${NETWORK_NAME}" \
  --hostname k3s-server \
  --volume "${REPO_ROOT}:/workspace:ro" \
  -e ENVIRONMENT=test \
  -e LANG=C.UTF-8 \
  -e LC_ALL=C.UTF-8 \
  -e SERVER_EXTRA_ARGS="--token ${K3S_TOKEN}" \
  "${IMAGE}" \
  /sbin/init >/dev/null

# Run the server bootstrap script ------------------------------------------------
echo "[+] Bootstrapping K3s server..."
docker exec "${SERVER_CONTAINER}" bash /workspace/ansible/server_user_data.sh

# Grab server IP within the docker network
SERVER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${SERVER_CONTAINER}")
K3S_URL="https://${SERVER_IP}:6443"

# Wait for API to come up (max 2 min)
echo "[+] Waiting for K3s API on ${K3S_URL} ..."
if ! docker exec "${SERVER_CONTAINER}" bash -c 'for i in {1..24}; do nc -z localhost 6443 && exit 0; sleep 5; done; exit 1'; then
  echo "❌ K3s API did not become ready in time" && exit 1
fi

# ----------------------------------------------------------------------------
# 3. Launch worker container & run edge bootstrap
# ----------------------------------------------------------------------------
echo "[+] Starting worker container '${WORKER_CONTAINER}'..."
docker run \
  --name "${WORKER_CONTAINER}" \
  --privileged \
  --cgroupns host \
  --security-opt seccomp=unconfined \
  --detach \
  --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --network "${NETWORK_NAME}" \
  --hostname k3s-worker \
  --volume "${REPO_ROOT}:/workspace:ro" \
  -e K3S_URL="${K3S_URL}" \
  -e K3S_TOKEN="${K3S_TOKEN}" \
  -e NODE_LABELS="${NODE_LABELS}" \
  -e AGENT_EXTRA_ARGS="${AGENT_EXTRA_ARGS}" \
  -e LANG=C.UTF-8 \
  -e LC_ALL=C.UTF-8 \
  "${IMAGE}" \
  /sbin/init >/dev/null

echo "[+] Bootstrapping K3s worker..."
docker exec "${WORKER_CONTAINER}" bash /workspace/ansible/edge_user_data.sh

# ----------------------------------------------------------------------------
# 4. Validation – list nodes & WhatsApp pod status
# ----------------------------------------------------------------------------
echo "[+] Validating cluster state..."
docker exec "${SERVER_CONTAINER}" k3s kubectl get nodes -o wide
docker exec "${SERVER_CONTAINER}" k3s kubectl get pods -n whatsapp

echo ""
echo "✅ Multi-node bootstrap completed successfully!" 