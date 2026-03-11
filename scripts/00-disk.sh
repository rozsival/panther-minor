#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Extend LVM logical volume to full disk capacity."

# =============================================================================
# 0. Disk — Extend LVM to full capacity
# =============================================================================
log_info "Extending LVM logical volume to full disk capacity..."

lvextend -An -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
resize2fs /dev/ubuntu-vg/ubuntu-lv

log_success "Disk fully allocated."

