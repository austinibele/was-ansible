#!/usr/bin/env bash
# test_worker.sh – spin up a worker container that joins an existing control-plane
set -euo pipefail

IMAGE=${IMAGE:-jrei/systemd-ubuntu:22.04}
NETWORK_NAME=${NETWORK_NAME:?Set NETWORK_NAME same as server network}
K3S_URL=${K3S_URL:?Set to https://<server-ip>:6443}
K3S_TOKEN=${K3S_TOKEN:?Set token used by server}
NODE_LABELS=${NODE_LABELS:-"env=edge,tenant=test"}
AGENT_EXTRA_ARGS=${AGENT_EXTRA_ARGS:-""}
SCRIPT_START="$(date +%s%N)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_CONTAINER="was-ansible-worker-${SCRIPT_START}"

cleanup() {
  set +e
  echo "[+] Cleaning up worker container ..."
  docker rm -f "${WORKER_CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

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
  -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 \
  -e K3S_URL="${K3S_URL}" \
  -e K3S_TOKEN="${K3S_TOKEN}" \
  -e NODE_LABELS="${NODE_LABELS}" \
  -e AGENT_EXTRA_ARGS="${AGENT_EXTRA_ARGS}" \
  "${IMAGE}" \
  /sbin/init >/dev/null

echo "[+] Bootstrapping worker..."
docker exec "${WORKER_CONTAINER}" bash /workspace/ansible/edge_user_data.sh

echo "[+] Worker bootstrap complete – check server nodes list." 