#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 6. Firewall (UFW)
# =============================================================================
log_info "Configuring UFW..."

ufw --force reset > /dev/null          # start from a clean state
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

log_success "UFW enabled. Open ports: ${SSH_PORT}/tcp, 80/tcp, 443/tcp"
