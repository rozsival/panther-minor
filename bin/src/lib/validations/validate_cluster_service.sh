validate_cluster_service() {
  local -a compose_args=(ps --format json)

  cluster_services="$(panther_compose "${compose_args[@]}")"
  service_names="$(echo "$cluster_services" | jq -r '. | "\(.Service)"')"

  if ! echo "$service_names" | grep -q "^$1$"; then
    printf "service '%s' not found in cluster\n\n" "$1"
    printf "available services:\n\n%s" "$service_names"
    return
  fi
}
