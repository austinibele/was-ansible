#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------
# 1) Install (or verify) Tailscale -------------------------------------
# ----------------------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  echo ">> Tailscale not found – installing…"

  curl -fsSL https://tailscale.com/install.sh | sh

  echo "   Installed Tailscale: $(tailscale version)"
else
  echo ">> Tailscale already present: $(tailscale version)"
fi

# ----------------------------------------------------------------------
# 2) Ensure tailscaled service is active --------------------------------
# ----------------------------------------------------------------------
if ! systemctl is-active --quiet tailscaled; then
  echo ">> Starting tailscaled service…"
  sudo systemctl enable --now tailscaled
else
  echo ">> tailscaled service already running."
fi

# ----------------------------------------------------------------------
# 3) Connect to Tailnet -------------------------------------------------
# ----------------------------------------------------------------------
if tailscale status >/dev/null 2>&1; then
  echo ">> Tailscale already connected to tailnet."
else
  echo ">> Tailscale is not logged into a tailnet – attempting login…"

  if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
    echo "   Using provided TAILSCALE_AUTHKEY."
    sudo tailscale up --authkey "$TAILSCALE_AUTHKEY"
  else
    echo "   No TAILSCALE_AUTHKEY provided. Launching interactive login (may require browser access)…"
    sudo tailscale up
  fi
fi 

# ----------------------------------------------------------------------
# 4) Display Tailscale IP address(es) ----------------------------------
# ----------------------------------------------------------------------
echo ">> Tailscale IP address(es) for this node: $(tailscale ip -4)"
