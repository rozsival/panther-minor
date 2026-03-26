panther_cluster_restart() {
  local -a compose_down_args=(down)
  local -a compose_up_args=(up)

  local service_args=''

  if [[ -n ${args[--service]+x} ]]; then
    service_args="${args[--service]}"
    # Bashly stores repeatable flags as a space-delimited string.
    # shellcheck disable=SC2206
    local -a services=(${service_args})
    compose_down_args+=("${services[@]}")
    compose_up_args+=("${services[@]}")
    panther_log_info "Restarting selected services: ${service_args}..."
  fi

  compose_up_args+=(--detach)

  if [[ -n ${args[--remove-orphans]+x} ]]; then
    compose_up_args+=(--remove-orphans)
  fi

  if [[ -n ${args[--volumes]+x} ]]; then
    compose_down_args+=(-v)
  fi

  if [[ -n ${args[--volumes]+x} && -n ${args[--service]+x} ]]; then
    panther_log_info "Restarting selected services and removing volumes: ${service_args}..."
    panther_compose "${compose_down_args[@]}"
    panther_compose "${compose_up_args[@]}"
    panther_log_success "Selected services restarted and volumes removed: ${service_args}."
  elif [[ -n ${args[--service]+x} ]]; then
    panther_log_info "Restarting selected services: ${service_args}..."
    panther_compose "${compose_down_args[@]}"
    panther_compose "${compose_up_args[@]}"
    panther_log_success "Selected services restarted: ${service_args}."
  elif [[ -n ${args[--volumes]+x} ]]; then
    panther_log_info 'Restarting cluster and removing volumes...'
    panther_compose "${compose_down_args[@]}"
    panther_compose "${compose_up_args[@]}"
    panther_log_success 'Cluster restarted and volumes removed.'
  else
    panther_log_info 'Restarting cluster...'
    panther_compose "${compose_down_args[@]}"
    panther_compose "${compose_up_args[@]}"
    panther_log_success 'Cluster restarted.'
  fi
}

panther_cluster_restart
