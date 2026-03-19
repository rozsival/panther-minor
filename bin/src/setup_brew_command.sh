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

		eval "\$(${brew_prefix}/bin/brew shellenv)"

		panther_log_info 'Installing LLMFit via Homebrew...'
		sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install llmfit"
		panther_log_success "LLMFit installed via Homebrew for user ${PANTHER_ALLOWED_USER}."

		panther_log_info 'Installing Hugging Face CLI via Homebrew...'
		sudo -u "${PANTHER_ALLOWED_USER}" bash -c "${brew_prefix}/bin/brew install huggingface-cli"
		panther_log_success "Hugging Face CLI installed via Homebrew for user ${PANTHER_ALLOWED_USER}."
	else
		panther_log_error 'Homebrew installation failed.'
	fi
}

panther_setup_brew
