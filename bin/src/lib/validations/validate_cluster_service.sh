validate_cluster_service() {
  local -a compose_args=(ps --format json)

  cluster_services="$(panther_compose "${compose_args[@]}")"
  service_names="$(echo "'$cluster_services'" | jq -r '.[].Service')"

  if ! grep -q "$1" <<<"$service_names"; then
    echo "Service '$1' not found in cluster"
    echo "Available services:"
    echo "$service_names" | awk '{print $1}' | tail -n +2
    return 1
  fi

  return 0
}
