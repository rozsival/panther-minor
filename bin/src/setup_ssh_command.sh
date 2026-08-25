panther_setup_ssh() {
  # Resolved up front because bash expands ${PANTHER_SSH_PORT} at the call site
  # below - before panther_prepare_setup_step could resolve it - so a standalone
  # 'setup ssh' on a fresh host died on 'unbound variable'. Resolution is
  # idempotent, so prepare doing it again is free.
  panther_resolve_setup_context
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

  # Ubuntu ships socket-activated SSH: 'ssh.socket' owns the listening port and
  # its shipped unit hardcodes 22, while 'ssh.service' is RequiredBy that socket
  # and inherits the socket's file descriptor. Restarting the service alone
  # therefore keeps serving port 22 whatever sshd_config says. Ubuntu's
  # 'sshd-socket-generator' turns the sshd_config Port into an ssh.socket
  # drop-in, but generators only re-run on a daemon-reload.
  panther_log_info 'Reloading systemd units so the SSH socket adopts the new port...'
  systemctl daemon-reload

  local socket_activated=0
  if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
    socket_activated=1
  fi

  if ((socket_activated)); then
    panther_log_info 'Restarting socket-activated SSH (ssh.socket)...'
    systemctl restart ssh.socket
  else
    panther_log_info 'Restarting SSH service...'
    systemctl restart ssh
  fi

  # UFW runs next and opens only PANTHER_SSH_PORT, so a listener left behind on
  # 22 becomes unreachable. Report that here rather than at the next login.
  local listening_ports
  if ((socket_activated)); then
    # '|| true' because pipefail makes the whole substitution fail when grep
    # matches nothing, and 'set -e' then killed the step here - right where it
    # is supposed to warn that SSH is about to become unreachable.
    listening_ports=$(systemctl show ssh.socket -p Listen --value | tr ' ' '\n' | grep -oE ':[0-9]+$' | tr -d ':' | sort -u | tr '\n' ' ' || true)
  else
    listening_ports=$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -u | tr '\n' ' ')
  fi
  listening_ports="${listening_ports% }"

  if [[ " $listening_ports " == *" $PANTHER_SSH_PORT "* ]]; then
    panther_log_success "SSH hardened on port ${PANTHER_SSH_PORT}. AllowUsers: ${PANTHER_ALLOWED_USER}"
  else
    panther_log_warn "SSH is listening on ${listening_ports:-no port}, not ${PANTHER_SSH_PORT}."
    panther_register_action "Confirm 'ss -tlnp | grep sshd' reports port ${PANTHER_SSH_PORT} before closing this session: UFW only opens ${PANTHER_SSH_PORT}."
  fi
}

panther_setup_ssh
