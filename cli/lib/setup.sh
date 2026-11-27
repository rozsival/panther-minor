panther_resolve_setup_context() {
  declare -g PANTHER_ALLOWED_USER
  declare -g PANTHER_ACTIONS_FILE

  # Every setup step calls panther_require_root, so $USER is always 'root' here
  # and never the human being configured. sudo records the real account in
  # SUDO_USER; a direct root login has no record of it and must pass the flag.
  PANTHER_ALLOWED_USER="$(panther_resolve_option '--allowed-user' PANTHER_ALLOWED_USER "${SUDO_USER:-}")"
  PANTHER_ACTIONS_FILE='/tmp/panther-minor_actions'

  if [[ -z "$PANTHER_ALLOWED_USER" ]]; then
    panther_log_error "Could not detect which user to configure. Run the CLI with 'sudo' from your own account, or pass --allowed-user <name>."
  fi

  # The allowed user owns .env, gets hf and runs the stack through Docker; root
  # would put all of that in root's home and run the CLI as root.
  if [[ "$PANTHER_ALLOWED_USER" == 'root' ]]; then
    panther_log_error "'root' cannot be the allowed user: the stack runs as your own account. Pass --allowed-user <name>."
  fi

  if ! id -u "$PANTHER_ALLOWED_USER" >/dev/null 2>&1; then
    panther_log_error "User '${PANTHER_ALLOWED_USER}' does not exist on this host."
  fi
}
panther_ensure_actions_file() {
  mkdir -p "$(dirname "$PANTHER_ACTIONS_FILE")"
  [[ -f "$PANTHER_ACTIONS_FILE" ]] || touch "$PANTHER_ACTIONS_FILE"
}
panther_register_action() {
  panther_ensure_actions_file
  printf '%s\n' "$*" >>"$PANTHER_ACTIONS_FILE"
}
panther_detect_group_gid() {
  local group_name="$1"
  getent group "$group_name" | awk -F: '{print $3}'
}
panther_upsert_env_key() {
  local env_file="$1"
  local key="$2"
  local value="$3"

  [[ -f "$env_file" ]] || touch "$env_file"

  # Replace the existing KEY= line in place, or append it. Rewriting through a
  # temp file and truncating back into the original keeps the file's inode,
  # owner, and permissions intact (this runs as root during setup and as the
  # user during `models t2i load`). value is written literally, so it is safe
  # for paths and characters that would trip up sed.
  if grep -qE "^${key}=" "$env_file"; then
    local tmp
    tmp="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "${key}="* ]]; then
        printf '%s=%s\n' "$key" "$value"
      else
        printf '%s\n' "$line"
      fi
    done <"$env_file" >"$tmp"
    cat "$tmp" >"$env_file"
    rm -f "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" >>"$env_file"
  fi
}
panther_sync_env_host_uid_and_gid() {
  local env_file="$1"
  [[ -f "$env_file" ]] || panther_log_error "Missing env file: $env_file"

  local host_uid host_gid
  host_uid="$(id -u "$PANTHER_ALLOWED_USER")"
  host_gid="$(id -g "$PANTHER_ALLOWED_USER")"

  panther_upsert_env_key "$env_file" HOST_UID "$host_uid"
  panther_upsert_env_key "$env_file" HOST_GID "$host_gid"
}
panther_sync_env_gpu_gids() {
  local env_file="$1"
  [[ -f "$env_file" ]] || panther_log_error "Missing env file: $env_file"

  local video_gid render_gid
  video_gid="$(panther_detect_group_gid video || true)"
  render_gid="$(panther_detect_group_gid render || true)"

  [[ -n "$video_gid" ]] || panther_log_error "Could not detect 'video' group GID"
  [[ -n "$render_gid" ]] || panther_log_error "Could not detect 'render' group GID"

  panther_upsert_env_key "$env_file" VIDEO_GID "$video_gid"
  panther_upsert_env_key "$env_file" RENDER_GID "$render_gid"
}
panther_check_env_ts_authkey() {
  local env_file="$1"
  [[ -f "$env_file" ]] || panther_log_error "Missing env file: $env_file"

  # The key only matters for the sidecar's first login: once the node exists,
  # its identity lives in the state volume and an empty or expired key is fine.
  # The volume alone does not prove a login (Compose creates it on the first
  # start either way), so ask Compose for the sidecar's health instead: its
  # /healthz answers 503 until the node has a tailnet address. A secret cannot
  # be derived from the host, so a missing one is a reminder, not an error.
  local health
  health="$(panther_compose ps --format '{{.Health}}' ts-proxy 2>/dev/null | head -1 || true)"
  [[ "$health" == 'healthy' ]] && return 0

  local key
  key="$(sed -n 's/^TS_AUTHKEY=//p' "$env_file" | tail -1)"
  key="${key//[\"\']/}"
  if [[ -z "$key" ]]; then
    panther_log_warn "TS_AUTHKEY is empty in $env_file; the ts-proxy sidecar cannot join the tailnet."
    panther_register_action "Set TS_AUTHKEY in .env (reusable, pre-approved, tagged tag:panther-minor) before the first 'panther-minor cluster start'."
  fi
}
panther_prepare_setup_step() {
  local message="$1"
  panther_resolve_setup_context
  panther_require_root
  panther_confirm "$message"
  panther_ensure_actions_file

  # Every setup step runs apt-get unattended. Without this, dpkg conffile
  # prompts and needrestart's DPkg::Post-Invoke hook (a ubuntu-server
  # recommend, which branches on this variable) open dialogs that block the
  # run on a terminal nobody is watching.
  export DEBIAN_FRONTEND=noninteractive
}
panther_print_setup_summary() {
  echo ''
  echo -e "\033[0;32m╔══════════════════════════════════════════════╗\033[0m"
  echo -e "\033[0;32m║  🐆 Panther Minor setup complete!            ║\033[0m"
  echo -e "\033[0;32m╠══════════════════════════════════════════════╣\033[0m"
  printf "\033[0;32m║  1. Check    : %-30s║\033[0m\n" "passed"
  printf "\033[0;32m║  2. Deps     : %-30s║\033[0m\n" "installed"
  printf "\033[0;32m║  3. AMD GPU  : %-30s║\033[0m\n" "installed"
  printf "\033[0;32m║  4. GRUB     : %-30s║\033[0m\n" "configured"
  printf "\033[0;32m║  5. Memory   : %-30s║\033[0m\n" "protected"
  printf "\033[0;32m║  6. Env      : %-30s║\033[0m\n" "synced"
  printf "\033[0;32m║  7. CLI      : %-30s║\033[0m\n" "installed"
  echo -e "\033[0;32m╚══════════════════════════════════════════════╝\033[0m"

  if [[ -s "$PANTHER_ACTIONS_FILE" ]]; then
    echo ''
    panther_log_warn '⚠  ACTIONS REQUIRED TO FINISH SETUP:'
    while IFS= read -r line; do
      echo -e "   \033[1;33m•\033[0m $line"
    done <"$PANTHER_ACTIONS_FILE"
  fi
}
