validate_cluster_service() {
  local -a compose_args=(ps --format json)

  cluster_services="$(panther_compose "${compose_args[@]}")"
  service_names="$(echo "$cluster_services" | jq -r '. | "\(.Service)"')"

  if ! echo "$service_names" | grep -q "^$1$"; then
    echo "service '$1' not found in cluster"
    echo "available services:"
    echo "$service_names"
    return
  fi
}
