#!/usr/bin/env bash
# -- Colour helpers ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Config --------------------------------------------------------------------
SERVER_NAME=panther-minor
ALLOWED_USER=vit
SSH_PORT=2222
SSHD_CONFIG=/etc/ssh/sshd_config
FAIL2BAN_JAIL=/etc/fail2ban/jail.local

# -- Deferred Actions ----------------------------------------------------------
# A file to store actions that need user attention at the end
ACTIONS_FILE="/tmp/${SERVER_NAME}_actions"
[[ -f "$ACTIONS_FILE" ]] || touch "$ACTIONS_FILE"

register_action() {
  echo "$*" >> "$ACTIONS_FILE"
}

# -- Bashrc Helpers ------------------------------------------------------------
register_bashrc_entry() {
  local label="$1"
  local cmd="$2"
  local user="${3:-$ALLOWED_USER}"
  local bashrc="/home/$user/.bashrc"

  if ! grep -qF "$cmd" "$bashrc" 2>/dev/null; then
    log_info "Adding $label to $bashrc..."
    echo -e "\n# $label\n$cmd" >> "$bashrc"
    chown "$user:$user" "$bashrc"
  fi
}
