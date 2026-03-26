panther_cluster_start() {
  local -a compose_args=(up)
  local service_args=''

  if [[ -n ${args[--service]+x} ]]; then
    service_args="${args[--service]}"
    # Bashly stores repeatable flags as a space-delimited string.
    # shellcheck disable=SC2206
    local -a services=(${service_args})
    compose_args+=("${services[@]}")
  fi

  compose_args+=(--detach)

  if [[ -n ${args[--remove-orphans]+x} ]]; then
    compose_args+=(--remove-orphans)
  fi

  if [[ -n ${args[--service]+x} ]]; then
    panther_log_info "Starting selected services: ${service_args}..."
    panther_compose "${compose_args[@]}"
    panther_log_success "Selected services started: ${service_args}."
  else
    panther_log_info 'Starting all cluster services...'
    panther_compose "${compose_args[@]}"
    panther_log_success 'Cluster started.'
  fi

}

panther_cluster_start
