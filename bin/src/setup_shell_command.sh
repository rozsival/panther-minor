panther_setup_shell() {
  panther_prepare_setup_step "Set up shell with Starship prompt for ${PANTHER_ALLOWED_USER}."

  panther_log_info "Setting up shell with Starship prompt for ${PANTHER_ALLOWED_USER}..."
  apt install -y starship

  usermod -aG video "$PANTHER_ALLOWED_USER"
  usermod -aG render "$PANTHER_ALLOWED_USER"
  loginctl enable-linger "$PANTHER_ALLOWED_USER"

  panther_register_bashrc_entry 'Starship' 'eval "$(starship init bash)"'
  panther_log_success "Shell set up with Starship prompt for ${PANTHER_ALLOWED_USER}."
}

panther_setup_shell
