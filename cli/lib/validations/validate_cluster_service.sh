validate_cluster_service() {
  local service_names error_file reason
  error_file=$(mktemp)

  # Distinguish "could not read the list" from "unknown service": an empty or
  # failed compose config would otherwise report every service as not found.
  if ! service_names=$(panther_services 2>"$error_file") || [[ -z "$service_names" ]]; then
    reason=$(grep -m1 . "$error_file" || true)
    rm -f "$error_file"
    printf "could not read the service list from 'docker compose config'%s\n" "${reason:+: $reason}"
    return
  fi
  rm -f "$error_file"

  if ! echo "$service_names" | grep -q "^$1$"; then
    printf "service '%s' not found in cluster\n\n" "$1"
    printf "available services:\n\n%s" "$service_names"
    return
  fi
}
