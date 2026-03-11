#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 11. Shell setup
# =============================================================================
log_info "Installing Starship prompt..."
apt install -y starship

register_bashrc_entry "Starship" 'eval "$(starship init bash)"'
log_success "Starship installed."
