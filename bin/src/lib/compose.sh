panther_compose() {
  (
    cd "$PANTHER_REPO_ROOT" || exit 1
    docker compose "$@"
  )
}
panther_services() {
  panther_compose config | yq '.services | keys[]'
}
panther_logs_service() {
  local service="$1"
  local -a compose_args=(logs --timestamps)

  if [[ -n ${args[--tail]+x} ]]; then
    local tail_lines="${args[--tail]:-100}"
    compose_args+=(--tail "$tail_lines")
    panther_log_info "Showing the latest ${tail_lines} log lines for ${service}..."
  else
    compose_args+=(--follow)
    panther_log_info "Streaming logs for ${service}..."
  fi

  compose_args+=("$service")
  panther_compose "${compose_args[@]}"
}
