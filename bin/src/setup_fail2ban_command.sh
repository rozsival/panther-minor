panther_setup_fail2ban() {
  panther_prepare_setup_step 'Install and configure fail2ban.'

  panther_log_info 'Installing fail2ban...'
  apt-get install -y fail2ban

  panther_log_info "Writing ${PANTHER_FAIL2BAN_JAIL}..."
  # Ubuntu Server has no rsyslog, so /var/log/auth.log never exists and the
  # journal is the only source of sshd auth failures. 'backend = systemd' is set
  # explicitly rather than inherited from Ubuntu's jail.d/defaults-debian.conf,
  # so the jail stays valid if that distro file ever changes.
  cat >"$PANTHER_FAIL2BAN_JAIL" <<EOF
[sshd]
enabled  = true
port     = ${PANTHER_SSH_PORT}
filter   = sshd
backend  = systemd
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
