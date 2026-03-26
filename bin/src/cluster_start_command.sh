panther_cluster_start() {
  local -a compose_args=(up -d)

  if [[ -n ${args[--remove-orphans]+x} ]]; then
    compose_args+=(--remove-orphans)
  fi

  panther_log_info 'Starting cluster...'
  panther_compose "${compose_args[@]}"
  panther_log_success 'Cluster started.'
}

panther_cluster_start
