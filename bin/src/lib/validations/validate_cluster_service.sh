validate_cluster_service() {
  if ! panther_services | grep -q "^$1$"; then
    printf "service '%s' not found in cluster\n\n" "$1"
    printf "available services:\n\n%s" "$service_names"
    return
  fi
}
