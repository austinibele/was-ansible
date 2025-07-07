#!/bin/bash
# ------------------------------------------------------------------
# Minimal bootstrap for an *edge* K3s agent
# ------------------------------------------------------------------
# Render this script with the four env-vars below substituted at launch.
#   K3S_URL         = https://<server-ip>:6443
#   K3S_TOKEN       = <node-token from server>
#   NODE_LABELS     = env=edge,tenant=<TENANT_ID>
#   AGENT_EXTRA_ARGS= --flannel-backend=wireguard-native   (optional)
#
# Then feed it to cloud-init, user-data, or just run via SSH.
# ------------------------------------------------------------------

set -euxo pipefail

# ▶ 1. Basic tooling ------------------------------------------------
if command -v apt-get &>/dev/null; then
  apt-get update -y && apt-get install -y python3-pip git
else
  yum install -y python3-pip git
fi
pip3 install --no-cache-dir ansible



# --- install Galaxy deps ------------------------------------
# Download requirements files first, then use local paths
curl -o /tmp/requirements.yml https://raw.githubusercontent.com/austinibele/was-ansible/refs/heads/main/ansible/requirements.yml
ansible-galaxy collection install -r /tmp/requirements.yml
ansible-galaxy role      install -r /tmp/requirements.yml
# -----------------------------------------------------------------

# existing ansible-pull invocation
ansible-pull \
  -U https://github.com/austinibele/was-ansible.git \
  ansible/playbooks/k3s_agent.yml \
  -e "k3s_url=$K3S_URL" \
  -e "k3s_token=$K3S_TOKEN" \
  -e "node_labels=$NODE_LABELS" \
  -e "agent_extra_args=$AGENT_EXTRA_ARGS"