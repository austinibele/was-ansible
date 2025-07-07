#!/bin/bash
set -euo pipefail
echo "Checking for updated Ansible dependencies..."
curl -o /tmp/requirements.yml https://raw.githubusercontent.com/austinibele/was-ansible/refs/heads/main/ansible/requirements.yml
ansible-galaxy collection install -r /tmp/requirements.yml --upgrade
ansible-galaxy role install -r /tmp/requirements.yml --force
rm /tmp/requirements.yml
echo "Dependencies updated successfully" 