panther_cluster_start() {
  panther_log_info 'Starting cluster...'
  panther_compose up -d
  panther_log_success 'Cluster started.'
}

panther_cluster_start
