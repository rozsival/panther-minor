#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

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

curl -sSL https://raw.githubusercontent.com/AlexsJones/llmfit/main/install.sh | bash > /dev/null
log_success "Essential packages installed."
