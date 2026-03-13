#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Extend LVM logical volume to full disk capacity."

# =============================================================================
# 0. Init server workspace
# =============================================================================
log_info "Extending LVM logical volume to full disk capacity..."
lvextend -An -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
resize2fs /dev/ubuntu-vg/ubuntu-lv
log_success "Disk fully allocated."

log_info "Setting up server timezone to Europe/Prague..."
timedatectl set-timezone Europe/Prague
log_success "Timezone set to Europe/Prague."

