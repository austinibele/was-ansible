#!/usr/bin/env bash
# test_server.sh – spin up a single container running the K3s control-plane via our bootstrap_server.sh
set -euo pipefail

IMAGE=${IMAGE:-jrei/systemd-ubuntu:22.04}
NETWORK_NAME=${NETWORK_NAME:-was-ansible-net}
K3S_TOKEN=${K3S_TOKEN:-"K108.dummy-token-string"}
SCRIPT_START="$(date +%s%N)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  -e ENVIRONMENT=test \
  -e SERVER_EXTRA_ARGS="--token ${K3S_TOKEN}" \
  "${IMAGE}" \
  /sbin/init >/dev/null

echo "[+] Running server bootstrap..."
docker exec "${SERVER_CONTAINER}" bash /workspace/ansible/bootstrap_server.sh

SERVER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${SERVER_CONTAINER}")
K3S_URL="https://${SERVER_IP}:6443"

echo "[+] Waiting for K3s control-plane to report Ready node ..."
if ! docker exec "${SERVER_CONTAINER}" bash -c 'for i in {1..36}; do k3s kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready" && exit 0; sleep 5; done; exit 1'; then
  echo "❌ K3s control-plane did not become Ready in 3 minutes" && exit 1
fi

# Retrieve kubeconfig for local kubectl usage if desired
docker cp "${SERVER_CONTAINER}:/etc/rancher/k3s/k3s.yaml" "${REPO_ROOT}/k3s-server-kubeconfig.yaml" >/dev/null 2>&1 || true

echo ""
echo "✅ Control-plane ready!"
echo "Export these variables then run ./test_worker.sh:" && echo ""
echo "export NETWORK_NAME=${NETWORK_NAME}"
echo "export K3S_URL=${K3S_URL}"
echo "export K3S_TOKEN=${K3S_TOKEN}"
echo "export SERVER_CONTAINER=${SERVER_CONTAINER}" 