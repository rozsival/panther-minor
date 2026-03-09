#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 9. Git configuration
# =============================================================================
log_info "Configuring Git for ${ALLOWED_USER}..."

# Configure Git globally for the allowed user
sudo -u "${ALLOWED_USER}" git config --global user.name "${SERVER_NAME}"
sudo -u "${ALLOWED_USER}" git config --global user.email "${ALLOWED_USER}@${SERVER_NAME}"
sudo -u "${ALLOWED_USER}" git config --global pull.rebase true

log_success "Git configured for ${ALLOWED_USER}."
