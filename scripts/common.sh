#!/usr/bin/env bash
# -- Colour helpers ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Config --------------------------------------------------------------------
SSH_PORT=2222
ALLOWED_USER=$USER
SSHD_CONFIG=/etc/ssh/sshd_config
FAIL2BAN_JAIL=/etc/fail2ban/jail.local

# -- Deferred Actions ----------------------------------------------------------
# A file to store actions that need user attention at the end
ACTIONS_FILE="/tmp/panther_minor_actions"
[[ -f "$ACTIONS_FILE" ]] || touch "$ACTIONS_FILE"

register_action() {
  echo "$*" >> "$ACTIONS_FILE"
}
