panther_t2i_download() {
  local model="${args[model]}"
  local force="${args[--force]:-}"
  panther_assert_supported_t2i "$model"
  panther_load_dotenv "$PANTHER_ENV_FILE"

  local model_config cache_dir
  model_config="$(panther_t2i_config "$model")"
  [[ -n "$model_config" ]] || panther_log_error "Text-to-image model '$model' not found in $(panther_t2i_config_file)"

  cache_dir="$(panther_hf_cache_dir)"

  local components
  components="$(jq -c '.components[]' <<<"$model_config")"

  while IFS= read -r component; do
    local repository file path local_dir
    repository="$(jq -r '.repository' <<<"$component")"
    file="$(jq -r '.file' <<<"$component")"
    path="$repository/$file"
    local_dir="$cache_dir/$repository"

    if [[ -f "$cache_dir/$path" && -z "$force" ]]; then
      panther_log_info "'$path' already present; skipping (use --force to re-download)."
      continue
    fi

    [[ -n "$force" ]] && rm -f "$cache_dir/$path"

    panther_log_info "Downloading '$path'..."
    hf download "$repository" --include "$file" --local-dir "$local_dir"
  done <<<"$components"

  # Reclaim files this or another model no longer references (e.g. after a config edit).
  panther_prune_orphans
  panther_log_success "Text-to-image model '$model' ready for use."
}

panther_t2i_download
