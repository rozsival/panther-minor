panther_cluster_build() {
	local -a compose_args=(build)
	if [[ -n ${args[--no-cache]+x} ]]; then
		compose_args+=(--no-cache)
		panther_log_info 'Building cluster images without cache...'
	else
		panther_log_info 'Building cluster images...'
	fi

	panther_compose "${compose_args[@]}"
	panther_log_success 'Cluster images built.'
}

panther_cluster_build
