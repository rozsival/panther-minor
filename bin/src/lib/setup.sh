panther_resolve_setup_context() {
  declare -g PANTHER_SERVER_NAME
  declare -g PANTHER_ALLOWED_USER
  declare -g PANTHER_SSH_PORT
  declare -g PANTHER_TIMEZONE
  declare -g PANTHER_LVM_DEVICE
  declare -g PANTHER_ACTIONS_FILE

  PANTHER_SERVER_NAME="$(panther_resolve_option '--server-name' PANTHER_SERVER_NAME "$HOSTNAME")"
  PANTHER_ALLOWED_USER="$(panther_resolve_option '--allowed-user' PANTHER_ALLOWED_USER "$USER")"
  PANTHER_SSH_PORT="$(panther_resolve_option '--ssh-port' PANTHER_SSH_PORT '2222')"
  PANTHER_TIMEZONE="$(panther_resolve_option '--timezone' PANTHER_TIMEZONE 'Europe/Prague')"
  PANTHER_LVM_DEVICE="$(panther_resolve_option '--lvm-device' PANTHER_LVM_DEVICE '/dev/ubuntu-vg/ubuntu-lv')"
  PANTHER_ACTIONS_FILE="/tmp/${PANTHER_SERVER_NAME}_actions"
}
panther_ensure_actions_file() {
  mkdir -p "$(dirname "$PANTHER_ACTIONS_FILE")"
  [[ -f "$PANTHER_ACTIONS_FILE" ]] || touch "$PANTHER_ACTIONS_FILE"
}
panther_register_action() {
  panther_ensure_actions_file
  printf '%s\n' "$*" >>"$PANTHER_ACTIONS_FILE"
}
panther_register_bashrc_entry() {
  local label="$1"
  local command="$2"
  local user_name="${3:-$PANTHER_ALLOWED_USER}"
  local bashrc="/home/$user_name/.bashrc"

  if ! grep -qF "$command" "$bashrc"; then
    panther_log_info "Adding $label to $bashrc..."
    printf '\n# %s\n%s\n' "$label" "$command" >>"$bashrc"
    chown "$user_name:$user_name" "$bashrc"
  fi
}
panther_detect_group_gid() {
  local group_name="$1"
  getent group "$group_name" | awk -F: '{print $3}'
}
panther_upsert_env_key() {
  local env_file="$1"
  local key="$2"
  local value="$3"

  if command -v augtool >/dev/null 2>&1; then
    augtool -A -L <<AUGEOF
set /files${env_file}/${key} "${value}"
save
AUGEOF
    return 0
  fi

  if grep -qE "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
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
panther_prepare_setup_step() {
  local message="$1"
  panther_resolve_setup_context
  panther_require_root
  panther_confirm "$message"
  panther_ensure_actions_file
}
panther_print_setup_summary() {
  echo ''
  echo -e "\033[0;32m╔══════════════════════════════════════════════╗\033[0m"
  echo -e "\033[0;32m║  🐆 ${PANTHER_SERVER_NAME} setup complete!            ║\033[0m"
  echo -e "\033[0;32m╠══════════════════════════════════════════════╣\033[0m"
  printf "\033[0;32m║  0. Init     : %-30s║\033[0m\n" "complete"
  printf "\033[0;32m║  1. Packages : %-30s║\033[0m\n" "installed"
  printf "\033[0;32m║  2. Brew     : %-30s║\033[0m\n" "ready"
  printf "\033[0;32m║  3. Docker   : %-30s║\033[0m\n" "ready"
  printf "\033[0;32m║  4. Tailscale: %-30s║\033[0m\n" "installed"
  printf "\033[0;32m║  5. SSH      : %-30s║\033[0m\n" "secured"
  printf "\033[0;32m║  6. UFW      : %-30s║\033[0m\n" "active"
  printf "\033[0;32m║  7. fail2ban : %-30s║\033[0m\n" "active"
  printf "\033[0;32m║  8. AMD GPU  : %-30s║\033[0m\n" "installed"
  printf "\033[0;32m║  9. GRUB     : %-30s║\033[0m\n" "configured"
  printf "\033[0;32m║ 10. Git      : %-30s║\033[0m\n" "configured"
  printf "\033[0;32m║ 11. Shell    : %-30s║\033[0m\n" "configured"
  printf "\033[0;32m║ 12. Env      : %-30s║\033[0m\n" "synced"
  echo -e "\033[0;32m╚══════════════════════════════════════════════╝\033[0m"

  if [[ -s "$PANTHER_ACTIONS_FILE" ]]; then
    echo ''
    panther_log_warn '⚠  ACTIONS REQUIRED TO FINISH SETUP:'
    while IFS= read -r line; do
      echo -e "   \033[1;33m•\033[0m $line"
    done <"$PANTHER_ACTIONS_FILE"
  fi

  echo ''
  panther_log_info "Reconnection: ssh -p ${PANTHER_SSH_PORT} ${PANTHER_ALLOWED_USER}@<server-ip>"
}
