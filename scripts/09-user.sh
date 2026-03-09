#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 9. Starship prompt
# =============================================================================
log_info "Installing Starship prompt..."
curl -fsSL https://starship.rs/install.sh | sh -s -- --yes > /dev/null

# Wire into the allowed user's .bashrc (idempotent)
BASHRC="/home/${ALLOWED_USER}/.bashrc"
STARSHIP_INIT='eval "$(starship init bash)"'
if ! grep -qF "starship init bash" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# Starship prompt" >> "$BASHRC"
  echo "$STARSHIP_INIT" >> "$BASHRC"
fi
chown "${ALLOWED_USER}:${ALLOWED_USER}" "$BASHRC"
log_success "Starship installed and added to ${BASHRC}."
