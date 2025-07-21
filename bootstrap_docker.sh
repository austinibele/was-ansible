#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# Helper: find the Ubuntu base codename the system is built on.
# ----------------------------------------------------------------------
get_base_codename() {
  local code
  # shellcheck source=/dev/null
  . /etc/os-release
  code="${UBUNTU_CODENAME:-}"
  [[ -z "$code" ]] && code="${VERSION_CODENAME:-}"
  if [[ -z "$code" ]]; then
    echo "Cannot determine Ubuntu codename from /etc/os-release" >&2
    exit 1
  fi
  echo "$code"
}

# ----------------------------------------------------------------------
# 1) Install AWS CLI ----------------------------------------------------
# ----------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
  echo ">> AWS CLI not found – installing…"
  curl -sSLo awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
  unzip -q awscliv2.zip
  sudo ./aws/install
  rm -rf awscliv2.zip aws
  echo "   Installed AWS CLI: $(aws --version 2>&1)"
else
  echo ">> AWS CLI already present: $(aws --version 2>&1)"
fi

# ----------------------------------------------------------------------
# 2) Install (or repair) Docker CE -------------------------------------
# ----------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo ">> Docker not found – installing…"
  # Determine correct Ubuntu codename _first_ so that we can repair any
  # previously-created Docker repository entry **before** running the
  # initial `apt-get update`.  If the repo still contains the literal
  # "$UBUNTU_CODENAME" placeholder, `apt-get update` will fail, which is
  # exactly what we are trying to avoid.

  CODENAME=$(get_base_codename)

  # Repair an existing, but broken, Docker list file that still contains
  # the placeholder rather than the real codename.  We only attempt the
  # fix when the placeholder string is detected.
  REPO_FILE=/etc/apt/sources.list.d/docker.list
  if [[ -f $REPO_FILE ]] && grep -q '\$UBUNTU_CODENAME' "$REPO_FILE"; then
    echo ">> Fixing stale Docker repo placeholder → $CODENAME"
    sudo sed -i -E "s#\\\$UBUNTU_CODENAME#$CODENAME#g" "$REPO_FILE"
  fi

  # Now it is safe to refresh package indices and install prerequisites.
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release

  # Add Docker’s GPG key (idempotent).
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Always (re-)write the Docker repo with the correct codename.
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

  sudo apt-get update -qq
  sudo apt-get install -y -qq \
       docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin

  echo "   Installed Docker: $(docker --version)"
else
  echo ">> Docker already present: $(docker --version)"
  # Repair repository codename if needed (helps Mint users).
  CODENAME=$(get_base_codename)
  REPO_FILE=/etc/apt/sources.list.d/docker.list
  if [[ -f $REPO_FILE ]] && ! grep -q " $CODENAME stable" "$REPO_FILE"; then
    echo ">> Fixing Docker repo codename → $CODENAME"
    sudo sed -i -E \
      "s#(download.docker.com/linux/ubuntu[[:space:]]+)[^[:space:]]+#\1${CODENAME}#" \
      "$REPO_FILE"
    sudo apt-get update -qq
  fi
fi

# ----------------------------------------------------------------------
# 3) Log in to ECR ------------------------------------------------------
# ----------------------------------------------------------------------
aws ecr get-login-password --region us-east-1 \
| docker login \
    --username AWS \
    --password-stdin 349514606126.dkr.ecr.us-east-1.amazonaws.com/myvisausa/crm-api
echo ">> ECR login complete."
