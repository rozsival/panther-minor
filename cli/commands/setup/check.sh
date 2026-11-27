# Changes nothing and needs no root, so it can run before anything else - also
# on a host someone else prepared. The host baseline (Docker, a hardened SSH,
# a firewall) is not this project's job: pantheon sets it up, and so does any
# Ubuntu host with Docker Engine. Every check runs before the step fails, so one
# run lists every fix.
panther_setup_check() {
  # Not panther_resolve_setup_context: it requires sudo's SUDO_USER, and this
  # step also runs as the user. Root itself is refused because the docker group
  # check needs the account that will run the stack.
  local user
  user="$(panther_resolve_option '--allowed-user' PANTHER_ALLOWED_USER "${SUDO_USER:-$(id -un)}")"
  [[ -n "$user" ]] || panther_log_error "Could not tell which user runs the stack. Run 'setup check' as that user, or pass --allowed-user <name>."
  [[ "$user" != 'root' ]] || panther_log_error "'root' cannot run the stack. Run 'setup check' as your own account (or with sudo from it), or pass --allowed-user <name>."
  id -u "$user" >/dev/null 2>&1 || panther_log_error "User '${user}' does not exist on this host."

  local failures=0
  local baseline='https://github.com/rozsival/pantheon'

  local os_id='' os_version=''
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null # the host's file, read at runtime
    os_id="$(. /etc/os-release && echo "${ID:-}")"
    # shellcheck source=/dev/null
    os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
  fi
  # 'sort -V' orders 26.04 before 26.10 and 27.04, so the minimum sorts first
  # exactly when the host is at least that release.
  if [[ "$os_id" == ubuntu && "$(printf '%s\n' 26.04 "$os_version" | sort -V | head -1)" == 26.04 ]]; then
    panther_log_success "Ubuntu ${os_version}."
  else
    panther_log_warn "Ubuntu 26.04 or newer is required (found ${os_id:-unknown} ${os_version:-unknown}): the AMD driver and ROCm repositories are pinned to it."
    failures=$((failures + 1))
  fi

  # --version and 'compose version' only need the binaries, not the daemon
  # socket: a user not yet in the docker group must get the group warning below,
  # not a failure here.
  if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
    panther_log_success "$(docker --version)."
  else
    panther_log_warn "Docker Engine is missing. Install it with pantheon ('setup docker', ${baseline}) or from https://docs.docker.com/engine/install/ubuntu/."
    failures=$((failures + 1))
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    panther_log_success "$(docker compose version)."
  else
    panther_log_warn "The Docker Compose plugin is missing: apt-get install docker-compose-plugin (from Docker's repository)."
    failures=$((failures + 1))
  fi

  if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
    panther_log_success "${user} is in the docker group."
  else
    # A warning, not a failure: the group applies only after a new login, so
    # setup can go on and the user fixes it afterwards.
    panther_log_warn "${user} is not in the docker group, so the CLI cannot reach Docker without sudo."
    if [[ -n "${PANTHER_ACTIONS_FILE:-}" ]]; then
      panther_register_action "Add ${user} to the docker group (sudo usermod -aG docker ${user}), then log out and back in."
    else
      panther_log_info "Fix: sudo usermod -aG docker ${user}, then log out and back in."
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    panther_log_success 'curl is installed.'
  else
    panther_log_warn 'curl is missing: sudo apt-get install -y curl.'
    failures=$((failures + 1))
  fi

  ((failures == 0)) || panther_log_error "${failures} prerequisite(s) missing: fix them, then re-run setup. A fresh server gets all of them from pantheon: ${baseline}"
  panther_log_success 'Host prerequisites met.'
}

panther_setup_check
