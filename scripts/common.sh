#!/usr/bin/env bash
# -- Colour helpers -----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Guards -------------------------------------------------------------------
require_root() {
  [[ $EUID -eq 0 ]] || log_error "This script must be run as root (use sudo)."
}

# Prompt for confirmation unless already confirmed by a parent (e.g. setup.sh).
# Usage: confirm "Description of what is about to run"
confirm() {
  [[ "${PANTHER_CONFIRMED:-0}" == "1" ]] && return 0
  local msg="${1:-Are you sure you want to continue?}"
  echo -e "${YELLOW}[CONFIRM]${NC} $msg"
  read -r -p "         Proceed? (y/N): " _reply
  [[ "$_reply" =~ ^[Yy]$ ]] || { log_warn "Aborted."; exit 0; }
}

# -- Config -------------------------------------------------------------------
SERVER_NAME=$HOSTNAME
ALLOWED_USER=$USER
SSH_PORT=2222
SSHD_CONFIG=/etc/ssh/sshd_config
FAIL2BAN_JAIL=/etc/fail2ban/jail.local

# -- Deferred Actions ---------------------------------------------------------
# A file to store actions that need user attention at the end
ACTIONS_FILE="/tmp/${SERVER_NAME}_actions"
[[ -f "$ACTIONS_FILE" ]] || touch "$ACTIONS_FILE"

register_action() {
  echo "$*" >> "$ACTIONS_FILE"
}

# -- Bashrc Helpers -----------------------------------------------------------
register_bashrc_entry() {
  local label="$1"
  local cmd="$2"
  local user="${3:-$ALLOWED_USER}"
  local bashrc="/home/$user/.bashrc"

  if ! grep -qF "$cmd" "$bashrc"; then
    log_info "Adding $label to $bashrc..."
    echo -e "\n# $label\n$cmd" >> "$bashrc"
    chown "$user:$user" "$bashrc"
  fi
}
