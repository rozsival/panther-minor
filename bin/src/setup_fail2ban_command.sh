panther_setup_fail2ban() {
  panther_prepare_setup_step 'Install and configure fail2ban.'

  panther_log_info 'Installing fail2ban...'
  apt-get install -y fail2ban

  panther_log_info "Writing ${PANTHER_FAIL2BAN_JAIL}..."
  # Ubuntu Server has no rsyslog, so /var/log/auth.log never exists and the
  # journal is the only source of sshd auth failures. 'backend = systemd' is set
  # explicitly rather than inherited from Ubuntu's jail.d/defaults-debian.conf,
  # so the jail stays valid if that distro file ever changes.
  #
  # 'ignoreip' covers the Tailscale CGNAT v4 pool and the tailnet ULA v6 prefix,
  # because every administrative login reaches this host over tailscale0. Without
  # it fail2ban's default (loopback only) treats the admin path as hostile: sshd
  # sets MaxAuthTries 3, so a client whose agent offers three keys exhausts
  # maxretry on its first connection, and any reconnect loop re-arms the ban past
  # bantime. Rate-limiting buys nothing against 'AuthenticationMethods publickey'
  # anyway; the jail still guards the port UFW exposes publicly.
  cat >"$PANTHER_FAIL2BAN_JAIL" <<EOF
[sshd]
enabled  = true
port     = ${PANTHER_SSH_PORT}
filter   = sshd
backend  = systemd
ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10 fd7a:115c:a1e0::/48
maxretry = 3
bantime  = 1h
findtime = 10m
EOF

  panther_log_info 'Restarting fail2ban...'
  systemctl enable --now fail2ban
  systemctl restart fail2ban
  panther_log_success 'fail2ban configured and running.'
}

panther_setup_fail2ban
