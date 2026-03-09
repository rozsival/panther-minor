#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 10. Shell setup
# =============================================================================
log_info "Installing Starship prompt..."
curl -fsSL https://starship.rs/install.sh | sh -s -- --yes > /dev/null

register_bashrc_entry "Starship prompt" 'eval "$(starship init bash)"'
log_success "Starship installed."
