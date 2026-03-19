panther_setup_ufw() {
	panther_prepare_setup_step 'Configure UFW firewall (reset and re-apply rules).'

	panther_log_info 'Configuring UFW...'
	ufw --force reset
	ufw default deny incoming
	ufw default allow outgoing

	ufw allow "${PANTHER_SSH_PORT}/tcp" comment 'SSH'
	ufw allow 80/tcp comment 'HTTP'
	ufw allow 443/tcp comment 'HTTPS'

	ufw --force enable

	panther_log_success "UFW enabled. Open ports: SSH(${PANTHER_SSH_PORT}), HTTP(80), HTTPS(443). AI/monitoring services accessible via localhost/Tailscale only."
}

panther_setup_ufw
