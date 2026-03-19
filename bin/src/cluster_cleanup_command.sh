panther_cluster_cleanup() {
	panther_log_info 'Cleaning up cluster containers, volumes, images, and orphans...'
	panther_compose down -v --rmi all --remove-orphans
	panther_log_success 'Cluster cleanup completed.'
}

panther_cluster_cleanup
