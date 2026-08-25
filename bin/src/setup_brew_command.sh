panther_setup_brew() {
  panther_prepare_setup_step 'Install Homebrew and LLMFit.'

  panther_log_info "Installing Homebrew (as ${PANTHER_ALLOWED_USER})..."
  mkdir -p /home/linuxbrew/.linuxbrew
  chown -R "${PANTHER_ALLOWED_USER}:${PANTHER_ALLOWED_USER}" /home/linuxbrew

  sudo -u "${PANTHER_ALLOWED_USER}" bash -c 'NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

  local brew_prefix
  brew_prefix=$(sudo -u "${PANTHER_ALLOWED_USER}" bash -c '
		if [ -d ~/.linuxbrew ]; then
			echo "$HOME/.linuxbrew"
		elif [ -d /home/linuxbrew/.linuxbrew ]; then
			echo "/home/linuxbrew/.linuxbrew"
		fi
	')

  if [[ -n "$brew_prefix" ]]; then
    panther_register_bashrc_entry 'Homebrew' "eval \"\$(${brew_prefix}/bin/brew shellenv)\""
    panther_log_success "Homebrew installed and configured for ${PANTHER_ALLOWED_USER}."

    # No 'eval "$(brew shellenv)"' here: brew derives HOMEBREW_PREFIX from its
    # own path, every call below is absolute and runs through 'sudo -u', and
    # exported vars would die with this process anyway. The .bashrc entry above
    # is what puts brew on the user's PATH.
    panther_log_info "Installing bottom via Homebrew..."
    sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install bottom"
    panther_log_success "bottom installed via Homebrew for user ${PANTHER_ALLOWED_USER}."

    panther_log_info 'Installing LLMFit via Homebrew...'
    sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install llmfit"
    panther_log_success "LLMFit installed via Homebrew for user ${PANTHER_ALLOWED_USER}."

    panther_log_info 'Installing Hugging Face CLI via Homebrew...'
    # Formula renamed to 'hf' upstream; 'huggingface-cli' only still resolves
    # through Homebrew's old-name mapping. 'hf' is also the binary the models
    # download commands invoke.
    sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install hf"
    panther_log_success "Hugging Face CLI installed via Homebrew for user ${PANTHER_ALLOWED_USER}."

    panther_log_info 'Installing yq via Homebrew...'
    sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install yq"
    panther_log_success "yq installed via Homebrew for user ${PANTHER_ALLOWED_USER}."
  else
    panther_log_error 'Homebrew installation failed.'
  fi
}

panther_setup_brew
