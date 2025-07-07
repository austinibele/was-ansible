#!/usr/bin/env bash
# test_server.sh – spin up a single container running the K3s control-plane via our bootstrap_server.sh
set -euo pipefail

IMAGE=${IMAGE:-jrei/systemd-ubuntu:22.04}
NETWORK_NAME=${NETWORK_NAME:-was-ansible-net}
K3S_TOKEN=${K3S_TOKEN:-"K108.dummy-token-string"}
ENVIRONMENT=${ENVIRONMENT:-"test"}
SERVER_EXTRA_ARGS=${SERVER_EXTRA_ARGS:-"--token ${K3S_TOKEN}"}
FORCE_UPDATE_DEPS=${FORCE_UPDATE_DEPS:-"false"}
SCRIPT_START="$(date +%s%N)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_CONTAINER="was-ansible-server-${SCRIPT_START}"

cleanup() {
  set +e
  echo "[+] Cleaning up server container & network ..."
  docker rm -f "${SERVER_CONTAINER}" >/dev/null 2>&1 || true
  if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    if [ "$(docker network inspect -f '{{ len .Containers }}' "${NETWORK_NAME}")" = "0" ]; then
      docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT INT TERM

if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "[+] Creating Docker network '${NETWORK_NAME}'..." && docker network create "${NETWORK_NAME}" >/dev/null
fi

echo "[+] Starting control-plane container '${SERVER_CONTAINER}'..."
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
  -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 \
  -e ENVIRONMENT="${ENVIRONMENT}" \
  -e SERVER_EXTRA_ARGS="${SERVER_EXTRA_ARGS}" \
  -e FORCE_UPDATE_DEPS="${FORCE_UPDATE_DEPS}" \
  "${IMAGE}" \
  /sbin/init >/dev/null

echo "[+] Running server bootstrap..."
docker exec "${SERVER_CONTAINER}" bash /workspace/server/bootstrap_server.sh

SERVER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${SERVER_CONTAINER}")
K3S_URL="https://${SERVER_IP}:6443"


echo ""
echo "✅ Control-plane ready!"
echo ""
echo "============================================================"
echo "  WORKER CONNECTION PARAMETERS"
echo "============================================================"
echo "To start a worker node, run ./test_worker.sh with these values:"
echo ""
echo "Network Name:      ${NETWORK_NAME}"
echo "K3S URL:           ${K3S_URL}"
echo "K3S Token:         ${K3S_TOKEN}"
echo "Server Container:  ${SERVER_CONTAINER}"
echo ""
echo "You can either:"
echo "  1) Export these as environment variables:"
echo "     export NETWORK_NAME='${NETWORK_NAME}'"
echo "     export K3S_URL='${K3S_URL}'"
echo "     export K3S_TOKEN='${K3S_TOKEN}'"
echo "     export SERVER_CONTAINER='${SERVER_CONTAINER}'"
echo "     ./test_worker.sh"
echo ""
echo "  2) Or just run ./test_worker.sh and enter them when prompted"
echo "============================================================"
echo ""
echo "[+] Waiting for worker node to join cluster (timeout: 5 minutes) ..."
echo "    Press Ctrl+C to skip worker wait and exit"

# Wait for a worker node to join the cluster
if docker exec "${SERVER_CONTAINER}" bash -c 'for i in {1..60}; do 
  node_count=$(k3s kubectl get nodes --no-headers 2>/dev/null | wc -l)
  if [ "$node_count" -gt 1 ]; then
    echo "Worker node detected, waiting for Ready status..."
    k3s kubectl get nodes --no-headers 2>/dev/null | grep -v "k3s-server" | grep -q "Ready" && exit 0
  fi
  sleep 5
done; exit 1'; then
  echo "✅ Worker node joined and is Ready!"
  echo ""
  echo "Final cluster status:"
  docker exec "${SERVER_CONTAINER}" k3s kubectl get nodes -o wide
  docker exec "${SERVER_CONTAINER}" k3s kubectl get pods -A
else
  echo "⚠️  No worker node joined within 5 minutes"
  echo "   Server is ready for worker connections"
fi 