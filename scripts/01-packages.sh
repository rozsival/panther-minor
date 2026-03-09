#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# =============================================================================
# 1. Essential Packages
# =============================================================================
log_info "Updating system and installing essential packages..."
apt update && apt upgrade -y > /dev/null
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
  unzip > /dev/null

log_info "Installing Homebrew (as ${ALLOWED_USER})..."
# Pre-create Homebrew directories to avoid permission issues
mkdir -p /home/linuxbrew/.linuxbrew
chown -R "${ALLOWED_USER}:${ALLOWED_USER}" /home/linuxbrew

# Install Homebrew as the allowed user
sudo -u "${ALLOWED_USER}" bash -c 'NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' > /dev/null

# Determine the brew prefix for the allowed user
BREW_PREFIX=$(sudo -u "${ALLOWED_USER}" bash -c '
  if [ -d ~/.linuxbrew ]; then
    echo "$HOME/.linuxbrew"
  elif [ -d /home/linuxbrew/.linuxbrew ]; then
    echo "/home/linuxbrew/.linuxbrew"
  fi
')

if [ -n "$BREW_PREFIX" ]; then
  # Register the clean eval command in bashrc
  register_bashrc_entry "Homebrew" "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\""
  log_success "Homebrew installed at ${BREW_PREFIX} and configured for ${ALLOWED_USER}."

  # Ensure the environment is available for the rest of this script
  eval "$(${BREW_PREFIX}/bin/brew shellenv)"

  log_info "Installing LLMFit via Homebrew..."
  sudo -u "${ALLOWED_USER}" bash -c "${BREW_PREFIX}/bin/brew install llmfit" > /dev/null

  log_success "LLMFit installed via Homebrew for ${ALLOWED_USER}."
else
  log_error "Homebrew installation failed."
fi

log_success "Essential packages installed."
