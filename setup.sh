#!/usr/bin/env bash
# =============================================================================
# Panther Minor — AI Workstation Setup
# https://github.com/rozsival/panther-minor
#
# Usage:
#   git clone https://github.com/rozsival/panther-minor.git && sudo bash panther-minor/setup.sh
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)."

# ── Config ────────────────────────────────────────────────────────────────────
SSH_PORT=2222
ALLOWED_USER=$USER
SSHD_CONFIG=/etc/ssh/sshd_config
FAIL2BAN_JAIL=/etc/fail2ban/jail.local

# =============================================================================
# 1. SSH Hardening
# =============================================================================
info "Configuring SSH ($SSHD_CONFIG)…"

# Back up original config (once)
if [[ ! -f "${SSHD_CONFIG}.orig" ]]; then
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.orig"
  info "Original sshd_config backed up to ${SSHD_CONFIG}.orig"
fi

# Helper: set or add a directive in sshd_config
set_sshd() {
  local key="$1" value="$2"
  # Replace existing (commented or uncommented) line, or append
  if grep -qE "^#?[[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
    sed -i -E "s|^#?[[:space:]]*(${key})[[:space:]].*|${key} ${value}|" "$SSHD_CONFIG"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}

set_sshd Port                          "$SSH_PORT"
set_sshd PasswordAuthentication        no
set_sshd ChallengeResponseAuthentication no
set_sshd UsePAM                        no
set_sshd PermitRootLogin               no
set_sshd MaxAuthTries                  3
set_sshd LoginGraceTime                30
set_sshd X11Forwarding                 no
set_sshd AllowTcpForwarding            no
set_sshd AllowUsers                    "$ALLOWED_USER"

info "Validating SSH configuration…"
sshd -t || error "sshd configuration is invalid — aborting to avoid locking you out."

info "Restarting SSH service…"
systemctl restart ssh
success "SSH hardened on port $SSH_PORT. AllowUsers: $ALLOWED_USER"

# =============================================================================
# 2. Firewall (UFW)
# =============================================================================
info "Configuring UFW…"

ufw --force reset > /dev/null          # start from a clean state
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

success "UFW enabled. Open ports: ${SSH_PORT}/tcp, 80/tcp, 443/tcp"

# =============================================================================
# 3. fail2ban
# =============================================================================
info "Installing fail2ban…"
apt-get update -qq
apt-get install -y fail2ban > /dev/null

info "Writing $FAIL2BAN_JAIL…"
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

info "Restarting fail2ban…"
systemctl enable --now fail2ban > /dev/null
systemctl restart fail2ban
success "fail2ban configured and running."

# =============================================================================
# 4. Docker group
# =============================================================================
info "Adding ${ALLOWED_USER} to the docker group…"
usermod -aG docker "${ALLOWED_USER}"
success "${ALLOWED_USER} added to docker group (effective on next login)."

# =============================================================================
# 5. Hugging Face CLI
# =============================================================================
info "Installing Hugging Face CLI…"
apt-get install -y python3-full python3-pip > /dev/null
sudo -u "${ALLOWED_USER}" bash -c "curl -LsSf https://hf.co/cli/install.sh | bash"
success "Hugging Face CLI installed for ${ALLOWED_USER}."

# =============================================================================
# 6. Starship prompt
# =============================================================================
info "Installing Starship prompt…"
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
success "Starship installed and added to ${BASHRC}."

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🐆 Panther Minor setup complete!            ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  SSH port    : ${SSH_PORT}                        ║${NC}"
echo -e "${GREEN}║  UFW rules   : ${SSH_PORT}/tcp  80/tcp  443/tcp   ║${NC}"
echo -e "${GREEN}║  fail2ban    : active                        ║${NC}"
echo -e "${GREEN}║  Docker      : ${ALLOWED_USER} added to group        ║${NC}"
echo -e "${GREEN}║  HF CLI      : installed                     ║${NC}"
echo -e "${GREEN}║  Starship    : active                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
warn "⚠  Reconnect via: ssh -p ${SSH_PORT} ${ALLOWED_USER}@<server-ip>"

# Hand off to a fresh login shell as the allowed user so Starship is active immediately
exec su - "${ALLOWED_USER}"
