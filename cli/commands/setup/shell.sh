panther_setup_shell() {
  # Resolved before the message below expands it: see setup/ssh.sh.
  panther_resolve_setup_context
  panther_prepare_setup_step "Set up shell with Starship prompt for ${PANTHER_ALLOWED_USER}."

  panther_log_info "Setting up shell with Starship prompt for ${PANTHER_ALLOWED_USER}..."
  apt-get install -y starship

  panther_log_info "Enabling linger for ${PANTHER_ALLOWED_USER}..."
  loginctl enable-linger "$PANTHER_ALLOWED_USER"

  # shellcheck disable=SC2016 # We want to register the literal command, not its output
  panther_register_bashrc_entry 'Starship' 'eval "$(starship init bash)"'

  # Ghostty's ssh-terminfo installs xterm-ghostty into ~/.terminfo, which ncurses
  # ignores for root and for setcap binaries such as nvtop (cap_perfmon).
  panther_log_info "Installing xterm-ghostty terminfo into /etc/terminfo..."
  tic -x -o /etc/terminfo "$PANTHER_REPO_ROOT/terminfo/xterm-ghostty.terminfo"
  panther_log_success "Shell set up with Starship prompt for ${PANTHER_ALLOWED_USER}."

  # As the user, after the ~/.bashrc entries above, so its login-shell checks
  # see the shell they will get. A failed check is a follow-up, not a reason to
  # abort the rest of 'setup all'.
  panther_log_info "Putting panther-minor on ${PANTHER_ALLOWED_USER}'s PATH..."
  if ! sudo -u "$PANTHER_ALLOWED_USER" -H "$PANTHER_CLI_BIN" install; then
    panther_register_action "Fix what 'panther-minor install' reported above, then re-run ./bin/panther-minor install as ${PANTHER_ALLOWED_USER}."
  fi
}

panther_setup_shell
