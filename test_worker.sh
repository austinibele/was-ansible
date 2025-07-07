#!/usr/bin/env bash
# test_worker.sh – spin up a worker container that joins an existing control-plane
set -euo pipefail

IMAGE=${IMAGE:-jrei/systemd-ubuntu:22.04}
NODE_LABELS=${NODE_LABELS:-"env=edge,tenant=test"}
AGENT_EXTRA_ARGS=${AGENT_EXTRA_ARGS:-""}
SCRIPT_START="$(date +%s%N)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_CONTAINER="was-ansible-worker-${SCRIPT_START}"

# Function to prompt for value if not set
prompt_for_value() {
    local var_name="$1"
    local prompt_message="$2"
    local default_value="$3"
    
    if [ -z "${!var_name:-}" ]; then
        echo ""
        if [ -n "$default_value" ]; then
            read -p "$prompt_message [$default_value]: " input_value
            if [ -z "$input_value" ]; then
                eval "$var_name='$default_value'"
            else
                eval "$var_name='$input_value'"
            fi
        else
            while [ -z "${!var_name:-}" ]; do
                read -p "$prompt_message: " input_value
                if [ -n "$input_value" ]; then
                    eval "$var_name='$input_value'"
                else
                    echo "This value is required. Please enter a value."
                fi
            done
        fi
    fi
}

echo "============================================================"
echo "  K3S WORKER NODE SETUP"
echo "============================================================"
echo "This script will create a K3s worker node to join an existing cluster."
echo "If you haven't already, please get the connection parameters from the server."
echo ""

# Prompt for required values
prompt_for_value "NETWORK_NAME" "Docker network name" "was-ansible-net"
prompt_for_value "K3S_URL" "K3s server URL (e.g., https://172.18.0.2:6443)" ""
prompt_for_value "K3S_TOKEN" "K3s cluster token" ""
prompt_for_value "SERVER_CONTAINER" "Server container name" ""

echo ""
echo "Using the following configuration:"
echo "  Network Name:      $NETWORK_NAME"
echo "  K3S URL:           $K3S_URL"
echo "  K3S Token:         $K3S_TOKEN"
echo "  Server Container:  $SERVER_CONTAINER"
echo "============================================================"
echo ""

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

echo "[+] Worker bootstrap complete – cluster nodes:"
docker exec "${SERVER_CONTAINER}" k3s kubectl get nodes -o wide
docker exec "${SERVER_CONTAINER}" k3s kubectl get pods -A 

sleep 1000 # Keep the script running for testing purposes