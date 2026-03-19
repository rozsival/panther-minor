panther_cluster_stop() {
	local -a compose_args=(down)
	if [[ -n ${args[--volumes]+x} ]]; then
		compose_args+=(-v)
		panther_log_info 'Stopping cluster and removing volumes...'
	else
		panther_log_info 'Stopping cluster...'
	fi

	panther_compose "${compose_args[@]}"
	panther_log_success 'Cluster stopped.'
}

panther_cluster_stop
