panther_cluster_status() {
  cluster_status=$(panther_compose ps --format json)
  formatted_status=$(echo "$cluster_status" | jq -r '. | "\(.Name)\t\(.State)\t\(.Status)"' | column -t -s $'\t')
  panther_log_info 'Cluster status:'
  echo "$formatted_status"
}

panther_cluster_status
