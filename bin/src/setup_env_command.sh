panther_setup_env() {
  panther_prepare_setup_step 'Set up env vars and sync GPU group IDs.'

  if [[ ! -f "$PANTHER_ENV_FILE" ]]; then
    [[ -f "$PANTHER_ENV_EXAMPLE_FILE" ]] || panther_log_error "Missing $PANTHER_ENV_EXAMPLE_FILE"
    panther_log_info "Creating $PANTHER_ENV_FILE from .env.example..."
    cp "$PANTHER_ENV_EXAMPLE_FILE" "$PANTHER_ENV_FILE"
    chown "$PANTHER_ALLOWED_USER:$PANTHER_ALLOWED_USER" "$PANTHER_ENV_FILE"
  fi

  panther_log_info "Syncing HOST_UID and HOST_GID in $PANTHER_ENV_FILE from host user $PANTHER_ALLOWED_USER..."
  panther_sync_env_host_uid_and_gid "$PANTHER_ENV_FILE"

  panther_log_info "Syncing VIDEO_GID and RENDER_GID in $PANTHER_ENV_FILE from host groups..."
  panther_sync_env_gpu_gids "$PANTHER_ENV_FILE"

  panther_log_success 'Env vars ready.'
}

panther_setup_env
