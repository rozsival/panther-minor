#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 4. SSH Hardening
# =============================================================================
log_info "Configuring SSH ($SSHD_CONFIG)..."

# Back up original config (once)
if [[ ! -f "${SSHD_CONFIG}.orig" ]]; then
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.orig"
  log_info "Original sshd_config backed up to ${SSHD_CONFIG}.orig"
fi

log_info "Applying SSH hardening via Augeas..."
# augtool commands to update sshd_config
# -s saves automatically
# -f reads from stdin
augtool -s <<EOF
set /files/etc/ssh/sshd_config/Port "$SSH_PORT"
set /files/etc/ssh/sshd_config/PasswordAuthentication no
set /files/etc/ssh/sshd_config/ChallengeResponseAuthentication no
set /files/etc/ssh/sshd_config/UsePAM no
set /files/etc/ssh/sshd_config/PermitRootLogin no
set /files/etc/ssh/sshd_config/MaxAuthTries 3
set /files/etc/ssh/sshd_config/LoginGraceTime 30
set /files/etc/ssh/sshd_config/X11Forwarding no
set /files/etc/ssh/sshd_config/AllowTcpForwarding no
set /files/etc/ssh/sshd_config/AllowUsers/1 "$ALLOWED_USER"
EOF

log_info "Validating SSH configuration..."
sshd -t || log_error "sshd configuration is invalid -- aborting to avoid locking you out."

log_info "Restarting SSH service..."
systemctl restart ssh
log_success "SSH hardened on port $SSH_PORT. AllowUsers: $ALLOWED_USER"
