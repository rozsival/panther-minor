panther_update() {
  local root="$PANTHER_REPO_ROOT"
  local installed target work stage old_manifest lock_fd

  # The install lives in the operator's home; root would leave root-owned files behind.
  [[ $EUID -ne 0 ]] || panther_log_error "Run update as the user who owns $root, not with sudo."

  # One update per install, held until exit: two runs would interleave their renames
  # into a mix of versions. Failing fast, not waiting, means no run acts on state
  # read before another one changed it.
  exec {lock_fd}<"$root"
  flock -n "$lock_fd" || panther_log_error "Another update is already running in $root."

  panther_update_read_installed "$root"
  panther_log_info "Resolving '${args[version]}' on GitHub..."
  panther_update_resolve "${args[version]}"

  installed="$(panther_update_describe "$PANTHER_UPDATE_INSTALLED_CHANNEL" "$PANTHER_UPDATE_INSTALLED_REF" "$PANTHER_UPDATE_INSTALLED_COMMIT")"
  target="$(panther_update_describe "$PANTHER_UPDATE_TARGET_CHANNEL" "$PANTHER_UPDATE_TARGET_REF" "$PANTHER_UPDATE_TARGET_COMMIT")"

  # A release tag names one build; a branch moves, so only its commit identifies it.
  if [[ "$PANTHER_UPDATE_INSTALLED_CHANNEL" == "$PANTHER_UPDATE_TARGET_CHANNEL" &&
    "$PANTHER_UPDATE_INSTALLED_REF" == "$PANTHER_UPDATE_TARGET_REF" &&
    ("$PANTHER_UPDATE_TARGET_CHANNEL" == release || "$PANTHER_UPDATE_INSTALLED_COMMIT" == "$PANTHER_UPDATE_TARGET_COMMIT") ]]; then
    panther_log_success "Panther Minor $installed is already installed."
    return 0
  fi

  # Converting deletes .git and every tracked non-runtime file: refuse whatever exists only here.
  if [[ "$PANTHER_UPDATE_INSTALLED_CHANNEL" == git ]]; then
    [[ -z "$(git -C "$root" status --porcelain --untracked-files=no)" ]] ||
      panther_log_error "$root has uncommitted changes to tracked files, which converting to an archive install would delete. Commit and push them, or discard them, then re-run."
    # Every local ref and HEAD (a detached HEAD, stashes, tags), not just branches.
    [[ -z "$(git -C "$root" rev-list --max-count=1 HEAD --all --not --remotes)" ]] ||
      panther_log_error "$root has commits (or stashes) on no remote, which removing .git would delete. Push or drop them, then re-run."
  fi

  panther_confirm "Update Panther Minor in $root from $installed to $target?"

  if [[ "$PANTHER_UPDATE_INSTALLED_CHANNEL" == git ]]; then
    panther_log_warn "$root is a Git checkout: this removes .git and every file the runtime does not need (cli/, docs/, tests, tooling). Never run it in a development clone."
    panther_confirm "Convert $root into an archive install?"
  fi

  if [[ "$PANTHER_UPDATE_TARGET_CHANNEL" == branch ]]; then
    panther_log_warn "$target is not a release: it is unstable, may be broken, and may change the host or .env incompatibly."
    panther_confirm "Install the unstable $target anyway?"
  elif [[ "$PANTHER_UPDATE_INSTALLED_REF" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ && "$PANTHER_UPDATE_INSTALLED_CHANNEL" != branch ]] &&
    panther_update_is_older "$PANTHER_UPDATE_TARGET_REF" "$PANTHER_UPDATE_INSTALLED_REF"; then
    panther_log_warn "$target is older than the installed $installed: a downgrade can leave .env, models and service data in a state the older version does not expect."
    panther_confirm "Downgrade to $target anyway?"
  fi

  work="$(mktemp -d)"
  # Staged inside the install, on its filesystem, so files move into place by rename.
  stage="$(mktemp -d "$root/.update.XXXXXX")"
  # shellcheck disable=SC2064 # expand now: the locals are gone when the trap fires
  trap "rm -rf '$work' '$stage'" EXIT

  panther_log_info "Downloading $target..."
  panther_update_fetch "$stage" "$work"

  old_manifest="$work/installed.manifest"
  if [[ -f "$root/.manifest" ]]; then
    cp "$root/.manifest" "$old_manifest"
  else
    # A Git checkout: every tracked file is the previous version's, and leaves with it.
    git -C "$root" ls-files >"$old_manifest"
  fi

  panther_update_apply "$root" "$stage" "$old_manifest"
  if [[ "$PANTHER_UPDATE_INSTALLED_CHANNEL" == git ]]; then
    rm -rf "$root/.git"
    panther_log_info "Converted the Git checkout into an archive install: removed .git and every file the runtime does not need."
  fi

  panther_log_success "Panther Minor $target installed in $root."
  panther_log_info "Rebuild and recreate the containers so they mount the new files: panther-minor cluster build && panther-minor cluster restart"
}

panther_update
