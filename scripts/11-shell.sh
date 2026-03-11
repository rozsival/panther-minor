#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Install Starship shell prompt."

# =============================================================================
# 11. Shell setup
# =============================================================================
log_info "Setting up shell with Starship prompt for ${ALLOWED_USER}..."
apt install -y starship

usermod -aG video "$ALLOWED_USER"
usermod -aG render "$ALLOWED_USER"
loginctl enable-linger "$ALLOWED_USER"

register_bashrc_entry "Starship" 'eval "$(starship init bash)"'
log_success "Shell set up with Starship prompt for ${ALLOWED_USER}."
