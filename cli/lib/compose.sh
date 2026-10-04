panther_compose() {
  (
    cd "$PANTHER_REPO_ROOT" || exit 1
    docker compose "$@"
  )
}
panther_services() {
  panther_compose config | yq '.services | keys[]'
}
# Blocks until a service reports healthy. Compose reports an empty string for services without a
# health check, so callers only use this for services that declare one.
panther_await_service_health() {
  local service="$1"
  local timeout="${2:-300}"
  local waited=0 status

  while ((waited < timeout)); do
    status="$(panther_compose ps --format '{{.Health}}' "$service" 2>/dev/null | head -1)"
    [[ "$status" == 'healthy' ]] && return 0
    sleep 3
    waited=$((waited + 3))
  done

  return 1
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
