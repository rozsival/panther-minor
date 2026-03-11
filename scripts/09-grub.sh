#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Update GRUB kernel parameters."

# =============================================================================
# 9. Kernel Parameters (GRUB)
# =============================================================================
log_info "Configuring GRUB kernel parameters..."

GRUB_FILE="/etc/default/grub"
NEW_PARAMS="amdgpu.mes=1 iommu=pt"

# Use Augeas to read the current value
CURRENT_CMDLINE=$(augtool -n get /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT | cut -d'=' -f2 | tr -d '"' | tr -d "'")

# Check if parameters are already there
UPDATED_CMDLINE="$CURRENT_CMDLINE"
for param in $NEW_PARAMS; do
  if [[ ! "$CURRENT_CMDLINE" =~ "$param" ]]; then
    UPDATED_CMDLINE="$UPDATED_CMDLINE $param"
  fi
done

# Trim leading/trailing spaces
UPDATED_CMDLINE=$(echo "$UPDATED_CMDLINE" | xargs)

if [[ "$CURRENT_CMDLINE" != "$UPDATED_CMDLINE" ]]; then
  log_info "Updating GRUB_CMDLINE_LINUX_DEFAULT to: $UPDATED_CMDLINE"
  augtool -s <<EOF
set /files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT "'$UPDATED_CMDLINE'"
EOF
  log_info "Running update-grub..."
  update-grub
  log_success "GRUB configuration updated."
else
  log_success "GRUB kernel parameters already set."
fi
