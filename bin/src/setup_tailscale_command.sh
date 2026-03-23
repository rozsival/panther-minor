panther_setup_tailscale() {
  panther_prepare_setup_step 'Install Tailscale.'

  panther_log_info 'Installing Tailscale...'
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list

  apt update
  apt install -y tailscale

  if command -v tailscale >/dev/null 2>&1; then
    panther_log_success 'Tailscale installed.'
    panther_register_action "Authenticate Tailscale: run 'sudo tailscale up' from your workstation via SSH (GUI with browser needed)."
  else
    panther_log_error 'Tailscale installation failed.'
  fi
}

panther_setup_tailscale
