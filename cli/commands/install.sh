panther_install() {
  # Everything lands in the caller's home, so root would install it for root.
  [[ $EUID -ne 0 ]] || panther_log_error "Run install as the user who uses the CLI, not with sudo: it installs into your home directory. 'setup shell' runs it for the allowed user."

  local link file
  link="$(panther_install_link)"
  file="$(panther_install_completion_file)"

  # Only ever replaces a symlink: a real file there is someone else's command.
  if [[ -e "$link" && ! -L "$link" ]]; then
    panther_log_error "$link exists and is not a symlink - move it aside, then re-run."
  fi
  if [[ "$(readlink "$link" 2>/dev/null || true)" != "$PANTHER_CLI_BIN" ]]; then
    mkdir -p "${link%/*}"
    ln -sfn "$PANTHER_CLI_BIN" "$link"
    panther_log_info "Linked $link -> $PANTHER_CLI_BIN."
  fi

  if [[ ! -f "$file" ]] || ! cmp -s "$file" <(panther_install_completion_script); then
    mkdir -p "${file%/*}"
    panther_install_completion_script >"$file.$$"
    mv "$file.$$" "$file"
    panther_log_info "Wrote $file."
  fi

  panther_install_remove_legacy_bashrc_entry
  panther_install_checks
}

panther_install
