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
  unattended-upgrades \
  unzip > /dev/null

log_success "Essential packages installed with unattended upgrades enabled."

# Install Homebrew as the allowed user
log_info "Installing Homebrew (as ${ALLOWED_USER})..."
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

  # Ensure the environment is available for the rest of this script
  eval "$(${BREW_PREFIX}/bin/brew shellenv)"

  log_info "Installing LLMFit via Homebrew..."
  sudo -u "${ALLOWED_USER}" bash -c "${BREW_PREFIX}/bin/brew install llmfit" > /dev/null

  log_info "Configuring Homebrew autoupdate..."
  sudo -u "${ALLOWED_USER}" bash -c "${BREW_PREFIX}/bin/brew tap domt4/autoupdate" > /dev/null
  # Since setup.sh is run as root, we can configure autoupdate without interaction.
  # The --sudo flag tells brew-autoupdate to use sudo for commands that need it.
  sudo -u "${ALLOWED_USER}" bash -c "${BREW_PREFIX}/bin/brew autoupdate start 86400 --cleanup --immediate --sudo --upgrade" > /dev/null

  log_success "Homebrew with llmfit and autoupdate configured for ${ALLOWED_USER}."
else
  log_warn "Homebrew installation could not be verified. Skipping LLMFit and Autoupdate."
fi
