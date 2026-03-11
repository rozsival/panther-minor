#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 7. fail2ban
# =============================================================================
log_info "Installing fail2ban..."
apt install -y fail2ban

log_info "Writing $FAIL2BAN_JAIL..."
cat > "$FAIL2BAN_JAIL" <<EOF
[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 1h
findtime = 10m
EOF

log_info "Restarting fail2ban..."
systemctl enable --now fail2ban
systemctl restart fail2ban
log_success "fail2ban configured and running."
