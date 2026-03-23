panther_setup_ssh() {
  panther_prepare_setup_step "Harden SSH configuration (port ${PANTHER_SSH_PORT}, key-only auth)."

  panther_log_info "Configuring SSH (${PANTHER_SSHD_CONFIG})..."

  if [[ ! -f "${PANTHER_SSHD_CONFIG}.orig" ]]; then
    cp "$PANTHER_SSHD_CONFIG" "${PANTHER_SSHD_CONFIG}.orig"
    panther_log_info "Original sshd_config backed up to ${PANTHER_SSHD_CONFIG}.orig"
  fi

  panther_log_info 'Applying SSH hardening via Augeas...'
  rm -f /etc/ssh/sshd_config.d/*.conf

  augtool -s <<AUGEOF
set /files/etc/ssh/sshd_config/Port "$PANTHER_SSH_PORT"
set /files/etc/ssh/sshd_config/PasswordAuthentication no
set /files/etc/ssh/sshd_config/KbdInteractiveAuthentication no
set /files/etc/ssh/sshd_config/ChallengeResponseAuthentication no
set /files/etc/ssh/sshd_config/PubkeyAuthentication yes
set /files/etc/ssh/sshd_config/AuthenticationMethods publickey
set /files/etc/ssh/sshd_config/UsePAM no
set /files/etc/ssh/sshd_config/PermitRootLogin no
set /files/etc/ssh/sshd_config/MaxAuthTries 3
set /files/etc/ssh/sshd_config/LoginGraceTime 30
set /files/etc/ssh/sshd_config/X11Forwarding no
set /files/etc/ssh/sshd_config/AllowTcpForwarding no
set /files/etc/ssh/sshd_config/AllowUsers/1 "$PANTHER_ALLOWED_USER"
AUGEOF

  panther_log_info 'Validating SSH configuration...'
  sshd -t || panther_log_error 'sshd configuration is invalid -- aborting to avoid locking you out.'

  panther_log_info 'Restarting SSH service...'
  systemctl restart ssh
  panther_log_success "SSH hardened on port ${PANTHER_SSH_PORT}. AllowUsers: ${PANTHER_ALLOWED_USER}"
}

panther_setup_ssh
