panther_update() {
  panther_log_info 'Fetching latest changes from upstream...'
  (
    cd "$PANTHER_REPO_ROOT" || exit 1
    git checkout main
    git fetch --prune
    git pull --rebase
    # Checkout latest tag
    latest_tag=$(git describe --tags --abbrev=0)
    git switch --detach "$latest_tag"
  )
  panther_log_success 'Repository updated.'
}

panther_update
