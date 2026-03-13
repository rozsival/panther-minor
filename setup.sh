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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_PATH="${SCRIPT_DIR}/scripts"

# Source common config
source "${SCRIPTS_PATH}/common.sh"

require_root
confirm "This will configure the full ${SERVER_NAME} workstation setup."

# Clear previous actions if any
: > "$ACTIONS_FILE"

# Signal to all sub-scripts that confirmation was already granted
export PANTHER_CONFIRMED=1

# -- Execution -----------------------------------------------------------------
echo -e "${BLUE}🐆 ${SERVER_NAME} setup starting...${NC}\n"

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
printf "${GREEN}║  0. Init     : %-30s║${NC}\n" "complete"
printf "${GREEN}║  1. Packages : %-30s║${NC}\n" "installed"
printf "${GREEN}║  2. Brew     : %-30s║${NC}\n" "ready"
printf "${GREEN}║  3. Docker   : %-30s║${NC}\n" "ready"
printf "${GREEN}║  4. Tailscale: %-30s║${NC}\n" "installed"
printf "${GREEN}║  5. SSH      : %-30s║${NC}\n" "secured"
printf "${GREEN}║  6. UFW      : %-30s║${NC}\n" "active"
printf "${GREEN}║  7. fail2ban : %-30s║${NC}\n" "active"
printf "${GREEN}║  8. AMD GPU  : %-30s║${NC}\n" "installed"
printf "${GREEN}║  9. GRUB     : %-30s║${NC}\n" "configured"
printf "${GREEN}║ 10. Git      : %-30s║${NC}\n" "configured"
printf "${GREEN}║ 11. Shell    : %-30s║${NC}\n" "configured"
printf "${GREEN}║ 12. Env      : %-30s║${NC}\n" "synced"
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
read -p "System reboot is required to apply all changes. Reboot now? (y/N): " _reboot
if [[ "$_reboot" =~ ^[Yy]$ ]]; then
  log_info "Rebooting system in 5 seconds..."
  sleep 5
  reboot
else
  log_warn "Reboot skipped. Please remember to reboot manually."
  # Hand off to a fresh login shell as the allowed user
  exec su - "${ALLOWED_USER}"
fi
