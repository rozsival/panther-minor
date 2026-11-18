panther_setup_ufw() {
  panther_prepare_setup_step 'Configure UFW firewall (reset and re-apply rules).'

  panther_log_info 'Configuring UFW...'
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  # The only public entry point. Services are reached through the ts-proxy
  # tailnet node or on loopback, never through a host port UFW would govern.
  ufw allow "${PANTHER_SSH_PORT}/tcp" comment 'SSH'

  ufw --force enable

  panther_log_success "UFW enabled. Open ports: SSH(${PANTHER_SSH_PORT}). AI/monitoring services accessible via the ts-proxy tailnet node or localhost only."
}

panther_setup_ufw
