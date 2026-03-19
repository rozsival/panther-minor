panther_setup_git() {
	panther_prepare_setup_step "Configure Git for ${PANTHER_ALLOWED_USER}."

	panther_log_info "Configuring Git for ${PANTHER_ALLOWED_USER}..."
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global user.name "${PANTHER_SERVER_NAME}"
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global user.email "${PANTHER_ALLOWED_USER}@${PANTHER_SERVER_NAME}"
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global pull.rebase true
	sudo -u "${PANTHER_ALLOWED_USER}" git config --global credential.helper store
	panther_log_success "Git configured for ${PANTHER_ALLOWED_USER}."
}

panther_setup_git
