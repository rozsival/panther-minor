#!/usr/bin/env bash
# =============================================================================
# Panther Minor - AI Workstation Setup
# https://github.com/rozsival/panther-minor
#
# Usage:
#   git clone https://github.com/rozsival/panther-minor.git && sudo bash panther-minor/setup.sh
# =============================================================================

set -euo pipefail

# -- Colour helpers ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Root check ----------------------------------------------------------------
[[ $EUID -ne 0 ]] && log_error "This script must be run as root (use sudo)."

# -- Config --------------------------------------------------------------------
SSH_PORT=2222
ALLOWED_USER=$USER
SSHD_CONFIG=/etc/ssh/sshd_config
FAIL2BAN_JAIL=/etc/fail2ban/jail.local

# =============================================================================
# 1. Essential Packages
# =============================================================================
log_info "Updating system and installing essential packages..."
apt update && apt upgrade -y
apt install -y \
  augeas-lenses \
  augeas-tools \
  build-essential \
  htop \
  jq \
  nvtop \
  python3-full \
  python3-pip \
  tree \
  unzip > /dev/null

log_success "Essential packages installed."

# =============================================================================
# 2. SSH Hardening
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

# =============================================================================
# 3. Firewall (UFW)
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

# =============================================================================
# 4. fail2ban
# =============================================================================
log_info "Installing fail2ban..."
apt install -y fail2ban > /dev/null

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
systemctl enable --now fail2ban > /dev/null
systemctl restart fail2ban
log_success "fail2ban configured and running."

# =============================================================================
# 5. Docker group
# =============================================================================
log_info "Adding ${ALLOWED_USER} to the docker group..."
usermod -aG docker "${ALLOWED_USER}"
log_success "${ALLOWED_USER} added to docker group (effective on next login)."

# =============================================================================
# 6. Starship prompt
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

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🐆 Panther Minor setup complete!            ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
printf "${GREEN}║  Packages    : %-30s║${NC}\n" "essentials installed"
printf "${GREEN}║  SSH port    : %-30s║${NC}\n" "${SSH_PORT}"
printf "${GREEN}║  UFW rules   : %-30s║${NC}\n" "${SSH_PORT}/tcp  80/tcp  443/tcp"
printf "${GREEN}║  fail2ban    : %-30s║${NC}\n" "active"
printf "${GREEN}║  Docker      : %-30s║${NC}\n" "${ALLOWED_USER} added to group"
printf "${GREEN}║  HF CLI      : %-30s║${NC}\n" "installed"
printf "${GREEN}║  Starship    : %-30s║${NC}\n" "active"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
log_warn "⚠  Reconnect via: ssh -p ${SSH_PORT} ${ALLOWED_USER}@<server-ip>"

# Hand off to a fresh login shell as the allowed user so Starship is active immediately
exec su - "${ALLOWED_USER}"
