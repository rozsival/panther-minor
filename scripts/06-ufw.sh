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

# Essential services (AI/monitoring services are localhost-only via docker-compose)
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

ufw --force enable

log_success "UFW enabled. Open ports: SSH(${SSH_PORT}), HTTP(80), HTTPS(443). AI/monitoring services accessible via localhost/Tailscale only."
