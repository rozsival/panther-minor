# Where the allowed user's CLI finds hf, or nothing. The probe is a
# non-interactive login shell, the kind 'bash -lc "panther-minor models ..."'
# over SSH gives: it reads ~/.profile (which puts ~/.local/bin on the PATH) but
# not the rest of ~/.bashrc, which returns early. An interactive probe also saw
# the Homebrew PATH line that panther-minor 15 and older appended to ~/.bashrc,
# and so called hf installed where the models commands could not run it. The
# path is read from a marker line, because the rc files may print banners.
panther_deps_user_hf() {
  # shellcheck disable=SC2016 # expands in the user's shell
  sudo -u "$PANTHER_ALLOWED_USER" -i bash -lc 'printf "hf=%s\n" "$(command -v hf)"' </dev/null 2>/dev/null |
    sed -n 's/^hf=//p' | tail -1 || true
}

panther_setup_deps() {
  # Resolved before the message below expands it.
  panther_resolve_setup_context
  panther_prepare_setup_step "Install the stack's packages and the Hugging Face CLI for ${PANTHER_ALLOWED_USER}."

  # jq for the model catalogs and update, augeas-tools for 'setup grub', nvtop to
  # watch the GPUs, python3-venv for the hf installer's virtual environment.
  panther_log_info 'Installing packages...'
  apt-get update
  apt-get install -y jq augeas-tools nvtop curl ca-certificates python3-venv
  panther_log_success 'Packages installed.'

  local hf_path
  hf_path="$(panther_deps_user_hf)"
  if [[ -n "$hf_path" ]]; then
    panther_log_success "Hugging Face CLI already installed for ${PANTHER_ALLOWED_USER}: ${hf_path}"
    return 0
  fi

  # The standalone installer puts hf into a venv under ~/.hf-cli and links it
  # into ~/.local/bin, which Ubuntu's ~/.profile puts on the PATH. Downloaded
  # first, because a failed download piped into bash would still exit 0.
  # --no-modify-path: ~/.profile already covers ~/.local/bin, so the installer
  # need not append to ~/.bashrc. --exclude-skill: no agent skill on the host.
  panther_log_info "Installing the Hugging Face CLI (hf) for ${PANTHER_ALLOWED_USER}..."
  local installer
  installer="$(mktemp)"
  curl -LsSf https://hf.co/cli/install.sh -o "$installer" || {
    rm -f "$installer"
    panther_log_error 'Could not download the Hugging Face CLI installer from https://hf.co/cli/install.sh.'
  }
  chmod 0644 "$installer"
  if ! sudo -u "$PANTHER_ALLOWED_USER" -H bash "$installer" --no-modify-path --exclude-skill; then
    rm -f "$installer"
    panther_log_error "The Hugging Face CLI installer failed for ${PANTHER_ALLOWED_USER}; see its output above."
  fi
  rm -f "$installer"

  hf_path="$(panther_deps_user_hf)"
  if [[ -n "$hf_path" ]]; then
    panther_log_success "Hugging Face CLI installed for ${PANTHER_ALLOWED_USER}: ${hf_path}"
  else
    panther_log_warn "hf was installed, but a login shell of ${PANTHER_ALLOWED_USER} does not find it."
    # shellcheck disable=SC2016 # a line for the user's shell config
    panther_register_action 'Put ~/.local/bin on the PATH of '"${PANTHER_ALLOWED_USER}"' (export PATH="$HOME/.local/bin:$PATH" in ~/.profile), so the models commands find hf.'
  fi
}

panther_setup_deps
