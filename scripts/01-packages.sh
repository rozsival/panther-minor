#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 1. Essential Packages
# =============================================================================
log_info "Updating system and installing essential packages..."
apt update
apt upgrade -y
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
  unattended-upgrades \
  unzip

log_success "Essential packages installed."
