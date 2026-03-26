panther_cluster_build() {
  local -a compose_args=(build)
  local service_args=''

  if [[ -n ${args[--no-cache]+x} ]]; then
    compose_args+=(--no-cache)
  fi

  if [[ -n ${args[--service]+x} ]]; then
    service_args="${args[--service]}"
    # Bashly stores repeatable flags as a space-delimited string.
    # shellcheck disable=SC2206
    local -a services=(${service_args})
    compose_args+=("${services[@]}")
  fi

  if [[ -n ${args[--no-cache]+x} && -n ${args[--service]+x} ]]; then
    panther_log_info "Building selected service images without cache: ${service_args}..."
  elif [[ -n ${args[--service]+x} ]]; then
    panther_log_info "Building selected service images: ${service_args}..."
  elif [[ -n ${args[--no-cache]+x} ]]; then
    panther_log_info 'Building cluster images without cache...'
  else
    panther_log_info 'Building cluster images...'
  fi

  panther_compose "${compose_args[@]}"
  panther_log_success 'Cluster images built.'
}

panther_cluster_build
