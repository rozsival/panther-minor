panther_proxy_renew_ssl() {
  local current_owner="$(id -u):$(id -g)"
  mkdir -p "$PANTHER_PROXY_DIR/acme" "$PANTHER_PROXY_DIR/ssl"

  docker run --rm \
    --user "$current_owner" \
    -v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
    -v "$PANTHER_PROXY_DIR/ssl:/ssl" \
    neilpang/acme.sh --cron

  cd "$PANTHER_REPO_ROOT" || exit 1
  docker compose exec proxy nginx -s reload
}

panther_proxy_renew_ssl
