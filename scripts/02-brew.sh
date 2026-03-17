#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
confirm "Install Homebrew and LLMFit."

# =============================================================================
# 2. Homebrew
# =============================================================================
log_info "Installing Homebrew (as ${ALLOWED_USER})..."

# Pre-create Homebrew directories to avoid permission issues
mkdir -p /home/linuxbrew/.linuxbrew
chown -R "${ALLOWED_USER}:${ALLOWED_USER}" /home/linuxbrew

# Install Homebrew as the allowed user
sudo -u "${ALLOWED_USER}" bash -c 'NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

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
	log_success "Homebrew installed and configured for ${ALLOWED_USER}."

	# Ensure the environment is available for the rest of this script
	eval "$(${BREW_PREFIX}/bin/brew shellenv)"

	log_info "Installing LLMFit via Homebrew..."
	sudo -u "${ALLOWED_USER}" bash -c "${BREW_PREFIX}/bin/brew install llmfit"
	log_success "LLMFit installed via Homebrew for user ${ALLOWED_USER}."

	log_info "Installing Hugging Face CLI via Homebrew..."
	sudo -u "${ALLOWED_USER}" bash -c "${BREW_PREFIX}/bin/brew install huggingface-cli"
	log_success "Hugging Face CLI installed via Homebrew for user ${ALLOWED_USER}."
else
	log_error "Homebrew installation failed."
fi
