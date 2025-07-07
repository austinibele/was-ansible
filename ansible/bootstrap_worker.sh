#!/bin/bash
# ------------------------------------------------------------------
# Minimal bootstrap for an *edge* K3s agent
# ------------------------------------------------------------------
# Render this script with the four env-vars below substituted at launch.
#   K3S_URL         = https://<server-ip>:6443
#   K3S_TOKEN       = <node-token from server>
#   NODE_LABELS     = env=edge,tenant=<TENANT_ID>
#   AGENT_EXTRA_ARGS= --flannel-backend=wireguard-native   (optional)
#   FORCE_UPDATE_DEPS = true to force update of ansible dependencies
#
# Then feed it to cloud-init, user-data, or just run via SSH.
# ------------------------------------------------------------------

set -euxo pipefail

# Environment variable definitions with defaults
K3S_URL=${K3S_URL:-""}
K3S_TOKEN=${K3S_TOKEN:-""}
NODE_LABELS=${NODE_LABELS:-"env=edge,tenant=test"}
AGENT_EXTRA_ARGS=${AGENT_EXTRA_ARGS:-"--flannel-backend=wireguard-native"}
WHATSAPP_SERVER_IMAGE_URI=${WHATSAPP_SERVER_IMAGE_URI:-""}
FORCE_UPDATE_DEPS=${FORCE_UPDATE_DEPS:-"false"}
ENVIRONMENT=${ENVIRONMENT:-"production"}

# ▶ 1. Update ansible dependencies if needed ------------------------
if [ "${FORCE_UPDATE_DEPS:-false}" = "true" ] || [ ! -f /root/.ansible_deps_installed ]; then
  echo "Updating Ansible Galaxy dependencies..."
  /usr/local/bin/update-ansible-deps.sh
  touch /root/.ansible_deps_installed
else
  echo "Ansible dependencies already installed, skipping update..."
fi

# ▶ 2. Clean up any existing git state that might interfere with ansible-pull ------------------------------------
rm -rf /root/.ansible/pull/was-ansible 2>/dev/null || true
cd /tmp

# ▶ 3. Run the Ansible pull-mode playbook ---------------------------
ansible-pull \
  -U https://github.com/austinibele/was-ansible.git \
  ansible/playbooks/k3s_worker.yml \
  -i "localhost," \
  -l localhost \
  -c local \
  -e "k3s_url=$K3S_URL" \
  -e "k3s_token=$K3S_TOKEN" \
  -e "node_labels=$NODE_LABELS" \
  -e "agent_extra_args=$AGENT_EXTRA_ARGS" \
  -e "whatsapp_server_image_uri=${WHATSAPP_SERVER_IMAGE_URI:-}" \
  -e "environment=$ENVIRONMENT"