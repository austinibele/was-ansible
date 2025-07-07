#!/bin/bash
# ------------------------------------------------------------------
# Minimal bootstrap for a K3s control-plane (server) node
# ------------------------------------------------------------------
# Required env vars (set via cloud-init or user-data):
#   ENVIRONMENT        = prod|dev (optional, default prod)
#   SERVER_EXTRA_ARGS  = optional extra args passed to the K3s server
#   FORCE_UPDATE_DEPS  = true to force update of ansible dependencies
# ------------------------------------------------------------------
set -euxo pipefail

# Environment variable definitions with defaults
ENVIRONMENT=${ENVIRONMENT:-"prod"}
SERVER_EXTRA_ARGS=${SERVER_EXTRA_ARGS:-""}
FORCE_UPDATE_DEPS=${FORCE_UPDATE_DEPS:-"false"}

# ▶ 1. Update ansible dependencies if needed ------------------------
if [ "${FORCE_UPDATE_DEPS:-false}" = "true" ] || [ ! -f /root/.ansible_deps_installed ]; then
  echo "Updating Ansible Galaxy dependencies..."
  /usr/local/bin/update-ansible-deps.sh
  touch /root/.ansible_deps_installed
else
  echo "Ansible dependencies already installed, skipping update..."
fi

# ▶ 2. Clean up any existing git state that might interfere with ansible-pull ----
rm -rf /root/.ansible/pull/was-ansible 2>/dev/null || true
cd /tmp

# ▶ 3. Run the Ansible pull-mode playbook ---------------------------
ansible-pull \
  -U https://github.com/austinibele/was-ansible.git \
  server/k3s_server.yml \
  -l localhost \
  -e "environment=${ENVIRONMENT:-prod}" \
  -e "server_extra_args=${SERVER_EXTRA_ARGS:-}" 