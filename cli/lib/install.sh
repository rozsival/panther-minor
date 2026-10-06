# `panther-minor` by name, the way `dot` and `devbox` are: a symlink in
# ~/.local/bin onto this checkout's bin/panther-minor, plus bash completion where
# bash-completion's lazy loader looks for it
# (~/.local/share/bash-completion/completions/<command>), so it costs nothing
# until the first <TAB> after `panther-minor`.

panther_install_link() { printf '%s\n' "$HOME/.local/bin/panther-minor"; }
panther_install_completion_file() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/panther-minor"
}

# The completion file's exact content. The bashly script only forwards each
# <TAB> to `panther-minor __complete`, so it holds no command list and a re-run
# is needed only when bashly's own completion function changes.
panther_install_completion_script() {
  # shellcheck disable=SC2016 # literal backticks
  printf '# Written by `panther-minor install` from `panther-minor completions bash`: re-run it, never edit.\n'
  send_completions bash
}

# Before `install` existed, `setup shell` made ~/.bashrc source the repository's
# .bashrc, which evaluated the completion script on every shell start. That file
# is gone, so the entry would fail in every new shell.
panther_install_remove_legacy_bashrc_entry() {
  local bashrc="$HOME/.bashrc"
  local entry="source '$PANTHER_REPO_ROOT/.bashrc'"
  local kept

  [[ -f "$bashrc" ]] && grep -qxF "$entry" "$bashrc" || return 0
  kept="$(grep -vxF -e "$entry" -e '# Panther Minor CLI' "$bashrc" || true)"
  # Rewritten in place, not replaced, so the file keeps its owner and mode.
  printf '%s\n' "$kept" >"$bashrc"
  panther_log_info "Removed the legacy Panther Minor CLI entry from $bashrc."
}

# How a fresh login shell sees `panther-minor` - what a new SSH session gets,
# independent of the PATH this process inherited (`setup shell` runs install
# through sudo, whose PATH has no ~/.local/bin). Prints `path=<resolved>` and,
# for a bash login shell, `loader=yes` when bash-completion's lazy loader is
# defined.
panther_install_fresh_shell() {
  local shell="${SHELL:-/bin/bash}"
  # shellcheck disable=SC2016 # expands in the probed shell
  env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" SHELL="$shell" TERM=dumb \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin "$shell" -lic \
    'printf "path=%s\n" "$(command -v panther-minor)"
     [ -n "${BASH_VERSION:-}" ] && declare -F _comp_load __load_completion >/dev/null && echo loader=yes
     exit 0' </dev/null 2>/dev/null || true
}

panther_install_completion_hint() {
  if [[ "$(uname -s)" == Darwin ]]; then
    # shellcheck disable=SC2016 # a command for the user to run
    echo 'brew install bash-completion@2, then source "$(brew --prefix)/etc/profile.d/bash_completion.sh" from ~/.bashrc'
  else
    echo "sudo apt-get install -y bash-completion, then source /usr/share/bash-completion/bash_completion from ~/.bashrc (Ubuntu's default ~/.bashrc does)"
  fi
}

# Reports every check before failing, so one run lists every fix.
panther_install_checks() {
  local link file probe resolved
  local failures=0
  link="$(panther_install_link)"
  file="$(panther_install_completion_file)"

  if [[ -L "$link" && "$(readlink "$link")" == "$PANTHER_CLI_BIN" ]]; then
    panther_log_success "$link -> $PANTHER_CLI_BIN"
  else
    panther_log_warn "$link is not a symlink onto $PANTHER_CLI_BIN."
    failures=$((failures + 1))
  fi

  if [[ -f "$file" ]] && cmp -s "$file" <(panther_install_completion_script); then
    panther_log_success "Bash completion at $file."
  else
    panther_log_warn "Bash completion at $file is missing or stale."
    failures=$((failures + 1))
  fi

  probe="$(panther_install_fresh_shell)"
  resolved="$(sed -n 's/^path=//p' <<<"$probe")"
  if [[ "$resolved" == "$link" ]]; then
    panther_log_success "A login shell (${SHELL:-/bin/bash}) resolves panther-minor to $link."
  elif [[ -z "$resolved" ]]; then
    # shellcheck disable=SC2016 # literal $HOME/$PATH in the hint
    panther_log_warn "A login shell (${SHELL:-/bin/bash}) does not find panther-minor - add ~/.local/bin to its PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
    failures=$((failures + 1))
  else
    panther_log_warn "A login shell resolves panther-minor to $resolved, ahead of $link - remove it or put ~/.local/bin first on the PATH."
    failures=$((failures + 1))
  fi

  if [[ "${SHELL:-/bin/bash}" != */bash ]]; then
    panther_log_info "Login shell $SHELL is not bash: completion is installed for bash only - for zsh, put 'source <(panther-minor completions zsh)' in ~/.zshrc after compinit."
  elif grep -qx 'loader=yes' <<<"$probe"; then
    panther_log_success 'A login shell loads bash-completion, which lazy-loads panther-minor completion.'
  else
    panther_log_warn "A login shell does not load bash-completion, so panther-minor completion never loads - $(panther_install_completion_hint)."
    failures=$((failures + 1))
  fi

  ((failures == 0)) || panther_log_error "$failures check(s) failed: fix them, then re-run $PANTHER_CLI_BIN install."
}
