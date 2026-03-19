panther_cluster_restart() {
	panther_log_info 'Restarting cluster...'
	panther_compose down
	panther_compose up -d
	panther_log_success 'Cluster restarted.'
}

panther_cluster_restart
