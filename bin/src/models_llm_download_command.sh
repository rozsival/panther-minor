panther_llm_download() {
  local model="${args[model]}"
  local force="${args[--force]:-}"
  panther_assert_supported_llm "$model"
  panther_load_dotenv "$PANTHER_ENV_FILE"

  local model_config hf_repository hf_file draft mmproj model_name cache_dir local_dir
  model_config="$(panther_llm_config "$model")"
  [[ -n "$model_config" ]] || panther_log_error "Model '$model' not found in $(panther_llm_config_file)"

  hf_repository="$(jq -r '.repository' <<<"$model_config")"
  hf_file="$(jq -r '.file' <<<"$model_config")"
  draft="$(jq -r '.draft // empty' <<<"$model_config")"
  mmproj="$(jq -r '.mmproj // empty' <<<"$model_config")"
  model_name="$(jq -r '.name' <<<"$model_config")"

  cache_dir="$(panther_hf_cache_dir)"
  # All of a model's files come from one repository, so they share one local dir.
  local_dir="$cache_dir/$hf_repository"

  local -a files=("$hf_repository/$hf_file")
  [[ -n "$mmproj" ]] && files+=("$hf_repository/$mmproj")
  [[ -n "$draft" ]] && files+=("$hf_repository/$draft")

  local all_present=1 f
  for f in "${files[@]}"; do
    [[ -f "$cache_dir/$f" ]] || all_present=0
  done

  if [[ "$all_present" == "1" && -z "$force" ]]; then
    panther_log_info "Model '$model_name' already present; skipping (use --force to re-download)."
  else
    if [[ -n "$force" ]]; then
      for f in "${files[@]}"; do
        rm -f "$cache_dir/$f"
      done
    fi

    local -a hf_download_args=("$hf_repository" --include "$hf_file" --local-dir "$local_dir")
    [[ -n "$draft" ]] && hf_download_args+=(--include "$draft")
    [[ -n "$mmproj" ]] && hf_download_args+=(--include "$mmproj")

    panther_log_info "Downloading '$model_name' from '$hf_repository'..."
    hf download "${hf_download_args[@]}"
  fi

  # Reclaim files this or another model no longer references (e.g. after a config edit).
  panther_prune_orphans
  panther_log_success "Model '$model_name' ready for use."
}

panther_llm_download
