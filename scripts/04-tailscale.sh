#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Install Tailscale."

# =============================================================================
# 4. Tailscale
# =============================================================================
log_info "Installing Tailscale..."

# Add Tailscale's official GPG key and repository
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

apt update
apt install -y tailscale

if command -v tailscale; then
  log_success "Tailscale installed."
  register_action "Authenticate Tailscale: run 'sudo tailscale up' from your workstation via SSH (GUI with browser needed)."
else
  log_error "Tailscale installation failed."
fi
