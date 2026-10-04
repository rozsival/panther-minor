panther_setup_tailscale() {
  panther_prepare_setup_step 'Install Tailscale.'

  # Resolved like the Docker source: UBUNTU_CODENAME still names the Ubuntu base
  # on derivatives, where VERSION_CODENAME names the derivative instead.
  local codename keyring staged
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

  # Upstream's own path, and the one the 'tailscale-archive-keyring' package
  # (a dependency of 'tailscale') owns after the first install, so signing-key
  # rotations arrive through apt instead of silently breaking the repository.
  keyring='/usr/share/keyrings/tailscale-archive-keyring.gpg'

  panther_log_info "Installing Tailscale for ${codename}..."

  apt-get update
  apt-get install -y ca-certificates curl

  # Staged through a temp file rather than 'curl | tee $keyring'. A pipeline
  # reports tee's status, not curl's, so an unpublished codename used to leave a
  # truncated keyring and an empty source behind and only surfaced later as
  # 'Unable to locate package tailscale'. Tailscale signs every suite with the
  # same key, so a 404 here means the release itself is not published yet.
  staged="$(mktemp)"
  if ! curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" -o "$staged"; then
    rm -f "$staged"
    panther_log_error "Tailscale publishes no repository for Ubuntu '${codename}' yet."
  fi

  install -m 0644 "$staged" "$keyring"
  rm -f "$staged"

  # Clean cutover from the one-line source this step used to fetch. Leaving it
  # next to the deb822 file would configure the same suite twice.
  rm -f /etc/apt/sources.list.d/tailscale.list

  # Written locally in deb822, matching docker.sources, instead of fetching
  # upstream's .tailscale-keyring.list: that is legacy one-line format and one
  # more per-codename artifact that can 404 on a freshly released Ubuntu.
  tee /etc/apt/sources.list.d/tailscale.sources <<EOF
Types: deb
URIs: https://pkgs.tailscale.com/stable/ubuntu
Suites: ${codename}
Components: main
Signed-By: ${keyring}
EOF

  apt-get update
  apt-get install -y tailscale

  if command -v tailscale >/dev/null 2>&1; then
    panther_log_success 'Tailscale installed.'
    panther_register_action "Authenticate Tailscale: run 'sudo tailscale up' from your workstation via SSH (GUI with browser needed)."
  else
    panther_log_error 'Tailscale installation failed.'
  fi
}

panther_setup_tailscale
