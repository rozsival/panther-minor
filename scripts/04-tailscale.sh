#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 4. Tailscale
# =============================================================================
log_info "Installing Tailscale..."

# Add Tailscale's official GPG key and repository
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list >/dev/null

apt update > /dev/null
apt install -y tailscale > /dev/null

if command -v tailscale >/dev/null 2>&1; then
  log_success "Tailscale installed."
  register_action "Authenticate Tailscale: run 'sudo tailscale up' from your workstation via SSH (GUI with browser needed)."
else
  log_error "Tailscale installation failed."
fi
