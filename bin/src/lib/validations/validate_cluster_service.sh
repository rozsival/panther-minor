validate_cluster_service() {
  local service_names
  service_names=$(panther_services)

  if ! "$service_names" | grep -q "^$1$"; then
    printf "service '%s' not found in cluster\n\n" "$1"
    printf "available services:\n\n%s" "$service_names"
    return
  fi
}
