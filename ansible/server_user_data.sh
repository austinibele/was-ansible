#!/bin/bash
# ------------------------------------------------------------------
# Minimal bootstrap for a K3s control-plane (server) node
# ------------------------------------------------------------------
# Required env vars (set via cloud-init or user-data):
#   ENVIRONMENT        = prod|dev (optional, default prod)
#   SERVER_EXTRA_ARGS  = optional extra args passed to the K3s server
# ------------------------------------------------------------------
set -euxo pipefail

# ▶ 1. Basic tooling ------------------------------------------------
if command -v apt-get &>/dev/null; then
  apt-get update -y && apt-get install -y python3-pip git curl
else
  yum install -y python3-pip git curl
fi
pip3 install --no-cache-dir ansible

# ▶ 2. Clean up any existing git state that might interfere with ansible-pull ----
rm -rf /root/.ansible/pull/was-ansible 2>/dev/null || true
cd /tmp

# ▶ 3. Install Galaxy deps ------------------------------------
curl -o /tmp/requirements.yml https://raw.githubusercontent.com/austinibele/was-ansible/refs/heads/main/ansible/requirements.yml
ansible-galaxy collection install -r /tmp/requirements.yml
ansible-galaxy role      install -r /tmp/requirements.yml

# ▶ 4. Run the Ansible pull-mode playbook ---------------------------
ansible-pull \
  -U https://github.com/austinibele/was-ansible.git \
  ansible/playbooks/k3s_server.yml \
  -e "environment=${ENVIRONMENT:-prod}" \
  -e "server_extra_args=${SERVER_EXTRA_ARGS:-}" 