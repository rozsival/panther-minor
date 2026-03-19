panther_setup_fail2ban() {
	panther_prepare_setup_step 'Install and configure fail2ban.'

	panther_log_info 'Installing fail2ban...'
	apt install -y fail2ban

	panther_log_info "Writing ${PANTHER_FAIL2BAN_JAIL}..."
	cat > "$PANTHER_FAIL2BAN_JAIL" <<EOF
[sshd]
enabled  = true
port     = ${PANTHER_SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
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
