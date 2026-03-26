panther_cluster_restart() {
  local -a compose_down_args=(down)
  local -a compose_up_args=(up -d)

  if [[ -n ${args[--volumes]+x} ]]; then
    compose_down_args+=(-v)
    panther_log_info 'Restarting cluster and removing volumes...'
  else
    panther_log_info 'Restarting cluster...'
  fi

  if [[ -n ${args[--remove-orphans]+x} ]]; then
    compose_up_args+=(--remove-orphans)
  fi

  panther_compose "${compose_down_args[@]}"
  panther_compose "${compose_up_args[@]}"
  panther_log_success 'Cluster restarted.'
}

panther_cluster_restart
