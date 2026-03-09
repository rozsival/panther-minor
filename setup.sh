#!/usr/bin/env bash
# =============================================================================
# Panther Minor - AI Workstation Setup
# https://github.com/rozsival/panther-minor
#
# Usage:
#   git clone https://github.com/rozsival/panther-minor.git && sudo bash panther-minor/setup.sh
# =============================================================================

set -euo pipefail

# -- Initial Checks ------------------------------------------------------------
[[ $EUID -ne 0 ]] && { echo "[ERROR] This script must be run as root (use sudo)." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_PATH="${SCRIPT_DIR}/scripts"

# Source common config
source "${SCRIPTS_PATH}/common.sh"

# Clear previous actions if any
cat /dev/null > "$ACTIONS_FILE"

# -- Execution -----------------------------------------------------------------
echo -e "${BLUE}🐆 ${SERVER_NAME} modular setup starting...${NC}\n"

for script in "${SCRIPTS_PATH}"/[0-9][0-9]-*.sh; do
  if [[ -x "$script" ]]; then
    "$script"
  else
    bash "$script"
  fi
done

# =============================================================================
# Final Summary
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🐆 ${SERVER_NAME} setup complete!            ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
printf "${GREEN}║  1. Packages : %-30s║${NC}\n" "installed"
printf "${GREEN}║  2. Docker   : %-30s║${NC}\n" "ready"
printf "${GREEN}║  3. Tailscale: %-30s║${NC}\n" "installed"
printf "${GREEN}║  4. SSH      : %-30s║${NC}\n" "hardened (port ${SSH_PORT})"
printf "${GREEN}║  5. UFW      : %-30s║${NC}\n" "active"
printf "${GREEN}║  6. fail2ban : %-30s║${NC}\n" "active"
printf "${GREEN}║  7. AMD GPU  : %-30s║${NC}\n" "v7.2 installed"
printf "${GREEN}║  8. GRUB     : %-30s║${NC}\n" "parameters set"
printf "${GREEN}║  9. Git      : %-30s║${NC}\n" "user/email/rebase set"
printf "${GREEN}║ 10. Shell    : %-30s║${NC}\n" "Starship active"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

if [[ -s "$ACTIONS_FILE" ]]; then
  echo ""
  log_warn "⚠  ACTIONS REQUIRED TO FINISH SETUP:"
  while IFS= read -r line; do
    echo -e "   ${YELLOW}•${NC} $line"
  done < "$ACTIONS_FILE"
fi

echo ""
log_info "Reconnection: ssh -p ${SSH_PORT} ${ALLOWED_USER}@<server-ip>"

# Clean up
rm -f "$ACTIONS_FILE"

# -- Reboot Prompt -------------------------------------------------------------
echo ""
read -p "System reboot is required to apply all changes. Reboot now? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  log_info "Rebooting system in 5 seconds..."
  sleep 5
  reboot
else
  log_warn "Reboot skipped. Please remember to reboot manually."
  # Hand off to a fresh login shell as the allowed user
  exec su - "${ALLOWED_USER}"
fi
