panther_update() {
	panther_log_info 'Fetching latest changes from upstream...'
	(
		cd "$PANTHER_REPO_ROOT" || exit 1
		git fetch --prune
		git pull --rebase
	)
	panther_log_success 'Repository updated.'
}

panther_update
