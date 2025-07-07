#!/usr/bin/env bash
# test_worker.sh – spin up a worker container that joins an existing control-plane
set -euo pipefail

IMAGE=${IMAGE:-jrei/systemd-ubuntu:22.04}
NETWORK_NAME=${NETWORK_NAME:-was-ansible-net}
K3S_URL=${K3S_URL:-https://127.0.0.1:6443}
K3S_TOKEN=${K3S_TOKEN:-K108.dummy-token-string}
SERVER_CONTAINER=${SERVER_CONTAINER:-$(docker ps -qf "name=was-ansible-server")}
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
docker exec "${WORKER_CONTAINER}" bash /workspace/ansible/bootstrap_worker.sh

echo "[+] Waiting for worker node to report Ready ..."
if ! docker exec "${SERVER_CONTAINER}" bash -c 'for i in {1..36}; do k3s kubectl get nodes --no-headers 2>/dev/null | grep -q "k3s-worker.*Ready" && exit 0; sleep 5; done; exit 1'; then
  echo "❌ Worker node did not become Ready in 3 minutes" && exit 1
fi

echo "[+] Worker bootstrap complete – cluster nodes:"
docker exec "${SERVER_CONTAINER}" k3s kubectl get nodes -o wide
docker exec "${SERVER_CONTAINER}" k3s kubectl get pods -A 