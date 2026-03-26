panther_cluster_stop() {
  local -a compose_args=(down)
  local service_args=''

  if [[ -n ${args[--service]+x} ]]; then
    service_args="${args[--service]}"
    # Bashly stores repeatable flags as a space-delimited string.
    # shellcheck disable=SC2206
    local -a services=(${service_args})
    compose_args+=("${services[@]}")
  fi

  if [[ -n ${args[--volumes]+x} && -n ${args[--service]+x} ]]; then
    panther_log_info "Stopping selected services and removing volumes: ${service_args}..."
    panther_compose "${compose_args[@]}"
    panther_log_success "Selected services stopped and volumes removed: ${service_args}."
  elif [[ -n ${args[--service]+x} ]]; then
    panther_log_info "Stopping selected services: ${service_args}..."
    panther_compose "${compose_args[@]}"
    panther_log_success "Selected services stopped: ${service_args}."
  elif [[ -n ${args[--volumes]+x} ]]; then
    panther_log_info 'Stopping cluster and removing volumes...'
    panther_compose "${compose_args[@]}"
    panther_log_success 'Cluster stopped and volumes removed.'
  else
    panther_log_info 'Stopping cluster...'
    panther_compose "${compose_args[@]}"
    panther_log_success 'Cluster stopped.'
  fi
}

panther_cluster_stop
